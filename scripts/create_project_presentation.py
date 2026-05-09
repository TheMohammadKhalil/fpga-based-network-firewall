#!/usr/bin/env python3
"""Generate a PowerPoint deck for the FPGA Ethernet bridge project.

The script writes a native .pptx package directly so it does not depend on
python-pptx being installed in the lab environment.
"""

from __future__ import annotations

import datetime as dt
import io
import math
import os
import posixpath
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

from PIL import Image


DOCX = Path("/home/mohamad/Downloads/FPGA_Ethernet_Bridge_Documentation.docx")
OUT = Path("presentations/FPGA_Ethernet_Bridge_Project_Discussion.pptx")

EMU = 914400
SLIDE_W = int(13.333333 * EMU)
SLIDE_H = int(7.5 * EMU)

COLORS = {
    "ink": "0B1324",
    "muted": "526070",
    "soft": "F5F7FB",
    "paper": "FFFFFF",
    "line": "D8DEE9",
    "blue": "2557D6",
    "teal": "00A6A6",
    "mint": "DFF8F3",
    "amber": "F59E0B",
    "rose": "E11D48",
    "violet": "6D5DF2",
    "slate": "162033",
    "blue_soft": "EAF1FF",
    "teal_soft": "E4FAF6",
    "amber_soft": "FFF4D7",
    "rose_soft": "FFE9EF",
    "violet_soft": "F0EEFF",
}


def emu(inches: float) -> int:
    return int(round(inches * EMU))


def xml_text(text: str) -> str:
    return escape(text, {'"': "&quot;"})


def rels_xml(rels: list[tuple[str, str, str]]) -> str:
    items = []
    for rid, typ, target in rels:
        rel_type = typ if typ.startswith("http") else f"http://schemas.openxmlformats.org/officeDocument/2006/relationships/{typ}"
        items.append(
            f'<Relationship Id="{rid}" '
            f'Type="{rel_type}" '
            f'Target="{xml_text(target)}"/>'
        )
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        + "".join(items)
        + "</Relationships>"
    )


def solid_fill(color: str, alpha: int | None = None) -> str:
    alpha_xml = f'<a:alpha val="{alpha}"/>' if alpha is not None else ""
    return f'<a:solidFill><a:srgbClr val="{color}">{alpha_xml}</a:srgbClr></a:solidFill>'


def line_xml(color: str | None, width: int = 9525, alpha: int | None = None) -> str:
    if color is None:
        return "<a:ln><a:noFill/></a:ln>"
    return f'<a:ln w="{width}">{solid_fill(color, alpha)}</a:ln>'


def geometry(prst: str) -> str:
    return f'<a:prstGeom prst="{prst}"><a:avLst/></a:prstGeom>'


def shadow(alpha: int = 12000) -> str:
    return (
        '<a:effectLst>'
        '<a:outerShdw blurRad="50800" dist="25400" dir="5400000" algn="tl" rotWithShape="0">'
        f'<a:srgbClr val="{COLORS["ink"]}"><a:alpha val="{alpha}"/></a:srgbClr>'
        "</a:outerShdw>"
        "</a:effectLst>"
    )


def shape_sppr(
    x: float,
    y: float,
    w: float,
    h: float,
    fill: str | None = None,
    line: str | None = None,
    prst: str = "rect",
    line_width: int = 9525,
    fill_alpha: int | None = None,
    line_alpha: int | None = None,
    with_shadow: bool = False,
) -> str:
    fill_xml = "<a:noFill/>" if fill is None else solid_fill(fill, fill_alpha)
    return (
        "<p:spPr>"
        f'<a:xfrm><a:off x="{emu(x)}" y="{emu(y)}"/><a:ext cx="{emu(w)}" cy="{emu(h)}"/></a:xfrm>'
        + geometry(prst)
        + fill_xml
        + line_xml(line, line_width, line_alpha)
        + (shadow() if with_shadow else "")
        + "</p:spPr>"
    )


def run_xml(
    text: str,
    size: float = 18,
    color: str = COLORS["ink"],
    bold: bool = False,
    font: str = "Aptos",
) -> str:
    bold_xml = ' b="1"' if bold else ""
    return (
        "<a:r>"
        f'<a:rPr lang="en-US" sz="{int(size * 100)}"{bold_xml} dirty="0">'
        + solid_fill(color)
        + f'<a:latin typeface="{xml_text(font)}"/><a:cs typeface="{xml_text(font)}"/>'
        "</a:rPr>"
        f"<a:t>{xml_text(text)}</a:t>"
        "</a:r>"
    )


def para_xml(
    text: str | list[tuple[str, dict]],
    size: float = 18,
    color: str = COLORS["ink"],
    bold: bool = False,
    bullet: bool = False,
    align: str = "l",
    space_after: int = 550,
    font: str = "Aptos",
) -> str:
    if bullet:
        ppr = (
            f'<a:pPr marL="{emu(0.26)}" indent="-{emu(0.16)}" algn="{align}">'
            f'<a:spcAft><a:spcPts val="{space_after}"/></a:spcAft>'
            '<a:buFont typeface="Aptos"/><a:buChar char="&#8226;"/>'
            "</a:pPr>"
        )
    else:
        ppr = (
            f'<a:pPr algn="{align}">'
            f'<a:spcAft><a:spcPts val="{space_after}"/></a:spcAft>'
            "<a:buNone/>"
            "</a:pPr>"
        )
    if isinstance(text, list):
        runs = "".join(run_xml(t, font=font, **opts) for t, opts in text)
    else:
        runs = run_xml(text, size=size, color=color, bold=bold, font=font)
    return f"<a:p>{ppr}{runs}</a:p>"


