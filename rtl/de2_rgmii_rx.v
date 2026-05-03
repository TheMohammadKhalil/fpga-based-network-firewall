`resetall
`timescale 1ns / 1ps
`default_nettype none

module de2_rgmii_rx (
    input  wire       rst,
    input  wire       rgmii_rx_clk,
    input  wire [3:0] rgmii_rxd,
    input  wire       rgmii_rx_ctl,
    input  wire       mii_select,

    output wire [7:0] m_axis_tdata,
    output wire       m_axis_tvalid,
    output wire       m_axis_tlast,
    output wire       m_axis_tuser,

    output wire       error_bad_frame,
    output wire       error_bad_fcs
);

wire rx_rst;

sync_reset #(.N(4))
rx_reset_sync_inst (
    .clk(rgmii_rx_clk),
    .rst(rst),
    .out(rx_rst)
);

wire [4:0] rgmii_q1;
wire [4:0] rgmii_q2;
reg  [4:0] rgmii_q1_d1 = 5'd0;

altddio_in #(
    .width(5),
    .intended_device_family("Cyclone IV E"),
    .power_up_high("OFF"),
    .invert_input_clocks("OFF"),
    .lpm_type("altddio_in")
)
rgmii_rx_ddr_inst (
    .datain({rgmii_rxd, rgmii_rx_ctl}),
    .inclock(rgmii_rx_clk),
    .inclocken(1'b1),
    .aclr(1'b0),
    .aset(1'b0),
    .sclr(1'b0),
    .sset(1'b0),
    .dataout_h(rgmii_q1),
    .dataout_l(rgmii_q2)
);

wire [7:0] gmii_rxd_a = {rgmii_q2[4:1], rgmii_q1_d1[4:1]};
wire [7:0] gmii_rxd_b = {rgmii_q1_d1[4:1], rgmii_q2[4:1]};
wire [7:0] gmii_rxd_c = {rgmii_q2[4:1], rgmii_q1[4:1]};
wire [7:0] gmii_rxd_d = {rgmii_q1[4:1], rgmii_q2[4:1]};

wire       gmii_rx_dv_a = rgmii_q1_d1[0];
wire       gmii_rx_dv_b = rgmii_q1_d1[0];
wire       gmii_rx_dv_c = rgmii_q1[0];
wire       gmii_rx_dv_d = rgmii_q1[0];

wire       gmii_rx_er_a = rgmii_q1_d1[0] ^ rgmii_q2[0];
wire       gmii_rx_er_b = rgmii_q1_d1[0] ^ rgmii_q2[0];
wire       gmii_rx_er_c = rgmii_q1[0] ^ rgmii_q2[0];
wire       gmii_rx_er_d = rgmii_q1[0] ^ rgmii_q2[0];

always @(posedge rgmii_rx_clk) begin
    if (rx_rst) begin
        rgmii_q1_d1 <= 5'd0;
    end else begin
        rgmii_q1_d1 <= rgmii_q1;
    end
end

wire [7:0] m_axis_tdata_a;
wire       m_axis_tvalid_a;
wire       m_axis_tlast_a;
wire       m_axis_tuser_a;
wire       start_packet_a;
wire       error_bad_frame_a;
wire       error_bad_fcs_a;

axis_gmii_rx #(
    .DATA_WIDTH(8),
    .USER_WIDTH(1)
)
axis_gmii_rx_inst_a (
    .clk(rgmii_rx_clk),
    .rst(rx_rst),
    .gmii_rxd(gmii_rxd_a),
    .gmii_rx_dv(gmii_rx_dv_a),
    .gmii_rx_er(gmii_rx_er_a),
    .m_axis_tdata(m_axis_tdata_a),
    .m_axis_tvalid(m_axis_tvalid_a),
    .m_axis_tlast(m_axis_tlast_a),
    .m_axis_tuser(m_axis_tuser_a),
    .ptp_ts(96'd0),
    .clk_enable(1'b1),
    .mii_select(mii_select),
    .cfg_rx_enable(1'b1),
    .start_packet(start_packet_a),
    .error_bad_frame(error_bad_frame_a),
    .error_bad_fcs(error_bad_fcs_a)
);

wire [7:0] m_axis_tdata_b;
wire       m_axis_tvalid_b;
wire       m_axis_tlast_b;
wire       m_axis_tuser_b;
wire       start_packet_b;
wire       error_bad_frame_b;
wire       error_bad_fcs_b;

axis_gmii_rx #(
    .DATA_WIDTH(8),
    .USER_WIDTH(1)
)
axis_gmii_rx_inst_b (
    .clk(rgmii_rx_clk),
    .rst(rx_rst),
    .gmii_rxd(gmii_rxd_b),
    .gmii_rx_dv(gmii_rx_dv_b),
    .gmii_rx_er(gmii_rx_er_b),
    .m_axis_tdata(m_axis_tdata_b),
    .m_axis_tvalid(m_axis_tvalid_b),
    .m_axis_tlast(m_axis_tlast_b),
    .m_axis_tuser(m_axis_tuser_b),
    .ptp_ts(96'd0),
    .clk_enable(1'b1),
    .mii_select(mii_select),
    .cfg_rx_enable(1'b1),
    .start_packet(start_packet_b),
    .error_bad_frame(error_bad_frame_b),
    .error_bad_fcs(error_bad_fcs_b)
);

wire [7:0] m_axis_tdata_c;
wire       m_axis_tvalid_c;
wire       m_axis_tlast_c;
wire       m_axis_tuser_c;
wire       start_packet_c;
wire       error_bad_frame_c;
wire       error_bad_fcs_c;

axis_gmii_rx #(
    .DATA_WIDTH(8),
    .USER_WIDTH(1)
)
axis_gmii_rx_inst_c (
    .clk(rgmii_rx_clk),
    .rst(rx_rst),
    .gmii_rxd(gmii_rxd_c),
    .gmii_rx_dv(gmii_rx_dv_c),
    .gmii_rx_er(gmii_rx_er_c),
    .m_axis_tdata(m_axis_tdata_c),
    .m_axis_tvalid(m_axis_tvalid_c),
    .m_axis_tlast(m_axis_tlast_c),
    .m_axis_tuser(m_axis_tuser_c),
    .ptp_ts(96'd0),
    .clk_enable(1'b1),
    .mii_select(mii_select),
    .cfg_rx_enable(1'b1),
    .start_packet(start_packet_c),
    .error_bad_frame(error_bad_frame_c),
    .error_bad_fcs(error_bad_fcs_c)
);

wire [7:0] m_axis_tdata_d;
wire       m_axis_tvalid_d;
wire       m_axis_tlast_d;
wire       m_axis_tuser_d;
wire       start_packet_d;
wire       error_bad_frame_d;
wire       error_bad_fcs_d;

axis_gmii_rx #(
    .DATA_WIDTH(8),
    .USER_WIDTH(1)
)
axis_gmii_rx_inst_d (
    .clk(rgmii_rx_clk),
    .rst(rx_rst),
    .gmii_rxd(gmii_rxd_d),
    .gmii_rx_dv(gmii_rx_dv_d),
    .gmii_rx_er(gmii_rx_er_d),
    .m_axis_tdata(m_axis_tdata_d),
    .m_axis_tvalid(m_axis_tvalid_d),
    .m_axis_tlast(m_axis_tlast_d),
    .m_axis_tuser(m_axis_tuser_d),
    .ptp_ts(96'd0),
    .clk_enable(1'b1),
    .mii_select(mii_select),
    .cfg_rx_enable(1'b1),
    .start_packet(start_packet_d),
    .error_bad_frame(error_bad_frame_d),
    .error_bad_fcs(error_bad_fcs_d)
);

reg       selected_valid_reg = 1'b0;
reg [1:0] selected_path_reg = 2'd0;

always @(posedge rgmii_rx_clk) begin
    if (rx_rst) begin
        selected_valid_reg <= 1'b0;
        selected_path_reg <= 2'd0;
    end else begin
        if (!selected_valid_reg) begin
            if (start_packet_a) begin
                selected_valid_reg <= 1'b1;
                selected_path_reg <= 2'd0;
            end else if (start_packet_b) begin
                selected_valid_reg <= 1'b1;
                selected_path_reg <= 2'd1;
            end else if (start_packet_c) begin
                selected_valid_reg <= 1'b1;
                selected_path_reg <= 2'd2;
            end else if (start_packet_d) begin
                selected_valid_reg <= 1'b1;
                selected_path_reg <= 2'd3;
            end
        end else begin
            case (selected_path_reg)
                2'd0: if (m_axis_tvalid_a && m_axis_tlast_a) selected_valid_reg <= 1'b0;
                2'd1: if (m_axis_tvalid_b && m_axis_tlast_b) selected_valid_reg <= 1'b0;
                2'd2: if (m_axis_tvalid_c && m_axis_tlast_c) selected_valid_reg <= 1'b0;
                2'd3: if (m_axis_tvalid_d && m_axis_tlast_d) selected_valid_reg <= 1'b0;
            endcase
        end
    end
end

assign m_axis_tdata =
    selected_path_reg == 2'd0 ? m_axis_tdata_a :
    selected_path_reg == 2'd1 ? m_axis_tdata_b :
    selected_path_reg == 2'd2 ? m_axis_tdata_c :
    m_axis_tdata_d;

assign m_axis_tvalid =
    selected_valid_reg && (
    selected_path_reg == 2'd0 ? m_axis_tvalid_a :
    selected_path_reg == 2'd1 ? m_axis_tvalid_b :
    selected_path_reg == 2'd2 ? m_axis_tvalid_c :
    m_axis_tvalid_d);

assign m_axis_tlast =
    selected_path_reg == 2'd0 ? m_axis_tlast_a :
    selected_path_reg == 2'd1 ? m_axis_tlast_b :
    selected_path_reg == 2'd2 ? m_axis_tlast_c :
    m_axis_tlast_d;

assign m_axis_tuser =
    selected_path_reg == 2'd0 ? m_axis_tuser_a :
    selected_path_reg == 2'd1 ? m_axis_tuser_b :
    selected_path_reg == 2'd2 ? m_axis_tuser_c :
    m_axis_tuser_d;

assign error_bad_frame =
    selected_path_reg == 2'd0 ? error_bad_frame_a :
    selected_path_reg == 2'd1 ? error_bad_frame_b :
    selected_path_reg == 2'd2 ? error_bad_frame_c :
    error_bad_frame_d;

assign error_bad_fcs =
    selected_path_reg == 2'd0 ? error_bad_fcs_a :
    selected_path_reg == 2'd1 ? error_bad_fcs_b :
    selected_path_reg == 2'd2 ? error_bad_fcs_c :
    error_bad_fcs_d;

endmodule

`resetall
