# Timing constraints for FPGA Ethernet Bridge - Terasic DE2-115
# Based on Alex Forencich's verilog-ethernet DE2-115 example SDC

# -----------------------------------------------------------------------------
# Board oscillators
# -----------------------------------------------------------------------------
create_clock -period 20.00 -name {CLOCK_50}  [get_ports {CLOCK_50}]

set_clock_groups -asynchronous -group [get_clocks {CLOCK_50}]

# -----------------------------------------------------------------------------
# JTAG
# -----------------------------------------------------------------------------
create_clock -period 40.000 -name {altera_reserved_tck} {altera_reserved_tck}
set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}]

set_input_delay  -clock altera_reserved_tck 5 [get_ports altera_reserved_tdi]
set_input_delay  -clock altera_reserved_tck 5 [get_ports altera_reserved_tms]
set_output_delay -clock altera_reserved_tck -clock_fall -fall -max 5 \
                 [get_ports altera_reserved_tdo]

# -----------------------------------------------------------------------------
# False paths — human-interface signals
# -----------------------------------------------------------------------------
set_false_path -from [get_ports {KEY[*]}]  -to *
set_false_path -from * -to [get_ports {LEDG[*]}]
set_false_path -from * -to [get_ports {LEDR[*]}]

# -----------------------------------------------------------------------------
# False paths — Ethernet reset and interrupt
# -----------------------------------------------------------------------------
set_false_path -from [get_ports ENET0_INT_N] -to *
set_false_path -from * -to [get_ports ENET0_RST_N]

set_false_path -from [get_ports ENET1_INT_N] -to *
set_false_path -from * -to [get_ports ENET1_RST_N]

# -----------------------------------------------------------------------------
# Derive PLL clocks and clock uncertainty
# -----------------------------------------------------------------------------
derive_pll_clocks
derive_clock_uncertainty

# -----------------------------------------------------------------------------
# RGMII input timing — ENET0
# RGMII setup/hold relative to the incoming RX clock (DDR, so both edges)
# -----------------------------------------------------------------------------
create_clock -period 8.000 -name {ENET0_RX_CLK} [get_ports {ENET0_RX_CLK}]
set_clock_groups -asynchronous -group [get_clocks {ENET0_RX_CLK}]

set_input_delay -clock ENET0_RX_CLK -max  1.5 [get_ports {ENET0_RX_DATA[*] ENET0_RX_DV}]
set_input_delay -clock ENET0_RX_CLK -min -0.5 [get_ports {ENET0_RX_DATA[*] ENET0_RX_DV}]
set_input_delay -clock ENET0_RX_CLK -clock_fall -max  1.5 \
                [get_ports {ENET0_RX_DATA[*] ENET0_RX_DV}] -add_delay
set_input_delay -clock ENET0_RX_CLK -clock_fall -min -0.5 \
                [get_ports {ENET0_RX_DATA[*] ENET0_RX_DV}] -add_delay

# -----------------------------------------------------------------------------
# RGMII input timing — ENET1
# -----------------------------------------------------------------------------
create_clock -period 8.000 -name {ENET1_RX_CLK} [get_ports {ENET1_RX_CLK}]
set_clock_groups -asynchronous -group [get_clocks {ENET1_RX_CLK}]

set_input_delay -clock ENET1_RX_CLK -max  1.5 [get_ports {ENET1_RX_DATA[*] ENET1_RX_DV}]
set_input_delay -clock ENET1_RX_CLK -min -0.5 [get_ports {ENET1_RX_DATA[*] ENET1_RX_DV}]
set_input_delay -clock ENET1_RX_CLK -clock_fall -max  1.5 \
                [get_ports {ENET1_RX_DATA[*] ENET1_RX_DV}] -add_delay
set_input_delay -clock ENET1_RX_CLK -clock_fall -min -0.5 \
                [get_ports {ENET1_RX_DATA[*] ENET1_RX_DV}] -add_delay

# GTX clock outputs to PHY
set_false_path -from * -to [get_ports {ENET0_GTX_CLK}]
set_false_path -from * -to [get_ports {ENET1_GTX_CLK}]
