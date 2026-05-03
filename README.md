# FPGA-Based Ethernet Bridge

This project currently builds a working transparent Ethernet bridge on the
Terasic DE2-115 FPGA board. The board sits inline between a router LAN port and
a laptop, forwards Ethernet frames in both directions, and lets the laptop gain
network and internet access through the FPGA over a wired LAN cable.

The original firewall RTL is still kept in the repository for reference and
future work, but the active Quartus board build now bypasses firewall rules,
slide switches, and HEX displays. The current goal is reliable LAN pass-through.

## Current Working Setup

Tested cabling:

```text
router LAN port -> FPGA ENET0
laptop Ethernet -> FPGA ENET1
```

Tested result:

- The laptop's Wi-Fi was disconnected.
- The wired interface became active.
- Internet access still worked through the LAN cable.
- This confirms traffic was passing through the FPGA bridge.

## What We Built

The active top-level design is `rtl/fpga.v`, which instantiates
`rtl/fpga_core.v`.

The bridge datapath is:

```text
ENET0 PHY RX
  -> DE2-115 RGMII RX aligner
  -> AXI-Stream async FIFO
  -> RGMII MAC transmitter
  -> ENET1 PHY TX

ENET1 PHY RX
  -> DE2-115 RGMII RX aligner
  -> AXI-Stream async FIFO
  -> RGMII MAC transmitter
  -> ENET0 PHY TX
```

Important implementation details:

- Uses the DE2-115 Ethernet ports in RGMII mode.
- Receives complete Ethernet frames on each port.
- Checks/strips the incoming FCS on RX.
- Re-generates the FCS on TX.
- Uses async FIFOs to cross from each PHY RX clock domain into the opposite TX
  clock domain.
- Removes the old switch-controlled firewall path from the board build.
- Removes HEX display outputs from the board build.
- Uses LEDs for live link, traffic, and error bring-up.

## Main Source Files

Active board build:

| File | Purpose |
| --- | --- |
| `rtl/fpga.v` | DE2-115 board top, PLL, reset, Ethernet pin wiring |
| `rtl/fpga_core.v` | Transparent two-port Ethernet bridge |
| `rtl/de2_rgmii_rx.v` | DE2-115 RGMII RX alignment and frame decode |
| `rtl/axis_async_fifo.v` | Clock-domain crossing FIFO for Ethernet frames |
| `rtl/sync_reset.v` | Reset synchronizer |
| `verilog-ethernet/rtl/eth_mac_1g__rgmii.v` | RGMII MAC wrapper used for TX |
| `verilog-ethernet/rtl/eth_mac_1g.v` | 1G Ethernet MAC core |
| `verilog-ethernet/rtl/axis_gmii_rx.v` | GMII RX frame logic |
| `verilog-ethernet/rtl/axis_gmii_tx.v` | GMII TX frame logic |
| `verilog-ethernet/rtl/rgmii_phy_if.v` | RGMII PHY interface |
| `verilog-ethernet/rtl/oddr.v` | DDR output wrapper |
| `verilog-ethernet/rtl/ssio_ddr_in.v` | DDR input wrapper |
| `verilog-ethernet/rtl/lfsr.v` | CRC/FCS support logic |

Project files:

| File | Purpose |
| --- | --- |
| `fpga_firewall.qpf` | Quartus project file |
| `fpga_firewall.qsf` | Device, source, and pin assignments |
| `fpga.sdc` | Timing constraints |
| `docs/fpga_lan_bringup.md` | Bring-up and debugging checklist |

Reference firewall RTL, not active in the current board build:

- `rtl/fpga_firewall_top.v`
- `rtl/firewall_regs.v`
- `rtl/firewall_rule_match.v`
- `rtl/firewall_l3_rule_match.v`
- `rtl/firewall_rule_table.v`
- `rtl/firewall_rx_parser.v`
- `rtl/firewall_tx_rebuild.v`
- `rtl/firewall_decision.v`
- `rtl/eth_header_extract.v`
- `rtl/eth_header_insert.v`
- `rtl/ip_header_extract.v`
- `rtl/tcp_udp_header_extract.v`
- `rtl/header_context_store.v`

