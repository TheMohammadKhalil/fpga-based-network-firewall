#!/usr/bin/env python3
"""Render documentation PNGs from the generated VCD and pcap files."""

from pathlib import Path
import subprocess

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from PIL import Image, ImageDraw, ImageFont


REPO = Path(__file__).resolve().parents[1]
DOCS = REPO / "docs"
VCD = REPO / "firewall_tb.vcd"


SIGNALS = [
    ("6", "s_axis_tvalid"),
    ("5", "s_axis_tlast"),
    ("%", "packet_allowed"),
    ("$", "packet_dropped"),
    ("!", "allow_packet"),
    ('"', "crc_error"),
    ("&", "m_axis_tvalid"),
    ("'", "m_axis_tlast"),
]


def parse_vcd(path, codes):
    values = {code: "0" for code, _ in SIGNALS}
    events = {name: [(0, 0)] for _, name in SIGNALS}
    time = 0

    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("#"):
            time = int(line[1:])
            continue
        if line[0] not in "01xz":
            continue

        value = 0 if line[0] in "0xz" else 1
        code = line[1:]
        if code not in codes:
            continue

        name = codes[code]
        if events[name][-1][1] != value:
            events[name].append((time, value))

    end_time = time
    for _, name in SIGNALS:
        if events[name][-1][0] != end_time:
            events[name].append((end_time, events[name][-1][1]))
    return events


def render_waveform():
    code_to_name = {code: name for code, name in SIGNALS}
    events = parse_vcd(VCD, code_to_name)
    start = 420_000
    end = 1_340_000

    fig, ax = plt.subplots(figsize=(16, 7.5), dpi=150)
    ax.set_facecolor("#101418")
    fig.patch.set_facecolor("#101418")

    colors = {
        "packet_allowed": "#46d369",
        "packet_dropped": "#ff5f56",
        "allow_packet": "#f6c85f",
        "crc_error": "#9aa0a6",
        "s_axis_tvalid": "#6aa9ff",
        "s_axis_tlast": "#89ddff",
        "m_axis_tvalid": "#c792ea",
        "m_axis_tlast": "#ffcb6b",
    }

    names = [name for _, name in SIGNALS]
    for row, name in enumerate(reversed(names)):
        y_base = row * 1.4
        points = [(t, v) for t, v in events[name] if start <= t <= end]
        before = max((item for item in events[name] if item[0] <= start), default=(start, 0))
        after = min((item for item in events[name] if item[0] >= end), default=(end, before[1]))
        points = [before] + points + [(end, after[1])]
        xs = [(t - start) / 1000 for t, _ in points]
        ys = [y_base + (0.75 if v else 0.0) for _, v in points]
        ax.step(xs, ys, where="post", color=colors[name], linewidth=2.2)
        ax.text(-18, y_base + 0.36, name, color="#e8eaed", ha="right", va="center", fontsize=10)
        ax.hlines(y_base, 0, (end - start) / 1000, color="#2a2f36", linewidth=0.6)

    annotations = [
        (492, "allowed packet"),
        (868, "dropped packet"),
        (1244, "allowed packet"),
    ]
    for x, label in annotations:
        ax.axvline(x - start / 1000, color="#ffffff", alpha=0.22, linestyle="--", linewidth=1)
        ax.text(x - start / 1000 + 4, len(names) * 1.4 - 0.7, label, color="#ffffff", fontsize=9)

    ax.set_xlim(0, (end - start) / 1000)
    ax.set_ylim(-0.5, len(names) * 1.4)
    ax.set_yticks([])
    ax.tick_params(axis="x", colors="#cfd3d7")
    ax.set_xlabel("time from 420 ns window start (ns)", color="#e8eaed")
    ax.set_title("Icarus waveform: FPGA firewall allow/drop decisions", color="#ffffff", pad=16)
    ax.grid(axis="x", color="#30363d", linestyle="-", linewidth=0.5)
    fig.tight_layout()
    fig.savefig(DOCS / "firewall_waveform_icarus.png")
    plt.close(fig)


def tshark_rows(path):
    cmd = [
        "tshark",
        "-r",
        str(path),
        "-T",
        "fields",
        "-e",
        "frame.number",
        "-e",
        "eth.dst",
        "-e",
        "eth.src",
        "-e",
        "eth.type",
    ]
    output = subprocess.check_output(cmd, text=True)
    return [line.split("\t") for line in output.splitlines() if line.strip()]


def render_wireshark_style():
    input_rows = tshark_rows(DOCS / "firewall_input_allowed_and_dropped.pcap")
    output_rows = tshark_rows(DOCS / "firewall_output_allowed_only.pcap")

    img = Image.new("RGB", (1500, 850), "#f4f6f8")
    draw = ImageDraw.Draw(img)
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 24)
    small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 18)
    mono = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 18)
    bold = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 20)

    draw.rectangle((0, 0, 1500, 58), fill="#3f6ea5")
    draw.text((22, 15), "Wireshark capture evidence - FPGA firewall traffic", fill="white", font=font)

    def table(y, title, rows, output=False):
        draw.text((28, y), title, fill="#111827", font=bold)
        y += 34
        draw.rectangle((28, y, 1470, y + 34), fill="#d9e8f7", outline="#aeb8c2")
        cols = [("No.", 50), ("Destination", 160), ("Source", 390), ("Type", 620), ("Result", 760), ("Info", 940)]
        for name, x in cols:
            draw.text((x, y + 7), name, fill="#111827", font=small)
        y += 34

        for row in rows:
            num, dst, src, eth_type = row[:4]
            allowed = dst.lower() == "00:11:22:33:44:55"
            result = "FORWARDED" if output else ("ALLOWED" if allowed else "DROPPED")
            fill = "#eaffea" if allowed else "#ffecec"
            draw.rectangle((28, y, 1470, y + 38), fill=fill, outline="#d0d7de")
            draw.text((50, y + 8), num, fill="#111827", font=mono)
            draw.text((160, y + 8), dst, fill="#111827", font=mono)
            draw.text((390, y + 8), src, fill="#111827", font=mono)
            draw.text((620, y + 8), eth_type, fill="#111827", font=mono)
            draw.text((760, y + 8), result, fill="#0f5132" if allowed else "#842029", font=bold)
            info = "matches allow_dst_mac rule" if allowed else "broadcast dst does not match allow_dst_mac"
            if output:
                info = "present on firewall output"
            draw.text((940, y + 8), info, fill="#111827", font=small)
            y += 38
        return y + 28

    y = table(92, "Input capture: docs/firewall_input_allowed_and_dropped.pcap", input_rows)
    y = table(y, "Output capture: docs/firewall_output_allowed_only.pcap", output_rows, output=True)

    draw.text(
        (28, y + 8),
        "Display filters used for documentation: eth.dst == 00:11:22:33:44:55 and eth.dst == ff:ff:ff:ff:ff:ff",
        fill="#374151",
        font=small,
    )
    draw.text(
        (28, y + 42),
        "The dropped broadcast frame appears in the input capture but is absent from the firewall output capture.",
        fill="#374151",
        font=small,
    )
    img.save(DOCS / "firewall_wireshark_traffic.png")


def main():
    DOCS.mkdir(exist_ok=True)
    render_waveform()
    render_wireshark_style()
    print("Wrote docs/firewall_waveform_icarus.png")
    print("Wrote docs/firewall_wireshark_traffic.png")


if __name__ == "__main__":
    main()
