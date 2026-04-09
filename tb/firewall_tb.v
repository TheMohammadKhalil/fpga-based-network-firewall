/*
 * Testbench for FPGA Firewall
 *
 * This testbench simulates the firewall with test Ethernet frames
 * to verify correct filtering behavior.
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

module firewall_tb;

// Test parameters
parameter CLK_PERIOD = 8;  // 125 MHz
parameter RESET_PERIOD = 50;

// Clock and reset
reg clk = 0;
reg rst = 1;

// Test stimulus registers
reg [7:0] s_axis_tdata = 8'd0;
reg s_axis_tvalid = 0;
reg s_axis_tlast = 0;
wire s_axis_tready;

// Output wires
wire [7:0] m_axis_tdata;
wire m_axis_tvalid;
wire m_axis_tlast;
reg m_axis_tready = 1;

// Configuration interface
reg cfg_clk = 0;
reg cfg_rst_n = 1;
reg cfg_we = 0;
reg [3:0] cfg_addr = 4'd0;
reg [31:0] cfg_wdata = 32'd0;
wire [31:0] cfg_rdata;

// Status outputs
wire packet_allowed;
wire packet_dropped;

// CRC error (tied low for basic tests)
reg crc_error_in = 0;

// Clock generation
always #((CLK_PERIOD/2)) clk = ~clk;

// Config clock generation
always #4 cfg_clk = ~cfg_clk;

// Reset sequence
initial begin
    #RESET_PERIOD;
    rst = 0;
    cfg_rst_n = 1;
end

// Configuration task
task configure_firewall;
    input [47:0] allow_dst;
    input [47:0] allow_src;
    input [15:0] allow_type;
    input [15:0] min_len;
    input [15:0] max_len;
    input        en_dst;
    input        en_src;
    input        en_type;
    input        drop_crc;

    reg [47:0] allow_dst_reg;
    reg [47:0] allow_src_reg;
    reg [15:0] allow_type_reg;
    reg [15:0] min_len_reg;
    reg [15:0] max_len_reg;
    reg        en_dst_reg;
    reg        en_src_reg;
    reg        en_type_reg;
    reg        drop_crc_reg;
begin
    allow_dst_reg = allow_dst;
    allow_src_reg = allow_src;
    allow_type_reg = allow_type;
    min_len_reg = min_len;
    max_len_reg = max_len;
    en_dst_reg = en_dst;
    en_src_reg = en_src;
    en_type_reg = en_type;
    drop_crc_reg = drop_crc;

    // Wait for config clock edge
    @(posedge cfg_clk);

    // Write allow_dst_mac (2 writes for 48 bits)
    cfg_we = 1; cfg_addr = 4'h0; cfg_wdata = allow_dst_reg[31:0];  @(posedge cfg_clk);
    cfg_we = 1; cfg_addr = 4'h1; cfg_wdata = {16'd0, allow_dst_reg[47:32]}; @(posedge cfg_clk);

    // Write allow_src_mac (2 writes)
    cfg_we = 1; cfg_addr = 4'h2; cfg_wdata = allow_src_reg[31:0];  @(posedge cfg_clk);
    cfg_we = 1; cfg_addr = 4'h3; cfg_wdata = {16'd0, allow_src_reg[47:32]}; @(posedge cfg_clk);

    // Write ethertype
    cfg_we = 1; cfg_addr = 4'h4; cfg_wdata = {16'd0, allow_type_reg}; @(posedge cfg_clk);

    // Write min/max frame length
    cfg_we = 1; cfg_addr = 4'h5; cfg_wdata = {16'd0, min_len_reg}; @(posedge cfg_clk);
    cfg_we = 1; cfg_addr = 4'h6; cfg_wdata = {16'd0, max_len_reg}; @(posedge cfg_clk);

    // Write control register
    cfg_we = 1; cfg_addr = 4'h7;
    cfg_wdata = {28'd0, drop_crc_reg, en_type_reg, en_src_reg, en_dst_reg};
    @(posedge cfg_clk);

    cfg_we = 0;
    cfg_addr = 4'd0;
    cfg_wdata = 32'd0;
end
endtask

// Instantiate the firewall top module
fpga_firewall_top dut (
    .clk(clk),
    .rst(rst),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tlast(s_axis_tlast),
    .s_axis_tready(s_axis_tready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tlast(m_axis_tlast),
    .m_axis_tready(m_axis_tready),
    .cfg_we(cfg_we),
    .cfg_addr(cfg_addr),
    .cfg_wdata(cfg_wdata),
    .crc_error_in(crc_error_in),
    .packet_allowed(packet_allowed),
    .packet_dropped(packet_dropped)
);

// Test sequence
initial begin
    $display("=== FPGA Firewall Testbench ===");
    $display("Starting simulation...");

    // Wait for reset to complete
    #100;

    $display("\n--- Test 1: Configure firewall ---");
    // Configure: Allow dst MAC 00:11:22:33:44:55, any src, ethertype 0x0800
    configure_firewall(
        48'h001122334455,  // allow_dst
        48'h000000000000,  // allow_src (not enforced)
        16'h0800,          // allow_ethertype (IPv4)
        16'd64,            // min_frame_length
        16'd1518,          // max_frame_length
        1'b1,              // enforce_dst_mac
        1'b0,              // enforce_src_mac
        1'b0,              // enforce_ethertype
        1'b1               // drop_crc_error
    );
    $display("Firewall configured.");

    #100;

    $display("\n--- Test 2: Send matching frame (should ALLOW) ---");
    // Send frame inline (task doesn't work with literal concatenations in Verilog-2001)
    send_frame_inline(
        48'h001122334455,  // dst_mac (matches)
        48'hAABBCCDDEEFF,  // src_mac
        16'h0800,          // ethertype (IPv4)
        64'hDEADBEEFCAFEBABE, // payload
        4'd8               // payload_len
    );

    #200;

    $display("\n--- Test 3: Send non-matching frame (should DROP) ---");
    // Send frame with non-matching destination MAC
    send_frame_inline(
        48'hFFFFFFFFFFFF,  // dst_mac (broadcast - doesn't match)
        48'hAABBCCDDEEFF,  // src_mac
        16'h0800,          // ethertype
        64'h1234567890ABCDEF, // payload
        4'd8               // payload_len
    );

    #200;

    $display("\n--- Test 4: Send matching frame (should ALLOW) ---");
    send_frame_inline(
        48'h001122334455,  // dst_mac (matches)
        48'h123456789ABC,  // src_mac
        16'h0800,          // ethertype
        64'hFEDCBA9876543210, // payload
        4'd8               // payload_len
    );

    #200;

    $display("\n=== Test Complete ===");
    $display("Check waveform for packet_allowed and packet_dropped signals.");

    #100;
    $finish;
end

// Send Ethernet frame inline (Verilog-2001 compatible)
task send_frame_inline;
    input [47:0] dst_mac;
    input [47:0] src_mac;
    input [15:0] ethertype;
    input [63:0] payload;
    input [3:0] payload_len;

    reg [47:0] dst_mac_reg;
    reg [47:0] src_mac_reg;
    reg [15:0] ethertype_reg;
    reg [63:0] payload_reg;
    reg [3:0] payload_len_reg;
    integer i;
begin
    dst_mac_reg = dst_mac;
    src_mac_reg = src_mac;
    ethertype_reg = ethertype;
    payload_reg = payload;
    payload_len_reg = payload_len;

    // Send destination MAC (6 bytes) - MSB first
    for (i = 0; i < 6; i = i + 1) begin
        @(posedge clk);
        s_axis_tdata = dst_mac_reg[47-(i*8) -: 8];
        s_axis_tvalid = 1;
        s_axis_tlast = 0;
    end

    // Send source MAC (6 bytes) - MSB first
    for (i = 0; i < 6; i = i + 1) begin
        @(posedge clk);
        s_axis_tdata = src_mac_reg[47-(i*8) -: 8];
        s_axis_tvalid = 1;
        s_axis_tlast = 0;
    end

    // Send ethertype (2 bytes) - MSB first
    for (i = 0; i < 2; i = i + 1) begin
        @(posedge clk);
        s_axis_tdata = ethertype_reg[15-(i*8) -: 8];
        s_axis_tvalid = 1;
        s_axis_tlast = 0;
    end

    // Send payload
    for (i = 0; i < payload_len_reg; i = i + 1) begin
        @(posedge clk);
        s_axis_tdata = (payload_reg >> (8*(payload_len_reg-1-i))) & 8'hFF;
        s_axis_tvalid = 1;
        s_axis_tlast = (i == payload_len_reg - 1);
    end

    // End of frame
    @(posedge clk);
    s_axis_tvalid = 0;
    s_axis_tlast = 0;
end
endtask

// Monitor outputs
always @(posedge clk) begin
    if (m_axis_tvalid && m_axis_tready) begin
        $display("[%0t] TX: data=0x%02h, last=%b", $time, m_axis_tdata, m_axis_tlast);
    end
    if (packet_allowed) begin
        $display("[%0t] *** PACKET ALLOWED ***", $time);
    end
    if (packet_dropped) begin
        $display("[%0t] *** PACKET DROPPED ***", $time);
    end
end

// Initial values
initial begin
    s_axis_tdata = 8'd0;
    s_axis_tvalid = 0;
    s_axis_tlast = 0;
    cfg_we = 0;
    cfg_addr = 4'd0;
    cfg_wdata = 32'd0;
end

endmodule

`resetall
