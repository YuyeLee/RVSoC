module isp_uart #(
    parameter  UART_RX_CLK_DIV = 108,   // 50MHz/4/115200Hz=108
    parameter  UART_TX_CLK_DIV = 434    // 50MHz/1/115200Hz=434
)(
    input  logic        clk,              // 时钟信号
    input  logic        i_uart_rx,        // UART接收数据线
    output logic        o_uart_tx,        // UART发送数据线
    output logic        o_rstn,           // 复位信号，低有效
    output logic [31:0] o_boot_addr,      // 输出Boot地址
    naive_bus.master    bus,              // 主总线接口，用于读写SoC资源
    naive_bus.slave     user_uart_bus     // 从设备UART接口（用户模式）
);

logic isp_uart_tx, user_uart_tx, isp_user_sel = 1'b0; // UART发送线选择（调试模式或用户模式）
logic [3:0] rstn_shift = 4'b0;                         // 延迟复位信号生成
logic uart_tx_line_fin, rx_ready, rd_ok = 1'b0, wr_ok = 1'b0, tx_start = 1'b0; // 控制发送与握手状态
logic [7:0] rx_data;                                  // 接收到的字符数据
logic [31:0] addr = 0, wr_data = 0;                   // 目标地址与写入数据寄存器
logic [7:0][7:0] rd_data_ascii;                       // 读取数据转为ASCII字符
logic [7:0][7:0] tx_data = 64'h0;                     // 要发送的ASCII字符数据

// FSM状态定义：解析串口指令
enum {NEW, CMD, OPEN, CLOSE, ADDR, EQUAL, DATA, FINAL, TRASH} fsm = NEW; 
// UART发送类型：用于指示何种模式的响应
enum {NONE, SELOPEN, SELCLOSE, RST} send_type = NONE;

// 字符匹配宏：便于处理常用命令格式（如"r addr" / "addr = data"）
`define  C  (rx_data=="r" || rx_data=="R")
`define  OP (rx_data=="o" || rx_data=="O")
`define  CL (rx_data=="s" || rx_data=="S")
`define  S  (rx_data==" " || rx_data=="\t")
`define  E  (rx_data=="\n" || rx_data=="\r")
`define  N  ((rx_data>="0" && rx_data<="9") || (rx_data>="a" && rx_data<="f") || (rx_data>="A" && rx_data<="F"))

// 将ASCII字符转换为4位十六进制值
function automatic logic [3:0] ascii2hex(input [7:0] ch);
    logic [7:0] rxbinary;
    if(ch >= "0" && ch <= "9") rxbinary = ch - "0";
    else if(ch >= "a" && ch <= "f") rxbinary = ch - "a" + 8'd10;
    else if(ch >= "A" && ch <= "F") rxbinary = ch - "A" + 8'd10;
    else rxbinary = 8'h0;
    return rxbinary[3:0];
endfunction

initial o_boot_addr = 0;  // 默认boot地址
assign o_rstn = rstn_shift[3];  // 延迟释放复位
assign o_uart_tx = isp_user_sel ? isp_uart_tx : user_uart_tx; // 根据模式选择UART发送源

// 初始化总线控制信号
initial begin
    bus.rd_req = 1'b0;
    bus.wr_req = 1'b0;
    bus.rd_addr = 0;
    bus.wr_addr = 0;
    bus.wr_data = 0;
end

assign bus.rd_be = 4'hf;  // 启用所有字节读
assign bus.wr_be = 4'hf;  // 启用所有字节写

// UART接收模块实例化
uart_rx #( .UART_RX_CLK_DIV(UART_RX_CLK_DIV) ) uart_rx_i (
    .clk(clk),
    .i_rx(i_uart_rx),
    .o_ready(rx_ready),
    .o_data(rx_data)
);

// UART发送模块（调试模式）
uart_tx_line #( .UART_TX_CLK_DIV(UART_TX_CLK_DIV) ) uart_tx_line_i (
    .clk(clk),
    .o_tx(isp_uart_tx),
    .i_start(tx_start),
    .o_fin(uart_tx_line_fin),
    .i_data(tx_data)
);

// UART发送模块（用户模式）
user_uart_tx #( .UART_TX_CLK_DIV(UART_TX_CLK_DIV) ) user_uart_in_isp_i (
    .clk(clk),
    .rstn(o_rstn),
    .o_uart_tx(user_uart_tx),
    .bus(user_uart_bus)
);

