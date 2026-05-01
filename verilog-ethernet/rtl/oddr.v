/*

Copyright (c) 2015-2018 Alex Forencich

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
 * Odd number of cycles delay
 */
module oddr #
(
    // target ("SIM", "GENERIC", "XILINX", "ALTERA")
    parameter TARGET = "GENERIC",
    // IODDR style ("IODDR", "IODDR2")
    parameter IODDR_STYLE = "IODDR",
    // number of bits
    parameter WIDTH = 1
)
(
    input  wire               clk,
    input  wire [WIDTH-1:0]   d1,
    input  wire [WIDTH-1:0]   d2,
    output wire [WIDTH-1:0]   q
);

generate
if (TARGET == "ALTERA") begin : altera_odd
    // Altera Cyclone V DDR output using altddio_out
    // The port names for Cyclone V altddio_out
    wire [WIDTH-1:0] q_wire;
    assign q = q_wire;

    if (WIDTH == 1) begin : single_bit
        altddio_out #(
            .intended_device_family("Cyclone IV E"),
            .invert_output("OFF"),
            .lpm_hint("UNUSED"),
            .lpm_type("altddio_out"),
            .power_up_state_low("LOW")
        )
        oddr_inst (
            .dataout(q_wire),
            .outclock(clk),
            .datain_h(d2),
            .datain_l(d1),
            .aclr(1'b0),
            .aset(1'b0),
            .oe(1'b1),
            .outclocken(1'b1),
            .sclr(1'b0)
        );
    end else begin : multi_bit
        genvar i;
        for (i = 0; i < WIDTH; i = i + 1) begin : bit_gen
            altddio_out #(
                .intended_device_family("Cyclone IV E"),
                .invert_output("OFF"),
                .lpm_hint("UNUSED"),
                .lpm_type("altddio_out"),
                .power_up_state_low("LOW")
            )
            oddr_inst (
                .dataout(q_wire[i]),
                .outclock(clk),
                .datain_h(d2[i]),
                .datain_l(d1[i]),
                .aclr(1'b0),
                .aset(1'b0),
                .oe(1'b1),
                .outclocken(1'b1),
                .sclr(1'b0)
            );
        end
    end

end else if (TARGET == "XILINX") begin : xilinx_odd

    if (IODDR_STYLE == "IODDR") begin : ioddr
        // Xilinx 7-series, Ultrascale
        ODDR #(
            .DDR_CLK_EDGE("SAME_EDGE"),
            .INIT(1'b0),
            .SRTYPE("SYNC")
        )
        oddr_inst (
            .Q(q),
            .C(clk),
            .CE(1'b1),
            .D1(d1),
            .D2(d2),
            .R(1'b0),
            .S(1'b0)
        );
    end else if (IODDR_STYLE == "IODDR2") begin : ioddr2
        // Xilinx Spartan-6
        OSERDES2 #(
            .DATA_RATE_OQ("SDR"),
            .DATA_RATE_OT("SDR"),
            .SERDES_MODE("MASTER"),
            .DATA_PASSTHROUGH("FALSE"),
            .INPUT_MODE("SERDES"),
            .OUTPUT_MODE("SINGLE_ENDED"),
            .DATA_WIDTH(WIDTH)
        )
        oddr_inst (
            .OQ(q),
            .CLK(clk),
            .CLKDIV(1'b0),
            .D1(d1),
            .D2(d2),
            .D3(1'b0),
            .D4(1'b0),
            .T1(1'b0),
            .T2(1'b0),
            .T3(1'b0),
            .T4(1'b0),
            .OC(1'b0),
            .OCE(1'b1),
            .SHIFTIN1(1'b0),
            .SHIFTIN2(1'b0),
            .SHIFTOUT1(),
            .SHIFTOUT2()
        );
    end

end else begin : sim_odd

    // Simulation / generic
    reg [WIDTH-1:0] q_reg = 0;

    assign q = q_reg;

    always @(posedge clk) begin
        q_reg <= d1;
    end

end
endgenerate

endmodule

`resetall
