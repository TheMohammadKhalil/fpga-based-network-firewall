module fpga_firewall_top (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,
    output wire        s_axis_tready,
    output wire [7:0]  m_axis_tdata,
    output wire        m_axis_tvalid,
    output wire        m_axis_tlast,
    input  wire        m_axis_tready,
    input  wire        cfg_we,
    input  wire [3:0]  cfg_addr,
    input  wire [31:0] cfg_wdata,
    input  wire        crc_error_in,
    output wire        packet_allowed,
    output wire        packet_dropped
);

wire [47:0] allow_dst_mac;
wire [47:0] allow_src_mac;
wire [15:0] allow_ethertype;
wire [15:0] min_frame_length;
wire [15:0] max_frame_length;
wire        enforce_dst_mac;
wire        enforce_src_mac;
wire        enforce_ethertype;
wire        drop_crc_error;

wire [47:0] parsed_dst_mac;
wire [47:0] parsed_src_mac;
wire [15:0] parsed_ethertype;
wire [15:0] parsed_frame_length;
wire        parsed_header_valid;
wire        parsed_frame_done;

wire [47:0] ctx_dst_mac;
wire [47:0] ctx_src_mac;
wire [15:0] ctx_ethertype;
wire [15:0] ctx_frame_length;
wire        ctx_crc_error;
wire        ctx_valid;

wire [7:0]  rx_payload_tdata;
wire        rx_payload_tvalid;
wire        rx_payload_tlast;
wire        rx_payload_tready;
wire        frame_buffered;
wire [15:0] payload_length;

wire [7:0]  allowed_payload_tdata;
wire        allowed_payload_tvalid;
wire        allowed_payload_tlast;
wire        allowed_payload_tready;

firewall_regs firewall_regs_inst (
    .clk(clk),
    .rst(rst),
    .cfg_we(cfg_we),
    .cfg_addr(cfg_addr),
    .cfg_wdata(cfg_wdata),
    .allow_dst_mac(allow_dst_mac),
    .allow_src_mac(allow_src_mac),
    .allow_ethertype(allow_ethertype),
    .min_frame_length(min_frame_length),
    .max_frame_length(max_frame_length),
    .enforce_dst_mac(enforce_dst_mac),
    .enforce_src_mac(enforce_src_mac),
    .enforce_ethertype(enforce_ethertype),
    .drop_crc_error(drop_crc_error)
);

eth_header_extract eth_header_extract_inst (
    .clk(clk),
    .rst(rst),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tlast(s_axis_tlast),
    .dst_mac(parsed_dst_mac),
    .src_mac(parsed_src_mac),
    .ethertype(parsed_ethertype),
    .frame_length(parsed_frame_length),
    .header_valid(parsed_header_valid),
    .frame_done(parsed_frame_done)
);

header_context_store header_context_store_inst (
    .clk(clk),
    .rst(rst),
    .in_dst_mac(parsed_dst_mac),
    .in_src_mac(parsed_src_mac),
    .in_ethertype(parsed_ethertype),
    .in_frame_length(parsed_frame_length),
    .in_crc_error(crc_error_in),
    .header_valid(parsed_header_valid),
    .frame_done(parsed_frame_done),
    .out_dst_mac(ctx_dst_mac),
    .out_src_mac(ctx_src_mac),
    .out_ethertype(ctx_ethertype),
    .out_frame_length(ctx_frame_length),
    .out_crc_error(ctx_crc_error),
    .context_valid(ctx_valid)
);

firewall_rule_match firewall_rule_match_inst (
    .dst_mac(ctx_dst_mac),
    .src_mac(ctx_src_mac),
    .ethertype(ctx_ethertype),
    .frame_length(ctx_frame_length),
    .crc_error(ctx_crc_error),
    .allow_dst_mac(allow_dst_mac),
    .allow_src_mac(allow_src_mac),
    .allow_ethertype(allow_ethertype),
    .min_frame_length(min_frame_length),
    .max_frame_length(max_frame_length),
    .enforce_dst_mac(enforce_dst_mac),
    .enforce_src_mac(enforce_src_mac),
    .enforce_ethertype(enforce_ethertype),
    .drop_crc_error(drop_crc_error),
    .allow_packet(packet_allowed)
);

firewall_rx_parser firewall_rx_parser_inst (
    .clk(clk),
    .rst(rst),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tlast(s_axis_tlast),
    .s_axis_tready(s_axis_tready),
    .m_axis_tdata(rx_payload_tdata),
    .m_axis_tvalid(rx_payload_tvalid),
    .m_axis_tlast(rx_payload_tlast),
    .m_axis_tready(rx_payload_tready),
    .frame_buffered(frame_buffered),
    .payload_length(payload_length)
);

firewall_decision firewall_decision_inst (
    .clk(clk),
    .rst(rst),
    .allow_packet(packet_allowed),
    .s_axis_tdata(rx_payload_tdata),
    .s_axis_tvalid(rx_payload_tvalid),
    .s_axis_tlast(rx_payload_tlast),
    .s_axis_tready(rx_payload_tready),
    .m_axis_tdata(allowed_payload_tdata),
    .m_axis_tvalid(allowed_payload_tvalid),
    .m_axis_tlast(allowed_payload_tlast),
    .m_axis_tready(allowed_payload_tready),
    .drop_pulse(packet_dropped)
);

firewall_tx_rebuild firewall_tx_rebuild_inst (
    .clk(clk),
    .rst(rst),
    .dst_mac(ctx_dst_mac),
    .src_mac(ctx_src_mac),
    .ethertype(ctx_ethertype),
    .context_valid(ctx_valid),
    .s_axis_tdata(allowed_payload_tdata),
    .s_axis_tvalid(allowed_payload_tvalid),
    .s_axis_tlast(allowed_payload_tlast),
    .s_axis_tready(allowed_payload_tready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tlast(m_axis_tlast),
    .m_axis_tready(m_axis_tready)
);

endmodule
