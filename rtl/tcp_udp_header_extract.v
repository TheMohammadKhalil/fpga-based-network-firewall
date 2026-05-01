// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * TCP / UDP Header Extractor
 *
 * Assumes a standard 20-byte IPv4 header (IHL = 5), so the L4 header
 * starts at byte 34 of the Ethernet frame.
 *
 * Both TCP and UDP share the same src/dst port layout at offset 0-3,
 * so this module works for either protocol.
 *
 * TCP-specific fields (flags, sequence number, ack number) are also
 * captured.  For UDP frames these registers will contain whatever data
 * happens to be in those byte positions; the rule matcher ignores them
 * unless the protocol is TCP (0x06).
 *
 * Outputs become valid when l4_header_valid pulses after the TCP window
 * field is fully captured.
 */
module tcp_udp_header_extract (
    input  wire        clk,
    input  wire        rst,

    // Raw AXI-Stream input
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,

    // L4 parsed fields
    output reg  [15:0] l4_src_port,
    output reg  [15:0] l4_dst_port,
    output reg  [31:0] tcp_seq_num,
    output reg  [31:0] tcp_ack_num,
    output reg  [7:0]  tcp_flags,    // [7]=CWR [6]=ECE [5]=URG [4]=ACK
                                     // [3]=PSH [2]=RST [1]=SYN [0]=FIN
    output reg  [15:0] tcp_window,

    // Status
    output reg         l4_header_valid,  // pulses one cycle after byte 47
    output reg         frame_done
);

// L4 header for standard IPv4 (IHL=5) starts at byte 34:
//   34-35 : src_port
//   36-37 : dst_port
//   38-41 : TCP seq_num  (or UDP length/checksum — captured but ignored)
//   42-45 : TCP ack_num
//   46    : TCP data offset (high nibble) + reserved/NS flag
//   47    : TCP flags

localparam L4_START = 16'd34;

reg [15:0] byte_cnt;
reg        in_frame;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        byte_cnt        <= 16'd0;
        in_frame        <= 1'b0;
        l4_src_port     <= 16'd0;
        l4_dst_port     <= 16'd0;
        tcp_seq_num     <= 32'd0;
        tcp_ack_num     <= 32'd0;
        tcp_flags       <= 8'd0;
        tcp_window      <= 16'd0;
        l4_header_valid <= 1'b0;
        frame_done      <= 1'b0;
    end else begin
        l4_header_valid <= 1'b0;
        frame_done      <= 1'b0;

        if (s_axis_tvalid) begin
            if (!in_frame) begin
                in_frame <= 1'b1;
                byte_cnt <= 16'd0;
            end

            case (byte_cnt)
                L4_START + 0: l4_src_port[15:8]  <= s_axis_tdata;
                L4_START + 1: l4_src_port[7:0]   <= s_axis_tdata;
                L4_START + 2: l4_dst_port[15:8]  <= s_axis_tdata;
                L4_START + 3: l4_dst_port[7:0]   <= s_axis_tdata;
                // TCP sequence number
                L4_START + 4: tcp_seq_num[31:24] <= s_axis_tdata;
                L4_START + 5: tcp_seq_num[23:16] <= s_axis_tdata;
                L4_START + 6: tcp_seq_num[15:8]  <= s_axis_tdata;
                L4_START + 7: tcp_seq_num[7:0]   <= s_axis_tdata;
                // TCP acknowledgement number
                L4_START + 8:  tcp_ack_num[31:24] <= s_axis_tdata;
                L4_START + 9:  tcp_ack_num[23:16] <= s_axis_tdata;
                L4_START + 10: tcp_ack_num[15:8]  <= s_axis_tdata;
                L4_START + 11: tcp_ack_num[7:0]   <= s_axis_tdata;
                // byte 46 = data offset / reserved / NS — not stored
                L4_START + 13: tcp_flags <= s_axis_tdata;   // TCP control flags
                L4_START + 14: tcp_window[15:8] <= s_axis_tdata;
                L4_START + 15: begin
                    tcp_window[7:0]  <= s_axis_tdata;
                    l4_header_valid   <= 1'b1;
                end
                default: ;
            endcase

            if (s_axis_tlast) begin
                frame_done      <= 1'b1;
                in_frame        <= 1'b0;
                byte_cnt        <= 16'd0;
                l4_header_valid <= 1'b0;
            end else begin
                byte_cnt <= byte_cnt + 16'd1;
            end
        end
    end
end

endmodule

`resetall
