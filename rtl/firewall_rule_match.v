module firewall_rule_match (
    input  wire [47:0] dst_mac,
    input  wire [47:0] src_mac,
    input  wire [15:0] ethertype,
    input  wire [15:0] frame_length,
    input  wire        crc_error,
    input  wire [47:0] allow_dst_mac,
    input  wire [47:0] allow_src_mac,
    input  wire [15:0] allow_ethertype,
    input  wire [15:0] min_frame_length,
    input  wire [15:0] max_frame_length,
    input  wire        enforce_dst_mac,
    input  wire        enforce_src_mac,
    input  wire        enforce_ethertype,
    input  wire        drop_crc_error,
    output wire        allow_packet
);

wire dst_ok;
wire src_ok;
wire type_ok;
wire len_ok;
wire crc_ok;

assign dst_ok = (!enforce_dst_mac)   || (dst_mac == allow_dst_mac);
assign src_ok = (!enforce_src_mac)   || (src_mac == allow_src_mac);
assign type_ok = (!enforce_ethertype) || (ethertype == allow_ethertype);
assign len_ok = (frame_length >= min_frame_length) && (frame_length <= max_frame_length);
assign crc_ok = (!drop_crc_error) || (!crc_error);

assign allow_packet = dst_ok && src_ok && type_ok && len_ok && crc_ok;

endmodule
