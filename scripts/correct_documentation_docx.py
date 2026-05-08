#!/usr/bin/env python3
from __future__ import annotations

import copy
import shutil
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET


SRC = Path("/home/mohamad/Downloads/Documentation Template  V3.0 (1) (3).docx")
OUT = Path("/home/mohamad/fpga_firewall/docs/FPGA_Ethernet_Bridge_Corrected_Documentation.docx")
TMP = Path("/tmp/fpga_docx_corrected")

W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
ET.register_namespace("w", W_NS)
NS = {"w": W_NS}


def wtag(name: str) -> str:
    return f"{{{W_NS}}}{name}"


REPLACEMENTS = {
    3: "Design and Implementation of an FPGA-Based Transparent Ethernet Bridge for Firewall Development",
    50: (
        "This project documents the design and implementation progress of an FPGA-based Ethernet hardware path on the Terasic DE2-115 board. "
        "The active FPGA build operates as a transparent two-port Ethernet bridge between a router and a laptop. It does not currently perform live packet filtering, rule matching, or key-field packet inspection. Instead, it receives Ethernet traffic from one PHY interface, converts the RGMII receive stream into AXI-Stream frame bytes, transfers the frame through an asynchronous FIFO, and transmits it through the opposite PHY interface."
    ),
    52: (
        "The implemented board path checks Ethernet frame integrity at the MAC receive stage by validating the frame check sequence (FCS). The receive path removes the incoming preamble and FCS, marks bad frames using the AXI-Stream user/error signal, and passes the remaining frame bytes through the bridge. The transmit MAC then adds the required preamble, pads short frames when needed, regenerates a new FCS, and sends the frame out of the opposite Ethernet port."
    ),
    54: (
        "The active design is written in Verilog HDL and is built from the board top-level, the main bridge core, RGMII receive alignment logic, asynchronous FIFOs, and Ethernet MAC/RGMII support modules from the verilog-ethernet project. Older firewall-related modules and simulation files remain in the repository as development material, but they are not included in the active Quartus build and therefore are not part of the code running on the FPGA board."
    ),
    91: "Table 1-1: Load Distribution",
    92: "Table A-1: Project Offering Information",
    93: "",
    94: "",
    98: "Figure 1-1: Overall Design of the FPGA Ethernet Bridge",
    99: "Figure 3-1: Top-Level System Flow of the FPGA Ethernet Bridge",
    100: "Figure 3-2: Board Top-Level Reset, PLL, and Bridge Core Flow",
    110: (
        "This project focuses on building and validating the FPGA Ethernet hardware path required for a future inline firewall. The current board implementation is a transparent Ethernet bridge. Its purpose is to prove that real Ethernet traffic can enter the FPGA through one physical port, cross the FPGA logic, and leave through the other physical port without relying on a software forwarding path."
    ),
    112: (
        "In the active FPGA build, frames are not parsed into destination MAC address, source MAC address, EtherType, IP fields, TCP/UDP ports, or other firewall rule fields. The bridge handles frames as AXI-Stream byte sequences. The only frame-level inspection performed by the active path is Ethernet frame boundary handling and FCS/bad-frame status detection."
    ),
    114: (
        "The FPGA board was tested as a transparent Ethernet bridge between a router and a laptop. This verified that DHCP, ARP, ICMP, and normal IP traffic can pass through the FPGA hardware path. Full integration of packet filtering or firewall decision logic into this live board path remains future work."
    ),
    119: (
        "An FPGA is suitable for this project because Ethernet frame movement, buffering, and future packet-processing logic can be implemented directly in hardware. The current phase focuses on the foundation: a reliable two-port bridge that can carry real traffic. This foundation is necessary before firewall filtering logic can be inserted into the live datapath with confidence."
    ),
    123: "The objectives of this project phase are to implement and validate the FPGA Ethernet bridge path that will support future firewall development. The project's objectives are to:",
    125: "• To configure the DE2-115 FPGA board as a transparent Ethernet bridge between two physical Ethernet ports.",
    126: "• To receive RGMII data from each Ethernet PHY and convert it into AXI-Stream frame bytes.",
    127: "• To transfer complete frame streams between receive and transmit clock domains using asynchronous FIFOs.",
    128: "• To preserve Ethernet frame contents while removing/checking the incoming FCS and regenerating a new FCS on transmit.",
    129: "• To implement the active bridge path in synthesizable Verilog HDL.",
    130: "• To identify the active modules used by the Quartus build: fpga.v, fpga_core.v, de2_rgmii_rx.v, axis_async_fifo.v, and the Ethernet MAC/RGMII support files.",
    131: "• To test the Ethernet path on the FPGA board with a transparent bridge setup between a router and a laptop.",
    132: "• To document accurately that live packet filtering and key-field extraction are not currently active in the FPGA board build.",
    135: "The FPGA-based Ethernet bridge shall fulfill the following design requirements:",
    136: "• The system shall forward Ethernet frames transparently between the two DE2-115 Ethernet ports.",
    137: "• The active board build shall not modify Ethernet payload or packet header fields such as MAC addresses, EtherType, IP addresses, or ports.",
    138: "• The receive path shall check Ethernet FCS/bad-frame status and carry the status through the stream using tuser.",
    139: "• The implementation shall be written in synthesizable Verilog HDL and compiled using the Quartus project file.",
    140: "• The system shall use a modular design including board top-level logic, RGMII receive alignment, MAC transmit logic, asynchronous FIFOs, reset handling, and LED/debug status.",
    141: "• The FPGA board Ethernet path shall be tested using a transparent bridge setup between a router and laptop.",
    142: "• Future work may insert firewall filtering logic into the live bridge path after the transparent forwarding path is stable.",
    144: "List of Design Constraints",
    145: "The main design constraints are:",
    146: "• Cost constraint: The project uses the available DE2-115 FPGA development board and existing software tools, avoiding custom hardware.",
    147: "• Hardware constraint: The design must run on the FPGA and interface correctly with the board Ethernet PHYs through RGMII.",
    148: "• Resource constraint: The active bridge must remain small enough to fit comfortably on the Cyclone IV FPGA while leaving resources for possible future filtering logic.",
    149: "• Timing constraint: The FPGA logic must meet the timing requirements of the board-side MAC/RGMII datapath and the internal clock-domain crossings. The project should avoid describing Ethernet itself as having a separate cable clock; the PHY recovers timing from the Ethernet signal, while the FPGA uses PHY/MAC-side interface clocks.",
    150: "• Ethernet compatibility constraint: The transmit path must generate valid Ethernet framing, including preamble, padding when required, and FCS generation.",
    151: "• Implementation constraint: The active design must be written in synthesizable Verilog HDL and included in the Quartus project file to be part of the FPGA bitstream.",
    152: "• Time constraint: This phase focuses on hardware bring-up, transparent bridge validation, and accurate documentation. Live firewall filtering integration is outside the active board build.",
    155: "The FPGA Ethernet bridge design is related to the following engineering standards, interfaces, and design technologies:",
    156: "• IEEE 802.3 Ethernet: Ethernet defines the frame format, MAC addressing, frame sizes, and FCS/error-detection behavior. The active bridge forwards Ethernet frames and regenerates the transmit FCS.",
    157: "• RGMII Interface: The Reduced Gigabit Media Independent Interface connects the Ethernet PHYs to the FPGA-side MAC logic. RGMII is a board-level digital interface between PHY and FPGA; it is not a separate clock carried by the Ethernet cable.",
    158: "• AXI-Stream-style Interface: The internal modules pass frame bytes using tdata, tvalid, tready, tlast, and tuser signals. In the active bridge, these signals carry bytes and frame status, not parsed firewall fields.",
    159: "• Verilog HDL: The active bridge and support modules are implemented in Verilog HDL for FPGA synthesis.",
    162: (
        "The design project implements a transparent FPGA Ethernet bridge as the live board path. One Ethernet PHY connects to the router, and the other connects to the laptop. Frames received on ENET0 are decoded, checked for FCS/bad-frame status, passed through an asynchronous FIFO, and transmitted on ENET1. The reverse direction uses the same structure from ENET1 to ENET0. The active Quartus build does not include the repository's firewall parser, rule table, header extraction, or allow/drop decision modules."
    ),
    169: "Figure 1.1: Overall Design of the FPGA-Based Transparent Ethernet Bridge",
    195: "Bridge packet capture and hardware testing",
    208: "This project combines computer networking, digital hardware design, and FPGA implementation. The active system is a transparent Ethernet bridge that forwards real network traffic through FPGA logic and provides a foundation for future firewall integration.",
    210: (
        "An FPGA, or Field Programmable Gate Array, is programmable hardware used to implement digital logic circuits. Unlike software running on a processor, FPGA logic operates as hardware. In this project, the FPGA implements the Ethernet bridge datapath, reset handling, FIFOs, and status LEDs."
    ),
    212: (
        "A network firewall is a device or system that decides whether traffic should be allowed or blocked according to rules. This concept motivates the project, but the active FPGA board build is not yet a live firewall. It currently forwards traffic transparently and does not apply allow/drop rules."
    ),
    215: (
        "Ethernet frames are data units used in Ethernet networks. Each frame contains a destination MAC address, source MAC address, EtherType or length field, payload, and frame check sequence. The active bridge does not parse these fields for filtering. It treats the frame contents as a byte stream, checks/removes the incoming FCS at receive, and regenerates FCS at transmit."
    ),
    218: (
        "Packet filtering means inspecting packet or frame fields and applying rules to allow or block traffic. In this project phase, packet filtering is not active on the FPGA board. The active result is a transparent Ethernet bridge; packet filtering remains future integration work."
    ),
    220: (
        "Hardware-based security implements security-related functions in hardware logic instead of relying only on software. This project prepares for that direction by proving the FPGA can sit inline between a router and laptop and carry real Ethernet traffic."
    ),
    222: (
        "This project is based on Verilog HDL. The active architecture includes the board top-level, main bridge core, RGMII receive alignment, asynchronous FIFO clock-domain crossing, Ethernet MAC transmit logic, and LED/debug status. Firewall parsing and rule-matching modules exist in the repository but are not part of the active Quartus build."
    ),
    225: (
        "The FPGA board was tested as a transparent Ethernet bridge. The router was connected to one Ethernet port and the laptop to the other. The test verified that real Ethernet traffic could pass through the FPGA hardware path."
    ),
    229: (
        "Several previous studies discuss FPGA devices for network security, packet filtering, and firewall acceleration. These studies are useful background for the project goal. However, the current active implementation should be described accurately as an Ethernet bridge foundation, not as a completed live firewall."
    ),
    231: (
        "Grossi et al. worked on configurable firewall concepts using FPGA hardware. Their work is relevant to the future direction of this project because it shows how FPGA logic can be used for packet security decisions."
    ),
    233: (
        "Ajami and Dinh designed a hardware network firewall on an FPGA platform. Their work supports the idea that packet decisions can be accelerated in hardware, which is a future goal after the bridge path is fully stable."
    ),
    235: (
        "Mohammed and Ueno presented an FPGA firewall with expandable rule descriptions. Their work is useful as background for future configurable rule support, although the active board build in this project does not currently apply such rules."
    ),
    237: (
        "Wicaksana and Sasongko focused on packet classification for an FPGA-based firewall. Their work is related to possible future filtering based on IP addresses, ports, and protocol fields. The active bridge does not currently inspect these higher-layer fields."
    ),
    239: (
        "Lee et al. studied how firewall policy descriptions can be converted into reconfigurable firewall processors. This is relevant to future work if rule policies are later translated into FPGA logic."
    ),
    241: (
        "Fiessler et al. proposed HyPaFilter, a hybrid FPGA packet filter. This work is relevant because it shows how FPGA acceleration can be combined with software flexibility, which may guide later development."
    ),
    243: (
        "Grossi et al. also presented a configurable FPGA-based packet sniffer for network security applications. Packet sniffing is related to traffic monitoring and field extraction, which are possible future additions to the current bridge."
    ),
    245: (
        "Son, Van Manh, and Phuong studied FPGA acceleration for firewall data processing. Their work supports the long-term goal of moving packet-processing tasks into FPGA hardware."
    ),
    247: (
        "Abdulsamad and Repas provided a survey about FPGA devices in network security. Their work helps justify FPGA use for packet-processing and security-related systems."
    ),
    249: (
        "From these studies, FPGA-based network security systems are useful when low-latency packet handling is required. Our current work follows this direction by first validating the live Ethernet bridge path on the FPGA board. The bridge does not yet perform live filtering, but it provides the hardware path needed for future inline firewall development."
    ),
    253: (
        "This chapter explained the background concepts related to the FPGA Ethernet bridge and future firewall direction. The most important concepts are FPGA devices, Ethernet frames, RGMII, AXI-Stream-style frame movement, Verilog HDL, and network firewall motivation. The literature supports FPGA use in network security, while the current implementation proves the basic inline Ethernet hardware path before live filtering is added."
    ),
    262: (
        "The active design requirements were driven by the need to pass real Ethernet traffic through the FPGA board. Therefore, the live system must correctly receive RGMII data, align and decode frame bytes, cross clock domains, and transmit the frame from the opposite Ethernet port."
    ),
    264: (
        "The current active build does not compare extracted Ethernet header fields with programmable firewall rules. The repository contains firewall-related modules from development work, but those modules are not included in the active Quartus file list and are not running on the FPGA board."
    ),
    266: (
        "The active design does not make an allow/drop decision for each frame. It forwards frame byte streams transparently. Bad-frame and FCS status are detected by the receive logic and carried through tuser; valid transmitted-frame events are also used for LED status."
    ),
    268: (
        "The design is modular because the FPGA implementation separates board-level logic, bridge core logic, RGMII receive alignment, FIFO clock-domain crossing, MAC transmit logic, reset handling, and LED/debug status."
    ),
    270: (
        "The hardware testing requirement shaped the board implementation. The FPGA Ethernet path was verified by a transparent bridge setup between a router and laptop, showing that Ethernet traffic could traverse the FPGA hardware path. Future work includes inserting filtering logic into this live bridge path."
    ),
    273: (
        "Several constraints affected the FPGA Ethernet bridge project. The economic constraint was handled by using the existing DE2-115 FPGA board and available design tools. The hardware constraint required the design to work with the board Ethernet PHYs and their RGMII interfaces. The active bridge was written in synthesizable Verilog HDL and compiled through the Quartus project, whose top-level entity is fpga. Resource use must remain reasonable so that future filtering logic can be added. Timing is important because the bridge crosses between receive and transmit clock domains and must satisfy the MAC/RGMII interface requirements. Ethernet itself does not provide a separate clock signal on the cable; the PHY recovers timing from the line, and the FPGA uses PHY/MAC-side interface clocks. The Ethernet compatibility constraint requires valid transmit framing, including preamble, padding when needed, and FCS generation. The main time limitation is that this phase validates the transparent bridge path, while full live firewall filtering remains future work."
    ),
    275: (
        "The project is based on Ethernet IEEE 802.3 behavior, the RGMII PHY-to-FPGA interface, AXI-Stream-style internal signals, and Verilog HDL. IEEE 802.3 defines Ethernet frame behavior, including MAC addressing and FCS. The active bridge does not inspect MAC/IP/TCP/UDP fields for filtering; it forwards the frame contents as a byte stream. RGMII connects each Ethernet PHY to the FPGA MAC-side logic. AXI-Stream-style signals move frame bytes internally using tdata, tvalid, tready, tlast, and tuser. Verilog HDL is used to describe the hardware modules that implement the bridge."
    ),
    278: (
        "Several design approaches were considered. A software-based firewall would be flexible, but it would not prove the FPGA could sit inline and forward real Ethernet traffic through hardware."
    ),
    280: (
        "A second approach was to implement full firewall filtering directly in FPGA hardware. This would require reliable field extraction, rule storage, buffering, allow/drop decision logic, and careful timing validation. It remains an important future direction."
    ),
    282: (
        "A third approach was to first create a stable transparent Ethernet bridge on the FPGA board, then later insert filtering logic into that proven path. This reduces debugging risk because the team can first verify the physical Ethernet path, RGMII handling, clock-domain crossing, and transmit operation."
    ),
    284: (
        "The selected approach for the current board build was the transparent Ethernet bridge between a router and laptop. This approach proves that traffic can pass through the FPGA hardware path. The limitation is that packet filtering, key-field extraction, and allow/drop rule matching are not yet active in the live board path."
    ),
    287: (
        "The active design consists of the DE2-115 board top-level and the transparent Ethernet bridge datapath. The board top-level, fpga.v, handles the PLL, reset synchronization, and physical Ethernet pin wiring. The main bridge logic, fpga_core.v, connects each receive path to the opposite transmit path. The de2_rgmii_rx.v module samples and aligns RGMII receive data, uses the GMII receive logic to identify frames, and reports FCS/bad-frame status. The axis_async_fifo.v modules transfer frame streams between clock domains. The verilog-ethernet MAC/RGMII support modules transmit frames, add preamble, pad short frames if required, and regenerate FCS. No active module in this Quartus build extracts packet header fields or applies filtering rules."
    ),
    292: "Figure 3.1: Top-Level System Flow of the FPGA Ethernet Bridge",
    294: (
        "The DE2-115 board is configured as a transparent Ethernet bridge. One FPGA Ethernet port connects to the router LAN port and the other connects to the laptop Ethernet port. Frames received from either side are forwarded through the FPGA bridge path and transmitted from the opposite side, allowing normal Ethernet communication between the laptop and router."
    ),
    296: "Figure 3.2: Board Top-Level Reset, PLL, and Bridge Core Flow",
    298: (
        "The board top-level prepares the FPGA-side logic before traffic is forwarded. The 50 MHz board oscillator is used by the PLL to generate the internal clocks required by the FPGA MAC-side logic. These are FPGA/interface clocks, not a separate clock carried by the Ethernet cable. The Ethernet PHYs recover timing from the physical Ethernet signal. A reset synchronizer and PHY reset delay ensure stable startup. Inside fpga_core, the receive logic converts RGMII input into frame bytes, checks FCS/bad-frame status, and passes the frame into an asynchronous FIFO. The FIFO transfers the frame stream into the opposite transmit clock domain. The transmit MAC then adds preamble, pads if necessary, regenerates FCS, and drives the opposite RGMII PHY."
    ),
    301: "Figure 3.3: Runtime Packet Sequence Through the FPGA Bridge",
    303: (
        "At runtime, the laptop can send DHCP, ARP, ICMP, DNS, and normal IP traffic through the FPGA bridge to the router. The router's replies return through the opposite direction of the same bridge. This verifies that the FPGA hardware path functions as an inline transparent Ethernet bridge. The active file map is: fpga.v for board top-level PLL, reset, and pin wiring; fpga_core.v for the main bridge datapath and LED/debug status; de2_rgmii_rx.v for RGMII receive alignment and frame decoding; axis_async_fifo.v for clock-domain crossing; and the verilog-ethernet MAC/RGMII files for transmit framing and RGMII support. The active output of this phase is a working transparent bridge, not a live packet-filtering firewall."
    ),
    307: 'IEEE Computer Society, "IEEE Standard for Ethernet," IEEE Std 802.3.',
    309: 'Hewlett-Packard Company and contributors, "Reduced Gigabit Media Independent Interface (RGMII), Version 2.0," 2002.',
    311: 'A. Forencich, "verilog-ethernet: Verilog Ethernet components for FPGA implementation," GitHub. [Online]. Available: https://github.com/alexforencich/verilog-ethernet',
    313: 'Intel Corporation, "Intel Quartus Prime Design Software Documentation." [Online]. Available: https://www.intel.com/content/www/us/en/products/details/fpga/development-tools/quartus-prime/docs.html',
    316: "",
    318: "The appendices include supporting project material such as code flowcharts, bring-up notes, packet captures, and relevant source-file lists.",
    319: "Appendix A: Project Offering Information",
    320: "Appendix B: Code",
    321: "",
    353: "FPGA-Based Transparent Ethernet Bridge for Firewall Development",
    355: "Advisor Name",
    356: "Eng. Hazem Marrar",
    361: "Year / Semester",
    362: "Spring 2025-2026",
    364: "Title of Senior Design Project",
    365: "FPGA-Based Transparent Ethernet Bridge for Firewall Development",
    367: "Design to be Achieved",
    368: (
        "This project implements a transparent Ethernet bridge on the Terasic DE2-115 FPGA board. The bridge forwards Ethernet frames between two physical Ethernet ports using RGMII receive logic, AXI-Stream-style internal frame movement, asynchronous FIFOs, and Ethernet MAC transmit logic. The active design validates the live Ethernet hardware path required for future firewall filtering integration."
    ),
    370: "Engineering Standard",
    371: "IEEE 802.3 Ethernet, RGMII, Verilog HDL, and Quartus FPGA design flow",
    373: "Design Requirements",
    374: "The design shall achieve the following requirements:",
    376: "Forward Ethernet frames transparently between the two DE2-115 Ethernet ports.",
    377: "Use RGMII to interface between the FPGA logic and Ethernet PHYs.",
    378: "Use AXI-Stream-style tdata, tvalid, tready, tlast, and tuser signals internally.",
    379: "Check incoming Ethernet FCS/bad-frame status and regenerate FCS on transmit.",
    380: "Use asynchronous FIFOs to cross between receive and transmit clock domains.",
    381: "Provide LED/debug indications for traffic, good frames, bad frames/FCS, reset, link speed, and heartbeat.",
    382: "Document clearly that active packet filtering and key-field extraction are not currently implemented in the live FPGA board path.",
    383: "",
    384: "",
    385: "",
    386: "",
    387: "Quartus Prime is used to compile and program the FPGA design.",
    391: "Realistic Constraints",
    396: "The project uses the available DE2-115 board and open/source-available HDL components, avoiding custom PCB fabrication or extra hardware cost.",
    400: "The design should operate in the normal lab environment for the DE2-115 board and connected Ethernet equipment.",
    404: "The design should remain modular and maintainable so that future firewall filtering logic can be inserted into the proven bridge datapath.",
    424: "Code flowchart, bring-up notes, packet captures, and source-code files",
    427: "Students should have completed courses related to digital logic, computer networks, Verilog HDL, and FPGA design.",
}


