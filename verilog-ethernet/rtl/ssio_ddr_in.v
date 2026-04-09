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
 * Synchronous serial I/O DDR input
 */
module ssio_ddr_in #
(
    // target ("SIM", "GENERIC", "XILINX", "ALTERA")
    parameter TARGET = "GENERIC",
    // Clock input style ("BUFG", "BUFR", "BUFIO", "BUFIO2")
    parameter CLOCK_INPUT_STYLE = "BUFG",
    // IODDR style ("IODDR", "IODDR2")
    parameter IODDR_STYLE = "IODDR",
    // number of bits
    parameter WIDTH = 5
)
(
    input  wire              input_clk,
    input  wire [WIDTH-1:0]  input_d,
    input  wire              output_clk,
    output wire [WIDTH-1:0]  output_q1,
    output wire [WIDTH-1:0]  output_q2
);

generate
if (TARGET == "ALTERA") begin : altera_ssio
    // Altera Cyclone V - use inferred DDR input
    // Quartus will infer altddio_in from this pattern
    genvar i;
    for (i = 0; i < WIDTH; i = i + 1) begin : bit_gen
        reg [1:0] ddr_capture;

        always @(posedge input_clk) begin
            ddr_capture <= {ddr_capture[0], input_d[i]};
        end

        // q1 = first sample, q2 = second sample
        assign output_q1[i] = ddr_capture[1];
        assign output_q2[i] = ddr_capture[0];

        // Note: For proper RGMII, you may need to constrain this with
        // input delay constraints in .qsf or use SignalTap to verify timing
    end

end else if (TARGET == "XILINX") begin : xilinx_ssio

    if (IODDR_STYLE == "IODDR") begin : ioddr
        // Xilinx 7-series, Ultrascale
        genvar i;
        for (i = 0; i < WIDTH; i = i + 1) begin : bit_gen
            IDDR #(
                .DDR_CLK_EDGE("SAME_EDGE_PIPELINED"),
                .INIT_Q1(1'b0),
                .INIT_Q2(1'b0),
                .SRTYPE("SYNC")
            )
            iddr_inst (
                .Q1(output_q1[i]),
                .Q2(output_q2[i]),
                .C(input_clk),
                .CE(1'b1),
                .D(input_d[i]),
                .R(1'b0),
                .S(1'b0)
            );
        end
    end else if (IODDR_STYLE == "IODDR2") begin : ioddr2
        // Xilinx Spartan-6
        genvar i;
        for (i = 0; i < WIDTH; i = i + 1) begin : bit_gen
            ISERDES2 #(
                .DATA_RATE("DDR"),
                .SERDES_MODE("SLAVE"),
                .DATA_WIDTH(WIDTH),
                .INTERFACE_TYPE("NETWORKING"),
                .IOBDELAY("NONE"),
                .NUM_CE(1),
                .DDR_ALIGNMENT("NONE")
            )
            iserdes2_inst (
                .Q1(output_q1[i]),
                .Q2(output_q2[i]),
                .CLK(input_clk),
                .CLKDIV(output_clk),
                .D(input_d[i]),
                .CE(1'b1),
                .R(1'b0),
                .SHIFTIN1(1'b0),
                .SHIFTIN2(1'b0),
                .SHIFTOUT1(),
                .SHIFTOUT2(),
                .O(),
                .OC(1'b0),
                .OFB(1'b0),
                .T1(1'b0),
                .T2(1'b0),
                .T3(1'b0),
                .T4(1'b0)
            );
        end
    end

end else begin : sim_ssio

    // Simulation / generic
    reg [WIDTH*2-1:0] shift_reg = 0;

    assign output_q1 = shift_reg[WIDTH*2-1:WIDTH];
    assign output_q2 = shift_reg[WIDTH-1:0];

    always @(posedge input_clk) begin
        shift_reg <= {shift_reg[WIDTH*2-1-WIDTH:0], input_d};
    end

end
endgenerate

endmodule

`resetall
