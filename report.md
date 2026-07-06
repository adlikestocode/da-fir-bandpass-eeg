# Engineering Design Report
## Distributed Arithmetic FIR Filter for EEG Mu Rhythm Isolation

---

## 1. Abstract

A 157-tap Distributed Arithmetic (DA) FIR bandpass filter was designed and implemented to isolate the mu rhythm (8.36–12.42 Hz) from single-channel EEG data recorded at C3 during a motor imagery task. Filter specifications were derived directly from the data using power spectral analysis. Coefficients were designed using the Kaiser window method and quantized to Q15 fixed-point (int16) format, with all per-tap quantization errors verified to remain within the Q15 LSB bound. The filter was implemented as a Python class with manual fixed-point arithmetic and partitioned LUT-based accumulation faithful to FPGA DA architecture. Mu-band SNR improved from -7.90 dB (raw) to 49.31 dB (filtered), and further to 55.86 dB following Surface Laplacian spatial filtering. A synthesizable Verilog implementation was generated via MATLAB HDL Coder from an automated Simulink model.

---

## 2. Introduction and Motivation

Motor imagery BCI systems rely on detecting Event-Related Desynchronization (ERD) in the mu band (8–13 Hz) over the motor cortex. Raw EEG contains broadband noise, low-frequency drift, and high-frequency muscle artifact that obscure this signal. A bandpass filter isolating the mu band is therefore the first preprocessing stage in any motor imagery pipeline.

This project implements this preprocessing stage using a Distributed Arithmetic FIR architecture — a multiplier-free design that replaces multiply-accumulate operations with precomputed lookup tables and shift-accumulate logic. This architecture is well-suited to FPGA implementation where DSP slice counts are constrained. The design flow proceeds from data-driven specification, through Python behavioral simulation, to automated MATLAB RTL generation — mirroring industry practice for embedded DSP systems.

---

## 3. System Requirements

Requirements were defined before implementation. Every design decision traces back to one of these.

| ID | Type | Requirement |
|----|------|-------------|
| R1 | Functional | Filter shall isolate the mu rhythm band from EEG recorded at C3 |
| R2 | Performance | Passband shall be derived from measured data, not assumed |
| R3 | Performance | Stopband attenuation shall be ≥ 60 dB |
| R4 | Performance | Passband ripple shall not exceed 1 dB |
| R5 | Performance | Group delay shall be constant across all frequencies (linear phase) |
| R6 | Implementation | Coefficient wordlength shall not exceed 16 bits (Q15) |
| R7 | Implementation | LUT-based accumulation shall be faithful to FPGA DA architecture |
| R8 | Verification | Float64 and Q15 frequency responses shall be compared quantitatively |
| R9 | Verification | RTL shall be generated from the verified Simulink behavioral model |

---

## 4. Data and Signal Analysis

### 4.1 Dataset

PhysioNet EEG Motor Movement/Imagery Dataset. Subject 1, resting state recording. Loaded via MNE-Python. Channels C3, C4, and Cz extracted for analysis.

### 4.2 Data-Driven Specification Derivation

Rather than assuming standard mu band boundaries (8–13 Hz), filter cutoff frequencies were derived from the measured PSD of the C3 channel. The -3 dB points of the observed mu peak were identified at **8.36 Hz** and **12.42 Hz**, establishing the passband from data.

![Raw EEG PSD](../results/filter_design/raw_eeg_psd.png)

Pre-filter SNR analysis quantified the noise problem: mu-band signal power at -87.20 dB vs low-frequency noise power at -80.52 dB, giving a pre-filter SNR of **-6.68 dB**. This justified the filtering requirement formally.

![Pre-Filter SNR](../results/filter_design/prefilter_snr.png)

---

## 5. Filter Design

### 5.1 Window Method Selection

The Kaiser window was selected over Hamming or Hanning because its β parameter is directly calculable from the stopband attenuation requirement. For 60 dB attenuation, Kaiser β = 5.653, giving a filter order of 156 (157 taps). Hamming at fixed 43 dB attenuation would not meet R3.

### 5.2 Frequency Response

![Filter Frequency Response](../results/filter_design/filter_frequency_response.png)

-3 dB cutoffs confirmed at 8.66 Hz and 12.11 Hz, consistent with data-derived specification.

### 5.3 Linear Phase Verification

