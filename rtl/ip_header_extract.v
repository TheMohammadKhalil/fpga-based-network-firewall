// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * IPv4 Header Extractor
 *
 * Processes the raw AXI-Stream byte-by-byte and extracts every field
 * of the IPv4 header.  Ethernet header occupies bytes 0-13; the IPv4
 * header begins at byte 14.
 *
 * Outputs become valid when ip_header_valid pulses (after byte 33,
 * i.e. after src/dst IP are captured).  All outputs remain stable
 * until frame_done pulses.
 *
 * If the EtherType is not 0x0800 (IPv4), is_ipv4 stays low and
 * ip_header_valid is never asserted.
 */
module ip_header_extract (
    input  wire        clk,
    input  wire        rst,

    // Raw AXI-Stream input (same bus seen by eth_header_extract)
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,

    // Parsed IPv4 fields
    output reg  [3:0]  ip_version,
    output reg  [3:0]  ip_ihl,           // header length in 32-bit words
    output reg  [5:0]  ip_dscp,
    output reg  [1:0]  ip_ecn,
    output reg  [15:0] ip_total_length,
    output reg  [15:0] ip_identification,
    output reg  [2:0]  ip_flags,         // [2]=MF  [1]=DF  [0]=reserved
    output reg  [12:0] ip_frag_offset,
    output reg  [7:0]  ip_ttl,
    output reg  [7:0]  ip_protocol,
    output reg  [15:0] ip_hdr_checksum,
    output reg  [31:0] ip_src,
    output reg  [31:0] ip_dst,

    // Status flags
    output reg         is_ipv4,          // EtherType == 0x0800
    output reg         ip_is_fragment,   // MF=1 or frag_offset != 0
    output reg         ip_header_valid,  // pulses one cycle after byte 33
    output reg         frame_done        // pulses on tlast
);

reg [15:0] byte_cnt;
reg        in_frame;
reg [7:0]  etype_hi;  // byte 12 (EtherType MSB)

always @(posedge clk or posedge rst) begin
    if (rst) begin
        byte_cnt         <= 16'd0;
        in_frame         <= 1'b0;
        etype_hi         <= 8'd0;
        is_ipv4          <= 1'b0;
        ip_version       <= 4'd0;
        ip_ihl           <= 4'd0;
        ip_dscp          <= 6'd0;
        ip_ecn           <= 2'd0;
        ip_total_length  <= 16'd0;
        ip_identification<= 16'd0;
        ip_flags         <= 3'd0;
        ip_frag_offset   <= 13'd0;
        ip_ttl           <= 8'd0;
        ip_protocol      <= 8'd0;
        ip_hdr_checksum  <= 16'd0;
        ip_src           <= 32'd0;
        ip_dst           <= 32'd0;
        ip_is_fragment   <= 1'b0;
        ip_header_valid  <= 1'b0;
        frame_done       <= 1'b0;
    end else begin
        ip_header_valid <= 1'b0;
        frame_done      <= 1'b0;

        if (s_axis_tvalid) begin
            if (!in_frame) begin
                in_frame <= 1'b1;
                byte_cnt <= 16'd0;
            end

            case (byte_cnt)
                // ---- Ethernet header (bytes 0-13) ----
                16'd12: etype_hi <= s_axis_tdata;
                16'd13: is_ipv4  <= (etype_hi == 8'h08) && (s_axis_tdata == 8'h00);

                // ---- IPv4 header (bytes 14-33, assuming IHL=5) ----
                16'd14: begin
                    ip_version <= s_axis_tdata[7:4];
                    ip_ihl     <= s_axis_tdata[3:0];
                end
                16'd15: begin
                    ip_dscp <= s_axis_tdata[7:2];
                    ip_ecn  <= s_axis_tdata[1:0];
                end
                16'd16: ip_total_length[15:8]   <= s_axis_tdata;
                16'd17: ip_total_length[7:0]    <= s_axis_tdata;
                16'd18: ip_identification[15:8] <= s_axis_tdata;
                16'd19: ip_identification[7:0]  <= s_axis_tdata;
                16'd20: begin
                    ip_flags[2:0]       <= s_axis_tdata[7:5]; // MF, DF, Rsvd
                    ip_frag_offset[12:8]<= s_axis_tdata[4:0];
                end
                16'd21: ip_frag_offset[7:0] <= s_axis_tdata;
                16'd22: ip_ttl             <= s_axis_tdata;
                16'd23: ip_protocol        <= s_axis_tdata;
                16'd24: ip_hdr_checksum[15:8] <= s_axis_tdata;
                16'd25: ip_hdr_checksum[7:0]  <= s_axis_tdata;
                16'd26: ip_src[31:24] <= s_axis_tdata;
                16'd27: ip_src[23:16] <= s_axis_tdata;
                16'd28: ip_src[15:8]  <= s_axis_tdata;
                16'd29: ip_src[7:0]   <= s_axis_tdata;
                16'd30: ip_dst[31:24] <= s_axis_tdata;
                16'd31: ip_dst[23:16] <= s_axis_tdata;
                16'd32: ip_dst[15:8]  <= s_axis_tdata;
                16'd33: begin
                    ip_dst[7:0]    <= s_axis_tdata;
                    // ip_flags and ip_frag_offset are already registered;
                    // compute fragment indicator from their stable values
                    ip_is_fragment <= ip_flags[2] || (ip_frag_offset != 13'd0);
                    if (is_ipv4)
                        ip_header_valid <= 1'b1;
                end
                default: ;
            endcase

            if (s_axis_tlast) begin
                frame_done      <= 1'b1;
                in_frame        <= 1'b0;
                byte_cnt        <= 16'd0;
                ip_header_valid <= 1'b0;
                is_ipv4         <= 1'b0;
            end else begin
                byte_cnt <= byte_cnt + 16'd1;
            end
        end
    end
end

endmodule

`resetall
