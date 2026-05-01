#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

iverilog -g2001 -Wall -o sim/firewall_tb \
    rtl/firewall_regs.v \
    rtl/eth_header_extract.v \
    rtl/ip_header_extract.v \
    rtl/tcp_udp_header_extract.v \
    rtl/header_context_store.v \
    rtl/firewall_rule_match.v \
    rtl/firewall_rule_table.v \
    rtl/firewall_l3_rule_match.v \
    rtl/firewall_rx_parser.v \
    rtl/firewall_decision.v \
    rtl/eth_header_insert.v \
    rtl/firewall_tx_rebuild.v \
    rtl/fpga_firewall_top.v \
    tb/firewall_tb.v

vvp sim/firewall_tb

echo
echo "Waveform written to firewall_tb.vcd"
echo "Open with: gtkwave firewall_tb.vcd docs/firewall_tb.gtkw"
