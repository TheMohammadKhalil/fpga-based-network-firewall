#!/usr/bin/env python3
"""Create small Wireshark pcaps matching tb/firewall_tb.v traffic."""

import struct
from pathlib import Path


def mac(hex_string):
    return bytes.fromhex(hex_string)


def eth_frame(dst, src, ethertype, payload):
    return mac(dst) + mac(src) + struct.pack("!H", ethertype) + payload


def pcap_packet(ts_sec, ts_usec, data):
    return struct.pack("<IIII", ts_sec, ts_usec, len(data), len(data)) + data


def write_pcap(path, packets):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as f:
        f.write(struct.pack("<IHHIIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))
        for index, packet in enumerate(packets):
            f.write(pcap_packet(1, index * 1000, packet))


allowed_1 = eth_frame(
    "001122334455",
    "aabbccddeeff",
    0x0800,
    bytes.fromhex("deadbeefcafebabe"),
)

dropped = eth_frame(
    "ffffffffffff",
    "aabbccddeeff",
    0x0800,
    bytes.fromhex("1234567890abcdef"),
)

allowed_2 = eth_frame(
    "001122334455",
    "123456789abc",
    0x0800,
    bytes.fromhex("fedcba9876543210"),
)

docs = Path(__file__).resolve().parents[1] / "docs"
write_pcap(docs / "firewall_input_allowed_and_dropped.pcap", [allowed_1, dropped, allowed_2])
write_pcap(docs / "firewall_output_allowed_only.pcap", [allowed_1, allowed_2])

print("Wrote docs/firewall_input_allowed_and_dropped.pcap")
print("Wrote docs/firewall_output_allowed_only.pcap")