## LED Map

During normal bridge operation:

```text
LEDG0 blink  raw traffic entering ENET0
LEDG1 blink  raw traffic entering ENET1
LEDG2 blink  valid frame transmitted ENET0 -> ENET1
LEDG3 blink  valid frame transmitted ENET1 -> ENET0
LEDG4 blink  ENET0 RX bad frame/FCS
LEDG5 blink  ENET1 RX bad frame/FCS
LEDG6 blink  valid received frame decoded
LEDG7 on     bridge out of reset
LEDG8 blink  heartbeat
```

For the normal cable setup:

```text
laptop -> router traffic should blink LEDG1 and LEDG3
router -> laptop traffic should blink LEDG0 and LEDG2
LEDG6 should blink when valid frames are decoded
LEDG4 and LEDG5 should normally stay off
```

Red LEDs show detected speed:

```text
ENET0: LEDR1 on              1000 Mb/s
ENET0: LEDR0 on, LEDR1 off   100 Mb/s
ENET1: LEDR3 on              1000 Mb/s
ENET1: LEDR2 on, LEDR3 off   100 Mb/s
```

## Hardware Requirements

- Terasic DE2-115 board
- Cyclone IV E device: `EP4CE115F29C7`
- Two Ethernet cables
- Router with an available LAN port
- Laptop or PC with Ethernet

Make sure the DE2-115 Ethernet jumpers are configured for RGMII mode. On the
DE2-115, `JP1` and `JP2` should be set to RGMII mode for the Ethernet PHYs.

## Build And Program

1. Open `fpga_firewall.qpf` in Quartus.
2. Run `Processing -> Start Compilation`.
3. Program the DE2-115 with the generated `.sof`.
4. Do not hold `KEY[3]`, because it resets the PLL.
5. After programming, `LEDG7` should be on and `LEDG8` should blink.

## Ubuntu Bring-Up

Create a clean wired connection profile:

```bash
nmcli device disconnect wlp8s0
nmcli connection delete fpga-lan
nmcli connection add type ethernet ifname enp7s0 con-name fpga-lan ipv4.method auto ipv6.method ignore
sudo ip addr flush dev enp7s0
nmcli connection up fpga-lan
```

Verify that the laptop is using the wired connection:

```bash
ip -4 addr show enp7s0
ip route get 8.8.8.8
nmcli device status
```

A working route should show `dev enp7s0` for internet traffic.

Test internet access through the FPGA:

```bash
ping -I enp7s0 -c 4 192.168.1.1
ping -I enp7s0 -c 4 8.8.8.8
ping -I enp7s0 -c 4 google.com
```

Useful packet capture during DHCP/debug:

```bash
sudo tcpdump -i enp7s0 -n -e 'arp or port 67 or port 68'
```

## What Was Removed From The Active Board Build

The following user-facing hardware controls are no longer part of the active
Quartus top-level design:

- Slide switches
- HEX seven-segment displays
- Switch-controlled firewall rule selection

The board now focuses only on forwarding Ethernet traffic so the laptop can use
the router through the FPGA.

## Current Project Status

Working:

- FPGA programs successfully in Quartus.
- Ethernet link comes up on the laptop.
- Traffic is visible through the FPGA.
- Internet access works with Wi-Fi disabled.
- The board behaves as a transparent LAN bridge.

Still available for future development:

- Firewall parser and rule-table RTL.
- Simulation/testbench material.
- Packet capture documentation scripts.

Future work:

- Re-introduce firewall filtering after the bridge path is stable.
- Add a clean configuration interface that does not depend on board switches.
- Add automated hardware bring-up notes and captures for demonstration.

## License

The Ethernet MAC and related components are from the
[verilog-ethernet](https://github.com/alexforencich/verilog-ethernet) project
by Alex Forencich and are licensed under the MIT License.

The firewall and board integration RTL in this repository is project work built
around that Ethernet core.
