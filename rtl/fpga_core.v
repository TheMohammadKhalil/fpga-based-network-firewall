/*

Copyright (c) 2020 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * FPGA core — inline Ethernet firewall for Terasic DE2-115
 *
 * Packet paths:
 *   ENET0 RX  -->  fpga_firewall_top  -->  ENET1 TX
 *   ENET1 RX  -->  fpga_firewall_top  -->  ENET0 TX
 *
 * Configuration (via SW[3:0]):
 *   SW[0]  enforce destination MAC  (allow_dst_mac register)
 *   SW[1]  enforce source MAC       (allow_src_mac register)
 *   SW[2]  enforce EtherType        (allow_ethertype register, default 0x0800)
 *   SW[3]  drop frames with CRC errors
 *
 *   The control register (addr 0x7) is updated every clock cycle with SW[3:0],
 *   so rule changes take effect immediately.  The allowed MAC addresses and
 *   EtherType default values are written once at startup; to change them a
 *   host-side config bus (not wired in this demo) would be needed.
 *
 * Status LEDs:
 *   LEDG[0]  allowed packet pulse
 *   LEDG[1]  dropped packet pulse
 *   LEDG[5:2] mirror SW[3:0] for quick board bring-up
 *   LEDG[6]  SW[17] config-mode indicator
 *   LEDG[7]  system out of reset
 *   LEDG[8]  heartbeat
 *   LEDR[7:4] dropped packet pulse bar
 *   LEDR[17:8], LEDR[3:0] mirror SW switches
 *
 * HEX displays (common-anode, active-low segments):
 *   HEX7-4   allowed packet count (16-bit, hex digits)
 *   HEX3-0   dropped packet count (16-bit, hex digits)
 */
module fpga_core #(
    parameter TARGET = "GENERIC"
) (
    // 125 MHz, synchronous reset
    input  wire        clk,
    input  wire        clk90,
    input  wire        rst,

    // GPIO
    input  wire [3:0]  btn,
    input  wire [17:0] sw,
    output wire [8:0]  ledg,
    output wire [17:0] ledr,
    output wire [6:0]  hex0,
    output wire [6:0]  hex1,
    output wire [6:0]  hex2,
    output wire [6:0]  hex3,
    output wire [6:0]  hex4,
    output wire [6:0]  hex5,
    output wire [6:0]  hex6,
    output wire [6:0]  hex7,

    // ENET0 — ingress / WAN side
    input  wire        phy0_rx_clk,
    input  wire [3:0]  phy0_rxd,
    input  wire        phy0_rx_ctl,
    output wire        phy0_tx_clk,
    output wire [3:0]  phy0_txd,
    output wire        phy0_tx_ctl,
    output wire        phy0_reset_n,
    input  wire        phy0_int_n,

    // ENET1 — egress / LAN side
    input  wire        phy1_rx_clk,
    input  wire [3:0]  phy1_rxd,
    input  wire        phy1_rx_ctl,
    output wire        phy1_tx_clk,
    output wire [3:0]  phy1_txd,
    output wire        phy1_tx_ctl,
    output wire        phy1_reset_n,
    input  wire        phy1_int_n
);

// ---------------------------------------------------------------------------
// ENET0 MAC
// ---------------------------------------------------------------------------
wire [7:0] mac0_rx_tdata;
wire       mac0_rx_tvalid;
wire       mac0_rx_tlast;
wire       mac0_rx_tuser;   // CRC error flag
wire       mac0_rx_error_bad_frame;
wire       mac0_rx_error_bad_fcs;
wire [1:0] mac0_speed;

wire [7:0] mac0_tx_tdata;
wire       mac0_tx_tvalid;
wire       mac0_tx_tready;
wire       mac0_tx_tlast;

wire mac0_rx_clk_unused, mac0_rx_rst_unused;
wire mac0_tx_clk, mac0_tx_rst;

