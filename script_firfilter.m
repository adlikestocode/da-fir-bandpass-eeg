clear; clc;

% 1. Load the payload
mat_path = 'C:\Users\adity_6z2h70p\OneDrive\Desktop\fir_filter_proj\filter_coefficients.mat';
payload = load(mat_path);

% 2. Extract and shape coefficients
float_coeffs = payload.float_coeffs(:).';
q15_ints     = payload.q15_ints(:).';

% 3. Normalize the values
normalized_q15 = double(q15_ints) / 32768;

% 4. Instantiate Objects
Filter_Float = dsp.FIRFilter('Numerator', float_coeffs);

% Pass the standard vector first, then configure the math properties
Filter_Bin = dsp.FIRFilter('Numerator', normalized_q15);
Filter_Bin.FullPrecisionOverride = false;
Filter_Bin.CoefficientsDataType = 'Custom';
Filter_Bin.CustomCoefficientsDataType = numerictype(true, 16, 15);

% Display objects in workspace
disp(Filter_Float);
disp(Filter_Bin);

%% FILTER ANALYSIS AND VERIFICATION PLOTS

fs = 160; % Sampling frequency in Hz
N = 157;  % Number of taps
nfft = 4096;

% Extract effective numerical coefficients for analysis
h_float = Filter_Float.Numerator;
h_bin   = Filter_Bin.Numerator; 

% Compute frequency responses
[H_float, f] = freqz(h_float, 1, nfft, fs);
[H_bin, ~]   = freqz(h_bin, 1, nfft, fs);

% Compute group delay
[gd_float, ~] = grpdelay(h_float, 1, nfft, fs);
[gd_bin, ~]   = grpdelay(h_bin, 1, nfft, fs);

% Generate time-domain stimuli
impulse_sig = [1, zeros(1, N*2)];
step_sig    = ones(1, N*2);

