################################################################################
# Vivado Project Creation Script for CV32E40X RISC-V Core
# 
# This script automatically creates a Vivado project with all RTL files,
# constraints, and proper configuration for the CV32E40X core.
#
# Usage:
#   vivado -mode batch -source create_vivado_project.tcl
#   or
#   vivado -mode tcl -source create_vivado_project.tcl
################################################################################

# Script configuration
set script_dir [file dirname [file normalize [info script]]]
set project_name "cv32e40x_project"
set project_dir "${script_dir}/vivado_project"

# FPGA part configuration - Modify this according to your target device
# Examples:
#   Artix-7:   xc7a35ticsg324-1L
#   Kintex-7:  xc7k325tffg900-2
#   Zynq:      xc7z020clg400-1
#   UltraScale+: xczu9eg-ffvb1156-2-e
set fpga_part "xc7a35ticsg324-1L"

################################################################################
# Create project
################################################################################
puts "=========================================="
puts "Creating Vivado project: ${project_name}"
puts "Target FPGA: ${fpga_part}"
puts "Project directory: ${project_dir}"
puts "=========================================="

# Remove existing project if it exists
if {[file exists ${project_dir}]} {
    puts "Warning: Project directory already exists. Removing..."
    file delete -force ${project_dir}
}

# Create new project
create_project ${project_name} ${project_dir} -part ${fpga_part} -force

# Set project properties
set proj [current_project]
set_property target_language Verilog $proj
set_property simulator_language Mixed $proj
set_property default_lib work $proj

################################################################################
# Add package file first (must be compiled before other files)
################################################################################
puts "\n=========================================="
puts "Adding package files..."
puts "=========================================="

set pkg_file "${script_dir}/rtl/include/cv32e40x_pkg.sv"
if {[file exists ${pkg_file}]} {
    add_files -norecurse -fileset [get_filesets sources_1] ${pkg_file}
    set_property file_type "SystemVerilog" [get_files ${pkg_file}]
    puts "Added: ${pkg_file}"
} else {
    puts "ERROR: Package file not found: ${pkg_file}"
    exit 1
}

################################################################################
# Add all RTL files
################################################################################
puts "\n=========================================="
puts "Adding RTL source files..."
puts "=========================================="

# Get all SystemVerilog files in rtl directory (excluding include directory)
set rtl_files [glob -nocomplain ${script_dir}/rtl/*.sv]

# Filter out the package file (already added)
set filtered_rtl_files {}
foreach file $rtl_files {
    if {[string match "*cv32e40x_pkg.sv" $file] == 0} {
        lappend filtered_rtl_files $file
    }
}

# Add RTL files
if {[llength $filtered_rtl_files] > 0} {
    add_files -norecurse -fileset [get_filesets sources_1] $filtered_rtl_files
    foreach file $filtered_rtl_files {
        set_property file_type "SystemVerilog" [get_files [file tail $file]]
        puts "Added: [file tail $file]"
    }
    puts "Total RTL files added: [llength $filtered_rtl_files]"
} else {
    puts "WARNING: No RTL files found!"
}

################################################################################
# Set top module
################################################################################
puts "\n=========================================="
puts "Setting top module..."
puts "=========================================="

set_property top cv32e40x_fpga_top [current_fileset]
puts "Top module set to: cv32e40x_fpga_top"

################################################################################
# Add constraint files
################################################################################
puts "\n=========================================="
puts "Adding constraint files..."
puts "=========================================="

# Add SDC constraint file
set sdc_file "${script_dir}/constraints/cv32e40x_core.sdc"
if {[file exists ${sdc_file}]} {
    add_files -fileset [get_filesets constrs_1] -norecurse ${sdc_file}
    set_property file_type "SDC" [get_files [file tail ${sdc_file}]]
    puts "Added: ${sdc_file}"
} else {
    puts "WARNING: SDC constraint file not found: ${sdc_file}"
}

# Add XDC constraint files if they exist
set xdc_files [glob -nocomplain ${script_dir}/constraints/*.xdc]
if {[llength $xdc_files] > 0} {
    add_files -fileset [get_filesets constrs_1] -norecurse $xdc_files
    foreach file $xdc_files {
        puts "Added: [file tail $file]"
    }
} else {
    puts "INFO: No XDC constraint files found"
}

################################################################################
# Set SystemVerilog compilation properties
################################################################################
puts "\n=========================================="
puts "Configuring synthesis settings..."
puts "=========================================="

# Set SystemVerilog as the file type for all .sv files
set_property file_type SystemVerilog [get_files *.sv]

# Configure synthesis settings for better results
set_property strategy "Vivado Synthesis Defaults" [get_runs synth_1]
set_property steps.synth_design.args.retiming true [get_runs synth_1]
set_property steps.synth_design.args.fsm_extraction one_hot [get_runs synth_1]

# Configure implementation settings
set_property strategy "Vivado Implementation Defaults" [get_runs impl_1]

################################################################################
# Set elaboration parameters (optional - customize as needed)
################################################################################
puts "\n=========================================="
puts "Setting module parameters..."
puts "=========================================="

# Example: Configure core parameters
# Uncomment and modify as needed for your configuration
# set_property generic {
#     RV32=1
#     A_EXT=0
#     B_EXT=0
#     M_EXT=1
#     ZC_EXT=1
# } [current_fileset]

puts "INFO: Using default parameters. Modify script to customize."

################################################################################
# Create simulation fileset (optional)
################################################################################
puts "\n=========================================="
puts "Configuring simulation..."
puts "=========================================="

set_property target_simulator "XSim" $proj
set_property -name {xsim.compile.xvlog.more_options} -value {-d SIM} -objects [get_filesets sim_1]

################################################################################
# Update compile order
################################################################################
puts "\n=========================================="
puts "Updating compile order..."
puts "=========================================="

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

################################################################################
# Generate project summary
################################################################################
puts "\n=========================================="
puts "PROJECT CREATION SUMMARY"
puts "=========================================="
puts "Project name:     ${project_name}"
puts "Project location: ${project_dir}"
puts "Target FPGA:      ${fpga_part}"
puts "Top module:       cv32e40x_core"
puts "RTL files:        [llength $filtered_rtl_files] files"
puts "Package files:    1 file (cv32e40x_pkg.sv)"

set total_sources [llength [get_files -of_objects [get_filesets sources_1]]]
set total_constraints [llength [get_files -of_objects [get_filesets constrs_1]]]

puts "Total sources:    ${total_sources}"
puts "Total constraints: ${total_constraints}"
puts "=========================================="
puts ""
puts "Project created successfully!"
puts ""
puts "Next steps:"
puts "  1. Open project: vivado ${project_dir}/${project_name}.xpr"
puts "  2. Create top-level wrapper if needed"
puts "  3. Run synthesis: launch_runs synth_1"
puts "  4. Run implementation: launch_runs impl_1"
puts "  5. Generate bitstream: launch_runs impl_1 -to_step write_bitstream"
puts ""
puts "Or run synthesis immediately:"
puts "  launch_runs synth_1 -jobs 4"
puts "  wait_on_run synth_1"
puts "=========================================="

################################################################################
# Optional: Launch synthesis automatically
################################################################################
# Uncomment the following lines to automatically launch synthesis
# puts "\nLaunching synthesis..."
# reset_run synth_1
# launch_runs synth_1 -jobs 4
# wait_on_run synth_1
# 
# if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
#     puts "ERROR: Synthesis failed!"
#     exit 1
# } else {
#     puts "Synthesis completed successfully!"
#     open_run synth_1
# }

puts "\n✓ Script completed successfully!"

