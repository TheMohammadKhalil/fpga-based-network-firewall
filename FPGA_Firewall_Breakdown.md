# FPGA Firewall — Full Code Breakdown

---

## 1. System Architecture Overview

The design is a **store-and-forward network firewall** running on a Cyclone V FPGA. It sits inline between two Ethernet segments: packets arrive on the RGMII PHY interface, get inspected, and are either forwarded or silently dropped.

```
PHY (RGMII)
    │
    ▼
eth_mac_1g_rgmii          ← 3rd-party verilog-ethernet MAC
    │ rx_axis (byte stream, push, no backpressure)
    ▼
firewall_rgmii_top         ← top-level wrapper
    │
    ▼
fpga_firewall_top          ← firewall core
    ├── firewall_regs          config registers (filter rules)
    ├── eth_header_extract     sniff header bytes from live stream
    ├── header_context_store   hold parsed header until frame ends
    ├── firewall_rule_match    combinational allow/drop decision
    ├── firewall_rx_parser     buffer full frame, strip 14-byte header
    ├── firewall_decision      gate payload through or silently drop
    └── firewall_tx_rebuild
            └── eth_header_insert   prepend header back onto payload
    │
    ▼
eth_mac_1g_rgmii (TX path)  ← same MAC, opposite direction
    │
    ▼
PHY (RGMII)
```

There are **two parallel paths** processing the same incoming byte stream simultaneously:

- **Header path** — `eth_header_extract` → `header_context_store` → `firewall_rule_match`: sniffs the first 14 bytes to make an allow/drop decision.
- **Payload path** — `firewall_rx_parser` → `firewall_decision` → `firewall_tx_rebuild`: buffers the full frame then replays the payload, gated by the decision.

---

## 2. Clock & Reset Domain

### Clocks

| Signal | Source | Used by |
|---|---|---|
| `clk_125mhz` | Board oscillator / PLL | MAC GTX (transmit reference) |
| `rx_clk` | Output of MAC (recovered from PHY RX) | All firewall logic |
| `tx_clk` | Output of MAC (derived from GTX) | MAC TX internals |
| `cfg_clk` | External (CPU/config bus) | Status sync registers only |

The entire firewall pipeline runs on `rx_clk`. The config registers (`firewall_regs`) also run on `rx_clk` — there is **no CDC** between `cfg_clk` and `rx_clk` for the write path (a known limitation).

### Resets

`rst_n` (active-low from board) is inverted to `sys_rst` (active-high). This is fed into the MAC as `gtx_rst`. The MAC then outputs `rx_rst` and `tx_rst` — these are the same reset synchronized to their respective clock domains by the MAC internally. The firewall core uses `rx_rst`.

---

## 3. Module-by-Module Breakdown

---

### `firewall_rgmii_top.v` — Top-Level Wrapper

**What it does:** Glues the verilog-ethernet MAC to the firewall core. Exposes physical RGMII pins and a simple config bus to the outside world.

**Key wiring decisions:**

```verilog
// MAC RX → firewall RX (push, no backpressure)
.s_axis_tdata(mac_rx_tdata),
.s_axis_tvalid(mac_rx_tvalid),
.s_axis_tlast(mac_rx_tlast),
.s_axis_tready(),   // left open — MAC never checks this

// firewall TX → MAC TX (with backpressure)
.m_axis_tdata(mac_tx_tdata),
.m_axis_tvalid(mac_tx_tvalid),
.m_axis_tlast(mac_tx_tlast),
.m_axis_tready(mac_tx_tready),  // MAC tells firewall when it can accept
```

The RX side is **push-only**: the MAC streams bytes without asking if the firewall is ready. The TX side uses proper AXI-Stream handshaking (`tvalid`/`tready`).

**Status pulse generation:**

The `packet_allowed`, `packet_dropped`, and `crc_error` signals live in the `rx_clk` domain. They are synchronized to `cfg_clk` using a two-flop synchronizer, then a rising-edge detector (`sync1 & ~sync2`) produces a single-cycle pulse on each event. These are status outputs only — they do not control data flow.

