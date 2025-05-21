module uart_tx_line #(
    parameter  UART_TX_CLK_DIV = 434    // UART波特率分频因子，适用于115200bps@50MHz时钟
)(
    input  logic            clk,        // 时钟信号
    output logic            o_tx,       // UART发送引脚
    input  logic            i_start,    // 发送启动信号
    output logic            o_fin,      // 发送完成标志
    input  logic [7:0][7:0] i_data      // 要发送的8个ASCII字符
);

logic [31:0] cnt = 0;             // 波特率定时器
logic [6:0] tx_cnt = 0;           // 发送bit计数器（最多110位）
logic busy, busy_latch;           // 发送忙标志
logic [99:0] tx_buffer, tx_shift; // 发送缓冲与移位寄存器

initial tx_shift = 91'h0;
initial o_tx = 1'b1;              // UART空闲时为高电平
initial o_fin = 1'b0;

assign busy = (tx_cnt > 7'd0);    // 正在发送

// 延迟一拍保存busy，用于生成o_fin信号
always @ (posedge clk)
    busy_latch <= busy;

// 构造要发送的数据帧：起始位(0)，数据位(8位)，停止位(1)
// 共10bit × 9字符（包含\n）= 90bit，加2bit填充位（共92bit）
assign tx_buffer = {2'b11, 8'h0A,       // 最后一个字符：换行符\n（结束标志）
                    2'b01, i_data[0],   // 每个字符加起始与停止位
                    2'b01, i_data[1],
                    2'b01, i_data[2],
                    2'b01, i_data[3],
                    2'b01, i_data[4],
                    2'b01, i_data[5],
                    2'b01, i_data[6],
                    2'b01, i_data[7],
                    2'b01, 8'b11111111}; // 填充（安全边界）

// 波特率定时器逻辑
always @ (posedge clk)
    cnt <= (cnt < UART_TX_CLK_DIV - 1) ? cnt + 1 : 0;

// 发送状态机：每UART_TX_CLK_DIV个周期发送1位
always @ (posedge clk) begin
    if(busy) begin
        if(cnt == 0) begin
            {tx_shift, o_tx} <= {1'b1, tx_shift}; // 右移发送数据
            tx_cnt <= tx_cnt - 7'd1;              // 减少剩余bit数
        end
    end else begin
        o_tx <= 1'b1; // 空闲态保持高电平
        if(i_start) begin
            tx_cnt   <= 7'd110;       // 设置需要发送的总bit数（11字节 × 10位）
            tx_shift <= tx_buffer;    // 加载发送数据
        end else begin
            tx_cnt <= 7'd0;
        end
    end
end

// 当busy从高变低时，发送完成
always @ (posedge clk)
    o_fin <= (busy_latch & ~busy);

endmodule