// 将读数据转为ASCII字符显示
generate
    genvar i;
    for(i = 0; i < 8; i++) begin : convert_binary_to_ascii
        always_comb begin
            if(bus.rd_data[3+4*i:4*i] > 4'h9)
                rd_data_ascii[i] = "a" - 8'd10 + bus.rd_data[3+4*i:4*i];
            else
                rd_data_ascii[i] = "0" + bus.rd_data[3+4*i:4*i];
        end
    end
endgenerate

// 读写成功标志更新
always_ff @(posedge clk) rd_ok <= (bus.rd_req & bus.rd_gnt);
always_ff @(posedge clk) wr_ok <= (bus.wr_req & bus.wr_gnt);

// UART发送逻辑，根据操作类型准备返回信息
always_ff @(posedge clk) begin
    if(rd_ok) begin
        tx_start <= 1'b1;
        send_type <= NONE;
        tx_data <= rd_data_ascii;  // 发送读取数据（ASCII）
    end else if(wr_ok) begin
        tx_start <= 1'b1;
        send_type <= NONE;
        tx_data <= "wr done ";  // 写完成反馈
    end else if(rx_ready && `E) begin
        if(!isp_user_sel) begin
            tx_start <= 1'b1;
            send_type <= SELCLOSE;
            tx_data <= "\r\ndebug "; // 进入debug模式提示
        end else if(fsm == CMD) begin
            tx_start <= 1'b1;
            send_type <= RST;
            tx_data <= "rst done"; // boot地址写入完成
        end else if(fsm == OPEN) begin
            tx_start <= 1'b1;
            send_type <= SELOPEN;
            tx_data <= "user    "; // 切换为用户模式
        end else if(fsm == TRASH) begin
            tx_start <= 1'b1;
            send_type <= NONE;
            tx_data <= "invalid "; // 无效命令提示
        end
    end else begin
        tx_start <= 1'b0;
        tx_data <= 64'h0;
    end
end

// 复位信号通过移位寄存器延迟释放
always_ff @(posedge clk)
    if(uart_tx_line_fin && send_type == RST)
        rstn_shift <= 4'h0; // 重新复位
    else
        rstn_shift <= {rstn_shift[2:0], 1'b1};

// 模式切换控制
always_ff @(posedge clk)
    if(uart_tx_line_fin && (send_type == RST || send_type == SELOPEN))
        isp_user_sel <= 1'b0; // 切换为用户模式
    else if(rx_ready && `E)
        isp_user_sel <= 1'b1; // 切换为调试模式

// 状态机执行串口命令解析
always_ff @(posedge clk) begin
    if(bus.rd_req && bus.rd_gnt) bus.rd_req <= 1'b0;
    else if(bus.wr_req && bus.wr_gnt) bus.wr_req <= 1'b0;
    else if(rx_ready) begin
        case(fsm)
            // 等待命令开头
            NEW: begin
                if(`C) begin fsm <= CMD; wr_data <= 0; end         // CMD: 设置boot地址
                else if(`OP) fsm <= OPEN;                          // OPEN: 切换为用户模式
                else if(`S || `E) begin fsm <= NEW; addr <= 0; wr_data <= 0; end
                else if(`N) begin fsm <= ADDR; addr <= {addr[27:0], ascii2hex(rx_data)}; end // 读写指令地址部分
                else fsm <= TRASH;
            end
            // 接收open后空格直到回车
            OPEN: begin
                if(`E) fsm <= NEW;
                else if(`S) fsm <= OPEN;
                else fsm <= TRASH;
            end
            // 接收设置boot地址的写数据
            CMD: begin
                if(`E) begin o_boot_addr <= {wr_data[31:2], 2'b00}; fsm <= NEW; addr <= 0; wr_data <= 0; end
                else if(`S) fsm <= CMD;
                else if(`N) begin wr_data <= {wr_data[27:0], ascii2hex(rx_data)}; fsm <= CMD; end
                else fsm <= TRASH;
            end
            // 接收读地址
            ADDR: begin
                if(`E) begin bus.rd_req <= 1'b1; bus.rd_addr <= addr; fsm <= NEW; addr <= 0; wr_data <= 0; end
                else if(`N) addr <= {addr[27:0], ascii2hex(rx_data)};
                else if(`S) fsm <= EQUAL; // 检查是否为写
                else fsm <= TRASH;
            end
            // 写操作，准备接收数据
            EQUAL: begin
                if(`E) begin bus.rd_req <= 1'b1; bus.rd_addr <= addr; fsm <= NEW; addr <= 0; wr_data <= 0; end
                else if(`N) begin wr_data <= {wr_data[27:0], ascii2hex(rx_data)}; fsm <= DATA; end
                else if(`S) fsm <= EQUAL;
                else fsm <= TRASH;
            end
            // 接收数据写入
            DATA: begin
                if(`E) begin bus.wr_req <= 1'b1; bus.wr_addr <= addr; bus.wr_data <= wr_data; fsm <= NEW; addr <= 0; wr_data <= 0; end
                else if(`N) wr_data <= {wr_data[27:0], ascii2hex(rx_data)};
                else if(`S) fsm <= FINAL;
                else fsm <= TRASH;
            end
            // 数据结束确认
            FINAL: begin
                if(`E) begin bus.wr_req <= 1'b1; bus.wr_addr <= addr; bus.wr_data <= wr_data; fsm <= NEW; addr <= 0; wr_data <= 0; end
                else if(`S) fsm <= FINAL;
                else fsm <= TRASH;
            end
            // 错误状态
            default: begin
                if(`E) begin fsm <= NEW; addr <= 0; wr_data <= 0; end
                else fsm <= TRASH;
            end
        endcase
    end
end

endmodule
