module uart_rx #(
    parameter  UART_RX_CLK_DIV = 108   // UART波特率分频因子，适用于115200bps@50MHz时钟
)(
    input  logic       clk,        // 时钟信号
    input  logic       i_rx,       // UART接收输入引脚
    output logic       o_ready,    // 数据接收完成标志（高电平有效）
    output logic [7:0] o_data      // 接收的8位数据
);

logic rx_bit;                     // 当前采样到的稳定位
logic busy;                       // 是否处于接收状态
logic last_busy = 1'b0;           // 上一个周期的busy，用于产生ready脉冲
logic [5:0] shift = 6'h0;         // 用于检测起始位的窗口（检测0 -> 开始接收）
logic [5:0] status = 6'h0;        // 当前接收状态：0=空闲，1~10=接收bit，>10=数据处理
logic [7:0] databuf = 8'h0;       // 接收缓冲区（从LSB开始填充）
logic [31:0] cnt = 0;             // 用于位时钟分频计数器

initial o_ready = 1'b0;
initial o_data  = 8'h0;

assign busy = (status != 6'h0);   // status非0即表示正在接收

// 多路判决判断接收位rx_bit是否为有效的稳定电平
assign rx_bit = (shift[0] & shift[1]) | (shift[0] & i_rx) | (shift[1] & i_rx);

// 用于识别从忙到闲（说明接收完成）
always @ (posedge clk)
    last_busy <= busy;

// 接收完成后一个周期输出o_ready
always @ (posedge clk)
    o_ready <= (~busy & last_busy);

// 波特率定时器
always @ (posedge clk)
    cnt <= (cnt < UART_RX_CLK_DIV - 1) ? cnt + 1 : 0;

// 接收状态机：波特率时钟有效时采样数据
always @ (posedge clk) begin
    if(cnt == 0) begin
        if(~busy) begin
            // 检测到起始位（连续采到多个低电平）
            if(shift == 6'b111000)
                status <= 6'h1;  // 开始接收第1位数据
        end else begin
            if(status[5] == 1'b0) begin
                // 正在接收数据位
                if(status[1:0] == 2'b11) // 每4个周期采样一次，保证采样在位中间
                    databuf <= {rx_bit, databuf[7:1]};
                status <= status + 6'h1;
            end else begin
                // 接收结束后将数据输出
                if(status < 62) begin
                    status <= 6'd62;     // 延迟1周期输出数据
                    o_data <= databuf;
                end else begin
                    status <= status + 6'd1; // 恢复到空闲状态
                end
            end
        end
        // 移动采样窗口：用于稳定检测
        shift <= shift << 1;
        shift[0] <= i_rx;
    end
end

endmodule
