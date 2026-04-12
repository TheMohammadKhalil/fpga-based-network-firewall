// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * FPGA Firewall Top-Level  —  L2 + L3/L4 packet filter
 *
 * Pipeline
 * --------
 *  MAC RX (AXI-Stream byte) ──┬─► eth_header_extract   (L2 fields)
 *                              ├─► ip_header_extract    (L3 fields, IPv4)
 *                              └─► tcp_udp_header_extract (L4 src/dst ports)
 *                                         │
 *                              header_context_store    (stable snapshot)
 *                                         │
 *                     ┌─────────────────  ┤  ──────────────────────┐
 *              firewall_rule_match (L2)   │   firewall_l3_rule_match
 *              (MAC/EtherType/length/CRC) │   (IP addr + port rules)
 *                     └──────────── AND ──┘
 *                                         │
 *                              firewall_rx_parser  (frame buffer)
 *                                         │
 *                              firewall_decision   (gate)
 *                                         │
 *                              firewall_tx_rebuild (prepend L2 header)
 *                                         │
 *                                      MAC TX
 *
 * Configuration bus (8-bit address)
 * ----------------------------------
 *  0x00-0x07 : L2 config registers  (see firewall_regs.v)
 *  0x10      : L3 rule table index selector
 *  0x11-0x17 : L3 rule fields for selected rule  (see firewall_rule_table.v)
 */
module fpga_firewall_top (
    input  wire        clk,
    input  wire        rst,

    // Input AXI-Stream (from MAC RX)
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,
    output wire        s_axis_tready,

    // Output AXI-Stream (to MAC TX)
    output wire [7:0]  m_axis_tdata,
    output wire        m_axis_tvalid,
    output wire        m_axis_tlast,
    input  wire        m_axis_tready,

    // Configuration bus (8-bit address)
    input  wire        cfg_we,
    input  wire [7:0]  cfg_addr,
    input  wire [31:0] cfg_wdata,

    // CRC error flag from MAC
    input  wire        crc_error_in,

    // Status
    output wire        packet_allowed,
    output wire        packet_dropped
);

// ==========================================================================
// L2 configuration registers
// ==========================================================================
wire [47:0] allow_dst_mac;
wire [47:0] allow_src_mac;
wire [15:0] allow_ethertype;
wire [15:0] min_frame_length;
wire [15:0] max_frame_length;
wire        enforce_dst_mac;
wire        enforce_src_mac;
wire        enforce_ethertype;
wire        drop_crc_error;