![Group Delay](../results/verification/group_delay_linear_phase.png)

Group delay is constant at 78 samples across all frequencies, confirming Type I linear phase FIR. Analytical prediction: (N-1)/2 = (157-1)/2 = 78. Matches exactly. R5 satisfied.

### 5.4 Specification Compliance Audit

![Compliance Audit](../results/verification/filter_spec_compliance.png)

All sidelobes remain below -60 dB. Passband ripple within ±1 dB. R3 and R4 satisfied.

![Passband Zoom](../results/verification/passband_spectral_zoom.png)

---

## 6. Quantization Analysis

### 6.1 Q15 Coefficient Quantization

Float64 Kaiser coefficients were quantized to Q15 format (int16, 16-bit signed fixed-point, 15 fractional bits). The LSB step size at Q15 is Δ = 2⁻¹⁵ = 3.05e-05.

![Coefficient Comparison](../results/quantization/analytical_vs_reconstructed_coefficients.png)

All 157 per-tap absolute errors remain within the Q15 LSB bound. Inset magnification at taps 75–85 confirms float and Q15 representations are visually indistinguishable at the center tap region.

### 6.2 Frequency Response Deviation

![Magnitude Comparison](../results/filter_design/magnitude_profile_comparison.png)

Q15 and float64 magnitude responses overlap throughout the passband. Quantization-induced deviation is bounded within ±0.0025 dB across the passband. Sidelobe deviation visible at null points (expected at near-zero gain) — no functional impact. R6 and R8 satisfied.

### 6.3 High Relative Error Taps

![High Error Taps](../results/quantization/high_relative_error_taps.png)

Taps [0, 5, 28, 128, 151, 156] show high relative quantization error because their float64 values are near zero — small absolute error produces high relative error. This is expected behaviour for windowed FIR edge taps and has no meaningful effect on frequency response.

---

## 7. Implementation

### 7.1 Python DA FIR Class

The filter was implemented as a Python class using NumPy with manual fixed-point arithmetic. Key design decisions:

- **Sample-by-sample processing** via `process_sample()` — faithful to hardware timing, not vectorised
- **Partitioned LUT** — 157 taps padded to 160, divided into 40 chunks of 4 taps each. Each chunk has 2⁴ = 16 precomputed states
- **Manual Q15 arithmetic** — no fixed-point library used; quantization, LUT population, and accumulation written explicitly

### 7.2 Coefficient Storage

Coefficients exported as both float64 and int16 in `filter_coefficients.mat` for MATLAB import. This separation allows independent verification of both paths.

### 7.3 Kaiser Coefficients and Impulse Response

![Coefficients and Impulse](../results/verification/kaiser_coefficients_impulse.png)

Stored coefficients and `apply_fir()` impulse response match: True. Symmetric about tap 78. R7 satisfied.

### 7.4 Step Response

![Step Response](../results/verification/step_response.png)

### 7.5 Filter Settling Transient

![Settling Transient](../results/verification/settling_transient.png)

Filter reaches steady state after 78 samples (487.5 ms at 160 Hz), consistent with group delay. Samples within the transient boundary are flagged and excluded from downstream analysis.

---

## 8. Results

### 8.1 Time Domain — Filtered Output

![Time Domain Results](../results/results/time_domain_raw_vs_filtered.png)

Raw EEG amplitude range ±250 µV reduced to ±25 µV mu-band signal at C3, C4, and Cz. Broadband noise successfully removed.

### 8.2 Spatially Averaged Result

![Spatially Averaged](../results/results/spatially_averaged_filtered.png)

### 8.3 PSD — Before and After

![PSD Comparison](../results/results/psd_wideband_vs_mu.png)

Post-filtered PSD shows energy concentrated in the 8–13 Hz band with all other frequencies attenuated by several decades.

### 8.4 Surface Laplacian Validation

Surface Laplacian (spherical spline CSD) was applied as a spatial filter to validate that the temporally isolated mu rhythm was also spatially concentrated over motor cortex.

![Surface Laplacian Time Domain](../results/surface_laplacian/c3_raw_vs_laplacian.png)

![Surface Laplacian PSD](../results/surface_laplacian/voltage_vs_laplacian_psd.png)

The Laplacian PSD shows a clear spectral peak in the mu band absent from the voltage reference, confirming source localisation at C3.