def text_box(
    obj_id: int,
    name: str,
    x: float,
    y: float,
    w: float,
    h: float,
    paragraphs: list[str | dict],
    fill: str | None = None,
    line: str | None = None,
    prst: str = "rect",
    pad: float = 0.08,
    with_shadow: bool = False,
    anchor: str = "t",
) -> str:
    para_parts = []
    for item in paragraphs:
        if isinstance(item, str):
            para_parts.append(para_xml(item))
        else:
            para_parts.append(para_xml(**item))
    return (
        "<p:sp>"
        f'<p:nvSpPr><p:cNvPr id="{obj_id}" name="{xml_text(name)}"/>'
        '<p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
        + shape_sppr(x, y, w, h, fill=fill, line=line, prst=prst, with_shadow=with_shadow)
        + "<p:txBody>"
        f'<a:bodyPr wrap="square" anchor="{anchor}" lIns="{emu(pad)}" tIns="{emu(pad)}" '
        f'rIns="{emu(pad)}" bIns="{emu(pad)}"><a:normAutofit/></a:bodyPr>'
        "<a:lstStyle/>"
        + "".join(para_parts)
        + "</p:txBody>"
        "</p:sp>"
    )


def shape(
    obj_id: int,
    name: str,
    x: float,
    y: float,
    w: float,
    h: float,
    fill: str | None,
    line: str | None = None,
    prst: str = "rect",
    line_width: int = 9525,
    fill_alpha: int | None = None,
    line_alpha: int | None = None,
    with_shadow: bool = False,
) -> str:
    return (
        "<p:sp>"
        f'<p:nvSpPr><p:cNvPr id="{obj_id}" name="{xml_text(name)}"/>'
        "<p:cNvSpPr/><p:nvPr/></p:nvSpPr>"
        + shape_sppr(
            x,
            y,
            w,
            h,
            fill=fill,
            line=line,
            prst=prst,
            line_width=line_width,
            fill_alpha=fill_alpha,
            line_alpha=line_alpha,
            with_shadow=with_shadow,
        )
        + "</p:sp>"
    )


def image_xml(
    obj_id: int,
    name: str,
    rid: str,
    x: float,
    y: float,
    w: float,
    h: float,
) -> str:
    return (
        "<p:pic>"
        f'<p:nvPicPr><p:cNvPr id="{obj_id}" name="{xml_text(name)}"/>'
        '<p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>'
        f'<p:blipFill><a:blip r:embed="{rid}"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>'
        "<p:spPr>"
        f'<a:xfrm><a:off x="{emu(x)}" y="{emu(y)}"/><a:ext cx="{emu(w)}" cy="{emu(h)}"/></a:xfrm>'
        + geometry("rect")
        + "</p:spPr>"
        "</p:pic>"
    )


def contain_box(img_w: int, img_h: int, x: float, y: float, w: float, h: float) -> tuple[float, float, float, float]:
    scale = min(w / img_w, h / img_h)
    iw = img_w * scale
    ih = img_h * scale
    return x + (w - iw) / 2, y + (h - ih) / 2, iw, ih


class Slide:
    def __init__(self, title: str = "", background: str = COLORS["soft"], dark: bool = False):
        self.title = title
        self.background = background
        self.dark = dark
        self.parts: list[str] = []
        self.rels: list[tuple[str, str, str]] = []
        self.next_id = 2
        self.next_rid = 2
        self.images: list[tuple[str, bytes]] = []

    def oid(self) -> int:
        value = self.next_id
        self.next_id += 1
        return value

    def rid(self) -> str:
        value = f"rId{self.next_rid}"
        self.next_rid += 1
        return value

    def add(self, xml: str) -> None:
        self.parts.append(xml)

    def add_text(self, name: str, x: float, y: float, w: float, h: float, paragraphs: list[str | dict], **kwargs) -> None:
        self.add(text_box(self.oid(), name, x, y, w, h, paragraphs, **kwargs))

    def add_shape(self, name: str, x: float, y: float, w: float, h: float, fill: str | None, **kwargs) -> None:
        self.add(shape(self.oid(), name, x, y, w, h, fill, **kwargs))

    def add_image(
        self,
        name: str,
        media_name: str,
        media_bytes: bytes,
        img_size: tuple[int, int],
        x: float,
        y: float,
        w: float,
        h: float,
        contain: bool = True,
    ) -> None:
        rid = self.rid()
        target = f"../media/{media_name}"
        self.rels.append((rid, "image", target))
        self.images.append((media_name, media_bytes))
        if contain:
            x, y, w, h = contain_box(img_size[0], img_size[1], x, y, w, h)
        self.add(image_xml(self.oid(), name, rid, x, y, w, h))

    def add_title(self, title: str, subtitle: str | None = None) -> None:
        color = COLORS["paper"] if self.dark else COLORS["ink"]
        muted = "C7D2E6" if self.dark else COLORS["muted"]
        self.add_text(
            "Slide title",
            0.72,
            0.36,
            9.2,
            0.7,
            [{"text": title, "size": 28, "color": color, "bold": True, "space_after": 50}],
            pad=0,
        )
        if subtitle:
            self.add_text(
                "Slide subtitle",
                0.75,
                1.02,
                8.8,
                0.35,
                [{"text": subtitle, "size": 11.5, "color": muted, "space_after": 50}],
                pad=0,
            )
        self.add_shape("Accent line", 0.72, 1.28 if subtitle else 1.04, 1.45, 0.045, COLORS["teal"], line=None)

    def add_footer(self, num: int) -> None:
        color = "B5C0D5" if self.dark else "8894A5"
        self.add_shape("Footer line", 0.72, 7.12, 11.88, 0.012, "CFD6E2" if not self.dark else "334057", line=None)
        self.add_text(
            "Footer",
            0.72,
            7.16,
            6.0,
            0.18,
            [{"text": "FPGA-Based Transparent Ethernet Bridge", "size": 7.8, "color": color, "space_after": 0}],
            pad=0,
        )
        self.add_text(
            "Slide number",
            11.98,
            7.16,
            0.62,
            0.18,
            [{"text": f"{num:02d}", "size": 7.8, "color": color, "align": "r", "space_after": 0}],
            pad=0,
        )

    def xml(self) -> str:
        sp_tree = (
            "<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>"
            "<p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/>"
            "<a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>"
            + "".join(self.parts)
        )
        return (
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
            'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
            'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
            "<p:cSld>"
            f"<p:bg><p:bgPr>{solid_fill(self.background)}<a:effectLst/></p:bgPr></p:bg>"
            f"<p:spTree>{sp_tree}</p:spTree>"
            "</p:cSld>"
            "<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>"
            "</p:sld>"
        )


