module core_instr_bus_adapter(
    input  logic        clk, rstn,             // 时钟与复位（低有效）
    input  logic [31:0] i_boot_addr,           // 启动地址
    input  logic        i_stall,               // 是否 stall（流水线阻塞）
    input  logic        i_bus_disable,         // 禁止取指（通常来自 IF 阶段控制）
    input  logic        i_ex_jmp,              // EX 阶段的跳转标志
    input  logic        i_id_jmp,              // ID 阶段的跳转标志
    input  logic [31:0] i_ex_target,           // EX 阶段跳转目标
    input  logic [31:0] i_id_target,           // ID 阶段跳转目标

    output logic [31:0] o_pc,                  // 当前指令地址
    output logic [31:0] o_instr,               // 当前指令

    naive_bus.master  bus_master               // 指令总线接口（只读）
);

// -----------------------------
// 内部变量
// -----------------------------
logic [31:0] npc;                 // next PC
logic [31:0] instr_hold = 32'd0;  // hold 指令值（在 stall 情况下保留）
logic        bus_busy   = 1'b0;   // 总线未授权标志（busy）
logic        stall_n    = 1'b0;   // stall_n = ~i_stall，表示可以前进

// -----------------------------
// 初始 PC 设置
// -----------------------------
initial o_pc = 32'd0;

// -----------------------------
// 总线写接口禁用（instruction bus 不写）
// -----------------------------
assign bus_master.wr_req  = 1'b0;
assign bus_master.wr_be   = 4'b0000;
assign bus_master.wr_addr = 32'd0;
assign bus_master.wr_data = 32'd0;

// -----------------------------
// 总线读接口赋值
// -----------------------------
assign bus_master.rd_req  = ~i_bus_disable;
assign bus_master.rd_be   = {4{~i_bus_disable}};
assign bus_master.rd_addr = npc;

// -----------------------------
// 下一条指令地址 npc 计算逻辑
// -----------------------------
always_comb begin
    if(i_ex_jmp)
        npc = i_ex_target;
    else if(i_id_jmp)
        npc = i_id_target;
    else if(i_bus_disable || bus_busy)
        npc = o_pc;           // 保持当前地址
    else
        npc = o_pc + 4;       // 顺序执行
end

// -----------------------------
// 时序逻辑：stall 与 busy 状态保持
// -----------------------------
always_ff @(posedge clk or negedge rstn)
    if(~rstn) begin
        stall_n     <= 1'b0;
        bus_busy    <= 1'b0;
        instr_hold  <= 32'd0;
    end else begin
        stall_n     <= ~i_stall;
        bus_busy    <= bus_master.rd_req & ~bus_master.rd_gnt;
        instr_hold  <= o_instr;
    end

// -----------------------------
// 指令选择逻辑
// -----------------------------
always_comb begin
    if(~stall_n)
        o_instr = instr_hold;                      // stall 时保持原值
    else if(i_ex_jmp || bus_busy)
        o_instr = 32'd0;                           // 跳转或 busy 时无效指令
    else
        o_instr = bus_master.rd_data;             // 正常读取
end

// -----------------------------
// PC 更新
// -----------------------------
always_ff @(posedge clk)
    if(~rstn)
        o_pc <= {i_boot_addr[31:2], 2'b00} - 32'd4; // 起始从 boot_addr - 4，使得第一次 npc = boot_addr
    else
        o_pc <= npc;

endmodule