def set_paragraph_text(par: ET.Element, text: str) -> None:
    first_r = par.find("w:r", NS)
    first_rpr = first_r.find("w:rPr", NS) if first_r is not None else None
    ppr = par.find("w:pPr", NS)
    keep = [copy.deepcopy(ppr)] if ppr is not None else []
    for child in list(par):
        par.remove(child)
    for child in keep:
        par.append(child)
    r = ET.SubElement(par, wtag("r"))
    if first_rpr is not None:
        rpr = copy.deepcopy(first_rpr)
        for node in list(rpr):
            if node.tag in {wtag("highlight"), wtag("shd")}:
                rpr.remove(node)
        r.append(rpr)
    if text:
        t = ET.SubElement(r, wtag("t"))
        t.set("{http://www.w3.org/XML/1998/namespace}space", "preserve")
        t.text = text


def remove_yellow_highlights(root: ET.Element) -> None:
    for rpr in root.findall(".//w:rPr", NS):
        for node in list(rpr):
            if node.tag == wtag("highlight"):
                rpr.remove(node)
            elif node.tag == wtag("shd"):
                fill = node.attrib.get(wtag("fill"), "").upper()
                if fill in {"FFFF00", "FFF200", "FFFF99"}:
                    rpr.remove(node)


def main() -> None:
    if TMP.exists():
        shutil.rmtree(TMP)
    TMP.mkdir(parents=True)
    with zipfile.ZipFile(SRC) as zin:
        zin.extractall(TMP)

    doc_xml = TMP / "word" / "document.xml"
    tree = ET.parse(doc_xml)
    root = tree.getroot()
    paragraphs = root.findall(".//w:p", NS)

    for idx, text in REPLACEMENTS.items():
        if idx < 1 or idx > len(paragraphs):
            raise IndexError(f"Paragraph index {idx} is out of range")
        set_paragraph_text(paragraphs[idx - 1], text)

    remove_yellow_highlights(root)
    tree.write(doc_xml, encoding="UTF-8", xml_declaration=True)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    if OUT.exists():
        OUT.unlink()
    with zipfile.ZipFile(OUT, "w", compression=zipfile.ZIP_DEFLATED) as zout:
        for path in sorted(TMP.rglob("*")):
            if path.is_file():
                zout.write(path, path.relative_to(TMP).as_posix())
    print(OUT)


if __name__ == "__main__":
    main()