def load_docx_media() -> dict[str, tuple[bytes, tuple[int, int]]]:
    media: dict[str, tuple[bytes, tuple[int, int]]] = {}
    with zipfile.ZipFile(DOCX) as zf:
        for name in sorted(n for n in zf.namelist() if n.startswith("word/media/")):
            data = zf.read(name)
            with Image.open(io.BytesIO(data)) as im:
                size = im.size
            media[Path(name).name] = (data, size)
    return media


def bullet(text: str, size: float = 16.5, color: str = COLORS["ink"]) -> dict:
    return {"text": text, "size": size, "color": color, "bullet": True, "space_after": 650}


def plain(text: str, size: float = 16, color: str = COLORS["ink"], bold: bool = False, align: str = "l") -> dict:
    return {"text": text, "size": size, "color": color, "bold": bold, "align": align, "space_after": 250}


def stat_card(slide: Slide, x: float, y: float, w: float, h: float, label: str, value: str, accent: str, soft: str) -> None:
    slide.add_shape(f"{label} card", x, y, w, h, COLORS["paper"], line=COLORS["line"], prst="roundRect", with_shadow=True)
    slide.add_shape(f"{label} accent", x, y, 0.08, h, accent, line=None, prst="rect")
    slide.add_text(
        f"{label} label",
        x + 0.22,
        y + 0.18,
        w - 0.35,
        0.22,
        [{"text": label.upper(), "size": 8.2, "color": accent, "bold": True, "space_after": 0}],
        pad=0,
    )
    slide.add_text(
        f"{label} value",
        x + 0.22,
        y + 0.47,
        w - 0.35,
        h - 0.54,
        [{"text": value, "size": 15, "color": COLORS["ink"], "bold": True, "space_after": 120}],
        pad=0,
    )
    slide.add_shape(f"{label} wash", x + w - 0.48, y + 0.16, 0.22, 0.22, soft, line=None, prst="ellipse")


def mini_flow(slide: Slide, x: float, y: float, labels: list[str], colors: list[str], w: float = 1.75) -> None:
    for i, label in enumerate(labels):
        sx = x + i * (w + 0.55)
        slide.add_shape(label, sx, y, w, 0.58, colors[i % len(colors)], line=None, prst="roundRect")
        slide.add_text(
            f"{label} text",
            sx + 0.04,
            y + 0.13,
            w - 0.08,
            0.25,
            [{"text": label, "size": 11.5, "color": COLORS["paper"], "bold": True, "align": "c", "space_after": 0}],
            pad=0,
            anchor="mid",
        )
        if i < len(labels) - 1:
            slide.add_shape("Arrow", sx + w + 0.12, y + 0.22, 0.32, 0.14, COLORS["muted"], line=None, prst="rightArrow")