**Config readback:**

Register address `0xF` returns a status word:

```
{16'd0, speed[1:0], link_up, 1'b0, packet_allowed, packet_dropped, crc_error_in}
```

All other addresses return 0.

---

### `eth_mac_1g_rgmii.v` — 1G Ethernet MAC (verilog-ethernet)

**Not your code**, but important to understand:

- Takes RGMII signals (4-bit DDR data, clocked on both edges) and produces/consumes a standard byte-wide AXI-Stream.
- **RX path:** RGMII DDR → GMII → byte stream. Asserts `rx_axis_tvalid` for each byte, `rx_axis_tlast` at end of frame, `rx_axis_tuser` if the CRC is bad.
- **TX path:** accepts byte stream with `tx_axis_tvalid/tready/tlast`, optionally pads to minimum frame length (64 bytes), then sends RGMII.
- The MAC strips the preamble and SFD on RX. The first byte your code sees is byte 0 of the Ethernet header (destination MAC).

---

### `firewall_regs.v` — Configuration Registers

**What it does:** A simple register file holding the filter rules. Written by an external CPU via `cfg_we`/`cfg_addr`/`cfg_wdata`.

**Register map:**

| Addr | Register | Width | Default |
|------|----------|-------|---------|
| `0x0` | `allow_dst_mac[31:0]` | 32b | `0` |
| `0x1` | `allow_dst_mac[47:32]` | 16b | `0` |
| `0x2` | `allow_src_mac[31:0]` | 32b | `0` |
| `0x3` | `allow_src_mac[47:32]` | 16b | `0` |
| `0x4` | `allow_ethertype` | 16b | `0x0800` (IPv4) |
| `0x5` | `min_frame_length` | 16b | `64` |
| `0x6` | `max_frame_length` | 16b | `1518` |
| `0x7[0]` | `enforce_dst_mac` | 1b | `0` |
| `0x7[1]` | `enforce_src_mac` | 1b | `0` |
| `0x7[2]` | `enforce_ethertype` | 1b | `0` |
| `0x7[3]` | `drop_crc_error` | 1b | `1` |

By default all MAC/ethertype enforcement is **off** (only CRC errors are dropped). The CPU enables rules by writing to `0x7`.

---

### `eth_header_extract.v` — Live Header Sniffer

**What it does:** Watches the raw incoming byte stream and extracts the 14-byte Ethernet header fields as it flows past. Runs in parallel with the parser — it does **not** buffer or delay the stream.

**Byte-to-field mapping:**

```
byte  0– 5  →  dst_mac[47:0]    (MSB first)
byte  6–11  →  src_mac[47:0]    (MSB first)
byte 12–13  →  ethertype[15:0]  (big-endian)
```

When byte 13 arrives, `header_valid` pulses high for one cycle — the header fields are valid and ready for downstream modules.

When `s_axis_tlast` arrives (end of frame), `frame_length` is latched as `byte_count + 1`, `frame_done` pulses, and the state resets for the next frame.

> **Note:** `header_valid` clears at frame end so there is no stale data between frames.

---

### `header_context_store.v` — Header Context Latch

**What it does:** Captures the header fields when `header_valid` pulses, then holds them stable until the frame is fully processed.

**The problem it solves:** `eth_header_extract` only has the complete length when `frame_done` fires (end of frame), but `header_valid` fires at byte 13. By the time the payload finishes and `firewall_tx_rebuild` needs the header to reconstruct the frame, the extractor has long moved on. This module bridges that gap.

```
header_valid pulse  →  latch dst_mac, src_mac, ethertype, crc_error
                        context_valid = 1
frame_done pulse    →  frame_length finally known, gets latched
one cycle later     →  context_valid = 0
```

`context_valid` stays high from `header_valid` until one cycle after `frame_done`, giving the TX rebuild path a stable window to read the header fields.

---

