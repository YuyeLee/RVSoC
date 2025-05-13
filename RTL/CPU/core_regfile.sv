module core_regfile(
    input  logic clk, rstn,                   // 时钟与异步复位（低有效）
    input  logic rd_latch,                    // 读取保持信号

    // Read port 1
    input  logic        i_re1,                // 是否读取 rs1
    input  logic [4:0]  i_raddr1,             // 读地址1
    output logic [31:0] o_rdata1,             // 读数据1

    // Read port 2
    input  logic        i_re2,                // 是否读取 rs2
    input  logic [4:0]  i_raddr2,
    output logic [31:0] o_rdata2,

    // Forward port 1
    input  logic        i_forward1,
    input  logic [4:0]  i_faddr1,
    input  logic [31:0] i_fdata1,

    // Forward port 2
    input  logic        i_forward2,
    input  logic [4:0]  i_faddr2,
    input  logic [31:0] i_fdata2,

    // Write port
    input  logic        i_we,
    input  logic [4:0]  i_waddr,
    input  logic [31:0] i_wdata
);

// -----------------------------
// Internal Registers
// -----------------------------
logic [31:0] regfile [0:31];           // 32 个 32 位寄存器（x0 ~ x31）
logic [31:0] reg_rdata1 = 0, reg_rdata2 = 0;

logic from_fw1 = 0, from_fw2 = 0;
logic [31:0] forward_data1 = 0, forward_data2 = 0;

// -----------------------------
// Read logic with forwarding/masking
// -----------------------------
assign o_rdata1 = from_fw1 ? forward_data1 : reg_rdata1;
assign o_rdata2 = from_fw2 ? forward_data2 : reg_rdata2;

// -----------------------------
// Read mux for port 1
// -----------------------------
always_ff @(posedge clk or negedge rstn)
    if(~rstn) begin
        from_fw1      <= 1'b0;
        forward_data1 <= 32'd0;
    end else begin
        if(rd_latch) begin
            from_fw1      <= 1'b1;
            forward_data1 <= o_rdata1; // 保持当前读取结果
        end else if(~i_re1 || i_raddr1 == 5'd0) begin
            from_fw1      <= 1'b1;
            forward_data1 <= 32'd0;    // x0 恒为 0
        end else if(i_forward1 && i_faddr1 == i_raddr1) begin
            from_fw1      <= 1'b1;
            forward_data1 <= i_fdata1;
        end else if(i_forward2 && i_faddr2 == i_raddr1) begin
            from_fw1      <= 1'b1;
            forward_data1 <= i_fdata2;
        end else if(i_we && i_waddr == i_raddr1) begin
            from_fw1      <= 1'b1;
            forward_data1 <= i_wdata;
        end else begin
            from_fw1      <= 1'b0;
            forward_data1 <= 32'd0;
        end
    end

// -----------------------------
// Read mux for port 2
// -----------------------------
always_ff @(posedge clk or negedge rstn)
    if(~rstn) begin
        from_fw2      <= 1'b0;
        forward_data2 <= 32'd0;
    end else begin
        if(rd_latch) begin
            from_fw2      <= 1'b1;
            forward_data2 <= o_rdata2;
        end else if(~i_re2 || i_raddr2 == 5'd0) begin
            from_fw2      <= 1'b1;
            forward_data2 <= 32'd0;
        end else if(i_forward1 && i_faddr1 == i_raddr2) begin
            from_fw2      <= 1'b1;
            forward_data2 <= i_fdata1;
        end else if(i_forward2 && i_faddr2 == i_raddr2) begin
            from_fw2      <= 1'b1;
            forward_data2 <= i_fdata2;
        end else if(i_we && i_waddr == i_raddr2) begin
            from_fw2      <= 1'b1;
            forward_data2 <= i_wdata;
        end else begin
            from_fw2      <= 1'b0;
            forward_data2 <= 32'd0;
        end
    end

// -----------------------------
// Register Read & Write
// -----------------------------
always_ff @(posedge clk)
    reg_rdata1 <= regfile[i_raddr1];

always_ff @(posedge clk)
    reg_rdata2 <= regfile[i_raddr2];

// 写操作（注意 x0 恒为 0）
always_ff @(posedge clk)
    if(i_we && i_waddr != 5'd0)
        regfile[i_waddr] <= i_wdata;

endmodule