firewall_regs firewall_regs_inst (
    .clk(clk),
    .rst(rst),
    .cfg_we(cfg_we && (cfg_addr[7:4] == 4'h0)), // respond to addr 0x00-0x0F
    .cfg_addr(cfg_addr[3:0]),
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

// ==========================================================================
// L2 header parser
// ==========================================================================
wire [47:0] parsed_dst_mac;
wire [47:0] parsed_src_mac;
wire [15:0] parsed_ethertype;
wire [15:0] parsed_frame_length;
wire        parsed_header_valid;
wire        parsed_frame_done;

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

// ==========================================================================
// L3 header parser (IPv4)
// ==========================================================================
wire        ip_is_ipv4;
wire        ip_is_fragment;
wire [3:0]  ip_version;
wire [3:0]  ip_ihl;
wire [5:0]  ip_dscp;
wire [1:0]  ip_ecn;
wire [15:0] ip_total_length;
wire [15:0] ip_identification;
wire [2:0]  ip_flags;
wire [12:0] ip_frag_offset;
wire [7:0]  ip_ttl;
wire [7:0]  ip_protocol;
wire [15:0] ip_hdr_checksum;
wire [31:0] ip_src;
wire [31:0] ip_dst;
wire        ip_header_valid;
// (ip frame_done is the same stream — use parsed_frame_done)

ip_header_extract ip_header_extract_inst (
    .clk(clk),
    .rst(rst),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tlast(s_axis_tlast),
    .ip_version(ip_version),
    .ip_ihl(ip_ihl),
    .ip_dscp(ip_dscp),
    .ip_ecn(ip_ecn),
    .ip_total_length(ip_total_length),
    .ip_identification(ip_identification),
    .ip_flags(ip_flags),
    .ip_frag_offset(ip_frag_offset),
    .ip_ttl(ip_ttl),
    .ip_protocol(ip_protocol),
    .ip_hdr_checksum(ip_hdr_checksum),
    .ip_src(ip_src),
    .ip_dst(ip_dst),
    .is_ipv4(ip_is_ipv4),
    .ip_is_fragment(ip_is_fragment),
    .ip_header_valid(ip_header_valid),
    .frame_done()   // shared with L2 frame_done
);

// ==========================================================================
// L4 header parser (TCP / UDP ports)
// ==========================================================================
wire [15:0] l4_src_port;
wire [15:0] l4_dst_port;
wire [31:0] tcp_seq_num;
wire [31:0] tcp_ack_num;
wire [7:0]  tcp_flags;
wire [15:0] tcp_window;
wire        l4_header_valid;

tcp_udp_header_extract tcp_udp_header_extract_inst (
    .clk(clk),
    .rst(rst),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tlast(s_axis_tlast),
    .l4_src_port(l4_src_port),
    .l4_dst_port(l4_dst_port),
    .tcp_seq_num(tcp_seq_num),
    .tcp_ack_num(tcp_ack_num),
    .tcp_flags(tcp_flags),
    .tcp_window(tcp_window),
    .l4_header_valid(l4_header_valid),
    .frame_done()   // shared with L2 frame_done
);

// ==========================================================================
// Header context store (latches all parsed fields)
// ==========================================================================
wire [47:0] ctx_dst_mac;
wire [47:0] ctx_src_mac;
wire [15:0] ctx_ethertype;
wire [15:0] ctx_frame_length;
wire        ctx_crc_error;
wire        ctx_is_ipv4;
wire        ctx_ip_is_fragment;
wire [3:0]  ctx_ip_version;
wire [3:0]  ctx_ip_ihl;
wire [5:0]  ctx_ip_dscp;
wire [1:0]  ctx_ip_ecn;
wire [15:0] ctx_ip_total_length;
wire [15:0] ctx_ip_identification;
wire [2:0]  ctx_ip_flags;
wire [12:0] ctx_ip_frag_offset;
wire [7:0]  ctx_ip_ttl;
wire [7:0]  ctx_ip_protocol;
wire [15:0] ctx_ip_hdr_checksum;
wire [31:0] ctx_ip_src;
wire [31:0] ctx_ip_dst;
wire [15:0] ctx_l4_src_port;
wire [15:0] ctx_l4_dst_port;
wire [31:0] ctx_tcp_seq_num;
wire [31:0] ctx_tcp_ack_num;
wire [7:0]  ctx_tcp_flags;
wire [15:0] ctx_tcp_window;
wire        ctx_valid;

header_context_store header_context_store_inst (
    .clk(clk),
    .rst(rst),
    // L2
    .in_dst_mac(parsed_dst_mac),
    .in_src_mac(parsed_src_mac),
    .in_ethertype(parsed_ethertype),
    .in_frame_length(parsed_frame_length),
    .in_crc_error(crc_error_in),
    .header_valid(parsed_header_valid),
    .frame_done(parsed_frame_done),
    // L3
    .is_ipv4(ip_is_ipv4),
    .ip_is_fragment(ip_is_fragment),
    .ip_version(ip_version),
    .ip_ihl(ip_ihl),
    .ip_dscp(ip_dscp),
    .ip_ecn(ip_ecn),
    .ip_total_length(ip_total_length),
    .ip_identification(ip_identification),
    .ip_flags(ip_flags),
    .ip_frag_offset(ip_frag_offset),
    .ip_ttl(ip_ttl),
    .ip_protocol(ip_protocol),
    .ip_hdr_checksum(ip_hdr_checksum),
    .ip_src(ip_src),
    .ip_dst(ip_dst),
    .ip_header_valid(ip_header_valid),
    // L4
    .l4_src_port(l4_src_port),
    .l4_dst_port(l4_dst_port),
    .tcp_seq_num(tcp_seq_num),
    .tcp_ack_num(tcp_ack_num),
    .tcp_flags(tcp_flags),
    .tcp_window(tcp_window),
    .l4_header_valid(l4_header_valid),
    // Outputs
    .out_dst_mac(ctx_dst_mac),
    .out_src_mac(ctx_src_mac),
    .out_ethertype(ctx_ethertype),
    .out_frame_length(ctx_frame_length),
    .out_crc_error(ctx_crc_error),
    .out_is_ipv4(ctx_is_ipv4),
    .out_ip_is_fragment(ctx_ip_is_fragment),
    .out_ip_version(ctx_ip_version),
    .out_ip_ihl(ctx_ip_ihl),
    .out_ip_dscp(ctx_ip_dscp),
    .out_ip_ecn(ctx_ip_ecn),
    .out_ip_total_length(ctx_ip_total_length),
    .out_ip_identification(ctx_ip_identification),
    .out_ip_flags(ctx_ip_flags),
    .out_ip_frag_offset(ctx_ip_frag_offset),
    .out_ip_ttl(ctx_ip_ttl),
    .out_ip_protocol(ctx_ip_protocol),
    .out_ip_hdr_checksum(ctx_ip_hdr_checksum),
    .out_ip_src(ctx_ip_src),
    .out_ip_dst(ctx_ip_dst),
    .out_l4_src_port(ctx_l4_src_port),
    .out_l4_dst_port(ctx_l4_dst_port),
    .out_tcp_seq_num(ctx_tcp_seq_num),
    .out_tcp_ack_num(ctx_tcp_ack_num),
    .out_tcp_flags(ctx_tcp_flags),
    .out_tcp_window(ctx_tcp_window),
    .context_valid(ctx_valid)
);

// ==========================================================================
// L2 rule match (combinational)
// ==========================================================================
wire l2_allow;

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
    .allow_packet(l2_allow)
);

// ==========================================================================
// L3 rule table
// ==========================================================================
localparam NUM_RULES = 8;

wire [NUM_RULES-1:0] rt_rule_valid;
wire [NUM_RULES-1:0] rt_rule_action;
wire [NUM_RULES-1:0] rt_rule_match_src_ip;
wire [NUM_RULES-1:0] rt_rule_match_dst_ip;
wire [NUM_RULES-1:0] rt_rule_match_protocol;
wire [NUM_RULES-1:0] rt_rule_match_src_port;
wire [NUM_RULES-1:0] rt_rule_match_dst_port;
wire [NUM_RULES-1:0] rt_rule_block_fragments;
wire [8*NUM_RULES-1:0]  rt_rule_protocol;
wire [32*NUM_RULES-1:0] rt_rule_src_ip;
wire [32*NUM_RULES-1:0] rt_rule_src_mask;
wire [32*NUM_RULES-1:0] rt_rule_dst_ip;
wire [32*NUM_RULES-1:0] rt_rule_dst_mask;
wire [16*NUM_RULES-1:0] rt_rule_src_port_min;
wire [16*NUM_RULES-1:0] rt_rule_src_port_max;
wire [16*NUM_RULES-1:0] rt_rule_dst_port_min;
wire [16*NUM_RULES-1:0] rt_rule_dst_port_max;

firewall_rule_table #(.NUM_RULES(NUM_RULES))
firewall_rule_table_inst (
    .clk(clk),
    .rst(rst),
    .cfg_we(cfg_we && (cfg_addr[7:4] == 4'h1)), // respond to addr 0x10-0x1F
    .cfg_addr(cfg_addr),
    .cfg_wdata(cfg_wdata),
    .rule_valid(rt_rule_valid),
    .rule_action(rt_rule_action),
    .rule_match_src_ip(rt_rule_match_src_ip),
    .rule_match_dst_ip(rt_rule_match_dst_ip),
    .rule_match_protocol(rt_rule_match_protocol),
    .rule_match_src_port(rt_rule_match_src_port),
    .rule_match_dst_port(rt_rule_match_dst_port),
    .rule_block_fragments(rt_rule_block_fragments),
    .rule_protocol(rt_rule_protocol),
    .rule_src_ip(rt_rule_src_ip),
    .rule_src_mask(rt_rule_src_mask),
    .rule_dst_ip(rt_rule_dst_ip),
    .rule_dst_mask(rt_rule_dst_mask),
    .rule_src_port_min(rt_rule_src_port_min),
    .rule_src_port_max(rt_rule_src_port_max),
    .rule_dst_port_min(rt_rule_dst_port_min),
    .rule_dst_port_max(rt_rule_dst_port_max)
);

// ==========================================================================
// L3/L4 rule match (combinational, 8 rules in parallel)
// ==========================================================================
wire l3_allow;

firewall_l3_rule_match #(.NUM_RULES(NUM_RULES))
firewall_l3_rule_match_inst (
    .is_ipv4(ctx_is_ipv4),
    .ip_is_fragment(ctx_ip_is_fragment),
    .ip_protocol(ctx_ip_protocol),
    .ip_src(ctx_ip_src),
    .ip_dst(ctx_ip_dst),
    .l4_src_port(ctx_l4_src_port),
    .l4_dst_port(ctx_l4_dst_port),
    .rule_valid(rt_rule_valid),
    .rule_action(rt_rule_action),
    .rule_match_src_ip(rt_rule_match_src_ip),
    .rule_match_dst_ip(rt_rule_match_dst_ip),
    .rule_match_protocol(rt_rule_match_protocol),
    .rule_match_src_port(rt_rule_match_src_port),
    .rule_match_dst_port(rt_rule_match_dst_port),
    .rule_block_fragments(rt_rule_block_fragments),
    .rule_protocol(rt_rule_protocol),
    .rule_src_ip(rt_rule_src_ip),
    .rule_src_mask(rt_rule_src_mask),
    .rule_dst_ip(rt_rule_dst_ip),
    .rule_dst_mask(rt_rule_dst_mask),
    .rule_src_port_min(rt_rule_src_port_min),
    .rule_src_port_max(rt_rule_src_port_max),
    .rule_dst_port_min(rt_rule_dst_port_min),
    .rule_dst_port_max(rt_rule_dst_port_max),
    .allow_packet(l3_allow)
);

// Final decision: packet must pass BOTH L2 and L3/L4 checks
assign packet_allowed = l2_allow && l3_allow;

// ==========================================================================
// Frame buffer (stores Ethernet payload after L2 header)
// ==========================================================================
wire [7:0]  rx_payload_tdata;
wire        rx_payload_tvalid;
wire        rx_payload_tlast;
wire        rx_payload_tready;
wire        frame_buffered;
wire [15:0] payload_length;

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

// ==========================================================================
// Decision gate (allow or silently drop payload)
// ==========================================================================
wire [7:0]  allowed_payload_tdata;
wire        allowed_payload_tvalid;
wire        allowed_payload_tlast;
wire        allowed_payload_tready;

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

// ==========================================================================
// TX rebuild (prepend Ethernet header to allowed payload)
// ==========================================================================
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

`resetall
