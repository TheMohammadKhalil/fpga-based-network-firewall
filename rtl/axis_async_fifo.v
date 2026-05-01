`resetall
`timescale 1ns / 1ps
`default_nettype none

module axis_async_fifo #
(
    parameter DEPTH = 1024,
    parameter DATA_WIDTH = 8,
    parameter USER_WIDTH = 1
)
(
    input  wire                  s_clk,
    input  wire                  s_rst,
    input  wire [DATA_WIDTH-1:0] s_axis_tdata,
    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,
    input  wire                  s_axis_tlast,
    input  wire [USER_WIDTH-1:0] s_axis_tuser,

    input  wire                  m_clk,
    input  wire                  m_rst,
    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire                  m_axis_tvalid,
    input  wire                  m_axis_tready,
    output wire                  m_axis_tlast,
    output wire [USER_WIDTH-1:0] m_axis_tuser
);

localparam ADDR_WIDTH = $clog2(DEPTH);
localparam WIDTH = DATA_WIDTH + 1 + USER_WIDTH;

reg [WIDTH-1:0] mem[0:DEPTH-1];

reg [ADDR_WIDTH:0] wr_ptr_bin_reg = 0;
reg [ADDR_WIDTH:0] wr_ptr_gray_reg = 0;
reg [ADDR_WIDTH:0] rd_ptr_bin_reg = 0;
reg [ADDR_WIDTH:0] rd_ptr_gray_reg = 0;

reg [ADDR_WIDTH:0] wr_ptr_gray_sync1_reg = 0;
reg [ADDR_WIDTH:0] wr_ptr_gray_sync2_reg = 0;
reg [ADDR_WIDTH:0] rd_ptr_gray_sync1_reg = 0;
reg [ADDR_WIDTH:0] rd_ptr_gray_sync2_reg = 0;

reg [WIDTH-1:0] m_axis_reg = 0;
reg m_axis_tvalid_reg = 1'b0;

wire [ADDR_WIDTH:0] wr_ptr_bin_next = wr_ptr_bin_reg + 1'b1;
wire [ADDR_WIDTH:0] rd_ptr_bin_next = rd_ptr_bin_reg + 1'b1;

wire [ADDR_WIDTH:0] wr_ptr_gray_next = wr_ptr_bin_next ^ (wr_ptr_bin_next >> 1);
wire [ADDR_WIDTH:0] rd_ptr_gray_next = rd_ptr_bin_next ^ (rd_ptr_bin_next >> 1);

wire full = wr_ptr_gray_next == {~rd_ptr_gray_sync2_reg[ADDR_WIDTH:ADDR_WIDTH-1], rd_ptr_gray_sync2_reg[ADDR_WIDTH-2:0]};
wire empty = rd_ptr_gray_reg == wr_ptr_gray_sync2_reg;

assign s_axis_tready = !full;

assign m_axis_tdata = m_axis_reg[DATA_WIDTH-1:0];
assign m_axis_tlast = m_axis_reg[DATA_WIDTH];
assign m_axis_tuser = m_axis_reg[DATA_WIDTH+1 +: USER_WIDTH];
assign m_axis_tvalid = m_axis_tvalid_reg;

always @(posedge s_clk or posedge s_rst) begin
    if (s_rst) begin
        wr_ptr_bin_reg <= 0;
        wr_ptr_gray_reg <= 0;
        rd_ptr_gray_sync1_reg <= 0;
        rd_ptr_gray_sync2_reg <= 0;
    end else begin
        rd_ptr_gray_sync1_reg <= rd_ptr_gray_reg;
        rd_ptr_gray_sync2_reg <= rd_ptr_gray_sync1_reg;

        if (s_axis_tvalid && s_axis_tready) begin
            mem[wr_ptr_bin_reg[ADDR_WIDTH-1:0]] <= {s_axis_tuser, s_axis_tlast, s_axis_tdata};
            wr_ptr_bin_reg <= wr_ptr_bin_next;
            wr_ptr_gray_reg <= wr_ptr_gray_next;
        end
    end
end

always @(posedge m_clk or posedge m_rst) begin
    if (m_rst) begin
        rd_ptr_bin_reg <= 0;
        rd_ptr_gray_reg <= 0;
        wr_ptr_gray_sync1_reg <= 0;
        wr_ptr_gray_sync2_reg <= 0;
        m_axis_reg <= 0;
        m_axis_tvalid_reg <= 1'b0;
    end else begin
        wr_ptr_gray_sync1_reg <= wr_ptr_gray_reg;
        wr_ptr_gray_sync2_reg <= wr_ptr_gray_sync1_reg;

        if (!m_axis_tvalid_reg || m_axis_tready) begin
            if (!empty) begin
                m_axis_reg <= mem[rd_ptr_bin_reg[ADDR_WIDTH-1:0]];
                rd_ptr_bin_reg <= rd_ptr_bin_next;
                rd_ptr_gray_reg <= rd_ptr_gray_next;
                m_axis_tvalid_reg <= 1'b1;
            end else begin
                m_axis_tvalid_reg <= 1'b0;
            end
        end
    end
end

endmodule

`resetall
