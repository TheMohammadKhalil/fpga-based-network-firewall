// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * Firewall L3/L4 Rule Table  —  8 configurable rules
 *
 * Each rule stores:
 *   - Valid flag
 *   - Action      : 0 = DENY, 1 = ALLOW
 *   - Match enables (one per field — when 0 that field is a wildcard)
 *   - IP src / src mask (32-bit each)
 *   - IP dst / dst mask (32-bit each)
 *   - IP protocol byte (e.g. 6=TCP, 17=UDP, 1=ICMP)
 *   - Source port range [min, max]
 *   - Destination port range [min, max]
 *
 * Per-rule bit count:
 *   valid(1) + action(1) + match_enables(6) + protocol(8)
 *   + src_ip(32) + src_mask(32) + dst_ip(32) + dst_mask(32)
 *   + src_port_min(16) + src_port_max(16)
 *   + dst_port_min(16) + dst_port_max(16)
 *   = 208 bits  x8 rules = 1664 registers
 *
 * Configuration bus — indirect addressing (8-bit cfg_addr):
 *
 *   addr 0x10  rule_index register [2:0]   (selects rule 0-7 for writes below)
 *   addr 0x11  rule_flags :
 *                [0]  rule_valid
 *                [1]  action        (0=DENY, 1=ALLOW)
 *                [2]  match_src_ip
 *                [3]  match_dst_ip
 *                [4]  match_protocol
 *                [5]  match_src_port
 *                [6]  match_dst_port
 *                [7]  block_fragments  (drop if ip_is_fragment)
 *              bits [15:8] = protocol value
 *   addr 0x12  src_ip   [31:0]
 *   addr 0x13  src_mask [31:0]
 *   addr 0x14  dst_ip   [31:0]
 *   addr 0x15  dst_mask [31:0]
 *   addr 0x16  src ports: {src_port_max[15:0], src_port_min[15:0]}
 *   addr 0x17  dst ports: {dst_port_max[15:0], dst_port_min[15:0]}
 *
 * Reset defaults
 *   Rule 0 defaults to ALLOW with all match enables cleared, which means
 *   "allow all IPv4" for first bring-up on hardware.
 *   Remaining rules reset invalid.
 *
 *   This keeps the data path easy to test on the board while preserving the
 *   full rule table in synthesis.  More specific rules can still be loaded
 *   later through the config path.
 *
 * Synthesis notes
 *   All output regs are declared as internal registers with (* noprune *)
 *   to guarantee Quartus does not eliminate them via constant propagation.
 *   Outputs are exposed via combinational assigns.
 */
module firewall_rule_table #(
    parameter NUM_RULES = 8
) (
    input  wire        clk,
    input  wire        rst,

    // Configuration bus (8-bit address)
    input  wire        cfg_we,
    input  wire [7:0]  cfg_addr,
    input  wire [31:0] cfg_wdata,

    // Rule table outputs
    output wire [NUM_RULES-1:0] rule_valid,
    output wire [NUM_RULES-1:0] rule_action,
    output wire [NUM_RULES-1:0] rule_match_src_ip,
    output wire [NUM_RULES-1:0] rule_match_dst_ip,
    output wire [NUM_RULES-1:0] rule_match_protocol,
    output wire [NUM_RULES-1:0] rule_match_src_port,
    output wire [NUM_RULES-1:0] rule_match_dst_port,
    output wire [NUM_RULES-1:0] rule_block_fragments,

    output wire [8*NUM_RULES-1:0]  rule_protocol,
    output wire [32*NUM_RULES-1:0] rule_src_ip,
    output wire [32*NUM_RULES-1:0] rule_src_mask,
    output wire [32*NUM_RULES-1:0] rule_dst_ip,
    output wire [32*NUM_RULES-1:0] rule_dst_mask,
    output wire [16*NUM_RULES-1:0] rule_src_port_min,
    output wire [16*NUM_RULES-1:0] rule_src_port_max,
    output wire [16*NUM_RULES-1:0] rule_dst_port_min,
    output wire [16*NUM_RULES-1:0] rule_dst_port_max
);

// ---------------------------------------------------------------------------
// Internal registers — (* noprune *) prevents Quartus from removing FFs
// even when it can determine the reset value by constant analysis.
// ---------------------------------------------------------------------------

// Rule index register (selects which rule to configure)
reg [2:0] rule_idx;

(* noprune *) reg [NUM_RULES-1:0] rule_valid_r;
(* noprune *) reg [NUM_RULES-1:0] rule_action_r;
(* noprune *) reg [NUM_RULES-1:0] rule_match_src_ip_r;
(* noprune *) reg [NUM_RULES-1:0] rule_match_dst_ip_r;
(* noprune *) reg [NUM_RULES-1:0] rule_match_protocol_r;
(* noprune *) reg [NUM_RULES-1:0] rule_match_src_port_r;
(* noprune *) reg [NUM_RULES-1:0] rule_match_dst_port_r;
(* noprune *) reg [NUM_RULES-1:0] rule_block_fragments_r;

