// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * L3 / L4 Rule Matching Engine  —  8 rules evaluated in parallel
 *
 * Each rule is evaluated combinationally against the captured packet
 * context.  The first matching rule (lowest index) determines the
 * packet action (ALLOW / DENY).  If no rule matches the default
 * policy is DENY.
 *
 * A rule "matches" when ALL enabled match conditions are true:
 *   - (src_ip  & src_mask) == (rule_src_ip  & src_mask)
 *   - (dst_ip  & dst_mask) == (rule_dst_ip  & dst_mask)
 *   - protocol == rule_protocol
 *   - src_port in [src_port_min .. src_port_max]
 *   - dst_port in [dst_port_min .. dst_port_max]
 *   - !(block_fragments && ip_is_fragment)
 *
 * If the packet is NOT IPv4 (is_ipv4 == 0) the L3 match is bypassed
 * and allow_packet is forced to 1 (L2 layer alone decides).
 *
 * Parameters
 *   NUM_RULES : number of rules (must equal rule_table parameter)
 */
module firewall_l3_rule_match #(
    parameter NUM_RULES = 8
) (
    // Packet context (registered by header_context_store)
    input  wire        is_ipv4,
    input  wire        ip_is_fragment,
    input  wire [7:0]  ip_protocol,
    input  wire [31:0] ip_src,
    input  wire [31:0] ip_dst,
    input  wire [15:0] l4_src_port,
    input  wire [15:0] l4_dst_port,

    // Rule table (from firewall_rule_table)
    input  wire [NUM_RULES-1:0] rule_valid,
    input  wire [NUM_RULES-1:0] rule_action,
    input  wire [NUM_RULES-1:0] rule_match_src_ip,
    input  wire [NUM_RULES-1:0] rule_match_dst_ip,
    input  wire [NUM_RULES-1:0] rule_match_protocol,
    input  wire [NUM_RULES-1:0] rule_match_src_port,
    input  wire [NUM_RULES-1:0] rule_match_dst_port,
    input  wire [NUM_RULES-1:0] rule_block_fragments,

    input  wire [8*NUM_RULES-1:0]  rule_protocol,
    input  wire [32*NUM_RULES-1:0] rule_src_ip,
    input  wire [32*NUM_RULES-1:0] rule_src_mask,
    input  wire [32*NUM_RULES-1:0] rule_dst_ip,
    input  wire [32*NUM_RULES-1:0] rule_dst_mask,
    input  wire [16*NUM_RULES-1:0] rule_src_port_min,
    input  wire [16*NUM_RULES-1:0] rule_src_port_max,
    input  wire [16*NUM_RULES-1:0] rule_dst_port_min,
    input  wire [16*NUM_RULES-1:0] rule_dst_port_max,

    // Result
    output wire allow_packet   // 1 = allow, 0 = deny
);

// -------------------------------------------------------------------------
// Per-rule hit vectors (combinational)
// -------------------------------------------------------------------------
wire [NUM_RULES-1:0] rule_hit;
wire [NUM_RULES-1:0] rule_allow_vec;

genvar r;
generate
for (r = 0; r < NUM_RULES; r = r + 1) begin : gen_rules

    // Extract rule fields from flat vectors
    wire [7:0]  r_protocol     = rule_protocol    [r*8  +: 8 ];
    wire [31:0] r_src_ip       = rule_src_ip      [r*32 +: 32];
    wire [31:0] r_src_mask     = rule_src_mask    [r*32 +: 32];
    wire [31:0] r_dst_ip       = rule_dst_ip      [r*32 +: 32];
    wire [31:0] r_dst_mask     = rule_dst_mask    [r*32 +: 32];
    wire [15:0] r_src_port_min = rule_src_port_min[r*16 +: 16];
    wire [15:0] r_src_port_max = rule_src_port_max[r*16 +: 16];
    wire [15:0] r_dst_port_min = rule_dst_port_min[r*16 +: 16];
    wire [15:0] r_dst_port_max = rule_dst_port_max[r*16 +: 16];

    // Individual match conditions
    wire src_ip_ok   = !rule_match_src_ip[r]   ||
                       ((ip_src  & r_src_mask) == (r_src_ip  & r_src_mask));
    wire dst_ip_ok   = !rule_match_dst_ip[r]   ||
                       ((ip_dst  & r_dst_mask) == (r_dst_ip  & r_dst_mask));
    wire proto_ok    = !rule_match_protocol[r]  ||
                       (ip_protocol == r_protocol);
    wire src_port_ok = !rule_match_src_port[r]  ||
                       ((l4_src_port >= r_src_port_min) &&
                        (l4_src_port <= r_src_port_max));
    wire dst_port_ok = !rule_match_dst_port[r]  ||
                       ((l4_dst_port >= r_dst_port_min) &&
                        (l4_dst_port <= r_dst_port_max));
    wire frag_ok     = !(rule_block_fragments[r] && ip_is_fragment);

    // This rule fires when valid and all enabled conditions pass
    assign rule_hit[r] = rule_valid[r] &&
                         src_ip_ok && dst_ip_ok &&
                         proto_ok  &&
                         src_port_ok && dst_port_ok &&
                         frag_ok;

    assign rule_allow_vec[r] = rule_hit[r] && rule_action[r];
end
endgenerate

// -------------------------------------------------------------------------
// Priority encoder: find lowest-index matching rule
// -------------------------------------------------------------------------
// any_hit   : at least one rule matched
// any_allow : a matched rule says ALLOW
//
// Because rules are evaluated in parallel, we need first-match priority.
// We compute a "mask" that keeps only the lowest-set-bit of rule_hit.

wire [NUM_RULES-1:0] first_hit;
assign first_hit = rule_hit & (~rule_hit + {{NUM_RULES-1{1'b0}}, 1'b1});
// first_hit is rule_hit with only the lowest-numbered set bit kept.

wire any_hit;
assign any_hit = |rule_hit;

// Action of the first-matching rule
wire first_action;
assign first_action = |(first_hit & rule_action);

// -------------------------------------------------------------------------
// Final decision
// -------------------------------------------------------------------------
// Non-IPv4 packets bypass L3 matching entirely (always allowed at L3).
// IPv4 packets: allow only if a valid rule matches and its action = ALLOW.
assign allow_packet = !is_ipv4 || (any_hit && first_action);

endmodule

`resetall
