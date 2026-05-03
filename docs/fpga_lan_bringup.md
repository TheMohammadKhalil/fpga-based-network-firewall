# FPGA LAN Bridge Bring-Up

This build makes the DE2-115 act as a transparent Ethernet bridge:

```text
router LAN port <-> FPGA ENET0 <-> bridge logic <-> FPGA ENET1 <-> laptop
```

## Program The FPGA

1. Open `fpga_firewall.qpf` in Quartus.
2. Run `Processing -> Start Compilation`.
3. Program the board with the generated `.sof`.
4. Do not hold `KEY[3]`; it resets the PLL.

Expected idle LEDs after programming:

```text
LEDG7 on     bridge out of reset
LEDG8 blink  125 MHz heartbeat
```

## Cable Setup

Use this first:

```text
router LAN port -> FPGA ENET0
laptop Ethernet -> FPGA ENET1
```

If DHCP still fails, swap the FPGA ports:

```text
router LAN port -> FPGA ENET1
laptop Ethernet -> FPGA ENET0
```

## Ubuntu DHCP Test

Reset the wired profile and request a fresh lease:

```bash
nmcli device disconnect wlp8s0
nmcli connection delete fpga-lan
nmcli connection add type ethernet ifname enp7s0 con-name fpga-lan ipv4.method auto ipv6.method ignore
sudo ip addr flush dev enp7s0
nmcli connection up fpga-lan
```

Check that the default route uses the cable:

```bash
ip -4 addr show enp7s0
ip route get 8.8.8.8
ping -I enp7s0 8.8.8.8
```

## Packet Capture

Run this while bringing `fpga-lan` up:

```bash
sudo tcpdump -i enp7s0 -n -e 'arp or port 67 or port 68'
```

Working DHCP shows the laptop request and a router reply. A reply usually looks
like traffic from port `67` to port `68`, often from `192.168.1.1`.

If the capture only shows the laptop MAC sending requests to
`ff:ff:ff:ff:ff:ff`, the router reply is not reaching the laptop.

## LED Meaning During DHCP

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

For the normal cable setup, a laptop DHCP request should blink `LEDG1`,
`LEDG3`, and `LEDG6`. A router DHCP reply should blink `LEDG0`, `LEDG2`, and
`LEDG6`. `LEDG4` and `LEDG5` should normally stay off.

Red LEDs show detected MAC speed:

```text
ENET0: LEDR1 on              1000 Mb/s
ENET0: LEDR0 on, LEDR1 off   100 Mb/s
ENET1: LEDR3 on              1000 Mb/s
ENET1: LEDR2 on, LEDR3 off   100 Mb/s
```
