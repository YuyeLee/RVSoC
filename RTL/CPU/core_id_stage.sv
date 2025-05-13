module core_id_stage(
    input  logic [31:0]  i_instr,              // 输入指令

    output logic         o_src1_reg_en,        // 是否需要读 rs1
    output logic         o_src2_reg_en,        // 是否需要读 rs2
    output logic         o_jal,                // 是否为 JAL 指令（跳转控制）
    output logic         o_alures2reg,         // ALU 结果是否写入寄存器
    output logic         o_memory2reg,         // 是否从 memory 读数据到寄存器
    output logic         o_mem_write,          // 是否进行 memory 写操作

    output logic [ 4:0]  o_src1_reg_addr,      // 源寄存器1地址 rs1
    output logic [ 4:0]  o_src2_reg_addr,      // 源寄存器2地址 rs2
    output logic [ 4:0]  o_dst_reg_addr,       // 目标寄存器地址 rd

    output logic [ 6:0]  o_opcode, o_funct7,   // opcode 与 funct7 字段
    output logic [ 2:0]  o_funct3,             // funct3 字段
    output logic [31:0]  o_imm                 // 解码得到的立即数
);

// 将指令按 RISC-V 格式拆解字段（固定格式，直接赋值）
assign {o_funct7, o_src2_reg_addr, o_src1_reg_addr, o_funct3, o_dst_reg_addr, o_opcode} = i_instr;

// 定义指令类型枚举
typedef enum logic [2:0] {
    UKNOWN_TYPE,
    R_TYPE,
    I_TYPE,
    IZ_TYPE,
    S_TYPE,
    B_TYPE,
    U_TYPE,
    J_TYPE
} instr_type_e;

instr_type_e instr_type; // 实际类型变量

// 定义常见 opcode（与 RISC-V spec 对应）
localparam  OPCODE_AUIPC  = 7'b0010111,
            OPCODE_LUI    = 7'b0110111,
            OPCODE_JAL    = 7'b1101111,
            OPCODE_JALR   = 7'b1100111,
            OPCODE_BRANCH = 7'b1100011,
            OPCODE_ALI    = 7'b0010011,
            OPCODE_ALR    = 7'b0110011,
            OPCODE_LOAD   = 7'b0000011,
            OPCODE_STORE  = 7'b0100011;

// ------------------------------
// 控制信号生成
// ------------------------------
assign o_jal        = (o_opcode == OPCODE_JAL);
assign o_memory2reg = (o_opcode == OPCODE_LOAD);
assign o_mem_write  = (o_opcode == OPCODE_STORE);
assign o_alures2reg = (o_opcode == OPCODE_JAL   ||
                       o_opcode == OPCODE_JALR  ||
                       o_opcode == OPCODE_LUI   ||
                       o_opcode == OPCODE_AUIPC ||
                       o_opcode == OPCODE_ALI   ||
                       o_opcode == OPCODE_ALR);

// ------------------------------
// 指令类型判断
// ------------------------------
always_comb begin
    unique case (o_opcode)
        OPCODE_AUIPC  : instr_type = U_TYPE;
        OPCODE_LUI    : instr_type = U_TYPE;
        OPCODE_JAL    : instr_type = J_TYPE;
        OPCODE_JALR   : instr_type = I_TYPE;
        OPCODE_BRANCH : instr_type = B_TYPE;
        OPCODE_ALI    : instr_type = I_TYPE;
        OPCODE_ALR    : instr_type = R_TYPE;
        OPCODE_LOAD   : instr_type = I_TYPE;
        OPCODE_STORE  : instr_type = S_TYPE;
        default       : instr_type = UKNOWN_TYPE;
    endcase
end

// ------------------------------
// 立即数生成
// ------------------------------
always_comb begin
    unique case (instr_type)
        I_TYPE : o_imm = {{20{i_instr[31]}}, i_instr[31:20]};                      // sign-extend imm[11:0]
        IZ_TYPE: o_imm = {20'h0, i_instr[31:20]};                                   // zero-extend imm[11:0]
        S_TYPE : o_imm = {{20{i_instr[31]}}, i_instr[31:25], i_instr[11:7]};       // sign-extend {imm[11:5], imm[4:0]}
        B_TYPE : o_imm = {{20{i_instr[31]}}, i_instr[7], i_instr[30:25], i_instr[11:8], 1'b0}; // sign-extend branch offset
        U_TYPE : o_imm = {i_instr[31:12], 12'b0};                                   // imm[31:12] << 12
        J_TYPE : o_imm = {{12{i_instr[31]}}, i_instr[19:12], i_instr[20], i_instr[30:21], 1'b0}; // sign-extend jump offset
        default: o_imm = 32'd0;
    endcase
end

// ------------------------------
// 源寄存器使能
// ------------------------------
always_comb begin
    unique case (instr_type)
        R_TYPE, S_TYPE, B_TYPE : begin
            o_src1_reg_en = 1'b1;
            o_src2_reg_en = 1'b1;
        end
        I_TYPE, IZ_TYPE : begin
            o_src1_reg_en = 1'b1;
            o_src2_reg_en = 1'b0;
        end
        default : begin
            o_src1_reg_en = 1'b0;
            o_src2_reg_en = 1'b0;
        end
    endcase
end

endmodule