% Run signals through the System Objects
y_imp_float = Filter_Float(impulse_sig.');
y_imp_bin   = Filter_Bin(impulse_sig.');
y_step_float = Filter_Float(step_sig.');
y_step_bin   = Filter_Bin(step_sig.');

% Reset filter states for safety
release(Filter_Float);
release(Filter_Bin);

figure('Name', 'FIR Filter Verification Panel', 'Position', [100, 100, 1200, 800]);

%% Plot 1: Magnitude Response
subplot(3,2,1);
plot(f, 20*log10(abs(H_float)), 'b', 'LineWidth', 1.5); hold on;
plot(f, 20*log10(abs(H_bin)), 'r--', 'LineWidth', 1.2);
grid on; xlim([0, fs/2]); ylim([-80, 5]);
title('Magnitude Response');
xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');
legend('Float', 'Fixed-Point (Q15)', 'Location', 'southwest');
% Verification highlights
xline(8.36, 'g:', '8.36 Hz');
xline(12.42, 'g:', '12.42 Hz');

%% Plot 2: Phase Response
subplot(3,2,2);
plot(f, unwrap(angle(H_float))*180/pi, 'b', 'LineWidth', 1.5); hold on;
plot(f, unwrap(angle(H_bin))*180/pi, 'r--', 'LineWidth', 1.2);
grid on; xlim([8.36, 12.42]); % Zoomed into passband for linearity check
title('Phase Response (Passband Zoom)');
xlabel('Frequency (Hz)'); ylabel('Phase (Degrees)');

%% Plot 3: Group Delay Response
subplot(3,2,3);
plot(f, gd_float, 'b', 'LineWidth', 1.5); hold on;
plot(f, gd_bin, 'r--', 'LineWidth', 1.2);
grid on; xlim([0, fs/2]); ylim([70, 85]);
title('Group Delay Response');
xlabel('Frequency (Hz)'); ylabel('Delay (Samples)');
yline((N-1)/2, 'k:', 'Target: 78 Samples');

%% Plot 4: Impulse Response
subplot(3,2,4);
stem(0:length(y_imp_float)-1, y_imp_float, 'b', 'Marker', 'o'); hold on;
stem(0:length(y_imp_bin)-1, y_imp_bin, 'r', 'Marker', 'x', 'LineStyle', '--');
grid on; xlim([0, N]);
title('Impulse Response (Symmetry & Peaks)');
xlabel('Sample Index (n)'); ylabel('Amplitude');
xline((N-1)/2, 'k:', 'Center Tap (78)');

%% Plot 5: Step Response
subplot(3,2,[5,6]);
plot(0:length(y_step_float)-1, y_step_float, 'b', 'LineWidth', 1.5); hold on;
plot(0:length(y_step_bin)-1, y_step_bin, 'r--', 'LineWidth', 1.2);
grid on; xlim([0, N*1.5]);
title('Step Response (Transient & Steady-State)');
xlabel('Sample Index (n)'); ylabel('Amplitude');
legend('Float', 'Fixed-Point (Q15)', 'Location', 'southeast');


%%  QUANTIFYING THE DIRECT-FORM BASELINE COST

% Query the native DSP System Toolbox cost engine
filter_cost = cost(Filter_Bin);

% Display the hardware breakdown structure
disp(filter_cost);


%%  AUTOMATED SIMULINK GENERATION

padded_coeffs = [q15_ints, zeros(1, 3)]; 

% Initialize and open the new Simulink model canvas
model_name = 'Custom_DA_FIR3-';
if bdIsLoaded(model_name)
    close_system(model_name, 0); 
end
new_system(model_name);
open_system(model_name);


fprintf('Configuring model parameters for strict HDL Coder synthesis...\n');
set_param(model_name, 'SolverType', 'Fixed-step');
set_param(model_name, 'Solver', 'FixedStepDiscrete');
set_param(model_name, 'FixedStep', 'auto');
set_param(model_name, 'SingleTaskRateTransMsg', 'error');
set_param(model_name, 'AlgebraicLoopMsg', 'error');
set_param(model_name, 'ProdHWDeviceType', 'ASIC/FPGA->ASIC/FPGA');
set_param(model_name, 'DataTypeOverride', 'Off');

% Parameter additions addressing specific report warnings:
set_param(model_name, 'BlockReduction', 'off');
set_param(model_name, 'ConditionallyExecuteInputs', 'off');
set_param(model_name, 'DefaultParameterBehavior', 'Inlined');
set_param(model_name, 'InheritOutputTypeSmallerThanSingle', 'on');

% Visualization rules
set_param(model_name, 'ShowLineDimensions', 'on');
set_param(model_name, 'ShowPortDataTypes', 'on');
set_param(model_name, 'SampleTimeColors', 'on'); % Clears sample time warning


fprintf('Spawning and populating 40 LUT chunks...\n');
for j = 1:40
    block_path = [model_name, '/LUT_Chunk_', num2str(j)];
    x_pos = 150 * j;
    
    add_block('simulink/Lookup Tables/Direct Lookup Table (n-D)', block_path, 'Position', [x_pos, 100, x_pos+100, 180]);
    
    chunk_coeffs = padded_coeffs((4*j-3):(4*j));
    computed_16_states = zeros(1, 16);
    for addr = 0:15
        bits = bitget(addr, 1:4); 
        computed_16_states(addr+1) = sum(bits .* double(chunk_coeffs)); 
    end
    
 
    fi_states = fi(computed_16_states, 1, 16, 15);
    table_str = mat2str(fi_states);
    
    set_param(block_path, 'NumberOfTableDimensions', '1');
    set_param(block_path, 'Table', table_str);
    set_param(block_path, 'InputsSelectThisObjectFromTable', 'Element');
    set_param(block_path, 'TableDataTypeStr', 'fixdt(1,16,15)');
end

fprintf('Wiring the input delay line, bit slices, and balanced adder tree...\n');

% 1. Spawn Driving Registers & Bit Slices
in_port_path = [model_name, '/In1'];
add_block('simulink/Sources/In1', in_port_path, 'Position', [50, -100, 80, -80]);
set_param(in_port_path, 'OutDataTypeStr', 'fixdt(1,16,15)');

for i = 1:4
    delay_path = [model_name, '/Delay_', num2str(i)];
    add_block('hdlsllib/Discrete/Delay', delay_path, 'Position', [150 + (i-1)*150, -110, 210 + (i-1)*150, -70]);
    set_param(delay_path, 'DelayLength', '1');
    
    if i == 1
        add_line(model_name, 'In1/1', 'Delay_1/1');
    else
        add_line(model_name, ['Delay_', num2str(i-1), '/1'], ['Delay_', num2str(i), '/1']);
    end
end

for j = 1:40
    slice_path = [model_name, '/BitSlice_Chunk_', num2str(j)];
    add_block('hdlsllib/Logic and Bit Operations/Bit Slice', slice_path, 'Position', [150*j + 30, 20, 150*j + 40, 60]);
    
    set_param(slice_path, 'lidx', '3'); 
    set_param(slice_path, 'ridx', '0'); 
    
    tap_index = mod(j-1, 4) + 1;
    add_line(model_name, ['Delay_', num2str(tap_index), '/1'], ['BitSlice_Chunk_', num2str(j), '/1']);
    add_line(model_name, ['BitSlice_Chunk_', num2str(j), '/1'], ['LUT_Chunk_', num2str(j), '/1']);
end

% 2. Generate and Wire Balanced Pipelined Adder Tree
current_stage_count = 40;
stage_idx = 1;
prev_block_prefix = 'LUT_Chunk_';
while current_stage_count > 1
    next_stage_count = ceil(current_stage_count / 2);
    y_pos = 200 + (stage_idx * 120);
    
    for k = 1:next_stage_count
        adder_name = ['Adder_S', num2str(stage_idx), '_', num2str(k)];
        adder_path = [model_name, '/', adder_name];
        x_pos = 300 * k + (stage_idx * 50);
        
        add_block('hdlsllib/Math Operations/Add', adder_path, 'Position', [x_pos, y_pos, x_pos+40, y_pos+40]);
        set_param(adder_path, 'Inputs', '++');
        
        % Force Adder to maintain full precision data inheritance
        set_param(adder_path, 'OutDataTypeStr', 'Inherit: Inherit via internal rule');
        
        in1_idx = 2*k - 1;
        add_line(model_name, [prev_block_prefix, num2str(in1_idx), '/1'], [adder_name, '/1']);
        
        if 2*k <= current_stage_count
            in2_idx = 2*k;
            add_line(model_name, [prev_block_prefix, num2str(in2_idx), '/1'], [adder_name, '/2']);
        else
            gnd_name = ['ConstZero_S', num2str(stage_idx), '_', num2str(k)];
            add_block('hdlsllib/Sources/Constant', [model_name, '/', gnd_name], 'Position', [x_pos-40, y_pos+20, x_pos-20, y_pos+30]);
            set_param([model_name, '/', gnd_name], 'Value', '0');
            set_param([model_name, '/', gnd_name], 'OutDataTypeStr', 'fixdt(1,16,15)');
            add_line(model_name, [gnd_name, '/1'], [adder_name, '/2']);
        end
    end
    
    prev_block_prefix = ['Adder_S', num2str(stage_idx), '_'];
    current_stage_count = next_stage_count;
    stage_idx = stage_idx + 1;
end

% 3. Wire into the Final Shift and Add Accumulator
last_adder_name = ['Adder_S', num2str(stage_idx-1), '_1'];
shift_block_path = [model_name, '/Shift_Arithmetic_Scale'];
out_port_path = [model_name, '/Out1'];

add_block('hdlsllib/Logic and Bit Operations/Shift Arithmetic', shift_block_path, 'Position', [500, y_pos + 150, 620, y_pos + 210]);
set_param(shift_block_path, 'BitShiftNumberSource', 'Dialog');
set_param(shift_block_path, 'BitShiftDirection', 'Right'); 
set_param(shift_block_path, 'BitShiftNumber', '2');         

add_block('simulink/Sinks/Out1', out_port_path, 'Position', [700, y_pos + 170, 730, y_pos + 190]);

add_line(model_name, [last_adder_name, '/1'], 'Shift_Arithmetic_Scale/1');
add_line(model_name, 'Shift_Arithmetic_Scale/1', 'Out1/1');


Simulink.BlockDiagram.arrangeSystem(model_name);
set_param(model_name, 'ZoomFactor', 'FitSystem');
fprintf('\n====================================================\n');
fprintf('   SUCCESS: COMPLETE DA FIR NETLIST GENERATED       \n');
fprintf('====================================================\n');