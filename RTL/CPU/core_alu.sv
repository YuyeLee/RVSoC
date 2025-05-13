module core_alu(
    input  logic [ 6:0] i_opcode,      // 指令 opcode 字段
    input  logic [ 6:0] i_funct7,      // 指令 funct7 字段（用于区分操作类型）
    input  logic [ 2:0] i_funct3,      // 指令 funct3 字段
    input  logic [31:0] i_num1u,       // 第一个操作数（无符号）
    input  logic [31:0] i_num2u,       // 第二个操作数（无符号）
    input  logic [31:0] i_pc,          // 当前 PC 值
    input  logic [31:0] i_immu,        // 立即数（无符号）
    
    output logic        o_branch_jalr,         // 是否为分支跳转（JALR/Branch）
    output logic [31:0] o_branch_jalr_target,  // 分支目标地址
    output logic [31:0] o_res                 // ALU 运算结果
);

logic [ 4:0] shamt_rs, shamt_imm;
logic [31:0] num1_plus_imm, pc_plus_imm;
logic signed [31:0] i_num1s, i_num2s, i_imms;

// 一些预先计算好的辅助信号
assign shamt_imm     = i_immu[4:0];       // 移位立即数
assign shamt_rs      = i_num2u[4:0];      // 移位寄存器值
assign num1_plus_imm = i_num1u + i_immu;  // base + offset
assign pc_plus_imm   = i_pc    + i_immu;  // PC 相对跳转
assign i_num1s       = i_num1u;           // 转换为有符号，用于比较
assign i_num2s       = i_num2u;
assign i_imms        = i_immu;

// ===============================
// 分支处理（BRANCH / JALR）
// ===============================
always_comb begin
    // 默认值（非分支）
    o_branch_jalr = 1'b0;
    o_branch_jalr_target = 32'd0;

    case(i_opcode)
        7'b1100111 : begin // JALR
            o_branch_jalr = 1'b1;
            o_branch_jalr_target = num1_plus_imm;
        end
        7'b1100011 : begin // BRANCH 类指令
            o_branch_jalr_target = pc_plus_imm;
            case(i_funct3)
                3'b000 : o_branch_jalr = (i_num1u == i_num2u);   // BEQ
                3'b001 : o_branch_jalr = (i_num1u != i_num2u);   // BNE
                3'b100 : o_branch_jalr = (i_num1s <  i_num2s);   // BLT
                3'b101 : o_branch_jalr = (i_num1s >= i_num2s);   // BGE
                3'b110 : o_branch_jalr = (i_num1u <  i_num2u);   // BLTU
                3'b111 : o_branch_jalr = (i_num1u >= i_num2u);   // BGEU
                default: o_branch_jalr = 1'b0;
            endcase
        end
        default : ; // 非分支指令不处理
    endcase
end

// ===============================
// 核心 ALU 运算逻辑
// ===============================
always_comb begin
    o_res = 32'd0; // 默认结果为 0

    casex({i_funct7, i_funct3, i_opcode})
        // 跳转类（返回地址）
        17'bxxxxxxx_xxx_110x111 : o_res = i_pc + 4;                     // JAL/JALR

        // LUI 和 AUIPC
        17'bxxxxxxx_xxx_0110111 : o_res = i_immu;                       // LUI
        17'bxxxxxxx_xxx_0010111 : o_res = pc_plus_imm;                 // AUIPC

        // 算术类
        17'b0000000_000_0110011 : o_res = i_num1u + i_num2u;           // ADD
        17'bxxxxxxx_000_0010011 : o_res = num1_plus_imm;               // ADDI
        17'b0100000_000_0110011 : o_res = i_num1u - i_num2u;           // SUB

        // 逻辑类
        17'b0000000_100_0110011 : o_res = i_num1u ^ i_num2u;           // XOR
        17'bxxxxxxx_100_0010011 : o_res = i_num1u ^ i_immu;            // XORI
        17'b0000000_110_0110011 : o_res = i_num1u | i_num2u;           // OR
        17'bxxxxxxx_110_0010011 : o_res = i_num1u | i_immu;            // ORI
        17'b0000000_111_0110011 : o_res = i_num1u & i_num2u;           // AND
        17'bxxxxxxx_111_0010011 : o_res = i_num1u & i_immu;            // ANDI

        // 移位类
        17'b0000000_001_0110011 : o_res = i_num1u << shamt_rs;         // SLL
        17'b0000000_001_0010011 : o_res = i_num1u << shamt_imm;        // SLLI
        17'b0000000_101_0110011 : o_res = i_num1u >> shamt_rs;         // SRL
        17'b0000000_101_0010011 : o_res = i_num1u >> shamt_imm;        // SRLI
        17'b0100000_101_0110011 : begin                                // SRA
            o_res = i_num1u >> shamt_rs;
            for(int i=0; i<shamt_rs; i++) o_res[31-i] = i_num1u[31];   // 补符号位
        end
        17'b0100000_101_0010011 : begin                                // SRAI
            o_res = i_num1u >> shamt_imm;
            for(int i=0; i<shamt_imm; i++) o_res[31-i] = i_num1u[31];
        end

        // 条件设置类（SLT系列）
        17'b0000000_010_0110011 : o_res = (i_num1s < i_num2s) ? 1 : 0; // SLT
        17'bxxxxxxx_010_0010011 : o_res = (i_num1s < i_imms ) ? 1 : 0; // SLTI
        17'b0000000_011_0110011 : o_res = (i_num1u < i_num2u) ? 1 : 0; // SLTU
        17'bxxxxxxx_011_0010011 : o_res = (i_num1u < i_immu ) ? 1 : 0; // SLTIU

        // 默认
        default : o_res = 32'd0;
    endcase
end

endmodule
