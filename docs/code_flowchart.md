# Code Flowchart: FPGA Ethernet Bridge

This document shows how the active FPGA bridge code works. It focuses on the
current working board build, not the older firewall modules that remain in the
repository for reference.

Important hardware note: the active Verilog instantiates two mirrored forwarding
paths for the intended transparent bridge. In the latest board test, router
traffic reached the laptop, but laptop traffic did not reach the router. The
top-level diagram below shows the intended bidirectional bridge; the later
runtime packet sequence documents the currently observed hardware behavior.

## Top-Level Bidirectional System Flow

```mermaid
flowchart LR
    ROUTER[Router LAN port]
    LAPTOP[Laptop Ethernet port]

    subgraph FPGA["DE2-115 FPGA board"]
        ENET0[ENET0 PHY<br/>router-side port]
        CORE[fpga_core<br/>active bridge code]
        ENET1[ENET1 PHY<br/>laptop-side port]
    end

    ROUTER <--> ENET0
    ENET0 <--> CORE
    CORE <--> ENET1
    ENET1 <--> LAPTOP
```

## Implemented Code Structure

```mermaid
flowchart LR
    ROUTER[Router LAN port]
    LAPTOP[Laptop Ethernet port]

    subgraph FPGA["DE2-115 FPGA Transparent Ethernet Bridge Code"]
        ENET0[ENET0 PHY<br/>RGMII RX/TX pins]
        ENET1[ENET1 PHY<br/>RGMII RX/TX pins]

        subgraph PATH01["Path implemented in code: ENET0 RX to ENET1 TX"]
            RX0[de2_rgmii_rx<br/>Decode ENET0 RGMII RX]
            FIFO01[axis_async_fifo<br/>fifo_0_to_1_inst]
            TX1[eth_mac_1g_rgmii TX<br/>Transmit on ENET1<br/>Add preamble and FCS]
            RX0 --> FIFO01 --> TX1
        end

        subgraph PATH10["Path implemented in code: ENET1 RX to ENET0 TX"]
            RX1[de2_rgmii_rx<br/>Decode ENET1 RGMII RX]
            FIFO10[axis_async_fifo<br/>fifo_1_to_0_inst]
            TX0[eth_mac_1g_rgmii TX<br/>Transmit on ENET0<br/>Add preamble and FCS]
            RX1 --> FIFO10 --> TX0
        end

        LEDS[LED debug outputs<br/>traffic, good frames, FCS errors, reset, heartbeat]
    end

    ROUTER <--> ENET0
    ENET0 --> RX0
    TX0 --> ENET0
    TX1 --> ENET1
    ENET1 --> RX1
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

## Intended Bidirectional Frame Flow In Code

The active Verilog contains two mirrored one-way hardware paths. The first path
has been observed working in the latest test. The second path exists in the code
but is the path to debug because laptop-to-router traffic is not reaching the
router.

```mermaid
flowchart LR
    subgraph DIR01["Direction A: router side to laptop side - observed working"]
        P0RX[ENET0 RX pins<br/>RX_CLK, RX_DATA, RX_DV]
        D0[de2_rgmii_rx<br/>RGMII DDR sample and align]
        G0[axis_gmii_rx<br/>Find preamble/SFD<br/>Check/remove FCS]
        S0[AXI-Stream frame bytes<br/>tdata, tvalid, tlast, tuser]
        F01[axis_async_fifo<br/>ENET0 RX clock to ENET1 TX clock]
        T1[eth_mac_1g / axis_gmii_tx<br/>Add preamble, pad if needed,<br/>regenerate FCS]
        P1TX[ENET1 TX pins<br/>GTX_CLK, TX_DATA, TX_EN]

        P0RX --> D0 --> G0 --> S0 --> F01 --> T1 --> P1TX
    end

    subgraph DIR10["Direction B: laptop side to router side - failing in latest test"]
        P1RX[ENET1 RX pins<br/>RX_CLK, RX_DATA, RX_DV]
        D1[de2_rgmii_rx<br/>RGMII DDR sample and align]
        G1[axis_gmii_rx<br/>Find preamble/SFD<br/>Check/remove FCS]
        S1[AXI-Stream frame bytes<br/>tdata, tvalid, tlast, tuser]
        F10[axis_async_fifo<br/>ENET1 RX clock to ENET0 TX clock]
        T0[eth_mac_1g / axis_gmii_tx<br/>Add preamble, pad if needed,<br/>regenerate FCS]
        P0TX[ENET0 TX pins<br/>GTX_CLK, TX_DATA, TX_EN]

        P1RX --> D1 --> G1 --> S1 --> F10 --> T0 --> P0TX
    end
```

## Runtime Packet Sequence

This is the latest observed behavior with the normal cabling:
router on ENET0 and laptop on ENET1.

```mermaid
sequenceDiagram
    participant Laptop
    participant ENET1 as FPGA ENET1
    participant Core as Bridge Core
    participant ENET0 as FPGA ENET0
    participant Router

    Router->>ENET0: Ethernet frame, e.g. DHCP reply/ARP/IP
    ENET0->>Core: ENET0 RX decoded to AXI-Stream bytes
    Core->>Core: FIFO01 crosses to ENET1 TX clock
    Core->>ENET1: ENET1 TX MAC adds preamble/FCS
    ENET1->>Laptop: Same frame contents forwarded

    Laptop--xENET1: Ethernet frame, e.g. DHCP/ARP/IP
    ENET1--xCore: ENET1 to ENET0 path is present in code
    Core--xENET0: But latest hardware test did not reach router
    ENET0--xRouter: Reverse direction remains under debug
```

## LED Debug Flow

```mermaid
flowchart LR
    subgraph RX_EVENTS["Receive-side events"]
        RAW0[ENET0 RX_CTL activity] --> LEDG0[LEDG0]
        RAW1[ENET1 RX_CTL activity] --> LEDG1[LEDG1]
        BAD0[ENET0 bad frame/FCS] --> LEDG4[LEDG4]
        BAD1[ENET1 bad frame/FCS] --> LEDG5[LEDG5]
        GOOD[Any valid decoded frame<br/>from either direction] --> LEDG6[LEDG6]
    end

    subgraph TX_EVENTS["Transmit-side events"]
        TX01[Valid frame transmitted<br/>ENET0 RX to ENET1 TX] --> LEDG2[LEDG2]
        TX10[Valid frame transmitted<br/>ENET1 RX to ENET0 TX] --> LEDG3[LEDG3]
    end

    subgraph SYSTEM_EVENTS["System status"]
        READY[Bridge out of reset] --> LEDG7[LEDG7]
        HEARTBEAT[125 MHz FPGA heartbeat divider] --> LEDG8[LEDG8]
    end
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

The active Verilog is intended to implement an inline transparent Ethernet
bridge. `fpga_core.v` instantiates two mirrored forwarding paths: ENET0 RX goes
through `fifo_0_to_1_inst` to ENET1 TX, and ENET1 RX goes through
`fifo_1_to_0_inst` to ENET0 TX. In the latest hardware test, only the
router-side to laptop-side direction was confirmed working. The laptop-side to
router-side direction is present in the code but did not reach the router and
must be debugged as the `ENET1 RX -> fifo_1_to_0_inst -> ENET0 TX` path. The
frame contents are forwarded as a byte stream; the active bridge does not parse
or filter MAC/IP/TCP/UDP fields.
