/*

Copyright (c) 2014-2018 Alex Forencich

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
 * Switch / button debouncer
 *
 * Samples the synchronised input every RATE clock cycles and passes it
 * through to the output.  At 125 MHz with RATE=125000 the debounce
 * window is 1 ms per stage.
 */
module debounce_switch #(
    parameter WIDTH = 1,
    parameter N     = 3,
    parameter RATE  = 125000
) (
    input  wire             clk,
    input  wire             rst,
    input  wire [WIDTH-1:0] in,
    output reg  [WIDTH-1:0] out
);

localparam CNT_W = $clog2(RATE);

// Two-flop synchroniser for each bit
reg [WIDTH-1:0] sync_1 = {WIDTH{1'b0}};
reg [WIDTH-1:0] sync_2 = {WIDTH{1'b0}};

always @(posedge clk) begin
    sync_1 <= in;
    sync_2 <= sync_1;
end

// Rate divider — sample sync_2 every RATE cycles
reg [CNT_W-1:0] cnt = {CNT_W{1'b0}};

always @(posedge clk) begin
    if (rst) begin
        cnt <= {CNT_W{1'b0}};
        out <= {WIDTH{1'b0}};
    end else begin
        cnt <= cnt + {{CNT_W-1{1'b0}}, 1'b1};
        if (cnt == RATE - 1) begin
            cnt <= {CNT_W{1'b0}};
            out <= sync_2;
        end
    end
end

endmodule

`resetall