def build_slides(media: dict[str, tuple[bytes, tuple[int, int]]]) -> list[Slide]:
    slides: list[Slide] = []

    # 1. Title
    s = Slide(background=COLORS["ink"], dark=True)
    s.add_shape("Top glow", 0, 0, 13.33, 1.05, COLORS["slate"], line=None)
    s.add_shape("Teal bar", 0, 0, 13.33, 0.08, COLORS["teal"], line=None)
    s.add_shape("Amber bar", 0, 0.08, 4.2, 0.045, COLORS["amber"], line=None)
    s.add_shape("Logo plate", 0.68, 0.52, 1.24, 1.44, COLORS["paper"], line="46526A", prst="roundRect", fill_alpha=94000)
    s.add_image("PSUT logo", "psut_logo.png", media["image1.png"][0], media["image1.png"][1], 0.75, 0.58, 1.05, 1.25)
    s.add_text(
        "University",
        1.95,
        0.82,
        6.9,
        0.52,
        [
            {"text": "Princess Sumaya University for Technology", "size": 14, "color": "D5DEEE", "bold": True, "space_after": 70},
            {"text": "King Abdullah II School of Engineering", "size": 10.5, "color": "AEBBD2", "space_after": 0},
        ],
        pad=0,
    )
    s.add_text(
        "Main title",
        0.85,
        2.0,
        10.8,
        1.75,
        [
            {"text": "FPGA-Based Transparent", "size": 40, "color": COLORS["paper"], "bold": True, "space_after": 110, "font": "Aptos Display"},
            {"text": "Ethernet Bridge", "size": 40, "color": COLORS["paper"], "bold": True, "space_after": 150, "font": "Aptos Display"},
            {"text": "Design and implementation for firewall development", "size": 17, "color": "C9D5EA", "space_after": 0},
        ],
        pad=0,
    )
    s.add_shape("Title accent", 0.88, 3.87, 2.1, 0.06, COLORS["teal"], line=None)
    s.add_text(
        "People",
        0.88,
        5.05,
        6.6,
        0.85,
        [
            {"text": "Sara Abu_Saed  |  Mohammad Khalil  |  Bader Basel", "size": 15, "color": COLORS["paper"], "bold": True, "space_after": 120},
            {"text": "Supervised by Eng. Hazem Marrar", "size": 12.5, "color": "B8C4DA", "space_after": 0},
        ],
        pad=0,
    )
    s.add_shape("Spring pill", 9.8, 6.22, 2.55, 0.48, "1F2A44", line="47536B", prst="roundRect")
    s.add_text(
        "Semester",
        9.9,
        6.36,
        2.35,
        0.16,
        [{"text": "Spring 2025-2026", "size": 10.5, "color": "DCE6F8", "bold": True, "align": "c", "space_after": 0}],
        pad=0,
    )
    slides.append(s)

    # 2. What we built
    s = Slide()
    s.add_title("What We Built", "Active board result described in the final documentation")
    stat_card(s, 0.78, 1.75, 3.65, 1.35, "Active build", "Transparent two-port Ethernet bridge", COLORS["teal"], COLORS["teal_soft"])
    stat_card(s, 4.85, 1.75, 3.65, 1.35, "Hardware", "Terasic DE2-115 between router and laptop", COLORS["blue"], COLORS["blue_soft"])
    stat_card(s, 8.92, 1.75, 3.65, 1.35, "Purpose", "Foundation for future FPGA firewall integration", COLORS["amber"], COLORS["amber_soft"])
    s.add_text(
        "Scope bullets",
        0.95,
        3.78,
        5.45,
        1.35,
        [
            bullet("Receives Ethernet traffic from one PHY interface."),
            bullet("Converts the RGMII receive stream into AXI-Stream frame bytes."),
            bullet("Transfers frames through asynchronous FIFOs."),
            bullet("Transmits frames through the opposite PHY interface."),
        ],
        pad=0,
    )
    s.add_shape("Scope panel", 7.02, 3.65, 4.9, 1.82, COLORS["ink"], line=None, prst="roundRect", with_shadow=True)
    s.add_text(
        "Current scope",
        7.28,
        3.93,
        4.36,
        1.2,
        [
            {"text": "Current scope", "size": 10, "color": COLORS["teal"], "bold": True, "space_after": 70},
            {"text": "Bridge datapath, FCS handling, clock-domain crossing, transmit framing.", "size": 16, "color": COLORS["paper"], "bold": True, "space_after": 90},
            {"text": "Live packet filtering remains future work.", "size": 13, "color": "C9D5EA", "space_after": 0},
        ],
        pad=0,
    )
    s.add_footer(2)
    slides.append(s)

    # 3. Live setup
    s = Slide()
    s.add_title("Live Test Setup", "Router LAN port to FPGA bridge to laptop Ethernet port")
    s.add_shape("Image panel", 0.85, 1.55, 7.5, 4.45, COLORS["paper"], line=COLORS["line"], prst="roundRect", with_shadow=True)
    s.add_image("Router FPGA Laptop", "router_fpga_laptop.png", media["image2.png"][0], media["image2.png"][1], 1.12, 1.88, 6.95, 3.6)
    s.add_text(
        "Setup bullets",
        8.78,
        1.75,
        3.55,
        3.1,
        [
            bullet("One FPGA Ethernet port connects to the router LAN port.", 16),
            bullet("The other FPGA Ethernet port connects to the laptop.", 16),
            bullet("Frames received from either side are forwarded to the opposite side.", 16),
            bullet("The test verified real Ethernet traffic through FPGA hardware.", 16),
        ],
        pad=0,
    )
    s.add_shape("Badge", 8.82, 5.18, 3.42, 0.62, COLORS["mint"], line=None, prst="roundRect")
    s.add_text(
        "Badge text",
        9.05,
        5.39,
        2.95,
        0.15,
        [{"text": "Inline transparent bridge", "size": 11.5, "color": COLORS["teal"], "bold": True, "align": "c", "space_after": 0}],
        pad=0,
    )
    s.add_footer(3)
    slides.append(s)

    # 4. Requirements
    s = Slide()
    s.add_title("Design Requirements", "The live system must move real Ethernet frames correctly")
    reqs = [
        ("RGMII receive", "Receive and decode traffic from the PHY interfaces.", COLORS["blue"], COLORS["blue_soft"]),
        ("AXI-Stream style", "Move frame bytes using tdata, tvalid, tready, tlast, and tuser.", COLORS["teal"], COLORS["teal_soft"]),
        ("Clock crossing", "Use asynchronous FIFOs between receive and transmit clock domains.", COLORS["violet"], COLORS["violet_soft"]),
        ("Frame integrity", "Check incoming FCS/bad-frame status and regenerate FCS on transmit.", COLORS["rose"], COLORS["rose_soft"]),
        ("Transmit framing", "Add preamble, pad short frames when needed, and drive the opposite PHY.", COLORS["amber"], COLORS["amber_soft"]),
        ("Debug status", "Provide LED indications for traffic, reset, link speed, and frame status.", COLORS["muted"], "EEF2F7"),
    ]
    for i, (head, body, accent, soft) in enumerate(reqs):
        x = 0.82 + (i % 3) * 4.15
        y = 1.55 + (i // 3) * 2.04
        s.add_shape(head, x, y, 3.65, 1.45, COLORS["paper"], line=COLORS["line"], prst="roundRect", with_shadow=True)
        s.add_shape(head + " color", x, y, 3.65, 0.08, accent, line=None)
        s.add_shape(head + " icon", x + 0.22, y + 0.3, 0.34, 0.34, soft, line=None, prst="ellipse")
        s.add_text(
            head + " txt",
            x + 0.72,
            y + 0.25,
            2.66,
            0.82,
            [
                {"text": head, "size": 13.5, "color": COLORS["ink"], "bold": True, "space_after": 65},
                {"text": body, "size": 10.4, "color": COLORS["muted"], "space_after": 0},
            ],
            pad=0,
        )
    s.add_footer(4)
    slides.append(s)

    # 5. Selected approach
    s = Slide()
    s.add_title("Selected Design Approach", "Stabilize the transparent bridge first, then insert filtering logic later")
    approaches = [
        ("Software firewall", "Flexible, but does not prove the FPGA can sit inline and forward real traffic.", COLORS["muted"], "EEF2F7"),
        ("Full FPGA firewall", "Important future direction; requires field extraction, rule storage, buffering, and timing validation.", COLORS["rose"], COLORS["rose_soft"]),
        ("Transparent bridge", "Selected current build: validates physical Ethernet path, RGMII handling, clock crossing, and transmit operation.", COLORS["teal"], COLORS["teal_soft"]),
    ]
    for i, (head, body, accent, soft) in enumerate(approaches):
        x = 0.88 + i * 4.18
        s.add_shape(head, x, 1.7, 3.62, 2.5, COLORS["paper"], line=COLORS["line"], prst="roundRect", with_shadow=True)
        s.add_shape(head + " num", x + 0.24, 1.98, 0.46, 0.46, accent, line=None, prst="ellipse")
        s.add_text(
            head + " number",
            x + 0.24,
            2.14,
            0.46,
            0.11,
            [{"text": str(i + 1), "size": 10, "color": COLORS["paper"], "bold": True, "align": "c", "space_after": 0}],
            pad=0,
            anchor="mid",
        )
        s.add_text(
            head + " text",
            x + 0.84,
            1.93,
            2.48,
            1.6,
            [
                {"text": head, "size": 15, "color": COLORS["ink"], "bold": True, "space_after": 120},
                {"text": body, "size": 11.2, "color": COLORS["muted"], "space_after": 0},
            ],
            pad=0,
        )
        if i == 2:
            s.add_shape("Selected ribbon", x + 0.24, 3.75, 1.08, 0.25, soft, line=None, prst="roundRect")
            s.add_text(
                "Selected text",
                x + 0.28,
                3.84,
                1.0,
                0.07,
                [{"text": "SELECTED", "size": 6.7, "color": accent, "bold": True, "align": "c", "space_after": 0}],
                pad=0,
            )
    s.add_shape("Limit panel", 1.34, 4.95, 10.65, 0.8, COLORS["ink"], line=None, prst="roundRect")
    s.add_text(
        "Limitation",
        1.65,
        5.18,
        10.1,
        0.25,
        [{"text": "Current limitation: active allow/drop packet filtering is not yet running on the FPGA board.", "size": 14, "color": COLORS["paper"], "bold": True, "align": "c", "space_after": 0}],
        pad=0,
    )
    s.add_footer(5)
    slides.append(s)

    # 6. Architecture
    s = Slide()
    s.add_title("Bridge Architecture", "Active modules in the Quartus board build")
    s.add_shape("Architecture image panel", 0.75, 1.5, 7.25, 4.38, COLORS["paper"], line=COLORS["line"], prst="roundRect", with_shadow=True)
    s.add_image("Top Level System Flow", "top_level_flow.png", media["image3.png"][0], media["image3.png"][1], 0.98, 1.75, 6.8, 3.75)
    modules = [
        ("fpga.v", "PLL, reset synchronization, physical pin wiring"),
        ("fpga_core.v", "Main bridge datapath and LED/debug status"),
        ("de2_rgmii_rx.v", "RGMII DDR receive alignment and frame decoding"),
        ("axis_async_fifo.v", "Clock-domain crossing between RX and opposite TX"),
        ("verilog-ethernet", "MAC/RGMII support for transmit framing"),
    ]
    y = 1.55
    for name, body in modules:
        s.add_shape(name, 8.32, y, 3.95, 0.68, COLORS["paper"], line=COLORS["line"], prst="roundRect")
        s.add_text(
            name + " module",
            8.55,
            y + 0.14,
            3.5,
            0.32,
            [
                {
                    "text": [
                        (name + ": ", {"size": 10.6, "color": COLORS["ink"], "bold": True}),
                        (body, {"size": 10.6, "color": COLORS["muted"]}),
                    ],
                    "space_after": 0,
                }
            ],
            pad=0,
        )
        y += 0.8
    s.add_footer(6)
    slides.append(s)

    # 7. Receive path
    s = Slide()
    s.add_title("Receive Path", "From RGMII pins to AXI-Stream frame bytes")
    mini_flow(s, 1.0, 1.86, ["RGMII RX", "Aligned GMII", "Frame bytes", "tuser status"], [COLORS["blue"], COLORS["teal"], COLORS["violet"], COLORS["rose"]], w=1.78)
    s.add_text(
        "Receive bullets",
        1.05,
        3.05,
        5.45,
        2.3,
        [
            bullet("Samples and aligns RGMII receive data.", 17),
            bullet("Uses GMII receive logic to identify frames.", 17),
            bullet("Checks frame integrity at the MAC receive stage using FCS.", 17),
            bullet("Removes incoming preamble and FCS, then marks bad frames through tuser.", 17),
        ],
        pad=0,
    )
    s.add_shape("Receive note", 7.25, 3.05, 4.7, 2.12, COLORS["paper"], line=COLORS["line"], prst="roundRect", with_shadow=True)
    s.add_text(
        "Receive note text",
        7.55,
        3.35,
        4.1,
        1.34,
        [
            {"text": "Important boundary", "size": 11, "color": COLORS["teal"], "bold": True, "space_after": 90},
            {"text": "The active bridge treats frame contents as a byte stream. It does not inspect MAC/IP/TCP/UDP fields for filtering in this phase.", "size": 17, "color": COLORS["ink"], "bold": True, "space_after": 0},
        ],
        pad=0,
    )
    s.add_footer(7)
    slides.append(s)

    # 8. Transmit path
    s = Slide()
    s.add_title("Transmit Path", "The opposite MAC rebuilds valid Ethernet output")
    mini_flow(s, 1.0, 1.86, ["Async FIFO", "TX MAC", "Preamble / pad", "New FCS", "RGMII TX"], [COLORS["violet"], COLORS["blue"], COLORS["amber"], COLORS["rose"], COLORS["teal"]], w=1.5)
    s.add_text(
        "Transmit bullets",
        0.98,
        3.08,
        5.6,
        2.2,
        [
            bullet("FIFO transfers the frame stream into the opposite transmit clock domain.", 17),
            bullet("Transmit MAC adds the required Ethernet preamble.", 17),
            bullet("Short frames are padded when needed.", 17),
            bullet("A new frame check sequence is regenerated before transmission.", 17),
        ],
        pad=0,
    )
    s.add_shape("FCS panel", 7.22, 2.78, 4.72, 1.72, COLORS["ink"], line=None, prst="roundRect", with_shadow=True)
    s.add_text(
        "FCS text",
        7.58,
        3.12,
        4.0,
        0.95,
        [
            {"text": "Receive checks FCS.", "size": 18, "color": COLORS["paper"], "bold": True, "space_after": 120, "align": "c"},
            {"text": "Transmit regenerates FCS.", "size": 18, "color": COLORS["teal"], "bold": True, "space_after": 0, "align": "c"},
        ],
        pad=0,
    )
    s.add_footer(8)
    slides.append(s)

    # 9. Board top level
    s = Slide()
    s.add_title("Board Top-Level Logic", "Clocking, reset synchronization, PHY reset delay, and bridge core")
    s.add_shape("Board image panel", 0.76, 1.42, 6.62, 4.55, COLORS["paper"], line=COLORS["line"], prst="roundRect", with_shadow=True)
    s.add_image("Board top flow", "board_top_flow.png", media["image4.png"][0], media["image4.png"][1], 0.98, 1.65, 6.18, 4.08)
    s.add_text(
        "Board bullets",
        7.9,
        1.68,
        4.15,
        3.3,
        [
            bullet("fpga.v handles PLL, reset synchronization, and physical Ethernet pin wiring.", 16),
            bullet("The 50 MHz board oscillator feeds the PLL for FPGA/interface clocks.", 16),
            bullet("PHY reset delay supports stable startup.", 16),
            bullet("Ethernet PHYs recover timing from the physical Ethernet signal.", 16),
        ],
        pad=0,
    )
    s.add_footer(9)
    slides.append(s)

    # 10. Runtime
    s = Slide()
    s.add_title("Runtime Packet Flow", "Traffic crosses the FPGA bridge in both directions")
    s.add_shape("Runtime image panel", 0.72, 1.38, 7.55, 4.75, COLORS["paper"], line=COLORS["line"], prst="roundRect", with_shadow=True)
    s.add_image("Runtime sequence", "runtime_sequence.png", media["image5.png"][0], media["image5.png"][1], 0.96, 1.67, 7.06, 4.12)
    s.add_text(
        "Runtime bullets",
        8.72,
        1.72,
        3.55,
        3.0,
        [
            bullet("Laptop traffic can include DHCP, ARP, ICMP, DNS, and normal IP traffic.", 15.8),
            bullet("Router replies return through the opposite direction of the same bridge.", 15.8),
            bullet("This verifies inline transparent Ethernet bridge behavior.", 15.8),
        ],
        pad=0,
    )
    s.add_shape("Result badge", 8.82, 5.04, 3.35, 0.66, COLORS["teal"], line=None, prst="roundRect")
    s.add_text(
        "Result badge text",
        9.02,
        5.27,
        2.95,
        0.16,
        [{"text": "Working bridge path", "size": 11.5, "color": COLORS["paper"], "bold": True, "align": "c", "space_after": 0}],
        pad=0,
    )
    s.add_footer(10)
    slides.append(s)

    # 11. Standards and constraints
    s = Slide()
    s.add_title("Standards and Constraints", "Engineering frame for the implementation")
    standards = [
        ("IEEE 802.3", "Ethernet frame behavior, MAC addressing, and FCS.", COLORS["blue"]),
        ("RGMII", "PHY-to-FPGA MAC-side interface.", COLORS["teal"]),
        ("AXI-Stream style", "Internal frame movement using tdata, tvalid, tready, tlast, tuser.", COLORS["violet"]),
        ("Verilog + Quartus", "Synthesizable HDL and FPGA design flow.", COLORS["amber"]),
    ]
    for i, (head, body, accent) in enumerate(standards):
        x = 0.84 + (i % 2) * 4.5
        y = 1.56 + (i // 2) * 1.48
        s.add_shape(head, x, y, 4.0, 1.02, COLORS["paper"], line=COLORS["line"], prst="roundRect", with_shadow=True)
        s.add_shape(head + " accent", x, y, 0.07, 1.02, accent, line=None)
        s.add_text(
            head + " text",
            x + 0.25,
            y + 0.22,
            3.5,
            0.54,
            [
                {"text": head, "size": 13, "color": COLORS["ink"], "bold": True, "space_after": 55},
                {"text": body, "size": 9.9, "color": COLORS["muted"], "space_after": 0},
            ],
            pad=0,
        )
    s.add_shape("Constraints panel", 9.7, 1.56, 2.62, 3.98, COLORS["ink"], line=None, prst="roundRect", with_shadow=True)
    s.add_text(
        "Constraints",
        9.98,
        1.9,
        2.07,
        2.9,
        [
            {"text": "Key constraints", "size": 11, "color": COLORS["teal"], "bold": True, "space_after": 100},
            {"text": "Existing DE2-115 board", "size": 12.8, "color": COLORS["paper"], "bold": True, "space_after": 120},
            {"text": "Timing across clock domains", "size": 12.8, "color": COLORS["paper"], "bold": True, "space_after": 120},
            {"text": "Valid Ethernet transmit framing", "size": 12.8, "color": COLORS["paper"], "bold": True, "space_after": 120},
            {"text": "Resource headroom for future filtering", "size": 12.8, "color": COLORS["paper"], "bold": True, "space_after": 0},
        ],
        pad=0,
    )
    s.add_footer(11)
    slides.append(s)

    # 12. Current limitations and future work
    s = Slide()
    s.add_title("Current Limitations and Future Work", "Accuracy matters: the active build is not a live firewall yet")
    s.add_shape("Limits", 0.88, 1.62, 5.62, 3.92, COLORS["paper"], line=COLORS["line"], prst="roundRect", with_shadow=True)
    s.add_shape("Future", 6.86, 1.62, 5.62, 3.92, COLORS["paper"], line=COLORS["line"], prst="roundRect", with_shadow=True)
    s.add_shape("Limits bar", 0.88, 1.62, 5.62, 0.12, COLORS["rose"], line=None)
    s.add_shape("Future bar", 6.86, 1.62, 5.62, 0.12, COLORS["teal"], line=None)
    s.add_text(
        "Limits text",
        1.22,
        2.0,
        4.95,
        2.9,
        [
            {"text": "Current board build", "size": 17, "color": COLORS["ink"], "bold": True, "space_after": 160},
            bullet("No live packet filtering.", 15.5),
            bullet("No active key-field packet inspection.", 15.5),
            bullet("No programmable allow/drop rule matching on the FPGA board.", 15.5),
            bullet("Older firewall-related files remain development material outside the active Quartus build.", 15.5),
        ],
        pad=0,
    )
    s.add_text(
        "Future text",
        7.2,
        2.0,
        4.95,
        2.8,
        [
            {"text": "Next integration steps", "size": 17, "color": COLORS["ink"], "bold": True, "space_after": 160},
            bullet("Insert filtering logic into the proven bridge path.", 15.5),
            bullet("Add header extraction for Ethernet/IP/TCP/UDP fields.", 15.5),
            bullet("Add rule storage and allow/drop decision logic.", 15.5),
            bullet("Validate timing and behavior with live traffic.", 15.5),
        ],
        pad=0,
    )
    s.add_footer(12)
    slides.append(s)

    # 13. Takeaway
    s = Slide(background=COLORS["ink"], dark=True)
    s.add_shape("Top bar", 0, 0, 13.33, 0.08, COLORS["teal"], line=None)
    s.add_shape("Panel", 0.78, 0.78, 11.78, 5.52, "101B31", line="2C3852", prst="roundRect", with_shadow=True)
    s.add_text(
        "Takeaway title",
        1.22,
        1.25,
        10.8,
        0.8,
        [{"text": "Project Takeaway", "size": 34, "color": COLORS["paper"], "bold": True, "align": "c", "space_after": 0, "font": "Aptos Display"}],
        pad=0,
    )
    s.add_shape("Takeaway accent", 5.45, 2.05, 2.42, 0.055, COLORS["teal"], line=None)
    takeaway = [
        ("Implemented", "a transparent Ethernet bridge on the DE2-115."),
        ("Validated", "RGMII receive alignment, FIFO clock crossing, MAC transmit framing, and FCS handling."),
        ("Established", "the live inline hardware path needed for future FPGA firewall filtering."),
    ]
    for i, (head, body) in enumerate(takeaway):
        y = 2.72 + i * 0.95
        s.add_shape(head, 1.75, y, 0.46, 0.46, [COLORS["teal"], COLORS["blue"], COLORS["amber"]][i], line=None, prst="ellipse")
        s.add_text(
            head + " text",
            2.45,
            y + 0.03,
            8.25,
            0.33,
            [
                {
                    "text": [
                        (head + " ", {"size": 17, "color": COLORS["paper"], "bold": True}),
                        (body, {"size": 17, "color": "D3DDF0"}),
                    ],
                    "space_after": 0,
                }
            ],
            pad=0,
        )
    s.add_text(
        "Discussion",
        0.95,
        6.58,
        11.45,
        0.28,
        [{"text": "Thank you", "size": 16, "color": COLORS["paper"], "bold": True, "align": "c", "space_after": 0}],
        pad=0,
    )
    slides.append(s)

    # 14. References
    s = Slide()
    s.add_title("References", "Sources listed in the final documentation")
    refs = [
        'IEEE Computer Society, "IEEE Standard for Ethernet," IEEE Std 802.3.',
        'Hewlett-Packard Company and contributors, "Reduced Gigabit Media Independent Interface (RGMII), Version 2.0," 2002.',
        'A. Forencich, "verilog-ethernet: Verilog Ethernet components for FPGA implementation," GitHub.',
        'Intel Corporation, "Intel Quartus Prime Design Software Documentation."',
    ]
    s.add_shape("Refs panel", 0.9, 1.58, 11.55, 4.55, COLORS["paper"], line=COLORS["line"], prst="roundRect", with_shadow=True)
    y = 1.98
    for i, ref in enumerate(refs, 1):
        s.add_shape(f"Ref {i}", 1.28, y - 0.03, 0.38, 0.38, [COLORS["blue"], COLORS["teal"], COLORS["amber"], COLORS["violet"]][i - 1], line=None, prst="ellipse")
        s.add_text(
            f"Ref number {i}",
            1.28,
            y + 0.1,
            0.38,
            0.1,
            [{"text": str(i), "size": 8.2, "color": COLORS["paper"], "bold": True, "align": "c", "space_after": 0}],
            pad=0,
            anchor="mid",
        )
        s.add_text(
            f"Ref text {i}",
            1.9,
            y,
            9.85,
            0.34,
            [{"text": ref, "size": 12.4, "color": COLORS["ink"], "space_after": 0}],
            pad=0,
        )
        y += 0.86
    s.add_footer(14)
    slides.append(s)

    return slides


def content_types(slide_count: int) -> str:
    overrides = [
        '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>',
        '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>',
        '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>',
        '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>',
        '<Override PartName="/ppt/presProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presProps+xml"/>',
        '<Override PartName="/ppt/viewProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.viewProps+xml"/>',
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>',
        '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>',
    ]
    for i in range(1, slide_count + 1):
        overrides.append(
            f'<Override PartName="/ppt/slides/slide{i}.xml" '
            'ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'
        )
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Default Extension="png" ContentType="image/png"/>'
        + "".join(overrides)
        + "</Types>"
    )


def presentation_xml(slide_count: int) -> str:
    slide_ids = []
    for i in range(1, slide_count + 1):
        slide_ids.append(f'<p:sldId id="{255 + i}" r:id="rId{i + 1}"/>')
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" saveSubsetFonts="1">'
        '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
        f'<p:sldIdLst>{"".join(slide_ids)}</p:sldIdLst>'
        f'<p:sldSz cx="{SLIDE_W}" cy="{SLIDE_H}" type="wide"/>'
        f'<p:notesSz cx="{emu(7.5)}" cy="{emu(10)}"/>'
        "<p:defaultTextStyle>"
        "<a:defPPr><a:defRPr lang=\"en-US\"/></a:defPPr>"
        "<a:lvl1pPr marL=\"0\" algn=\"l\"><a:defRPr sz=\"1800\"/></a:lvl1pPr>"
        "</p:defaultTextStyle>"
        "</p:presentation>"
    )


