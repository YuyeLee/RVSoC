// 用户模式下的UART发送模块，支持FIFO缓冲写入字符并自动串行发送
module user_uart_tx #(
    parameter  UART_TX_CLK_DIV = 434    // UART波特率分频因子
)(
    input  logic     clk, rstn,         // 时钟与异步复位
    output logic     o_uart_tx,         // 串口TX输出
    naive_bus.slave  bus                // 从设备总线接口，用于主机写入字符
);

localparam TX_CNT = 5'd19;              // 一帧10位（含起止位），2×8bit字符+起止控制位

logic [9:0] fifo_rd_pointer = 10'h0, fifo_wr_pointer = 10'h0, fifo_len;
logic fifo_full, fifo_empty;
logic rd_addr_valid, wr_addr_valid;
logic [31:0] cnt = 0;
logic [4:0] tx_cnt = 0;
logic [7:0] tx_shift = 8'h0;
logic [7:0] fifo_rd_data = 8'h0;

initial o_uart_tx = 1'b1; // 默认高电平，空闲状态

assign rd_addr_valid = (bus.rd_addr[31:2] == 30'h0); // 地址解码
assign wr_addr_valid = (bus.wr_addr[31:2] == 30'h0);

assign fifo_len = fifo_wr_pointer - fifo_rd_pointer;
assign fifo_empty = (fifo_len == 10'h000);
assign fifo_full  = (fifo_len == 10'h3ff);

assign bus.rd_gnt = bus.rd_req; // 读总线始终握手

// 读取FIFO长度（仅支持地址0）
always @ (posedge clk or negedge rstn)
    if(~rstn)
        bus.rd_data <= 0;
    else if(bus.rd_req & rd_addr_valid)
        bus.rd_data <= {22'h0, fifo_len};
    else
        bus.rd_data <= 0;

// 写入地址判断与写使能
always_comb
    if(bus.wr_req && wr_addr_valid && bus.wr_be[0])
        bus.wr_gnt <= ~fifo_full;
    else
        bus.wr_gnt <= bus.wr_req;

// 写指针控制
always @ (posedge clk or negedge rstn)
    if(~rstn)
        fifo_wr_pointer <= 10'h0;
    else if(bus.wr_req & wr_addr_valid & bus.wr_be[0] & ~fifo_full)
        fifo_wr_pointer <= fifo_wr_pointer + 10'h1;

// 波特率计数器
always @ (posedge clk or negedge rstn)
    if(~rstn)
        cnt <= 0;
    else
        cnt <= (cnt < UART_TX_CLK_DIV - 1) ? cnt + 1 : 0;

// UART发送状态机：从FIFO中读取字符发送
always @ (posedge clk or negedge rstn) begin
    if(~rstn) begin
        fifo_rd_pointer <= 10'h0;
        o_uart_tx       <= 1'b1;
        tx_shift        <= 8'h00;
        tx_cnt          <= 5'h0;
    end else begin
        if(tx_cnt > 5'd0) begin
            if(cnt == 0) begin
                if(tx_cnt == TX_CNT) begin
                    // 起始位 + 数据位 + 停止位
                    {tx_shift, o_uart_tx} <= ~{fifo_rd_data, 1'b1};
                    fifo_rd_pointer <= fifo_rd_pointer + 10'h1;
                end else begin
                    {tx_shift, o_uart_tx} <= {1'b0, tx_shift[7:1], ~tx_shift[0]};
                end
                tx_cnt <= tx_cnt - 5'd1;
            end
        end else begin
            o_uart_tx <= 1'b1; // 空闲
            tx_cnt <= fifo_empty ? 5'd0 : TX_CNT; // 如果FIFO非空，启动发送
        end
    end
end

// FIFO实现
logic [7:0] fifo_ram [1024];

// 读取数据
always @ (posedge clk)
    fifo_rd_data <= fifo_ram[fifo_rd_pointer];

// 写入数据
always @ (posedge clk)
    if(bus.wr_req & wr_addr_valid & bus.wr_be[0] & ~fifo_full)
        fifo_ram[fifo_wr_pointer] <= bus.wr_data[7:0];

endmodule