(* noprune *) reg [8*NUM_RULES-1:0]  rule_protocol_r;
(* noprune *) reg [32*NUM_RULES-1:0] rule_src_ip_r;
(* noprune *) reg [32*NUM_RULES-1:0] rule_src_mask_r;
(* noprune *) reg [32*NUM_RULES-1:0] rule_dst_ip_r;
(* noprune *) reg [32*NUM_RULES-1:0] rule_dst_mask_r;
(* noprune *) reg [16*NUM_RULES-1:0] rule_src_port_min_r;
(* noprune *) reg [16*NUM_RULES-1:0] rule_src_port_max_r;
(* noprune *) reg [16*NUM_RULES-1:0] rule_dst_port_min_r;
(* noprune *) reg [16*NUM_RULES-1:0] rule_dst_port_max_r;

// Expose internal registers via output wires
assign rule_valid           = rule_valid_r;
assign rule_action          = rule_action_r;
assign rule_match_src_ip    = rule_match_src_ip_r;
assign rule_match_dst_ip    = rule_match_dst_ip_r;
assign rule_match_protocol  = rule_match_protocol_r;
assign rule_match_src_port  = rule_match_src_port_r;
assign rule_match_dst_port  = rule_match_dst_port_r;
assign rule_block_fragments = rule_block_fragments_r;
assign rule_protocol        = rule_protocol_r;
assign rule_src_ip          = rule_src_ip_r;
assign rule_src_mask        = rule_src_mask_r;
assign rule_dst_ip          = rule_dst_ip_r;
assign rule_dst_mask        = rule_dst_mask_r;
assign rule_src_port_min    = rule_src_port_min_r;
assign rule_src_port_max    = rule_src_port_max_r;
assign rule_dst_port_min    = rule_dst_port_min_r;
assign rule_dst_port_max    = rule_dst_port_max_r;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rule_idx <= 3'd0;

        // Default: rule 0 is a wildcard ALLOW rule for IPv4 bring-up.
        // Any IPv4 packet matches rule 0 because all per-field match
        // enables reset low.  Rules 1..N stay invalid until configured.
        rule_valid_r           <= {{(NUM_RULES-1){1'b0}}, 1'b1};
        rule_action_r          <= {NUM_RULES{1'b1}}; // default action ALLOW
        rule_match_src_ip_r    <= {NUM_RULES{1'b0}};
        rule_match_dst_ip_r    <= {NUM_RULES{1'b0}};
        rule_match_protocol_r  <= {NUM_RULES{1'b0}};
        rule_match_src_port_r  <= {NUM_RULES{1'b0}};
        rule_match_dst_port_r  <= {NUM_RULES{1'b0}};
        rule_block_fragments_r <= {NUM_RULES{1'b0}};

        rule_protocol_r    <= {8*NUM_RULES{1'b0}};
        rule_src_ip_r      <= {32*NUM_RULES{1'b0}};
        rule_src_mask_r    <= {32*NUM_RULES{1'b0}};
        rule_dst_ip_r      <= {32*NUM_RULES{1'b0}};
        rule_dst_mask_r    <= {32*NUM_RULES{1'b0}};
        rule_src_port_min_r<= {16*NUM_RULES{1'b0}};
        rule_src_port_max_r<= {16*NUM_RULES{1'b1}}; // 0xFFFF (all ports)
        rule_dst_port_min_r<= {16*NUM_RULES{1'b0}};
        rule_dst_port_max_r<= {16*NUM_RULES{1'b1}};
    end else if (cfg_we) begin
        case (cfg_addr)
            // ---- Rule index selector ----
            8'h10: rule_idx <= cfg_wdata[2:0];

            // ---- Rule flags + protocol (for rule_idx) ----
            8'h11: begin
                rule_valid_r          [rule_idx] <= cfg_wdata[0];
                rule_action_r         [rule_idx] <= cfg_wdata[1];
                rule_match_src_ip_r   [rule_idx] <= cfg_wdata[2];
                rule_match_dst_ip_r   [rule_idx] <= cfg_wdata[3];
                rule_match_protocol_r [rule_idx] <= cfg_wdata[4];
                rule_match_src_port_r [rule_idx] <= cfg_wdata[5];
                rule_match_dst_port_r [rule_idx] <= cfg_wdata[6];
                rule_block_fragments_r[rule_idx] <= cfg_wdata[7];
                rule_protocol_r[rule_idx*8 +: 8] <= cfg_wdata[15:8];
            end

            // ---- Per-rule IP and port fields ----
            8'h12: rule_src_ip_r  [rule_idx*32 +: 32] <= cfg_wdata;
            8'h13: rule_src_mask_r[rule_idx*32 +: 32] <= cfg_wdata;
            8'h14: rule_dst_ip_r  [rule_idx*32 +: 32] <= cfg_wdata;
            8'h15: rule_dst_mask_r[rule_idx*32 +: 32] <= cfg_wdata;
            8'h16: begin
                rule_src_port_min_r[rule_idx*16 +: 16] <= cfg_wdata[15:0];
                rule_src_port_max_r[rule_idx*16 +: 16] <= cfg_wdata[31:16];
            end
            8'h17: begin
                rule_dst_port_min_r[rule_idx*16 +: 16] <= cfg_wdata[15:0];
                rule_dst_port_max_r[rule_idx*16 +: 16] <= cfg_wdata[31:16];
            end

            default: ;
        endcase
    end
end

endmodule

`resetall