def presentation_rels(slide_count: int) -> str:
    rels = [("rId1", "slideMaster", "slideMasters/slideMaster1.xml")]
    for i in range(1, slide_count + 1):
        rels.append((f"rId{i + 1}", "slide", f"slides/slide{i}.xml"))
    rels.append((f"rId{slide_count + 2}", "presProps", "presProps.xml"))
    rels.append((f"rId{slide_count + 3}", "viewProps", "viewProps.xml"))
    return rels_xml(rels)


def theme_xml() -> str:
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="FPGA Bridge Theme">'
        "<a:themeElements>"
        "<a:clrScheme name=\"FPGA Bridge\">"
        '<a:dk1><a:srgbClr val="0B1324"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>'
        '<a:dk2><a:srgbClr val="162033"/></a:dk2><a:lt2><a:srgbClr val="F5F7FB"/></a:lt2>'
        '<a:accent1><a:srgbClr val="2557D6"/></a:accent1><a:accent2><a:srgbClr val="00A6A6"/></a:accent2>'
        '<a:accent3><a:srgbClr val="F59E0B"/></a:accent3><a:accent4><a:srgbClr val="E11D48"/></a:accent4>'
        '<a:accent5><a:srgbClr val="6D5DF2"/></a:accent5><a:accent6><a:srgbClr val="526070"/></a:accent6>'
        '<a:hlink><a:srgbClr val="2557D6"/></a:hlink><a:folHlink><a:srgbClr val="6D5DF2"/></a:folHlink>'
        "</a:clrScheme>"
        "<a:fontScheme name=\"Aptos\"><a:majorFont><a:latin typeface=\"Aptos Display\"/></a:majorFont>"
        "<a:minorFont><a:latin typeface=\"Aptos\"/></a:minorFont></a:fontScheme>"
        "<a:fmtScheme name=\"Clean\"><a:fillStyleLst><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
        "<a:gradFill rotWithShape=\"1\"><a:gsLst><a:gs pos=\"0\"><a:schemeClr val=\"phClr\"/></a:gs>"
        "<a:gs pos=\"100000\"><a:schemeClr val=\"phClr\"><a:tint val=\"50000\"/></a:schemeClr></a:gs></a:gsLst>"
        "<a:lin ang=\"5400000\" scaled=\"0\"/></a:gradFill>"
        "<a:solidFill><a:schemeClr val=\"phClr\"><a:tint val=\"90000\"/></a:schemeClr></a:solidFill></a:fillStyleLst>"
        "<a:lnStyleLst><a:ln w=\"9525\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:ln>"
        "<a:ln w=\"25400\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:ln>"
        "<a:ln w=\"38100\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:ln></a:lnStyleLst>"
        "<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle>"
        "<a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>"
        "<a:bgFillStyleLst><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
        "<a:solidFill><a:schemeClr val=\"phClr\"><a:tint val=\"95000\"/></a:schemeClr></a:solidFill>"
        "<a:solidFill><a:schemeClr val=\"phClr\"><a:shade val=\"95000\"/></a:schemeClr></a:solidFill></a:bgFillStyleLst>"
        "</a:fmtScheme>"
        "</a:themeElements>"
        "<a:objectDefaults/><a:extraClrSchemeLst/>"
        "</a:theme>"
    )