### `firewall_rule_match.v` — Allow/Drop Decision (Combinational)

**What it does:** Pure combinational logic. Takes the latched header context and filter rules, outputs `allow_packet` immediately with no clock delay.

```verilog
dst_ok  = (!enforce_dst_mac)   || (dst_mac  == allow_dst_mac);
src_ok  = (!enforce_src_mac)   || (src_mac  == allow_src_mac);
type_ok = (!enforce_ethertype) || (ethertype == allow_ethertype);
len_ok  = (frame_length >= min_frame_length) && (frame_length <= max_frame_length);
crc_ok  = (!drop_crc_error)    || (!crc_error);

allow_packet = dst_ok && src_ok && type_ok && len_ok && crc_ok;
```

Each rule is independently bypass-able via the `enforce_*` flags. All five conditions must pass simultaneously. This is pure glue logic — no registers, no clock.

---

### `firewall_rx_parser.v` — Frame Buffer

**What it does:** Buffers the entire incoming frame payload into a BRAM (`payload_mem`, 2048 bytes), then streams it back out once the complete frame has arrived. This is the "store" in store-and-forward — it is why the firewall can make a decision on the *complete* frame (including CRC and length) before forwarding a single byte.

**Two-phase state machine:**

**Phase 1 — Buffering:**

```
s_axis_tready = !streaming      accept bytes while not replaying
byte 0:   marks frame start, byte_count set to 1, nothing stored
bytes 1–13:  header bytes, not stored (byte_count < 14)
bytes 14+:   payload bytes, stored into payload_mem[]
on tlast: payload_length latched, enter streaming phase
```

**Phase 2 — Streaming:**

```
s_axis_tready = 0               no new frame accepted during replay
reads payload_mem[rd_ptr] one byte per cycle (when m_axis_tready)
asserts m_axis_tlast on last byte
resets back to idle when done
```

The payload is stripped of its 14-byte Ethernet header — only the Layer 3+ payload is passed downstream. The header is re-prepended later by `firewall_tx_rebuild`.

**Key parameters:** `MAX_FRAME_BYTES = 2048`, `PTR_W = 11` (2^11 = 2048 entries in BRAM).

---

### `firewall_decision.v` — Gate / Drop

**What it does:** The actual enforcement point. Receives the payload stream from the parser and either passes it through or silently discards it based on `allow_packet`.

```verilog
s_axis_tready = m_axis_tready || !allow_packet;
```

This means:

- If **allowed:** `tready` follows the downstream ready — the payload flows through only when the output accepts it.
- If **dropped:** `tready` is always 1 — drain the stream as fast as it comes, output nothing.

On `tlast` of a dropped frame, `drop_pulse` fires for one cycle (used as the `packet_dropped` status signal).

**Timing note:** `allow_packet` comes from `firewall_rule_match`, which is combinational on the context. The rule match result must be stable by the time the first payload byte exits the parser. Since the parser buffers the whole frame before streaming, the context is always ready in time — this is by design.

---

### `firewall_tx_rebuild.v` — TX Frame Reconstructor

**What it does:** Detects when an allowed payload stream starts and triggers the header insertion. Wraps `eth_header_insert`.

```verilog
// Trigger condition: payload arriving AND header context available
if (!in_frame && s_axis_tvalid && context_valid_sync) begin
    in_frame           <= 1'b1;
    header_start_pulse <= 1'b1;   // one-cycle trigger to eth_header_insert
end
```

`context_valid_sync` is a one-cycle delayed version of `context_valid` (from `header_context_store`), giving the context registers one extra cycle to settle before they are read.

It passes `s_axis_tvalid` gated by `context_valid_sync` to prevent `eth_header_insert` from acting on stale payloads between frames.

---

### `eth_header_insert.v` — Header Prepender

**What it does:** When `header_valid` pulses, outputs the 14 header bytes (dst_mac, src_mac, ethertype) one per cycle, then switches to forwarding the payload stream transparently.

**State machine:**

