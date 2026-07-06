onbreak resume
onerror resume
vsim -voptargs=+acc work.da_fir_bandpass_tb

add wave sim:/da_fir_bandpass_tb/u_da_fir_bandpass/clk
add wave sim:/da_fir_bandpass_tb/u_da_fir_bandpass/reset
add wave sim:/da_fir_bandpass_tb/u_da_fir_bandpass/clk_enable
add wave sim:/da_fir_bandpass_tb/u_da_fir_bandpass/In1
add wave sim:/da_fir_bandpass_tb/u_da_fir_bandpass/ce_out
add wave sim:/da_fir_bandpass_tb/u_da_fir_bandpass/Out1
add wave sim:/da_fir_bandpass_tb/Out1_ref
run -all