def slide_master_xml() -> str:
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        "<p:cSld><p:spTree>"
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
        '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
        "</p:spTree></p:cSld>"
        '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" '
        'accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
        '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>'
        "<p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles>"
        "</p:sldMaster>"
    )


def slide_layout_xml() -> str:
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank" preserve="1">'
        "<p:cSld name=\"Blank\"><p:spTree>"
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
        '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
        "</p:spTree></p:cSld>"
        "<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>"
        "</p:sldLayout>"
    )


def core_xml() -> str:
    now = dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:dcterms="http://purl.org/dc/terms/" '
        'xmlns:dcmitype="http://purl.org/dc/dcmitype/" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        "<dc:title>FPGA-Based Transparent Ethernet Bridge Project Discussion</dc:title>"
        "<dc:creator>Codex</dc:creator>"
        "<cp:lastModifiedBy>Codex</cp:lastModifiedBy>"
        f'<dcterms:created xsi:type="dcterms:W3CDTF">{now}</dcterms:created>'
        f'<dcterms:modified xsi:type="dcterms:W3CDTF">{now}</dcterms:modified>'
        "</cp:coreProperties>"
    )


def app_xml(slide_count: int) -> str:
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
        'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
        "<Application>Codex</Application>"
        f"<Slides>{slide_count}</Slides>"
        "<PresentationFormat>On-screen Show (16:9)</PresentationFormat>"
        "</Properties>"
    )


