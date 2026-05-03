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
 * FPGA core - transparent two-port Ethernet bridge for Terasic DE2-115
 *
 * The board-level build uses the DE2-specific RGMII RX aligner on each PHY,
 * one RGMII MAC transmitter per PHY, and forwards complete Ethernet frames
 * through small async FIFOs:
 *
 *   ENET0 RX frames  -->  FIFO  -->  ENET1 TX
 *   ENET1 RX frames  -->  FIFO  -->  ENET0 TX
 *
 * The RX path strips/checks the FCS and the TX MAC regenerates it, so the FPGA
 * no longer relies on a timing-sensitive raw RGMII wire pass-through.
 *
 * Status LEDs:
 *   LEDG[0]  raw ENET0 RX activity
 *   LEDG[1]  raw ENET1 RX activity
 *   LEDG[2]  frame transmitted ENET0 -> ENET1
 *   LEDG[3]  frame transmitted ENET1 -> ENET0
 *   LEDG[4]  ENET0 RX bad frame/FCS
 *   LEDG[5]  ENET1 RX bad frame/FCS
 *   LEDG[6]  any good MAC RX frame
 *   LEDG[7]  bridge out of reset
 *   LEDG[8]  heartbeat
 */
module fpga_core #(
    parameter TARGET = "GENERIC"
) (
    // 125 MHz, synchronous reset
    input  wire        clk,
    input  wire        clk90,
    input  wire        rst,

    // GPIO
    output wire [8:0]  ledg,
    output wire [17:0] ledr,

    // ENET0 - bridge port A
    input  wire        phy0_rx_clk,
    input  wire [3:0]  phy0_rxd,
    input  wire        phy0_rx_ctl,
    output wire        phy0_tx_clk,
    output wire [3:0]  phy0_txd,
    output wire        phy0_tx_ctl,
    output wire        phy0_reset_n,
    input  wire        phy0_int_n,

    // ENET1 - bridge port B
    input  wire        phy1_rx_clk,
    input  wire [3:0]  phy1_rxd,
    input  wire        phy1_rx_ctl,
    output wire        phy1_tx_clk,
    output wire [3:0]  phy1_txd,
    output wire        phy1_tx_ctl,
    output wire        phy1_reset_n,
    input  wire        phy1_int_n
);

// Hold the external PHYs in reset after FPGA configuration so their strap pins
// and RGMII mode are latched cleanly before traffic starts.
reg [23:0] phy_reset_cnt = 24'd0;
wire       phy_reset_done = &phy_reset_cnt;
wire       bridge_rst = rst || !phy_reset_done;

always @(posedge clk) begin
    if (rst) begin
        phy_reset_cnt <= 24'd0;
    end else if (!phy_reset_done) begin
        phy_reset_cnt <= phy_reset_cnt + 24'd1;
    end
end

assign phy0_reset_n = phy_reset_done;
assign phy1_reset_n = phy_reset_done;

// ---------------------------------------------------------------------------
// RGMII transmit MACs
// ---------------------------------------------------------------------------
wire        phy0_rx_rst;
wire        mac0_tx_clk;
wire        mac0_tx_rst;
wire [7:0]  mac0_rx_tdata;
wire        mac0_rx_tvalid;
wire        mac0_rx_tlast;
wire        mac0_rx_tuser;
wire [7:0]  mac0_tx_tdata;
wire        mac0_tx_tvalid;
wire        mac0_tx_tready;
wire        mac0_tx_tlast;
wire        mac0_tx_tuser;
wire        mac0_tx_error_underflow;
wire        mac0_rx_error_bad_frame;
wire        mac0_rx_error_bad_fcs;
wire [1:0]  mac0_speed;

wire        phy1_rx_rst;
wire        mac1_tx_clk;
wire        mac1_tx_rst;
wire [7:0]  mac1_rx_tdata;
wire        mac1_rx_tvalid;
wire        mac1_rx_tlast;
wire        mac1_rx_tuser;
wire [7:0]  mac1_tx_tdata;
wire        mac1_tx_tvalid;
wire        mac1_tx_tready;
wire        mac1_tx_tlast;
wire        mac1_tx_tuser;
wire        mac1_tx_error_underflow;
wire        mac1_rx_error_bad_frame;
wire        mac1_rx_error_bad_fcs;
wire [1:0]  mac1_speed;

sync_reset #(.N(4))
phy0_rx_reset_sync_inst (
    .clk(phy0_rx_clk),
    .rst(bridge_rst),
    .out(phy0_rx_rst)
);

sync_reset #(.N(4))
phy1_rx_reset_sync_inst (
    .clk(phy1_rx_clk),
    .rst(bridge_rst),
    .out(phy1_rx_rst)
);

