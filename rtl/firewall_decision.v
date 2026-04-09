module firewall_decision (
    input  wire       clk,
    input  wire       rst,
    input  wire       allow_packet,
    input  wire [7:0] s_axis_tdata,
    input  wire       s_axis_tvalid,
    input  wire       s_axis_tlast,
    output wire       s_axis_tready,
    output reg  [7:0] m_axis_tdata,
    output reg        m_axis_tvalid,
    output reg        m_axis_tlast,
    input  wire       m_axis_tready,
    output reg        drop_pulse
);

assign s_axis_tready = m_axis_tready || !allow_packet;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        m_axis_tdata  <= 8'd0;
        m_axis_tvalid <= 1'b0;
        m_axis_tlast  <= 1'b0;
        drop_pulse    <= 1'b0;
    end else begin
        m_axis_tvalid <= 1'b0;
        m_axis_tlast  <= 1'b0;
        drop_pulse    <= 1'b0;

        if (s_axis_tvalid) begin
            if (allow_packet) begin
                if (m_axis_tready) begin
                    m_axis_tdata  <= s_axis_tdata;
                    m_axis_tvalid <= 1'b1;
                    m_axis_tlast  <= s_axis_tlast;
                end
            end else if (s_axis_tlast) begin
                drop_pulse <= 1'b1;
            end
        end
    end
end

endmodule