def write_pptx(slides: list[Slide]) -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    slide_count = len(slides)
    with zipfile.ZipFile(OUT, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("[Content_Types].xml", content_types(slide_count))
        zf.writestr("_rels/.rels", rels_xml([
            ("rId1", "officeDocument", "ppt/presentation.xml"),
            ("rId2", "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties", "docProps/core.xml"),
            ("rId3", "extended-properties", "docProps/app.xml"),
        ]))
        zf.writestr("docProps/core.xml", core_xml())
        zf.writestr("docProps/app.xml", app_xml(slide_count))
        zf.writestr("ppt/presentation.xml", presentation_xml(slide_count))
        zf.writestr("ppt/_rels/presentation.xml.rels", presentation_rels(slide_count))
        zf.writestr("ppt/theme/theme1.xml", theme_xml())
        zf.writestr("ppt/slideMasters/slideMaster1.xml", slide_master_xml())
        zf.writestr("ppt/slideMasters/_rels/slideMaster1.xml.rels", rels_xml([
            ("rId1", "slideLayout", "../slideLayouts/slideLayout1.xml"),
            ("rId2", "theme", "../theme/theme1.xml"),
        ]))
        zf.writestr("ppt/slideLayouts/slideLayout1.xml", slide_layout_xml())
        zf.writestr("ppt/slideLayouts/_rels/slideLayout1.xml.rels", rels_xml([
            ("rId1", "slideMaster", "../slideMasters/slideMaster1.xml"),
        ]))
        zf.writestr(
            "ppt/presProps.xml",
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:presentationPr xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"/>',
        )
        zf.writestr(
            "ppt/viewProps.xml",
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:viewPr xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"/>',
        )
        written_media: set[str] = set()
        for i, slide in enumerate(slides, 1):
            zf.writestr(f"ppt/slides/slide{i}.xml", slide.xml())
            rels = [("rId1", "slideLayout", "../slideLayouts/slideLayout1.xml")] + slide.rels
            zf.writestr(f"ppt/slides/_rels/slide{i}.xml.rels", rels_xml(rels))
            for media_name, data in slide.images:
                if media_name not in written_media:
                    zf.writestr(f"ppt/media/{media_name}", data)
                    written_media.add(media_name)


def main() -> None:
    if not DOCX.exists():
        raise SystemExit(f"Missing documentation file: {DOCX}")
    media = load_docx_media()
    missing = [name for name in ["image1.png", "image2.png", "image3.png", "image4.png", "image5.png"] if name not in media]
    if missing:
        raise SystemExit(f"Missing expected images in DOCX: {', '.join(missing)}")
    slides = build_slides(media)
    write_pptx(slides)
    print(OUT.resolve())


if __name__ == "__main__":
    main()
