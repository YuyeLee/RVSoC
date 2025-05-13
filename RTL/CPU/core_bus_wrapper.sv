module core_bus_wrapper(
    input  logic        clk, rstn,             // 时钟与复位（低有效）
    input  logic        i_re, i_we,            // 读/写请求
    output logic        o_conflict,            // 总线冲突检测
    input  logic [ 2:0] i_funct3,              // 用于区分 load/store 类型（LW/LH/LB）
    input  logic [31:0] i_addr,                // 访问地址
    input  logic [31:0] i_wdata,               // 写入数据
    output logic [31:0] o_rdata,               // 读出数据

    naive_bus.master  bus_master               // 总线主设备接口
);

logic i_re_latch = 1'b0;               // 保存读请求信号
logic o_conflict_latch = 1'b0;         // 保存冲突信息
logic [1:0]  addr_lsb, rd_addr_lsb=2'b0; // 地址低2位，用于字节对齐
logic [31:0] addr_bus, wdata, rdata, rdata_latch=0;
logic [2:0]  rd_funct3 = 3'b0;         // 保存 funct3，用于回读
logic [3:0]  byte_enable;              // 字节使能

// 地址对齐（用于总线对齐32位）
assign addr_bus = {i_addr[31:2], 2'b00};
assign addr_lsb = i_addr[1:0];

// 冲突检测：发起请求但未授权即为冲突
assign o_conflict = (bus_master.rd_req & ~bus_master.rd_gnt) |
                    (bus_master.wr_req & ~bus_master.wr_gnt);

// 读通道接口赋值
assign bus_master.rd_req  = i_re;
assign bus_master.rd_be   = i_re ? byte_enable : 4'b0000;
assign bus_master.rd_addr = i_re ? addr_bus : 32'b0;
assign rdata = bus_master.rd_data;

// 写通道接口赋值
assign bus_master.wr_req  = i_we;
assign bus_master.wr_be   = i_we ? byte_enable : 4'b0000;
assign bus_master.wr_addr = i_we ? addr_bus : 32'b0;
assign bus_master.wr_data = i_we ? wdata     : 32'b0;

// ========= 字节使能逻辑 ========= //
// 依据 funct3 和地址对齐，决定哪几个字节有效
always_comb
    casex(i_funct3)
        3'bx00: // Byte (SB/LB)
            case(addr_lsb)
                2'b00: byte_enable <= 4'b0001;
                2'b01: byte_enable <= 4'b0010;
                2'b10: byte_enable <= 4'b0100;
                default: byte_enable <= 4'b1000;
            endcase
        3'bx01: // Halfword (SH/LH)
            case(addr_lsb)
                2'b00: byte_enable <= 4'b0011;
                2'b10: byte_enable <= 4'b1100;
                default: byte_enable <= 4'b0000;
            endcase
        3'b010: // Word (SW/LW)
            byte_enable <= (addr_lsb == 2'b00) ? 4'b1111 : 4'b0000;
        default:
            byte_enable <= 4'b0000;
    endcase

// ========= 写数据对齐逻辑 ========= //
always_comb
    case(i_funct3)
        3'b000: // SB
            case(addr_lsb)
                2'b00: wdata <= {24'b0, i_wdata[7:0]};
                2'b01: wdata <= {16'b0, i_wdata[7:0], 8'b0};
                2'b10: wdata <= {8'b0, i_wdata[7:0], 16'b0};
                default: wdata <= {i_wdata[7:0], 24'b0};
            endcase
        3'b001: // SH
            case(addr_lsb)
                2'b00: wdata <= {16'b0, i_wdata[15:0]};
                2'b10: wdata <= {i_wdata[15:0], 16'b0};
                default: wdata <= 32'b0;
            endcase
        3'b010: // SW
            wdata <= (addr_lsb == 2'b00) ? i_wdata : 32'b0;
        default:
            wdata <= 32'b0;
    endcase

// ========= 时序寄存 ========= //
always_ff @(posedge clk or negedge rstn)
    if(~rstn) begin
        i_re_latch        <= 1'b0;
        rd_addr_lsb       <= 2'b00;
        rd_funct3         <= 3'b000;
        o_conflict_latch  <= 1'b0;
        rdata_latch       <= 32'b0;
    end else begin
        i_re_latch        <= i_re;
        rd_addr_lsb       <= addr_lsb;
        rd_funct3         <= i_funct3;
        o_conflict_latch  <= o_conflict;
        rdata_latch       <= o_rdata;
    end

// ========= 读数据回传与扩展 ========= //
always_comb begin
    if(i_re_latch) begin
        if(~o_conflict_latch) begin
            case(rd_funct3)
                3'b000: // LB
                    case(rd_addr_lsb)
                        2'b00: o_rdata <= {{24{rdata[7]}}, rdata[7:0]};
                        2'b01: o_rdata <= {{24{rdata[15]}}, rdata[15:8]};
                        2'b10: o_rdata <= {{24{rdata[23]}}, rdata[23:16]};
                        default: o_rdata <= {{24{rdata[31]}}, rdata[31:24]};
                    endcase
                3'b100: // LBU
                    case(rd_addr_lsb)
                        2'b00: o_rdata <= {24'b0, rdata[7:0]};
                        2'b01: o_rdata <= {24'b0, rdata[15:8]};
                        2'b10: o_rdata <= {24'b0, rdata[23:16]};
                        default: o_rdata <= {24'b0, rdata[31:24]};
                    endcase
                3'b001: // LH
                    case(rd_addr_lsb)
                        2'b00: o_rdata <= {{16{rdata[15]}}, rdata[15:0]};
                        2'b10: o_rdata <= {{16{rdata[31]}}, rdata[31:16]};
                        default: o_rdata <= 32'b0;
                    endcase
                3'b101: // LHU
                    case(rd_addr_lsb)
                        2'b00: o_rdata <= {16'b0, rdata[15:0]};
                        2'b10: o_rdata <= {16'b0, rdata[31:16]};
                        default: o_rdata <= 32'b0;
                    endcase
                3'b010: // LW
                    o_rdata <= (rd_addr_lsb == 2'b00) ? rdata : 32'b0;
                default:
                    o_rdata <= 32'b0;
            endcase
        end else begin
            o_rdata <= 32'b0; // 读冲突返回 0
        end
    end else begin
        o_rdata <= rdata_latch; // 保持上一次读结果
    end
end

endmodule
