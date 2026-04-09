module eth_header_insert (
    input  wire        clk,
    input  wire        rst,
    input  wire [47:0] dst_mac,
    input  wire [47:0] src_mac,
    input  wire [15:0] ethertype,
    input  wire        header_valid,
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,
    output wire        s_axis_tready,
    output reg  [7:0]  m_axis_tdata,
    output reg         m_axis_tvalid,
    output reg         m_axis_tlast,
    input  wire        m_axis_tready
);

reg [3:0] hdr_index;
reg       sending_header;
reg       sending_payload;

assign s_axis_tready = sending_payload && m_axis_tready;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        hdr_index      <= 4'd0;
        sending_header <= 1'b0;
        sending_payload<= 1'b0;
        m_axis_tdata   <= 8'd0;
        m_axis_tvalid  <= 1'b0;
        m_axis_tlast   <= 1'b0;
    end else begin
        m_axis_tvalid <= 1'b0;
        m_axis_tlast  <= 1'b0;

        if (header_valid && !sending_header && !sending_payload) begin
            sending_header <= 1'b1;
            hdr_index      <= 4'd0;
        end

        if (sending_header && m_axis_tready) begin
            m_axis_tvalid <= 1'b1;
            case (hdr_index)
                4'd0:  m_axis_tdata <= dst_mac[47:40];
                4'd1:  m_axis_tdata <= dst_mac[39:32];
                4'd2:  m_axis_tdata <= dst_mac[31:24];
                4'd3:  m_axis_tdata <= dst_mac[23:16];
                4'd4:  m_axis_tdata <= dst_mac[15:8];
                4'd5:  m_axis_tdata <= dst_mac[7:0];
                4'd6:  m_axis_tdata <= src_mac[47:40];
                4'd7:  m_axis_tdata <= src_mac[39:32];
                4'd8:  m_axis_tdata <= src_mac[31:24];
                4'd9:  m_axis_tdata <= src_mac[23:16];
                4'd10: m_axis_tdata <= src_mac[15:8];
                4'd11: m_axis_tdata <= src_mac[7:0];
                4'd12: m_axis_tdata <= ethertype[15:8];
                4'd13: m_axis_tdata <= ethertype[7:0];
                default: m_axis_tdata <= 8'h00;
            endcase

            if (hdr_index == 4'd13) begin
                sending_header  <= 1'b0;
                sending_payload <= 1'b1;
            end else begin
                hdr_index <= hdr_index + 4'd1;
            end
        end else if (sending_payload && s_axis_tvalid && m_axis_tready) begin
            m_axis_tdata  <= s_axis_tdata;
            m_axis_tvalid <= 1'b1;
            m_axis_tlast  <= s_axis_tlast;
            if (s_axis_tlast) begin
                sending_payload <= 1'b0;
            end
        end
    end
end

endmodule