eth_mac_1g_rgmii #(
    .TARGET(TARGET),
    .IODDR_STYLE("IODDR"),
    .CLOCK_INPUT_STYLE("BUFG"),
    .USE_CLK90("TRUE"),
    .FORCE_GIGABIT(0),
    .ENABLE_PADDING(1),
    .MIN_FRAME_LENGTH(64)
)
mac0_inst (
    .gtx_clk(clk),
    .gtx_clk90(clk90),
    .gtx_rst(bridge_rst),
    .rx_clk(),
    .rx_rst(),
    .tx_clk(mac0_tx_clk),
    .tx_rst(mac0_tx_rst),

    .tx_axis_tdata(mac0_tx_tdata),
    .tx_axis_tvalid(mac0_tx_tvalid),
    .tx_axis_tready(mac0_tx_tready),
    .tx_axis_tlast(mac0_tx_tlast),
    .tx_axis_tuser(mac0_tx_tuser),

    .rx_axis_tdata(),
    .rx_axis_tvalid(),
    .rx_axis_tlast(),
    .rx_axis_tuser(),

    .rgmii_rx_clk(phy0_rx_clk),
    .rgmii_rxd(4'd0),
    .rgmii_rx_ctl(1'b0),
    .rgmii_tx_clk(phy0_tx_clk),
    .rgmii_txd(phy0_txd),
    .rgmii_tx_ctl(phy0_tx_ctl),

    .tx_error_underflow(mac0_tx_error_underflow),
    .rx_error_bad_frame(),
    .rx_error_bad_fcs(),
    .speed(mac0_speed),

    .cfg_ifg(8'd12),
    .cfg_tx_enable(1'b1),
    .cfg_rx_enable(1'b1)
);

eth_mac_1g_rgmii #(
    .TARGET(TARGET),
    .IODDR_STYLE("IODDR"),
    .CLOCK_INPUT_STYLE("BUFG"),
    .USE_CLK90("TRUE"),
    .FORCE_GIGABIT(0),
    .ENABLE_PADDING(1),
    .MIN_FRAME_LENGTH(64)
)
mac1_inst (
    .gtx_clk(clk),
    .gtx_clk90(clk90),
    .gtx_rst(bridge_rst),
    .rx_clk(),
    .rx_rst(),
    .tx_clk(mac1_tx_clk),
    .tx_rst(mac1_tx_rst),

    .tx_axis_tdata(mac1_tx_tdata),
    .tx_axis_tvalid(mac1_tx_tvalid),
    .tx_axis_tready(mac1_tx_tready),
    .tx_axis_tlast(mac1_tx_tlast),
    .tx_axis_tuser(mac1_tx_tuser),

    .rx_axis_tdata(),
    .rx_axis_tvalid(),
    .rx_axis_tlast(),
    .rx_axis_tuser(),

    .rgmii_rx_clk(phy1_rx_clk),
    .rgmii_rxd(4'd0),
    .rgmii_rx_ctl(1'b0),
    .rgmii_tx_clk(phy1_tx_clk),
    .rgmii_txd(phy1_txd),
    .rgmii_tx_ctl(phy1_tx_ctl),

    .tx_error_underflow(mac1_tx_error_underflow),
    .rx_error_bad_frame(),
    .rx_error_bad_fcs(),
    .speed(mac1_speed),

    .cfg_ifg(8'd12),
    .cfg_tx_enable(1'b1),
    .cfg_rx_enable(1'b1)
);

// ---------------------------------------------------------------------------
// DE2-115 RGMII receivers
// ---------------------------------------------------------------------------
de2_rgmii_rx de2_rgmii_rx0_inst (
    .rst(bridge_rst),
    .rgmii_rx_clk(phy0_rx_clk),
    .rgmii_rxd(phy0_rxd),
    .rgmii_rx_ctl(phy0_rx_ctl),
    .mii_select(mac0_speed != 2'b10),
    .m_axis_tdata(mac0_rx_tdata),
    .m_axis_tvalid(mac0_rx_tvalid),
    .m_axis_tlast(mac0_rx_tlast),
    .m_axis_tuser(mac0_rx_tuser),
    .error_bad_frame(mac0_rx_error_bad_frame),
    .error_bad_fcs(mac0_rx_error_bad_fcs)
);

de2_rgmii_rx de2_rgmii_rx1_inst (
    .rst(bridge_rst),
    .rgmii_rx_clk(phy1_rx_clk),
    .rgmii_rxd(phy1_rxd),
    .rgmii_rx_ctl(phy1_rx_ctl),
    .mii_select(mac1_speed != 2'b10),
    .m_axis_tdata(mac1_rx_tdata),
    .m_axis_tvalid(mac1_rx_tvalid),
    .m_axis_tlast(mac1_rx_tlast),
    .m_axis_tuser(mac1_rx_tuser),
    .error_bad_frame(mac1_rx_error_bad_frame),
    .error_bad_fcs(mac1_rx_error_bad_fcs)
);

// ---------------------------------------------------------------------------
// Transparent frame forwarding
// ---------------------------------------------------------------------------
axis_async_fifo #(
    .DEPTH(4096),
    .DATA_WIDTH(8),
    .USER_WIDTH(1)
)
fifo_0_to_1_inst (
    .s_clk(phy0_rx_clk),
    .s_rst(phy0_rx_rst),
    .s_axis_tdata(mac0_rx_tdata),
    .s_axis_tvalid(mac0_rx_tvalid),
    .s_axis_tready(),
    .s_axis_tlast(mac0_rx_tlast),
    .s_axis_tuser(mac0_rx_tuser),

    .m_clk(mac1_tx_clk),
    .m_rst(mac1_tx_rst),
    .m_axis_tdata(mac1_tx_tdata),
    .m_axis_tvalid(mac1_tx_tvalid),
    .m_axis_tready(mac1_tx_tready),
    .m_axis_tlast(mac1_tx_tlast),
    .m_axis_tuser(mac1_tx_tuser)
);

axis_async_fifo #(
    .DEPTH(4096),
    .DATA_WIDTH(8),
    .USER_WIDTH(1)
)
fifo_1_to_0_inst (
    .s_clk(phy1_rx_clk),
    .s_rst(phy1_rx_rst),
    .s_axis_tdata(mac1_rx_tdata),
    .s_axis_tvalid(mac1_rx_tvalid),
    .s_axis_tready(),
    .s_axis_tlast(mac1_rx_tlast),
    .s_axis_tuser(mac1_rx_tuser),

    .m_clk(mac0_tx_clk),
    .m_rst(mac0_tx_rst),
    .m_axis_tdata(mac0_tx_tdata),
    .m_axis_tvalid(mac0_tx_tvalid),
    .m_axis_tready(mac0_tx_tready),
    .m_axis_tlast(mac0_tx_tlast),
    .m_axis_tuser(mac0_tx_tuser)
);

// ---------------------------------------------------------------------------
// Event capture for LED debug
// ---------------------------------------------------------------------------
reg mac0_good_toggle = 1'b0;
reg mac0_bad_toggle = 1'b0;

always @(posedge phy0_rx_clk) begin
    if (phy0_rx_rst) begin
        mac0_good_toggle <= 1'b0;
        mac0_bad_toggle  <= 1'b0;
    end else if (mac0_rx_tvalid && mac0_rx_tlast) begin
        if (mac0_rx_tuser) begin
            mac0_bad_toggle <= ~mac0_bad_toggle;
        end else begin
            mac0_good_toggle <= ~mac0_good_toggle;
        end
    end
end

reg mac1_good_toggle = 1'b0;
reg mac1_bad_toggle = 1'b0;

always @(posedge phy1_rx_clk) begin
    if (phy1_rx_rst) begin
        mac1_good_toggle <= 1'b0;
        mac1_bad_toggle  <= 1'b0;
    end else if (mac1_rx_tvalid && mac1_rx_tlast) begin
        if (mac1_rx_tuser) begin
            mac1_bad_toggle <= ~mac1_bad_toggle;
        end else begin
            mac1_good_toggle <= ~mac1_good_toggle;
        end
    end
end

wire mac0_tx_frame = mac0_tx_tvalid && mac0_tx_tready &&
                     mac0_tx_tlast && !mac0_tx_tuser;
wire mac1_tx_frame = mac1_tx_tvalid && mac1_tx_tready &&
                     mac1_tx_tlast && !mac1_tx_tuser;

reg [25:0] raw0_stretch;
reg [25:0] raw1_stretch;
reg [25:0] tx0_stretch;
reg [25:0] tx1_stretch;
reg [25:0] bad0_stretch;
reg [25:0] bad1_stretch;
reg [25:0] good_stretch;
reg [25:0] heartbeat_div;

reg [2:0]  phy0_rx_ctl_sync;
reg [2:0]  phy1_rx_ctl_sync;
reg [2:0]  mac0_good_sync;
reg [2:0]  mac0_bad_sync;
reg [2:0]  mac1_good_sync;
reg [2:0]  mac1_bad_sync;

wire mac0_good_pulse = mac0_good_sync[2] ^ mac0_good_sync[1];
wire mac0_bad_pulse  = mac0_bad_sync[2]  ^ mac0_bad_sync[1];
wire mac1_good_pulse = mac1_good_sync[2] ^ mac1_good_sync[1];
wire mac1_bad_pulse  = mac1_bad_sync[2]  ^ mac1_bad_sync[1];

localparam [25:0] STATUS_STRETCH_CYCLES = 26'd15_625_000; // 125 ms @ 125 MHz

always @(posedge clk) begin
    if (bridge_rst) begin
        raw0_stretch     <= 26'd0;
        raw1_stretch     <= 26'd0;
        tx0_stretch      <= 26'd0;
        tx1_stretch      <= 26'd0;
        bad0_stretch     <= 26'd0;
        bad1_stretch     <= 26'd0;
        good_stretch     <= 26'd0;
        heartbeat_div    <= 26'd0;
        phy0_rx_ctl_sync <= 3'd0;
        phy1_rx_ctl_sync <= 3'd0;
        mac0_good_sync   <= 3'd0;
        mac0_bad_sync    <= 3'd0;
        mac1_good_sync   <= 3'd0;
        mac1_bad_sync    <= 3'd0;
    end else begin
        heartbeat_div <= heartbeat_div + 26'd1;

        phy0_rx_ctl_sync <= {phy0_rx_ctl_sync[1:0], phy0_rx_ctl};
        phy1_rx_ctl_sync <= {phy1_rx_ctl_sync[1:0], phy1_rx_ctl};
        mac0_good_sync   <= {mac0_good_sync[1:0], mac0_good_toggle};
        mac0_bad_sync    <= {mac0_bad_sync[1:0], mac0_bad_toggle};
        mac1_good_sync   <= {mac1_good_sync[1:0], mac1_good_toggle};
        mac1_bad_sync    <= {mac1_bad_sync[1:0], mac1_bad_toggle};

        if (phy0_rx_ctl_sync[2]) begin
            raw0_stretch <= STATUS_STRETCH_CYCLES;
        end else if (raw0_stretch != 26'd0) begin
            raw0_stretch <= raw0_stretch - 26'd1;
        end

        if (phy1_rx_ctl_sync[2]) begin
            raw1_stretch <= STATUS_STRETCH_CYCLES;
        end else if (raw1_stretch != 26'd0) begin
            raw1_stretch <= raw1_stretch - 26'd1;
        end

        if (mac0_tx_frame) begin
            tx0_stretch <= STATUS_STRETCH_CYCLES;
        end else if (tx0_stretch != 26'd0) begin
            tx0_stretch <= tx0_stretch - 26'd1;
        end

        if (mac1_tx_frame) begin
            tx1_stretch <= STATUS_STRETCH_CYCLES;
        end else if (tx1_stretch != 26'd0) begin
            tx1_stretch <= tx1_stretch - 26'd1;
        end

        if (mac0_bad_pulse || mac0_rx_error_bad_frame || mac0_rx_error_bad_fcs) begin
            bad0_stretch <= STATUS_STRETCH_CYCLES;
        end else if (bad0_stretch != 26'd0) begin
            bad0_stretch <= bad0_stretch - 26'd1;
        end

        if (mac1_bad_pulse || mac1_rx_error_bad_frame || mac1_rx_error_bad_fcs) begin
            bad1_stretch <= STATUS_STRETCH_CYCLES;
        end else if (bad1_stretch != 26'd0) begin
            bad1_stretch <= bad1_stretch - 26'd1;
        end

        if (mac0_good_pulse || mac1_good_pulse) begin
            good_stretch <= STATUS_STRETCH_CYCLES;
        end else if (good_stretch != 26'd0) begin
            good_stretch <= good_stretch - 26'd1;
        end
    end
end

assign ledg[0] = (raw0_stretch != 26'd0);
assign ledg[1] = (raw1_stretch != 26'd0);
assign ledg[2] = (tx1_stretch != 26'd0);
assign ledg[3] = (tx0_stretch != 26'd0);
assign ledg[4] = (bad0_stretch != 26'd0);
assign ledg[5] = (bad1_stretch != 26'd0);
assign ledg[6] = (good_stretch != 26'd0);
assign ledg[7] = ~bridge_rst;
assign ledg[8] = heartbeat_div[25];

assign ledr[0] = mac0_speed[0];
assign ledr[1] = mac0_speed[1];
assign ledr[2] = mac1_speed[0];
assign ledr[3] = mac1_speed[1];
assign ledr[4] = mac0_tx_error_underflow;
assign ledr[5] = mac1_tx_error_underflow;
assign ledr[6] = ~phy0_int_n;
assign ledr[7] = ~phy1_int_n;
assign ledr[17:8] = 10'd0;

endmodule

`resetall
