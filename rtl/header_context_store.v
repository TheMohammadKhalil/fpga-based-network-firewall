// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * Header Context Store
 *
 * Latches the parsed L2, L3, and L4 header fields into stable registers
 * so that the rule-match engines have a consistent snapshot for the
 * duration of the decision.  context_valid goes high after the L2 header
 * is captured and remains asserted until the next frame overwrites the
 * stored context or reset occurs.
 *
 * L3/L4 fields are captured opportunistically: they are latched whenever
 * the corresponding *_valid pulses arrive.  If the frame is too short
 * to contain an IP or L4 header the fields remain at their reset values.
 */
module header_context_store (
    input  wire        clk,
    input  wire        rst,

    // ---- L2 inputs (from eth_header_extract) ----
    input  wire [47:0] in_dst_mac,
    input  wire [47:0] in_src_mac,
    input  wire [15:0] in_ethertype,
    input  wire [15:0] in_frame_length,
    input  wire        in_crc_error,
    input  wire        header_valid,    // L2 header fully parsed
    input  wire        frame_done,      // tlast seen

    // ---- L3 inputs (from ip_header_extract) ----
    input  wire        is_ipv4,
    input  wire        ip_is_fragment,
    input  wire [3:0]  ip_version,
    input  wire [3:0]  ip_ihl,
    input  wire [5:0]  ip_dscp,
    input  wire [1:0]  ip_ecn,
    input  wire [15:0] ip_total_length,
    input  wire [15:0] ip_identification,
    input  wire [2:0]  ip_flags,
    input  wire [12:0] ip_frag_offset,
    input  wire [7:0]  ip_ttl,
    input  wire [7:0]  ip_protocol,
    input  wire [15:0] ip_hdr_checksum,
    input  wire [31:0] ip_src,
    input  wire [31:0] ip_dst,
    input  wire        ip_header_valid,  // L3 header fully parsed

    // ---- L4 inputs (from tcp_udp_header_extract) ----
    input  wire [15:0] l4_src_port,
    input  wire [15:0] l4_dst_port,
    input  wire [31:0] tcp_seq_num,
    input  wire [31:0] tcp_ack_num,
    input  wire [7:0]  tcp_flags,
    input  wire [15:0] tcp_window,
    input  wire        l4_header_valid,  // L4 header fully parsed

    // ---- Stable context outputs ----
    // L2
    output reg  [47:0] out_dst_mac,
    output reg  [47:0] out_src_mac,
    output reg  [15:0] out_ethertype,
    output reg  [15:0] out_frame_length,
    output reg         out_crc_error,
    // L3
    output reg         out_is_ipv4,
    output reg         out_ip_is_fragment,
    output reg  [3:0]  out_ip_version,
    output reg  [3:0]  out_ip_ihl,
    output reg  [5:0]  out_ip_dscp,
    output reg  [1:0]  out_ip_ecn,
    output reg  [15:0] out_ip_total_length,
    output reg  [15:0] out_ip_identification,
    output reg  [2:0]  out_ip_flags,
    output reg  [12:0] out_ip_frag_offset,
    output reg  [7:0]  out_ip_ttl,
    output reg  [7:0]  out_ip_protocol,
    output reg  [15:0] out_ip_hdr_checksum,
    output reg  [31:0] out_ip_src,
    output reg  [31:0] out_ip_dst,
    // L4
    output reg  [15:0] out_l4_src_port,
    output reg  [15:0] out_l4_dst_port,
    output reg  [31:0] out_tcp_seq_num,
    output reg  [31:0] out_tcp_ack_num,
    output reg  [7:0]  out_tcp_flags,
    output reg  [15:0] out_tcp_window,

    output reg         context_valid
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        out_dst_mac          <= 48'd0;
        out_src_mac          <= 48'd0;
        out_ethertype        <= 16'd0;
        out_frame_length     <= 16'd0;
        out_crc_error        <= 1'b0;
        out_is_ipv4          <= 1'b0;
        out_ip_is_fragment   <= 1'b0;
        out_ip_version       <= 4'd0;
        out_ip_ihl           <= 4'd0;
        out_ip_dscp          <= 6'd0;
        out_ip_ecn           <= 2'd0;
        out_ip_total_length  <= 16'd0;
        out_ip_identification<= 16'd0;
        out_ip_flags         <= 3'd0;
        out_ip_frag_offset   <= 13'd0;
        out_ip_ttl           <= 8'd0;
        out_ip_protocol      <= 8'd0;
        out_ip_hdr_checksum  <= 16'd0;
        out_ip_src           <= 32'd0;
        out_ip_dst           <= 32'd0;
        out_l4_src_port      <= 16'd0;
        out_l4_dst_port      <= 16'd0;
        out_tcp_seq_num      <= 32'd0;
        out_tcp_ack_num      <= 32'd0;
        out_tcp_flags        <= 8'd0;
        out_tcp_window       <= 16'd0;
        context_valid        <= 1'b0;
    end else begin
        // Latch the L2 header fields as soon as they are available.
        if (header_valid) begin
            out_dst_mac      <= in_dst_mac;
            out_src_mac      <= in_src_mac;
            out_ethertype    <= in_ethertype;
            context_valid    <= 1'b1;

            out_is_ipv4          <= 1'b0;
            out_ip_is_fragment   <= 1'b0;
            out_ip_version       <= 4'd0;
            out_ip_ihl           <= 4'd0;
            out_ip_dscp          <= 6'd0;
            out_ip_ecn           <= 2'd0;
            out_ip_total_length  <= 16'd0;
            out_ip_identification<= 16'd0;
            out_ip_flags         <= 3'd0;
            out_ip_frag_offset   <= 13'd0;
            out_ip_ttl           <= 8'd0;
            out_ip_protocol      <= 8'd0;
            out_ip_hdr_checksum  <= 16'd0;
            out_ip_src           <= 32'd0;
            out_ip_dst           <= 32'd0;
            out_l4_src_port      <= 16'd0;
            out_l4_dst_port      <= 16'd0;
            out_tcp_seq_num      <= 32'd0;
            out_tcp_ack_num      <= 32'd0;
            out_tcp_flags        <= 8'd0;
            out_tcp_window       <= 16'd0;
        end

        // Latch final length/CRC status at end of frame.  The MAC reports
        // these only after the whole frame has been received.
        if (frame_done) begin
            out_frame_length <= in_frame_length;
            out_crc_error    <= in_crc_error;
        end

        // Latch L3 fields when the IPv4 header is fully parsed
        if (ip_header_valid) begin
            out_is_ipv4           <= is_ipv4;
            out_ip_is_fragment    <= ip_is_fragment;
            out_ip_version        <= ip_version;
            out_ip_ihl            <= ip_ihl;
            out_ip_dscp           <= ip_dscp;
            out_ip_ecn            <= ip_ecn;
            out_ip_total_length   <= ip_total_length;
            out_ip_identification <= ip_identification;
            out_ip_flags          <= ip_flags;
            out_ip_frag_offset    <= ip_frag_offset;
            out_ip_ttl            <= ip_ttl;
            out_ip_protocol       <= ip_protocol;
            out_ip_hdr_checksum   <= ip_hdr_checksum;
            out_ip_src            <= ip_src;
            out_ip_dst            <= ip_dst;
        end

        // Latch L4 fields when ports / TCP flags are available
        if (l4_header_valid) begin
            out_l4_src_port <= l4_src_port;
            out_l4_dst_port <= l4_dst_port;
            out_tcp_seq_num <= tcp_seq_num;
            out_tcp_ack_num <= tcp_ack_num;
            out_tcp_flags   <= tcp_flags;
            out_tcp_window  <= tcp_window;
        end
    end
end

endmodule

`resetall
