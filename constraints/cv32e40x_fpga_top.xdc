################################################################################
# XDC Constraints for CV32E40X FPGA Top Module
# Target: Artix-7 xc7a35ticsg324-1L
################################################################################

################################################################################
# Clock Constraints
################################################################################
# Main system clock - adjust frequency as needed (default 50MHz)
create_clock -period 20.000 -name sys_clk [get_ports clk_i]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets clk_i]

################################################################################
# Input/Output Delays (relative to clock)
################################################################################
set_input_delay -clock sys_clk -min 1.0 [all_inputs]
set_input_delay -clock sys_clk -max 5.0 [all_inputs]
set_output_delay -clock sys_clk -min 1.0 [all_outputs]
set_output_delay -clock sys_clk -max 5.0 [all_outputs]

# Exclude clock from input delay
set_input_delay 0.0 -clock sys_clk [get_ports clk_i]

################################################################################
# Pin Assignments (Example for common development boards)
# Uncomment and modify according to your specific board
################################################################################

## Clock pin (example - modify according to your board)
# set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports clk_i]

## Reset pin (active-low)
# set_property -dict {PACKAGE_PIN C12 IOSTANDARD LVCMOS33} [get_ports rst_ni]

## Debug request pin
# set_property -dict {PACKAGE_PIN D9 IOSTANDARD LVCMOS33} [get_ports debug_req_i]

## External interrupts (8 pins)
# set_property -dict {PACKAGE_PIN A8 IOSTANDARD LVCMOS33} [get_ports {irq_i[0]}]
# set_property -dict {PACKAGE_PIN C11 IOSTANDARD LVCMOS33} [get_ports {irq_i[1]}]
# set_property -dict {PACKAGE_PIN C10 IOSTANDARD LVCMOS33} [get_ports {irq_i[2]}]
# set_property -dict {PACKAGE_PIN A10 IOSTANDARD LVCMOS33} [get_ports {irq_i[3]}]
# set_property -dict {PACKAGE_PIN D13 IOSTANDARD LVCMOS33} [get_ports {irq_i[4]}]
# set_property -dict {PACKAGE_PIN B18 IOSTANDARD LVCMOS33} [get_ports {irq_i[5]}]
# set_property -dict {PACKAGE_PIN A18 IOSTANDARD LVCMOS33} [get_ports {irq_i[6]}]
# set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports {irq_i[7]}]

## Core sleep status output
# set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33} [get_ports core_sleep_o]

## Status LEDs (8 pins for debugging)
# set_property -dict {PACKAGE_PIN H5 IOSTANDARD LVCMOS33} [get_ports {status_leds_o[0]}]
# set_property -dict {PACKAGE_PIN J5 IOSTANDARD LVCMOS33} [get_ports {status_leds_o[1]}]
# set_property -dict {PACKAGE_PIN T9 IOSTANDARD LVCMOS33} [get_ports {status_leds_o[2]}]
# set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {status_leds_o[3]}]
# set_property -dict {PACKAGE_PIN E1 IOSTANDARD LVCMOS33} [get_ports {status_leds_o[4]}]
# set_property -dict {PACKAGE_PIN G1 IOSTANDARD LVCMOS33} [get_ports {status_leds_o[5]}]
# set_property -dict {PACKAGE_PIN G2 IOSTANDARD LVCMOS33} [get_ports {status_leds_o[6]}]
# set_property -dict {PACKAGE_PIN H2 IOSTANDARD LVCMOS33} [get_ports {status_leds_o[7]}]

################################################################################
# Physical Constraints
################################################################################
# Configuration bank voltages
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

################################################################################
# Timing Exceptions
################################################################################
# Add false paths for asynchronous signals if needed
# set_false_path -from [get_ports rst_ni]
# set_false_path -from [get_ports debug_req_i]

################################################################################
# Implementation Strategies
################################################################################
# Optimize for area to fit in smaller device
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]

################################################################################
# Notes
################################################################################
# 1. This is a template constraint file. Pin assignments are commented out.
# 2. Before implementation, uncomment and modify pin assignments according to
#    your specific FPGA board.
# 3. For common development boards (Basys3, Arty, etc.), refer to the board's
#    constraint file template.
# 4. The I/O count is now reduced to approximately 19 signals:
#    - clk_i (1)
#    - rst_ni (1)
#    - debug_req_i (1)
#    - irq_i[7:0] (8)
#    - core_sleep_o (1)
#    - status_leds_o[7:0] (8)
#    Total: 20 I/O pins (well within 210 available pins)
################################################################################