eth_mac_1g_rgmii #(
    .TARGET(TARGET),
    .IODDR_STYLE("IODDR2"),
    .CLOCK_INPUT_STYLE("BUFG"),
    .USE_CLK90("TRUE"),
    .ENABLE_PADDING(1),
    .MIN_FRAME_LENGTH(64)
)
eth_mac0_inst (
    .gtx_clk(clk),
    .gtx_clk90(clk90),
    .gtx_rst(rst),
    .rx_clk(mac0_rx_clk_unused),
    .rx_rst(mac0_rx_rst_unused),
    .tx_clk(mac0_tx_clk),
    .tx_rst(mac0_tx_rst),

    // TX — reverse direction, ENET1 RX -> firewall -> ENET0 TX
    .tx_axis_tdata(mac0_tx_tdata),
    .tx_axis_tvalid(mac0_tx_tvalid),
    .tx_axis_tready(mac0_tx_tready),
    .tx_axis_tlast(mac0_tx_tlast),
    .tx_axis_tuser(1'b0),

    // RX data is handled by a board-specific RGMII receiver below.
    // Keep the RX clock connected so the MAC TX path tracks PHY link speed.
    .rx_axis_tdata(),
    .rx_axis_tvalid(),
    .rx_axis_tlast(),
    .rx_axis_tuser(),

    // RGMII pins
    .rgmii_rx_clk(phy0_rx_clk),
    .rgmii_rxd(4'd0),
    .rgmii_rx_ctl(1'b0),
    .rgmii_tx_clk(phy0_tx_clk),
    .rgmii_txd(phy0_txd),
    .rgmii_tx_ctl(phy0_tx_ctl),

    // Status (unused)
    .tx_error_underflow(),
    .rx_error_bad_frame(),
    .rx_error_bad_fcs(),
    .speed(mac0_speed),

    .cfg_ifg(8'd12),
    .cfg_tx_enable(1'b1),
    .cfg_rx_enable(1'b1)
);

assign phy0_reset_n = ~rst;

de2_rgmii_rx de2_rgmii_rx0_inst (
    .rst(rst),
    .rgmii_rx_clk(phy0_rx_clk),
    .rgmii_rxd(phy0_rxd),
    .rgmii_rx_ctl(phy0_rx_ctl),
    .m_axis_tdata(mac0_rx_tdata),
    .m_axis_tvalid(mac0_rx_tvalid),
    .m_axis_tlast(mac0_rx_tlast),
    .m_axis_tuser(mac0_rx_tuser),
    .error_bad_frame(mac0_rx_error_bad_frame),
    .error_bad_fcs(mac0_rx_error_bad_fcs)
);

// ---------------------------------------------------------------------------
// ENET1 MAC
// ---------------------------------------------------------------------------
wire [7:0] mac1_rx_tdata;
wire       mac1_rx_tvalid;
wire       mac1_rx_tlast;
wire       mac1_rx_tuser;   // CRC error flag
wire       mac1_rx_error_bad_frame;
wire       mac1_rx_error_bad_fcs;

wire [7:0] mac1_tx_tdata;
wire       mac1_tx_tvalid;
wire       mac1_tx_tready;
wire       mac1_tx_tlast;

wire mac1_rx_clk_unused, mac1_rx_rst_unused;
wire mac1_tx_clk, mac1_tx_rst;

eth_mac_1g_rgmii #(
    .TARGET(TARGET),
    .IODDR_STYLE("IODDR2"),
    .CLOCK_INPUT_STYLE("BUFG"),
    .USE_CLK90("TRUE"),
    .ENABLE_PADDING(1),
    .MIN_FRAME_LENGTH(64)
)
eth_mac1_inst (
    .gtx_clk(clk),
    .gtx_clk90(clk90),
    .gtx_rst(rst),
    .rx_clk(mac1_rx_clk_unused),
    .rx_rst(mac1_rx_rst_unused),
    .tx_clk(mac1_tx_clk),
    .tx_rst(mac1_tx_rst),

    // TX — receives filtered frames from firewall
    .tx_axis_tdata(mac1_tx_tdata),
    .tx_axis_tvalid(mac1_tx_tvalid),
    .tx_axis_tready(mac1_tx_tready),
    .tx_axis_tlast(mac1_tx_tlast),
    .tx_axis_tuser(1'b0),

    // RX data is handled by a board-specific RGMII receiver below.
    // Keep the RX clock connected so the MAC TX path tracks PHY link speed.
    .rx_axis_tdata(),
    .rx_axis_tvalid(),
    .rx_axis_tlast(),
    .rx_axis_tuser(),

    // RGMII pins
    .rgmii_rx_clk(phy1_rx_clk),
    .rgmii_rxd(4'd0),
    .rgmii_rx_ctl(1'b0),
    .rgmii_tx_clk(phy1_tx_clk),
    .rgmii_txd(phy1_txd),
    .rgmii_tx_ctl(phy1_tx_ctl),

    // Status (unused)
    .tx_error_underflow(),
    .rx_error_bad_frame(),
    .rx_error_bad_fcs(),
    .speed(),

    .cfg_ifg(8'd12),
    .cfg_tx_enable(1'b1),
    .cfg_rx_enable(1'b1)
);

assign phy1_reset_n = ~rst;

de2_rgmii_rx de2_rgmii_rx1_inst (
    .rst(rst),
    .rgmii_rx_clk(phy1_rx_clk),
    .rgmii_rxd(phy1_rxd),
    .rgmii_rx_ctl(phy1_rx_ctl),
    .m_axis_tdata(mac1_rx_tdata),
    .m_axis_tvalid(mac1_rx_tvalid),
    .m_axis_tlast(mac1_rx_tlast),
    .m_axis_tuser(mac1_rx_tuser),
    .error_bad_frame(mac1_rx_error_bad_frame),
    .error_bad_fcs(mac1_rx_error_bad_fcs)
);

// ---------------------------------------------------------------------------
// Firewall configuration bus — directly from physical SW pins (no latches).
//
// A register in the address path (the old cfg_addr_lat approach) gives
// Quartus a reset-value to propagate, causing it to prove the rule-table
// write enable is always 0 and eliminate all 1 664 rule-table flip-flops.
// Driving cfg_addr combinationally from SW[7:0] prevents that: the path
// from physical pins to the write enable is purely combinational, so
// Quartus cannot determine whether cfg_addr[7:4] == 4'h1 is ever true.
//
//   SW[17] = 0   Runtime mode
//     Continuously writes L2 control register (addr 0x07) with SW[3:0]:
//       SW[0]  enforce_dst_mac
//       SW[1]  enforce_src_mac
//       SW[2]  enforce_ethertype
//       SW[3]  drop_crc_error
//
//   SW[17] = 1   Config mode — write any register including L3 rule table
//     cfg_addr  = SW[7:0]   (set switches to target address, e.g. 0x11)
//     cfg_wdata = {14'd0, SW[17:0]}   (18 live non-constant data bits)
//     cfg_we    = 1 continuously while SW[17]=1 — so set addr+data first,
//                 then flip SW[17] to commit.
//
// L3 rule table address map (addr 0x10-0x17):
//   0x10  rule_index [2:0]
//   0x11  rule_flags[7:0] + protocol[15:8]
//   0x12  src_ip    [31:0]   (bits [17:0] from SW; upper 14 bits = 0)
//   0x13  src_mask  [31:0]
//   0x14  dst_ip    [31:0]
//   0x15  dst_mask  [31:0]
//   0x16  src_ports {max[31:16], min[15:0]}
//   0x17  dst_ports {max[31:16], min[15:0]}
// ---------------------------------------------------------------------------

wire        cfg_we    = 1'b1;                           // always writing
wire [7:0]  cfg_addr  = sw[17] ? sw[7:0] : 8'h07;     // addr from SW or ctrl reg
wire [31:0] cfg_wdata = sw[17] ? {14'd0, sw[17:0]}     // 18 non-constant bits
                                : {28'd0, sw[3:0]};    // L2 control bits

// ---------------------------------------------------------------------------
// Bidirectional firewall pipelines
//
//   0_to_1: ENET0 RX -> firewall -> ENET1 TX
//   1_to_0: ENET1 RX -> firewall -> ENET0 TX
//
// Your PC-to-router traffic enters the reverse path in a normal inline setup,
// so the packet counters must include both directions.
// ---------------------------------------------------------------------------

wire [7:0] rx0_fifo_tdata;
wire       rx0_fifo_tvalid;
wire       rx0_fifo_tready;
wire       rx0_fifo_tlast;
wire       rx0_fifo_tuser;

axis_async_fifo #(
    .DEPTH(2048),
    .DATA_WIDTH(8),
    .USER_WIDTH(1)
) rx0_fifo_inst (
    .s_clk(phy0_rx_clk),
    .s_rst(rst),
    .s_axis_tdata(mac0_rx_tdata),
    .s_axis_tvalid(mac0_rx_tvalid),
    .s_axis_tready(),
    .s_axis_tlast(mac0_rx_tlast),
    .s_axis_tuser(mac0_rx_tuser),

    .m_clk(clk),
    .m_rst(rst),
    .m_axis_tdata(rx0_fifo_tdata),
    .m_axis_tvalid(rx0_fifo_tvalid),
    .m_axis_tready(rx0_fifo_tready),
    .m_axis_tlast(rx0_fifo_tlast),
    .m_axis_tuser(rx0_fifo_tuser)
);

wire [7:0] tx1_fifo_tdata;
wire       tx1_fifo_tvalid;
wire       tx1_fifo_tready;
wire       tx1_fifo_tlast;

axis_fifo #(
    .DEPTH(2048),
    .DATA_WIDTH(8),
    .KEEP_ENABLE(0),
    .LAST_ENABLE(1),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(0),
    .USER_WIDTH(1),
    .FRAME_FIFO(0)
) tx1_fifo_inst (
    .clk(clk),
    .rst(rst),
    .s_axis_tdata(tx1_fifo_tdata),
    .s_axis_tkeep(1'b1),
    .s_axis_tvalid(tx1_fifo_tvalid),
    .s_axis_tready(tx1_fifo_tready),
    .s_axis_tlast(tx1_fifo_tlast),
    .s_axis_tid(1'b0),
    .s_axis_tdest(1'b0),
    .s_axis_tuser(1'b0),
    .m_axis_tdata(mac1_tx_tdata),
    .m_axis_tkeep(),
    .m_axis_tvalid(mac1_tx_tvalid),
    .m_axis_tready(mac1_tx_tready),
    .m_axis_tlast(mac1_tx_tlast),
    .m_axis_tid(),
    .m_axis_tdest(),
    .m_axis_tuser(),
    .pause_req(1'b0),
    .pause_ack(),
    .status_depth(),
    .status_depth_commit(),
    .status_overflow(),
    .status_bad_frame(),
    .status_good_frame()
);

wire fw01_packet_allowed;
wire fw01_packet_dropped;

fpga_firewall_top firewall_0_to_1_inst (
    .clk(clk),
    .rst(rst),
    .s_axis_tdata(rx0_fifo_tdata),
    .s_axis_tvalid(rx0_fifo_tvalid),
    .s_axis_tlast(rx0_fifo_tlast),
    .s_axis_tready(rx0_fifo_tready),
    .m_axis_tdata(tx1_fifo_tdata),
    .m_axis_tvalid(tx1_fifo_tvalid),
    .m_axis_tlast(tx1_fifo_tlast),
    .m_axis_tready(tx1_fifo_tready),
    .cfg_we(cfg_we),
    .cfg_addr(cfg_addr),
    .cfg_wdata(cfg_wdata),
    .crc_error_in(rx0_fifo_tuser),
    .packet_allowed(fw01_packet_allowed),
    .packet_dropped(fw01_packet_dropped)
);

wire [7:0] rx1_fifo_tdata;
wire       rx1_fifo_tvalid;
wire       rx1_fifo_tready;
wire       rx1_fifo_tlast;
wire       rx1_fifo_tuser;

axis_async_fifo #(
    .DEPTH(2048),
    .DATA_WIDTH(8),
    .USER_WIDTH(1)
) rx1_fifo_inst (
    .s_clk(phy1_rx_clk),
    .s_rst(rst),
    .s_axis_tdata(mac1_rx_tdata),
    .s_axis_tvalid(mac1_rx_tvalid),
    .s_axis_tready(),
    .s_axis_tlast(mac1_rx_tlast),
    .s_axis_tuser(mac1_rx_tuser),

    .m_clk(clk),
    .m_rst(rst),
    .m_axis_tdata(rx1_fifo_tdata),
    .m_axis_tvalid(rx1_fifo_tvalid),
    .m_axis_tready(rx1_fifo_tready),
    .m_axis_tlast(rx1_fifo_tlast),
    .m_axis_tuser(rx1_fifo_tuser)
);

wire [7:0] tx0_fifo_tdata;
wire       tx0_fifo_tvalid;
wire       tx0_fifo_tready;
wire       tx0_fifo_tlast;

axis_fifo #(
    .DEPTH(2048),
    .DATA_WIDTH(8),
    .KEEP_ENABLE(0),
    .LAST_ENABLE(1),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(0),
    .USER_WIDTH(1),
    .FRAME_FIFO(0)
) tx0_fifo_inst (
    .clk(clk),
    .rst(rst),
    .s_axis_tdata(tx0_fifo_tdata),
    .s_axis_tkeep(1'b1),
    .s_axis_tvalid(tx0_fifo_tvalid),
    .s_axis_tready(tx0_fifo_tready),
    .s_axis_tlast(tx0_fifo_tlast),
    .s_axis_tid(1'b0),
    .s_axis_tdest(1'b0),
    .s_axis_tuser(1'b0),
    .m_axis_tdata(mac0_tx_tdata),
    .m_axis_tkeep(),
    .m_axis_tvalid(mac0_tx_tvalid),
    .m_axis_tready(mac0_tx_tready),
    .m_axis_tlast(mac0_tx_tlast),
    .m_axis_tid(),
    .m_axis_tdest(),
    .m_axis_tuser(),
    .pause_req(1'b0),
    .pause_ack(),
    .status_depth(),
    .status_depth_commit(),
    .status_overflow(),
    .status_bad_frame(),
    .status_good_frame()
);

wire fw10_packet_allowed;
wire fw10_packet_dropped;

fpga_firewall_top firewall_1_to_0_inst (
    .clk(clk),
    .rst(rst),
    .s_axis_tdata(rx1_fifo_tdata),
    .s_axis_tvalid(rx1_fifo_tvalid),
    .s_axis_tlast(rx1_fifo_tlast),
    .s_axis_tready(rx1_fifo_tready),
    .m_axis_tdata(tx0_fifo_tdata),
    .m_axis_tvalid(tx0_fifo_tvalid),
    .m_axis_tlast(tx0_fifo_tlast),
    .m_axis_tready(tx0_fifo_tready),
    .cfg_we(cfg_we),
    .cfg_addr(cfg_addr),
    .cfg_wdata(cfg_wdata),
    .crc_error_in(rx1_fifo_tuser),
    .packet_allowed(fw10_packet_allowed),
    .packet_dropped(fw10_packet_dropped)
);

wire [1:0] packet_allowed_inc = {1'b0, fw01_packet_allowed} +
                                {1'b0, fw10_packet_allowed};
wire [1:0] packet_dropped_inc = {1'b0, fw01_packet_dropped} +
                                {1'b0, fw10_packet_dropped};
wire       any_packet_allowed = |packet_allowed_inc;
wire       any_packet_dropped = |packet_dropped_inc;

// ---------------------------------------------------------------------------
// Packet counters (16-bit, wrap)
// ---------------------------------------------------------------------------
reg [15:0] allowed_count;
reg [15:0] dropped_count;

always @(posedge clk) begin
    if (rst) begin
        allowed_count <= 16'd0;
        dropped_count <= 16'd0;
    end else begin
        allowed_count <= allowed_count + {14'd0, packet_allowed_inc};
        dropped_count <= dropped_count + {14'd0, packet_dropped_inc};
    end
end

// ---------------------------------------------------------------------------
// LED stretching and bring-up indicators
//
// The packet status outputs from the firewall are one clk-cycle pulses.
// Stretch them just long enough to see while keeping allowed and dropped
// indications visually separate during normal ping traffic.
// ---------------------------------------------------------------------------
reg [25:0] allowed_stretch;
reg [25:0] dropped_stretch;
reg [25:0] heartbeat_div;

localparam [25:0] STATUS_STRETCH_CYCLES = 26'd15_625_000; // 125 ms @ 125 MHz

always @(posedge clk) begin
    if (rst) begin
        allowed_stretch <= 26'd0;
        dropped_stretch <= 26'd0;
        heartbeat_div   <= 26'd0;
    end else begin
        heartbeat_div <= heartbeat_div + 26'd1;

        if (any_packet_allowed)
            allowed_stretch <= STATUS_STRETCH_CYCLES;
        else if (allowed_stretch != 26'd0)
            allowed_stretch <= allowed_stretch - 26'd1;

        if (any_packet_dropped)
            dropped_stretch <= STATUS_STRETCH_CYCLES;
        else if (dropped_stretch != 26'd0)
            dropped_stretch <= dropped_stretch - 26'd1;
    end
end

assign ledg[0] = (allowed_stretch != 26'd0);
assign ledg[1] = (dropped_stretch != 26'd0);
assign ledg[5:2] = sw[3:0];
assign ledg[6] = sw[17];
assign ledg[7] = ~rst;
assign ledg[8] = heartbeat_div[25];
assign ledr[17:8] = sw[17:8];
assign ledr[7:4] = (dropped_stretch != 26'd0) ? 4'b1111 : 4'b0000;
assign ledr[3:0] = sw[3:0];

// ---------------------------------------------------------------------------
// 7-segment display: common-anode, active-low segments
//   HEX7-4  allowed_count
//   HEX3-0  dropped_count
// ---------------------------------------------------------------------------
function [6:0] seg7;
    input [3:0] d;
    begin
        case (d)
            4'h0: seg7 = 7'b1000000;
            4'h1: seg7 = 7'b1111001;
            4'h2: seg7 = 7'b0100100;
            4'h3: seg7 = 7'b0110000;
            4'h4: seg7 = 7'b0011001;
            4'h5: seg7 = 7'b0010010;
            4'h6: seg7 = 7'b0000010;
            4'h7: seg7 = 7'b1111000;
            4'h8: seg7 = 7'b0000000;
            4'h9: seg7 = 7'b0010000;
            4'ha: seg7 = 7'b0001000;
            4'hb: seg7 = 7'b0000011;
            4'hc: seg7 = 7'b1000110;
            4'hd: seg7 = 7'b0100001;
            4'he: seg7 = 7'b0000110;
            4'hf: seg7 = 7'b0001110;
            default: seg7 = 7'b1111111;
        endcase
    end
endfunction

// Dropped count on HEX3-0
assign hex0 = seg7(dropped_count[3:0]);
assign hex1 = seg7(dropped_count[7:4]);
assign hex2 = seg7(dropped_count[11:8]);
assign hex3 = seg7(dropped_count[15:12]);

// Allowed count on HEX7-4
assign hex4 = seg7(allowed_count[3:0]);
assign hex5 = seg7(allowed_count[7:4]);
assign hex6 = seg7(allowed_count[11:8]);
assign hex7 = seg7(allowed_count[15:12]);

endmodule

`resetall