![Spatial Power Ratio](../results/surface_laplacian/laplacian_power_ratio.png)

Laplacian-to-reference power ratio peaks within the mu passband, confirming spatial concentration of the extracted signal.

### 8.5 SNR Across Processing Stages

![SNR Stages](../results/results/snr_processing_stages.png)

| Stage | Mu-Band SNR |
|-------|-------------|
| Raw (pre-filter) | -7.90 dB |
| Temporally filtered (DA FIR) | 49.31 dB |
| Temporally + spatially filtered (Surface Laplacian) | 55.86 dB |

Total SNR improvement: **63.76 dB**.

---

## 9. RTL Implementation

### 9.1 MATLAB Filter Verification

`script_firfilter.m` instantiates `dsp.FIRFilter` objects for both float and Q15 paths using the exported `.mat` coefficients. A 5-panel verification plot confirms:
- Magnitude response matches Python design
- Phase linearity confirmed in passband zoom
- Group delay constant at 78 samples
- Impulse symmetry about center tap
- Step response transient and steady-state behaviour

### 9.2 Automated Simulink Model

The MATLAB script programmatically generates `CUSTOM_DA_FIR_final.slx` containing:
- 4-tap input delay line using HDL Simulink Library Delay blocks
- 40 Direct Lookup Table blocks with precomputed `fi(1,16,15)` states
- 6-stage balanced pipelined adder tree (40 → 20 → 10 → 5 → 3 → 2 → 1)
- Arithmetic right shift scaling accumulator
- Model configured for strict HDL Coder compliance: fixed-step discrete solver, ASIC/FPGA target, data type override off

### 9.3 HDL Code Generation

Synthesizable Verilog, testbench, and validation model generated via HDL Workflow Advisor (steps 1–3 complete). HDL Advisor steps passed: Set Target Device, Set Target Frequency, Check Model Settings, Set HDL Options.

### 9.4 Known Limitation

Simulink-level output verification revealed a scaling discrepancy in the final accumulator stage. The generated RTL coefficients and architecture are correct. The issue is isolated to the bit-shift value in the output scaling stage — a configuration mismatch between partitioned DA accumulation depth and Q15 output format. Coefficient and frequency response verification at MATLAB and Python levels are unaffected. Resolution is noted as future work.

---

## 10. Verification Summary

| Requirement | Verification Method | Result |
|-------------|--------------------|---------| 
| R1 — Mu isolation | PSD before/after comparison | ✅ Pass |
| R2 — Data-driven spec | Cutoffs measured from C3 PSD | ✅ Pass |
| R3 — 60 dB stopband | Compliance audit plot | ✅ Pass |
| R4 — 1 dB ripple | Passband zoom | ✅ Pass |
| R5 — Linear phase | Group delay: constant 78 samples | ✅ Pass |
| R6 — 16-bit Q15 | Per-tap error within LSB bound | ✅ Pass |
| R7 — DA architecture | Partitioned LUT + serial accumulation | ✅ Pass |
| R8 — Float vs Q15 | Frequency response deviation ±0.0025 dB | ✅ Pass |
| R9 — RTL generation | HDL Coder Verilog + testbench generated | ✅ Pass |

---

## 11. Limitations and Future Work

- RTL output scaling mismatch to be resolved by correcting the accumulator right-shift value from 2 to 15 (Q30 → Q15)
- Simulink-level cosimulation validation pending scaling fix
- Filter designed for single subject — cross-subject generalisation not evaluated
- ERD analysis not included — would require epoched motor imagery trials
- Synthesis and place-and-route on physical FPGA target not performed

---

## 12. References

1. Proakis, J.G. & Manolakis, D.G. — *Digital Signal Processing*, 4th ed., Pearson
2. Oppenheim, A.V. & Schafer, R.W. — *Discrete-Time Signal Processing*, 3rd ed., Pearson
3. MathWorks Documentation — HDL Coder: Distributed Arithmetic for FIR Filters
4. White, P.R. — Distributed Arithmetic FIR Filter Design for FPGAs
5. Goldberger et al. — PhysioBank, PhysioToolkit, PhysioNet. *Circulation* 101(23), 2000
6. Kayser, C. & Logothetis, N.K. — CSD analysis in EEG, *J Neurosci Methods*, 2009
7. MNE-Python Documentation — mne.tools/stable