```
IDLE:
    header_valid pulse → sending_header = 1, hdr_index = 0

SENDING_HEADER (14 cycles, gated on m_axis_tready):
    hdr_index  0– 5  →  dst_mac bytes (MSB first)
    hdr_index  6–11  →  src_mac bytes (MSB first)
    hdr_index 12–13  →  ethertype bytes
    on index 13: sending_header = 0, sending_payload = 1

SENDING_PAYLOAD:
    s_axis_tready = m_axis_tready   (transparent passthrough)
    forward tdata/tvalid/tlast directly
    on tlast: sending_payload = 0, return to IDLE
```

`s_axis_tready` is only asserted during SENDING_PAYLOAD, so the payload source is stalled while the header is being output.

---

## 4. Full Data Flow — Step by Step

Here is what happens for a single Ethernet frame end-to-end:

```
1.  PHY drives RGMII signals.

2.  MAC recovers clock, decodes DDR, strips preamble/SFD.

3.  MAC outputs byte stream on rx_axis (tdata/tvalid/tlast/tuser).

4a. eth_header_extract (parallel, non-buffering):
      - Captures bytes 0–13 into registers.
      - Pulses header_valid after byte 13.
      - Pulses frame_done on tlast, latches frame_length.

4b. firewall_rx_parser (parallel, buffering):
      - Accepts all bytes (tready = 1 while !streaming).
      - Discards bytes 0–13 (Ethernet header).
      - Stores bytes 14+ into payload_mem[].
      - On tlast: enters streaming phase.

5.  header_context_store:
      - On header_valid: latches mac/ethertype/crc_error, context_valid = 1.
      - On frame_done+1: context_valid = 0.

6.  firewall_rule_match (combinational):
      - Evaluates allow_packet from context + rules.
      - Result is stable before parser begins streaming.

7.  firewall_decision:
      - If allow_packet = 1: forwards payload bytes to tx_rebuild.
      - If allow_packet = 0: drains payload to /dev/null, fires drop_pulse.

8.  firewall_tx_rebuild + eth_header_insert (allowed frames only):
      - Detects first payload byte, fires header_start_pulse.
      - Outputs 14 header bytes (from context_store).
      - Then forwards payload bytes.
      - Produces complete reconstructed Ethernet frame.

9.  MAC accepts reconstructed frame on tx_axis.

10. MAC adds preamble/SFD, encodes RGMII DDR, drives PHY.
```

---

## 5. What Can Be Filtered

| Rule | Register | Behavior when enforced |
|---|---|---|
| Destination MAC | `0x0`/`0x1` + `enforce_dst_mac` | Drop if dst MAC ≠ configured value |
| Source MAC | `0x2`/`0x3` + `enforce_src_mac` | Drop if src MAC ≠ configured value |
| EtherType | `0x4` + `enforce_ethertype` | Drop if ethertype ≠ configured value (default: IPv4 `0x0800`) |
| Min frame length | `0x5` | Drop if frame shorter than N bytes |
| Max frame length | `0x6` | Drop if frame longer than N bytes |
| CRC errors | `drop_crc_error` in `0x7` | Drop frames with bad FCS (on by default) |

All rules are ANDed — a frame must pass every enabled rule to be forwarded.

---

## 6. Key Limitations

1. **No CDC on config writes** — `firewall_regs` clocks on `rx_clk` but config signals come from `cfg_clk`. Rule changes during active traffic could cause metastability.

2. **One frame at a time** — the parser holds one frame in BRAM. A new frame cannot start buffering until the previous payload finishes streaming out.

3. **No IP/TCP parsing** — filtering is Layer 2 only (MAC addresses, EtherType, frame length).

4. **Single rule per field** — only one allowed MAC address per direction, one allowed EtherType.

5. **`gtx_clk90` tied to `clk_125mhz`** — proper RGMII TX timing requires a 90° phase-shifted clock from a PLL. Without it, TX timing margins will be marginal and may fail at speed.
