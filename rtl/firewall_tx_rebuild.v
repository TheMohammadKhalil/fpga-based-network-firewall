module firewall_tx_rebuild (
    input  wire        clk,
    input  wire        rst,
    input  wire [47:0] dst_mac,
    input  wire [47:0] src_mac,
    input  wire [15:0] ethertype,
    input  wire        context_valid,
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,
    output wire        s_axis_tready,
    output wire [7:0]  m_axis_tdata,
    output wire        m_axis_tvalid,
    output wire        m_axis_tlast,
    input  wire        m_axis_tready
);

reg in_frame;
reg header_start_pulse;
reg context_valid_sync;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        in_frame           <= 1'b0;
        header_start_pulse <= 1'b0;
        context_valid_sync <= 1'b0;
    end else begin
        header_start_pulse <= 1'b0;
        context_valid_sync <= context_valid;

        if (!in_frame && s_axis_tvalid && context_valid_sync) begin
            in_frame           <= 1'b1;
            header_start_pulse <= 1'b1;
        end

        if (s_axis_tvalid && s_axis_tlast && s_axis_tready) begin
            in_frame <= 1'b0;
        end
    end
end

eth_header_insert eth_header_insert_inst (
    .clk(clk),
    .rst(rst),
    .dst_mac(dst_mac),
    .src_mac(src_mac),
    .ethertype(ethertype),
    .header_valid(header_start_pulse),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tvalid(s_axis_tvalid && context_valid_sync),
    .s_axis_tlast(s_axis_tlast),
    .s_axis_tready(s_axis_tready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tlast(m_axis_tlast),
    .m_axis_tready(m_axis_tready)
);

endmodule
