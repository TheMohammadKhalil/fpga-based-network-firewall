# FPGA Ethernet Bridge / Firewall RTL

The current Quartus board build is a transparent two-port Ethernet bridge for
the Terasic DE2-115. Connect the router LAN port to ENET0 and the PC/device to
ENET1; the FPGA receives complete Ethernet frames with DE2-115-specific RGMII
RX alignment and re-transmits them through the other MAC so the device can
obtain normal router/internet access.

The original configurable firewall RTL and simulation testbench are still in
the repository for development and reference, but the board-level `fpga` design
now bypasses the firewall rules, switches, and HEX displays.

## Original Firewall RTL Features

- **RGMII Interface**: Direct connection to Ethernet PHY chips
- **Configurable Rules**: Filter by destination MAC, source MAC, ethertype, frame length
- **CRC Error Detection**: Optionally drop frames with CRC errors
- **AXI-Stream Interface**: Standard streaming interface for Ethernet frames
- **Real-time Filtering**: Packets are filtered on-the-fly with minimal latency

## Architecture

```
                    +------------------+
RGMII PHY <-------> |  Ethernet MAC    |
                    |  (eth_mac_1g)    |
                    +--------+---------+
                             |
                    AXI-Stream Interface
                             |
                    +--------v---------+
                    |  Firewall Core   |
                    |  +-------------+ |
                    |  | Header      | |
                    |  | Extractor   | |
                    |  +------+------+ |
                    |         |        |
                    |  +------v--------+|
                    |  | Context      ||
                    |  | Store        ||
                    |  +------+-------+|
                    |         |        |
                    |  +------v--------+|
                    |  | Rule Match   ||
                    |  +------+-------+|
                    |         |        |
                    |  +------v--------+|
                    |  | TX Rebuild   ||
                    |  +--------------+|
                    +--------+---------+
                             |
                    +--------v---------+
                    |  Ethernet MAC    |
                    +--------+---------+
                             |
RGMII PHY <------------------+
```

## Firewall Rules

The firewall supports the following filtering criteria:

| Register | Address | Description |
|----------|---------|-------------|
| allow_dst_mac | 0x0-0x1 | Destination MAC to allow (48-bit) |
| allow_src_mac | 0x2-0x3 | Source MAC to allow (48-bit) |
| allow_ethertype | 0x4 | Ethertype to allow (16-bit) |
| min_frame_length | 0x5 | Minimum frame length (16-bit) |
| max_frame_length | 0x6 | Maximum frame length (16-bit) |
| control | 0x7 | Control flags (enforce bits + drop_crc) |

### Control Register (0x7)

| Bit | Name | Description |
|-----|------|-------------|
| 0 | enforce_dst_mac | Enable destination MAC filtering |
| 1 | enforce_src_mac | Enable source MAC filtering |
| 2 | enforce_ethertype | Enable ethertype filtering |
| 3 | drop_crc_error | Drop frames with CRC errors |

## Files

### Top-Level Modules
- `rtl/firewall_rgmii_top.v` - Top-level wrapper with RGMII interface
- `rtl/fpga_firewall_top.v` - Core firewall top module

### Firewall Components
- `rtl/firewall_regs.v` - Configuration register bank
- `rtl/eth_header_extract.v` - Extract Ethernet header from incoming frames
- `rtl/header_context_store.v` - Store header context for frame processing
- `rtl/firewall_rule_match.v` - Match frame against configured rules
- `rtl/firewall_rx_parser.v` - Parse and buffer incoming frames
- `rtl/firewall_tx_rebuild.v` - Rebuild frames with headers for transmission
- `rtl/eth_header_insert.v` - Insert Ethernet headers on outgoing frames
- `rtl/firewall_decision.v` - Allow/drop decision logic

### Ethernet MAC (verilog-ethernet)
- `verilog-ethernet/rtl/eth_mac_1g.v` - 1G Ethernet MAC core
- `verilog-ethernet/rtl/eth_mac_1g__rgmii.v` - RGMII wrapper
- `verilog-ethernet/rtl/rgmii_phy_if.v` - RGMII PHY interface
- `rtl/de2_rgmii_rx.v` - DE2-115 RGMII RX alignment wrapper
- `verilog-ethernet/rtl/axis_gmii_rx.v` - GMII to AXI-Stream receiver
- `verilog-ethernet/rtl/axis_gmii_tx.v` - AXI-Stream to GMII transmitter

### Testbench
- `tb/firewall_tb.v` - Simulation testbench

## Quartus Compilation

### Requirements
- Intel/Altera Quartus Prime 18.1 or later
- Cyclone V device (or update .qsf for your device)

### Steps
1. Open Quartus Prime
2. Open project: `fpga_firewall.qpf`
3. Update pin assignments in `fpga_firewall.qsf` for your board
4. Compile: Processing -> Start Compilation
5. Program device with generated `.sof` file

### Pin Assignments
Update the pin assignments in `fpga_firewall.qsf` to match your specific FPGA board. The default assignments are placeholders.

## Simulation

### Using Icarus Verilog
```bash
iverilog -o firewall_tb \
    rtl/*.v \
    verilog-ethernet/rtl/*.v \
    lib/axis/rtl/*.v \
    tb/firewall_tb.v

vvp firewall_tb
```

### Using ModelSim
```bash
vlog rtl/*.v verilog-ethernet/rtl/*.v lib/axis/rtl/*.v tb/firewall_tb.v
vsim firewall_tb
run 1000ns
```

## Configuration Example

To allow frames from a specific MAC address:

```verilog
// Write to configuration registers (AXI-lite style)
cfg_we = 1;
cfg_addr = 4'h0;  // allow_dst_mac[31:0]
cfg_wdata = 32'h33445566;
// ... continue for all registers
```

## Status Outputs

| Signal | Description |
|--------|-------------|
| packet_allowed | Pulse when a packet passes the firewall |
| packet_dropped | Pulse when a packet is dropped |
| speed[1:0] | Link speed (00=10M, 01=100M, 10=1G) |
| link_up | Link status indicator |

## License

The Ethernet MAC and related components are from the [verilog-ethernet](https://github.com/alexforencich/verilog-ethernet) project by Alex Forencich (MIT License).

The firewall core is original work.
# fpga-based-network-firewall
