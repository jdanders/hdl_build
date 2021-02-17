report_timing -setup -npaths 200 -detail summary -file "TQ_200paths_setup.txt"
report_timing -hold -npaths 200 -detail summary -file "TQ_200paths_hold.txt"
report_timing -recovery -npaths 200 -detail summary -file "TQ_200paths_recovery.txt"
report_timing -removal -npaths 200 -detail summary -file "TQ_200paths_removal.txt"
report_timing -setup -npaths 5 -detail full_path -file "TQ_5paths_setup_detail.txt"
report_ucp -file "TQ_Unconstrained_paths.txt"
check_timing -include loops -file "TQ_loops.txt"
check_timing -include latches -file "TQ_latches.txt"
#report_metastability -file "TQ_metastability.txt"
report_sdc -file "TQ_sdc_report.txt"
report_clock_transfers -file "TQ_clock_transfers.txt"

# options for check_timing -include
#  no_clock
#  multiple_clock
#  generated_clock
#  no_input_delay
#  no_output_delay
#  partial_input_delay
#  partial_output_delay
#  io_min_max_delay_consistency
#  reference_pin
#  latency_override
#  loops
#  latches
#  pos_neg_clock_domain
#  pll_cross_check
#  uncertainty
#  virtual_clock
#  partial_multicycle
#  multicycle_consistency
#  partial_min_max_delay
#  clock_assignments_on_output_ports
#  input_delay_assigned_to_clock
#  generated_io_delay
