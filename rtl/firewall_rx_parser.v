module firewall_rx_parser #(
    parameter MAX_FRAME_BYTES = 2048,
    parameter PTR_W = 11
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,
    output wire        s_axis_tready,
    output reg  [7:0]  m_axis_tdata,
    output reg         m_axis_tvalid,
    output reg         m_axis_tlast,
    input  wire        m_axis_tready,
    output reg         frame_buffered,
    output reg  [15:0] payload_length
);

reg [7:0] payload_mem [0:MAX_FRAME_BYTES-1];
reg [PTR_W-1:0] rd_ptr;
reg [15:0]      byte_count;
reg [15:0]      payload_count;
reg             buffering;
reg             streaming;

// Ready to accept RX data whenever not in the streaming-out phase.
// During buffering we keep accepting; tready=0 only when we are replaying
// the buffered payload so that no new frame clobbers the buffer.
assign s_axis_tready = !streaming;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rd_ptr         <= {PTR_W{1'b0}};
        byte_count     <= 16'd0;
        payload_count  <= 16'd0;
        payload_length <= 16'd0;
        buffering      <= 1'b0;
        streaming      <= 1'b0;
        frame_buffered <= 1'b0;
        m_axis_tdata   <= 8'd0;
        m_axis_tvalid  <= 1'b0;
        m_axis_tlast   <= 1'b0;
    end else begin
        m_axis_tvalid <= 1'b0;
        m_axis_tlast  <= 1'b0;

        // Buffering phase: capture incoming frame.
        // Accept data whenever valid and not in the streaming-out phase.
        // The s_axis_tready == !streaming, so data arrives when !streaming.
        if (!streaming && s_axis_tvalid) begin
            if (!buffering) begin
                // First byte of a new frame — start buffering, byte_count=0
                buffering     <= 1'b1;
                byte_count    <= 16'd1;   // first byte consumed this cycle
                payload_count <= 16'd0;
                // byte 0 is never payload (header starts here), no store needed
            end else begin
                // Subsequent bytes of the same frame
                if (byte_count >= 16'd14 && payload_count < MAX_FRAME_BYTES) begin
                    payload_mem[payload_count[PTR_W-1:0]] <= s_axis_tdata;
                    payload_count <= payload_count + 16'd1;
                end

                if (s_axis_tlast) begin
                    buffering      <= 1'b0;
                    payload_length <= payload_count;
                    frame_buffered <= 1'b1;
                    streaming      <= 1'b1;
                    rd_ptr         <= {PTR_W{1'b0}};
                end else begin
                    byte_count <= byte_count + 16'd1;
                end
            end
        end

        // Streaming phase: output buffered payload
        if (streaming && frame_buffered && m_axis_tready) begin
            if (rd_ptr < payload_length) begin
                m_axis_tdata  <= payload_mem[rd_ptr];
                m_axis_tvalid <= 1'b1;
                if (rd_ptr == payload_length - 1'b1) begin
                    m_axis_tlast  <= 1'b1;
                    streaming     <= 1'b0;
                    frame_buffered<= 1'b0;
                    rd_ptr        <= {PTR_W{1'b0}};
                    payload_count <= 16'd0;
                end else begin
                    rd_ptr <= rd_ptr + 1'b1;
                end
            end else begin
                streaming      <= 1'b0;
                frame_buffered <= 1'b0;
                rd_ptr         <= {PTR_W{1'b0}};
                payload_count  <= 16'd0;
            end
        end
    end
end

endmodule
