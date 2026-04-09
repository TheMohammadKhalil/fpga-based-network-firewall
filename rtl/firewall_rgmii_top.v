/*
 * FPGA Firewall Top-Level with RGMII Interface
 *
 * This module integrates the 1G Ethernet MAC with the firewall logic
 * to create a network firewall that filters Ethernet frames.
 *
 * Features:
 * - RGMII interface for PHY connection
 * - Configurable MAC filtering rules via registers
 * - CRC error detection and dropping
 * - Frame length validation
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

module firewall_rgmii_top #(
    // Target FPGA: "SIM", "GENERIC", "XILINX", "ALTERA"
    parameter TARGET = "ALTERA",
    // IODDR style for RGMII
    parameter IODDR_STYLE = "IODDR2",
    // Clock input style
    parameter CLOCK_INPUT_STYLE = "BUFG",
    // Use 90 degree clock for RGMII transmit
    parameter USE_CLK90 = "TRUE",
    // Enable frame padding to minimum Ethernet frame size
    parameter ENABLE_PADDING = 1,
    // Minimum frame length (Ethernet minimum is 64 bytes)
    parameter MIN_FRAME_LENGTH = 64,
    // Maximum frame bytes to buffer in firewall
    parameter MAX_FRAME_BYTES = 2048
) (
    // 125 MHz clock from PHY or PLL
    input  wire        clk_125mhz,
    // Reset from PHY or system
    input  wire        rst_n,

    // RGMII interface to PHY
    input  wire        rgmii_rx_clk,
    input  wire [3:0]  rgmii_rxd,
    input  wire        rgmii_rx_ctl,
    output wire        rgmii_tx_clk,
    output wire [3:0]  rgmii_txd,
    output wire        rgmii_tx_ctl,

    // Configuration interface (AXI-lite style)
    input  wire        cfg_clk,
    input  wire        cfg_rst_n,
    input  wire        cfg_we,
    input  wire [3:0]  cfg_addr,
    input  wire [31:0] cfg_wdata,
    output wire [31:0] cfg_rdata,

    // Status outputs
    output wire        link_up,
    output wire [1:0]  speed,
    output wire        packet_allowed_pulse,
    output wire        packet_dropped_pulse,
    output wire        crc_error_pulse
);

// Internal clocks and resets
wire rx_clk;
wire rx_rst;
wire tx_clk;
wire tx_rst;
wire gtx_rst;

// Internal reset inversion
wire sys_rst = ~rst_n;
wire cfg_rst = ~cfg_rst_n;

// MAC AXI stream interfaces
wire [7:0] mac_rx_tdata;
wire       mac_rx_tvalid;
wire       mac_rx_tlast;
wire       mac_rx_tuser;

wire [7:0] mac_tx_tdata;
wire       mac_tx_tvalid;
wire       mac_tx_tready;
wire       mac_tx_tlast;
wire       mac_tx_tuser;

// Firewall internal signals
wire [7:0] fw_rx_tdata;
wire       fw_rx_tvalid;
wire       fw_rx_tlast;
wire       fw_rx_tready;
wire       fw_frame_buffered;
wire [15:0] fw_payload_length;

wire [7:0] fw_tx_tdata;
wire       fw_tx_tvalid;
wire       fw_tx_tlast;
wire       fw_tx_tready;

wire       packet_allowed;
wire       packet_dropped;
wire       crc_error_in;

// CRC error from MAC
assign crc_error_in = mac_rx_tuser;

// Drive the MAC's master reset; rx_rst and tx_rst are outputs from the MAC
assign gtx_rst = sys_rst;

// RGMII MAC instance
eth_mac_1g_rgmii #(
    .TARGET(TARGET),
    .IODDR_STYLE(IODDR_STYLE),
    .CLOCK_INPUT_STYLE(CLOCK_INPUT_STYLE),
    .USE_CLK90(USE_CLK90),
    .ENABLE_PADDING(ENABLE_PADDING),
    .MIN_FRAME_LENGTH(MIN_FRAME_LENGTH)
)
eth_mac_inst (
    .gtx_clk(clk_125mhz),
    .gtx_clk90(clk_125mhz),  // Should come from PLL with 90 degree phase shift
    .gtx_rst(gtx_rst),
    .rx_clk(rx_clk),
    .rx_rst(rx_rst),
    .tx_clk(tx_clk),
    .tx_rst(tx_rst),

    // TX axis to MAC
    .tx_axis_tdata(mac_tx_tdata),
    .tx_axis_tvalid(mac_tx_tvalid),
    .tx_axis_tready(mac_tx_tready),
    .tx_axis_tlast(mac_tx_tlast),
    .tx_axis_tuser(mac_tx_tuser),

    // RX axis from MAC
    .rx_axis_tdata(mac_rx_tdata),
    .rx_axis_tvalid(mac_rx_tvalid),
    .rx_axis_tlast(mac_rx_tlast),
    .rx_axis_tuser(mac_rx_tuser),

    // RGMII to PHY
    .rgmii_rx_clk(rgmii_rx_clk),
    .rgmii_rxd(rgmii_rxd),
    .rgmii_rx_ctl(rgmii_rx_ctl),
    .rgmii_tx_clk(rgmii_tx_clk),
    .rgmii_txd(rgmii_txd),
    .rgmii_tx_ctl(rgmii_tx_ctl),

    // Status
    .tx_error_underflow(),
    .rx_error_bad_frame(),
    .rx_error_bad_fcs(),
    .speed(speed),

    // Configuration
    .cfg_ifg(8'd12),       // Standard IFG (96 bits = 12 bytes)
    .cfg_tx_enable(1'b1),
    .cfg_rx_enable(1'b1)
);

// Firewall top instance
fpga_firewall_top firewall_inst (
    .clk(rx_clk),
    .rst(rx_rst),

    // RX axis from MAC (MAC RX has no tready; firewall must always accept)
    .s_axis_tdata(mac_rx_tdata),
    .s_axis_tvalid(mac_rx_tvalid),
    .s_axis_tlast(mac_rx_tlast),
    .s_axis_tready(),               // Open: MAC RX pushes without backpressure

    // TX axis to MAC (filtered packets)
    .m_axis_tdata(mac_tx_tdata),
    .m_axis_tvalid(mac_tx_tvalid),
    .m_axis_tlast(mac_tx_tlast),
    .m_axis_tready(mac_tx_tready),  // MAC TX ready signal

    // Configuration interface
    .cfg_we(cfg_we),
    .cfg_addr(cfg_addr),
    .cfg_wdata(cfg_wdata),

    // CRC error input
    .crc_error_in(crc_error_in),

    // Status outputs
    .packet_allowed(packet_allowed),
    .packet_dropped(packet_dropped)
);

// Link status (simple - could be enhanced with PHY MDIO status)
assign link_up = (speed != 2'b00);

// Pulse generation for status
reg packet_allowed_sync1 = 1'b0;
reg packet_allowed_sync2 = 1'b0;
reg packet_dropped_sync1 = 1'b0;
reg packet_dropped_sync2 = 1'b0;
reg crc_error_sync1 = 1'b0;
reg crc_error_sync2 = 1'b0;

always @(posedge cfg_clk or negedge cfg_rst_n) begin
    if (!cfg_rst_n) begin
        packet_allowed_sync1 <= 1'b0;
        packet_allowed_sync2 <= 1'b0;
        packet_dropped_sync1 <= 1'b0;
        packet_dropped_sync2 <= 1'b0;
        crc_error_sync1 <= 1'b0;
        crc_error_sync2 <= 1'b0;
    end else begin
        packet_allowed_sync1 <= packet_allowed;
        packet_allowed_sync2 <= packet_allowed_sync1;
        packet_dropped_sync1 <= packet_dropped;
        packet_dropped_sync2 <= packet_dropped_sync1;
        crc_error_sync1      <= crc_error_in;
        crc_error_sync2      <= crc_error_sync1;
    end
end

assign packet_allowed_pulse = packet_allowed_sync1 & ~packet_allowed_sync2;
assign packet_dropped_pulse = packet_dropped_sync1 & ~packet_dropped_sync2;
assign crc_error_pulse      = crc_error_sync1      & ~crc_error_sync2;

// Simple config readback (returns 0 for unimplemented registers)
reg [31:0] cfg_rdata_reg = 32'd0;

always @(posedge cfg_clk or negedge cfg_rst_n) begin
    if (!cfg_rst_n) begin
        cfg_rdata_reg <= 32'd0;
    end else if (cfg_addr == 4'hF) begin
        // Read status register (readable without cfg_we)
        cfg_rdata_reg <= {16'd0, speed, link_up, 1'b0, packet_allowed, packet_dropped, crc_error_in};
    end else begin
        cfg_rdata_reg <= 32'd0;
    end
end

assign cfg_rdata = cfg_rdata_reg;

endmodule

`resetall
