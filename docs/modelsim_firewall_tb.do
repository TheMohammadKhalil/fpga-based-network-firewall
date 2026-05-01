vlib work
vlog rtl/*.v
vlog verilog-ethernet/rtl/*.v
vlog lib/axis/rtl/*.v
vlog tb/firewall_tb.v
vsim work.firewall_tb

add wave -divider "AXI input"
add wave sim:/firewall_tb/s_axis_tvalid
add wave sim:/firewall_tb/s_axis_tlast
add wave -radix hexadecimal sim:/firewall_tb/s_axis_tdata

add wave -divider "Firewall decision"
add wave sim:/firewall_tb/packet_allowed
add wave sim:/firewall_tb/packet_dropped
add wave sim:/firewall_tb/allow_packet
add wave sim:/firewall_tb/crc_error

add wave -divider "AXI output"
add wave sim:/firewall_tb/m_axis_tvalid
add wave sim:/firewall_tb/m_axis_tlast
add wave -radix hexadecimal sim:/firewall_tb/m_axis_tdata

run -all
wave zoom full
