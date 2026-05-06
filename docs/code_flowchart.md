# Code Flowchart: FPGA Ethernet Bridge

This document shows how the active FPGA bridge code works. It focuses on the
current working board build, not the older firewall modules that remain in the
repository for reference.

## Top-Level System Flow

```mermaid
flowchart LR
    ROUTER[Router LAN port]
    LAPTOP[Laptop Ethernet port]

    subgraph FPGA["DE2-115 FPGA Ethernet Bridge"]
        ENET0[ENET0 PHY / RGMII pins]
        ENET1[ENET1 PHY / RGMII pins]

        RX0[de2_rgmii_rx<br/>Decode ENET0 RGMII RX]
        RX1[de2_rgmii_rx<br/>Decode ENET1 RGMII RX]

        FIFO01[axis_async_fifo<br/>ENET0 RX clock -> ENET1 TX clock]
        FIFO10[axis_async_fifo<br/>ENET1 RX clock -> ENET0 TX clock]

        TX1[eth_mac_1g_rgmii TX<br/>Regenerate preamble and FCS]
        TX0[eth_mac_1g_rgmii TX<br/>Regenerate preamble and FCS]

        LEDS[LED debug outputs<br/>traffic, good frames, FCS errors, reset, heartbeat]
    end

    ROUTER <--> ENET0
    ENET0 --> RX0 --> FIFO01 --> TX1 --> ENET1
    ENET1 --> RX1 --> FIFO10 --> TX0 --> ENET0
    ENET1 <--> LAPTOP

    RX0 --> LEDS
    RX1 --> LEDS
    TX0 --> LEDS
    TX1 --> LEDS
```

## Board Top Flow

```mermaid
flowchart TD
    CLOCK[CLOCK_50<br/>50 MHz board oscillator]
    KEY3[KEY3<br/>PLL reset button]
    PLL[altpll<br/>Generates 125 MHz and 125 MHz + 90 deg]
    CLK[clk_int<br/>125 MHz]
    CLK90[clk90_int<br/>125 MHz phase shifted]
    LOCKED[pll_locked]
    RST[sync_reset<br/>Synchronous core reset]
    CORE[fpga_core<br/>Transparent Ethernet bridge]
    PHYRESET[PHY reset delay<br/>Hold ENET0/ENET1 reset after config]

    CLOCK --> PLL
    KEY3 --> PLL
    PLL --> CLK
    PLL --> CLK90
    PLL --> LOCKED --> RST
    CLK --> RST
    CLK --> CORE
    CLK90 --> CORE
    RST --> CORE
    CORE --> PHYRESET
    PHYRESET --> ENET0RST[ENET0_RST_N]
    PHYRESET --> ENET1RST[ENET1_RST_N]
```

## Per-Direction Frame Flow

The bridge is symmetric. The same logic exists in both directions.

```mermaid
flowchart TD
    PHYRX[PHY RX pins<br/>RX_CLK, RX_DATA, RX_DV]
    DDR[altddio_in<br/>Sample RGMII on both clock edges]
    ALIGN[DE2 RGMII alignment candidates<br/>Try possible nibble/edge alignments]
    GMII[axis_gmii_rx<br/>Find preamble/SFD, output AXI-Stream bytes]
    FCS[Frame status<br/>tlast + tuser marks bad frame/FCS]
    FIFO[axis_async_fifo<br/>Cross RX clock domain to opposite TX clock]
    TXMAC[eth_mac_1g / axis_gmii_tx<br/>Add preamble, pad if needed, regenerate FCS]
    DDRTX[altddio_out<br/>Drive RGMII TX DDR data]
    PHYTX[Opposite PHY TX pins<br/>GTX_CLK, TX_DATA, TX_EN]

    PHYRX --> DDR --> ALIGN --> GMII --> FCS --> FIFO --> TXMAC --> DDRTX --> PHYTX
```

## Runtime Packet Sequence

This is what happens when the laptop gets internet access through the FPGA.

```mermaid
sequenceDiagram
    participant Laptop
    participant ENET1 as FPGA ENET1
    participant Core as Bridge Core
    participant ENET0 as FPGA ENET0
    participant Router

    Laptop->>ENET1: DHCP/ARP/Ethernet frame
    ENET1->>Core: RGMII RX decoded to AXI-Stream
    Core->>Core: FIFO crosses to ENET0 TX clock
    Core->>ENET0: MAC regenerates FCS and transmits
    ENET0->>Router: Frame forwarded to router

    Router->>ENET0: DHCP reply / ARP / IP traffic
    ENET0->>Core: RGMII RX decoded to AXI-Stream
    Core->>Core: FIFO crosses to ENET1 TX clock
    Core->>ENET1: MAC regenerates FCS and transmits
    ENET1->>Laptop: Frame forwarded to laptop
```

## LED Debug Flow

```mermaid
flowchart LR
    RAW0[ENET0 RX_CTL activity] --> LEDG0[LEDG0]
    RAW1[ENET1 RX_CTL activity] --> LEDG1[LEDG1]
    TX01[Valid ENET0 -> ENET1 TX frame] --> LEDG2[LEDG2]
    TX10[Valid ENET1 -> ENET0 TX frame] --> LEDG3[LEDG3]
    BAD0[ENET0 bad frame/FCS] --> LEDG4[LEDG4]
    BAD1[ENET1 bad frame/FCS] --> LEDG5[LEDG5]
    GOOD[Any valid decoded frame] --> LEDG6[LEDG6]
    READY[Bridge out of reset] --> LEDG7[LEDG7]
    HEARTBEAT[125 MHz heartbeat divider] --> LEDG8[LEDG8]
```

## File-To-Function Map

| File | Role in the flowchart |
| --- | --- |
| `rtl/fpga.v` | Board top, PLL, reset synchronization, physical pin wiring |
| `rtl/fpga_core.v` | Main bridge logic and LED/debug status |
| `rtl/de2_rgmii_rx.v` | RGMII DDR receive alignment and frame decode |
| `rtl/axis_async_fifo.v` | Clock-domain crossing between RX and opposite TX |
| `verilog-ethernet/rtl/eth_mac_1g__rgmii.v` | RGMII MAC wrapper used for transmit |
| `verilog-ethernet/rtl/eth_mac_1g.v` | Ethernet MAC TX/RX frame logic |
| `verilog-ethernet/rtl/axis_gmii_rx.v` | Converts GMII bytes into AXI-Stream frames |
| `verilog-ethernet/rtl/axis_gmii_tx.v` | Converts AXI-Stream frames into GMII transmit bytes |
| `verilog-ethernet/rtl/rgmii_phy_if.v` | Converts between GMII and RGMII DDR pins |
| `verilog-ethernet/rtl/oddr.v` | DDR output wrapper for RGMII TX |
| `verilog-ethernet/rtl/ssio_ddr_in.v` | DDR input wrapper for RGMII RX |

## Short Explanation For Documentation

The FPGA is configured as an inline Ethernet bridge. Each Ethernet PHY provides
RGMII receive data to the FPGA. The receive logic samples both RGMII clock
edges, aligns the nibbles into bytes, checks the Ethernet frame, and emits an
AXI-Stream frame. An async FIFO transfers that frame into the opposite port's
transmit clock domain. The transmit MAC then rebuilds the Ethernet transmit
stream, including preamble and FCS, and drives the opposite RGMII PHY. The same
path exists in reverse, so the router and laptop can exchange DHCP, ARP, DNS,
ICMP, and normal IP traffic through the FPGA.
