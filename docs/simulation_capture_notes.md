# Firewall Simulation and Traffic Evidence

## Waveform Screenshot

Run the Icarus testbench from the repository root:

```bash
scripts/run_firewall_tb.sh
gtkwave firewall_tb.vcd docs/firewall_tb.gtkw
```

In this workspace, the rendered waveform PNG was generated with:

```bash
MPLCONFIGDIR=/tmp/matplotlib scripts/render_docs_screenshots.py
```

Generated screenshot:

```text
docs/firewall_waveform_icarus.png
```

The GTKWave layout shows:

- `packet_allowed`
- `packet_dropped`
- `allow_packet`
- `crc_error`
- `s_axis_tvalid`
- `s_axis_tlast`
- `m_axis_tvalid`
- `m_axis_tlast`

For ModelSim/Questa, run:

```tcl
do docs/modelsim_firewall_tb.do
```

The testbench sends three frames:

| Test | Destination MAC | Expected result |
|------|------------------|-----------------|
| 2 | `00:11:22:33:44:55` | Allowed |
| 3 | `ff:ff:ff:ff:ff:ff` | Dropped |
| 4 | `00:11:22:33:44:55` | Allowed |

## Wireshark Screenshot

Generate the pcaps:

```bash
scripts/create_docs_pcaps.py
```

Open `docs/firewall_input_allowed_and_dropped.pcap` in Wireshark to show both received frames. Useful display filters:

```text
eth.dst == 00:11:22:33:44:55
```

```text
eth.dst == ff:ff:ff:ff:ff:ff
```

Open `docs/firewall_output_allowed_only.pcap` to show the forwarded traffic after firewall filtering. It contains only the allowed destination-MAC frames, so the broadcast frame from test 3 is absent.

Generated screenshot:

```text
docs/firewall_wireshark_traffic.png
```
