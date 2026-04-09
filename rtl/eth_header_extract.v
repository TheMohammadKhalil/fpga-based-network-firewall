module eth_header_extract (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,
    output wire [47:0] dst_mac,
    output wire [47:0] src_mac,
    output wire [15:0] ethertype,
    output wire [15:0] frame_length,
    output wire        header_valid,
    output wire        frame_done
);

reg [15:0] byte_count;
reg        in_frame;
reg        header_valid_reg;
reg        frame_done_reg;

assign header_valid = header_valid_reg;
assign frame_done = frame_done_reg;

reg [47:0] dst_mac_reg;
reg [47:0] src_mac_reg;
reg [15:0] ethertype_reg;
reg [15:0] frame_length_reg;

assign dst_mac = dst_mac_reg;
assign src_mac = src_mac_reg;
assign ethertype = ethertype_reg;
assign frame_length = frame_length_reg;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        dst_mac_reg      <= 48'd0;
        src_mac_reg      <= 48'd0;
        ethertype_reg    <= 16'd0;
        frame_length_reg <= 16'd0;
        header_valid_reg <= 1'b0;
        frame_done_reg   <= 1'b0;
        byte_count       <= 16'd0;
        in_frame         <= 1'b0;
    end else begin
        frame_done_reg <= 1'b0;

        if (s_axis_tvalid) begin
            if (!in_frame) begin
                in_frame         <= 1'b1;
                byte_count       <= 16'd0;
                header_valid_reg <= 1'b0;
            end

            case (byte_count)
                16'd0:  dst_mac_reg[47:40] <= s_axis_tdata;
                16'd1:  dst_mac_reg[39:32] <= s_axis_tdata;
                16'd2:  dst_mac_reg[31:24] <= s_axis_tdata;
                16'd3:  dst_mac_reg[23:16] <= s_axis_tdata;
                16'd4:  dst_mac_reg[15:8]  <= s_axis_tdata;
                16'd5:  dst_mac_reg[7:0]   <= s_axis_tdata;
                16'd6:  src_mac_reg[47:40] <= s_axis_tdata;
                16'd7:  src_mac_reg[39:32] <= s_axis_tdata;
                16'd8:  src_mac_reg[31:24] <= s_axis_tdata;
                16'd9:  src_mac_reg[23:16] <= s_axis_tdata;
                16'd10: src_mac_reg[15:8]  <= s_axis_tdata;
                16'd11: src_mac_reg[7:0]   <= s_axis_tdata;
                16'd12: ethertype_reg[15:8] <= s_axis_tdata;
                16'd13: begin
                    ethertype_reg[7:0]   <= s_axis_tdata;
                    header_valid_reg     <= 1'b1;
                end
                default: begin
                end
            endcase

            if (s_axis_tlast) begin
                frame_length_reg <= byte_count + 16'd1;
                frame_done_reg   <= 1'b1;
                in_frame         <= 1'b0;
                header_valid_reg <= 1'b0;
                byte_count       <= 16'd0;
            end else begin
                byte_count <= byte_count + 16'd1;
            end
        end
    end
end

endmodule
