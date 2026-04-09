module header_context_store (
    input  wire        clk,
    input  wire        rst,
    input  wire [47:0] in_dst_mac,
    input  wire [47:0] in_src_mac,
    input  wire [15:0] in_ethertype,
    input  wire [15:0] in_frame_length,
    input  wire        in_crc_error,
    input  wire        header_valid,
    input  wire        frame_done,
    output reg  [47:0] out_dst_mac,
    output reg  [47:0] out_src_mac,
    output reg  [15:0] out_ethertype,
    output reg  [15:0] out_frame_length,
    output reg         out_crc_error,
    output reg         context_valid
);

reg frame_done_delayed;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        out_dst_mac      <= 48'd0;
        out_src_mac      <= 48'd0;
        out_ethertype    <= 16'd0;
        out_frame_length <= 16'd0;
        out_crc_error    <= 1'b0;
        context_valid    <= 1'b0;
        frame_done_delayed <= 1'b0;
    end else begin
        frame_done_delayed <= frame_done;

        if (header_valid) begin
            out_dst_mac      <= in_dst_mac;
            out_src_mac      <= in_src_mac;
            out_ethertype    <= in_ethertype;
            out_crc_error    <= in_crc_error;
            out_frame_length <= in_frame_length;
            context_valid    <= 1'b1;
        end

        // Clear context after it has been used by tx_rebuild
        if (frame_done_delayed) begin
            context_valid <= 1'b0;
        end
    end
end

endmodule
