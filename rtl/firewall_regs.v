module firewall_regs (
    input  wire        clk,
    input  wire        rst,
    input  wire        cfg_we,
    input  wire [3:0]  cfg_addr,
    input  wire [31:0] cfg_wdata,
    output reg  [47:0] allow_dst_mac,
    output reg  [47:0] allow_src_mac,
    output reg  [15:0] allow_ethertype,
    output reg  [15:0] min_frame_length,
    output reg  [15:0] max_frame_length,
    output reg         enforce_dst_mac,
    output reg         enforce_src_mac,
    output reg         enforce_ethertype,
    output reg         drop_crc_error
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        allow_dst_mac      <= 48'h000000000000;
        allow_src_mac      <= 48'h000000000000;
        allow_ethertype    <= 16'h0800;
        min_frame_length   <= 16'd64;
        max_frame_length   <= 16'd1518;
        enforce_dst_mac    <= 1'b0;
        enforce_src_mac    <= 1'b0;
        enforce_ethertype  <= 1'b0;
        drop_crc_error     <= 1'b1;
    end else if (cfg_we) begin
        case (cfg_addr)
            4'h0: allow_dst_mac[31:0]   <= cfg_wdata;
            4'h1: allow_dst_mac[47:32]  <= cfg_wdata[15:0];
            4'h2: allow_src_mac[31:0]   <= cfg_wdata;
            4'h3: allow_src_mac[47:32]  <= cfg_wdata[15:0];
            4'h4: allow_ethertype       <= cfg_wdata[15:0];
            4'h5: min_frame_length      <= cfg_wdata[15:0];
            4'h6: max_frame_length      <= cfg_wdata[15:0];
            4'h7: begin
                enforce_dst_mac   <= cfg_wdata[0];
                enforce_src_mac   <= cfg_wdata[1];
                enforce_ethertype <= cfg_wdata[2];
                drop_crc_error    <= cfg_wdata[3];
            end
            default: begin
            end
        endcase
    end
end

endmodule
