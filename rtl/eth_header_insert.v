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

// Latched header values for the current frame. Latched on the same cycle
// header_valid pulses so they remain stable through the 14-byte header send
// even if the upstream context_store updates while we're emitting.
reg [47:0] dst_mac_lat;
reg [47:0] src_mac_lat;
reg [15:0] ethertype_lat;

reg [3:0] hdr_index;
reg       sending_header;
reg       sending_payload;
reg [7:0] payload_buf_data;
reg       payload_buf_last;
reg       payload_buf_valid;

// "Output register has space" -- either empty or being consumed this cycle.
wire output_ready = !m_axis_tvalid || m_axis_tready;

assign s_axis_tready =
    (!sending_header && !sending_payload && !payload_buf_valid) ||
    (sending_payload && output_ready);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        hdr_index         <= 4'd0;
        sending_header    <= 1'b0;
        sending_payload   <= 1'b0;
        payload_buf_data  <= 8'd0;
        payload_buf_last  <= 1'b0;
        payload_buf_valid <= 1'b0;
        m_axis_tdata      <= 8'd0;
        m_axis_tvalid     <= 1'b0;
        m_axis_tlast      <= 1'b0;
        dst_mac_lat       <= 48'd0;
        src_mac_lat       <= 48'd0;
        ethertype_lat     <= 16'd0;
    end else begin
        // Clear output register only when actually consumed downstream.
        if (m_axis_tvalid && m_axis_tready) begin
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
        end

        // Start of a new frame: latch the header fields and arm hdr send.
        if (header_valid && !sending_header && !sending_payload) begin
            sending_header <= 1'b1;
            hdr_index      <= 4'd0;
            dst_mac_lat    <= dst_mac;
            src_mac_lat    <= src_mac;
            ethertype_lat  <= ethertype;
        end

        // Idle capture: stash the first payload byte while we send the header.
        if (!sending_header && !sending_payload && !payload_buf_valid &&
            s_axis_tvalid && s_axis_tready) begin
            payload_buf_data  <= s_axis_tdata;
            payload_buf_last  <= s_axis_tlast;
            payload_buf_valid <= 1'b1;
        end

        // Header emit: 14 bytes of dst/src/ethertype.
        if (sending_header && output_ready) begin
            m_axis_tvalid <= 1'b1;
            case (hdr_index)
                4'd0:  m_axis_tdata <= dst_mac_lat[47:40];
                4'd1:  m_axis_tdata <= dst_mac_lat[39:32];
                4'd2:  m_axis_tdata <= dst_mac_lat[31:24];
                4'd3:  m_axis_tdata <= dst_mac_lat[23:16];
                4'd4:  m_axis_tdata <= dst_mac_lat[15:8];
                4'd5:  m_axis_tdata <= dst_mac_lat[7:0];
                4'd6:  m_axis_tdata <= src_mac_lat[47:40];
                4'd7:  m_axis_tdata <= src_mac_lat[39:32];
                4'd8:  m_axis_tdata <= src_mac_lat[31:24];
                4'd9:  m_axis_tdata <= src_mac_lat[23:16];
                4'd10: m_axis_tdata <= src_mac_lat[15:8];
                4'd11: m_axis_tdata <= src_mac_lat[7:0];
                4'd12: m_axis_tdata <= ethertype_lat[15:8];
                4'd13: m_axis_tdata <= ethertype_lat[7:0];
                default: m_axis_tdata <= 8'h00;
            endcase

            if (hdr_index == 4'd13) begin
                sending_header <= 1'b0;
            end else begin
                hdr_index <= hdr_index + 4'd1;
            end
        end
        // After header: drain the buffered first payload byte.
        else if (!sending_header && !sending_payload && payload_buf_valid &&
                 output_ready) begin
            m_axis_tdata      <= payload_buf_data;
            m_axis_tvalid     <= 1'b1;
            m_axis_tlast      <= payload_buf_last;
            payload_buf_valid <= 1'b0;
            if (!payload_buf_last) begin
                sending_payload <= 1'b1;
            end
        end
        // Pass-through of remaining payload bytes from upstream.
        else if (sending_payload && s_axis_tvalid && s_axis_tready) begin
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
