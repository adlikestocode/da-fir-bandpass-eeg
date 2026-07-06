# DA-FIR Bandpass Filter — EEG Mu Rhythm Isolation

> **Design and simulate a Distributed Arithmetic FIR filter in Python to isolate the mu rhythm (8–13 Hz) from a single-channel motor imagery EEG signal (C3, PhysioNet dataset), implementing fixed-point arithmetic and LUT-based accumulation faithful to FPGA hardware constraints, with RTL synthesis via MATLAB HDL Coder.**

---

## Project Status

| Phase | Status | Description |
|-------|--------|-------------|
| Phase 1 — Behavioral Simulation | ✅ Complete | Python DA FIR on real PhysioNet EEG |
| Phase 2 — RTL Implementation | ✅ Complete | Verilog generated via MATLAB HDL Coder |

---

## Key Results

**Mu-Band SNR across processing stages:**

![SNR Across Processing Stages](assets/snr_processing_stages.png)

The filter improves mu-band SNR from **-7.90 dB** (raw) to **49.31 dB** (filtered), with Surface Laplacian spatial filtering further improving to **55.86 dB**.

**Before vs After Filtering — PSD:**

![PSD Comparison](assets/psd_wideband_vs_mu.png)

---

## Skills Demonstrated

| Skill | How |
|-------|-----|
| Digital Signal Processing | Kaiser window FIR design, data-driven spec derivation, frequency response analysis |
| Fixed-Point Arithmetic | Manual Q15 quantization, per-tap error analysis, float vs int16 comparison |
| Hardware-Aware Design | DA architecture with partitioned LUTs, FPGA-targeted Simulink model |
| RTL Synthesis | MATLAB HDL Coder automated Verilog generation, testbench, validation model |
| Biomedical Signal Analysis | PhysioNet EEG data, Surface Laplacian spatial filtering, mu rhythm extraction |
| Systems Engineering | Requirements-first design, V&V across all processing stages, documented tradeoffs |

**Context:** Preprocessing stage for a real-time motor imagery BCI pipeline.

---

## Repository Structure

```
da-fir-bandpass-eeg/
├── notebook/
│   └── firfilter.ipynb              ← Full Python pipeline — data to verification
├── matlab/
│   ├── scripts/
│   │   └── script_firfilter.m       ← Filter analysis + automated Simulink generation
│   ├── simulink/
│   │   └── CUSTOM_DA_FIR_final.slx  ← DA FIR Simulink model (HDL Coder ready)
│   └── hdl_output/
│       ├── da_fir_bandpass.v        ← Generated synthesizable Verilog
│       ├── da_fir_bandpass_tb.v     ← Generated testbench
│       ├── da_fir_bandpass_val.slx  ← HDL Coder validation model
│       └── filter_response_plot.png ← MATLAB verification panel
├── data/
│   └── filter_coefficients.mat      ← Exported float64 + Q15 int16 coefficients
├── results/
│   ├── filter_design/               ← Frequency response, group delay, compliance
│   ├── quantization/                ← Q15 error analysis, tap deviation plots
│   ├── verification/                ← Impulse, step, settling transient
│   ├── surface_laplacian/           ← CSD analysis, spectral power ratio
│   └── results/                     ← Final filtered output, PSD, SNR
└── docs/
    └── report.md                    ← Engineering design document
```

---

## Pipeline Overview

```
PhysioNet EEG Data (PhysioBank, Subject 1)
    │
    ▼
MNE-Python — Load, extract C3/C4/Cz, compute PSD
    │
    ▼
Data-Driven Spec Derivation
    │   Passband:  8.36 – 12.42 Hz (mu rhythm, derived from data)
    │   Stopband:  ≥ 60 dB attenuation
    │   Taps:      157 (Kaiser window, β parameterized to spec)
    │
    ▼
Python DA FIR Class (NumPy)
    │   Manual Q15 quantization  →  int16 coefficients
    │   Partitioned LUT (40 chunks × 4 taps × 16 states)
    │   Bit-serial accumulation  →  faithful to FPGA timing
    │
    ▼
Verification (Python)
    │   Float64 vs Q15 frequency response comparison
    │   Per-tap quantization error analysis
    │   Group delay: constant 78 samples (linear phase confirmed)
    │   Specification compliance audit
    │
    ▼
Surface Laplacian (Spherical Spline CSD)
    │   Spatial filtering via MNE
    │   SNR: -7.90 dB → 49.31 dB → 55.86 dB
    │
    ▼
Export → filter_coefficients.mat
    │
    ▼
MATLAB — script_firfilter.m
    │   dsp.FIRFilter objects (float + Q15)
    │   5-panel verification (magnitude, phase, group delay, impulse, step)
    │   Automated Simulink model generation
    │       40 partitioned LUTs (fi, fixdt(1,16,15))
    │       Balanced pipelined adder tree (6 stages)
    │       Arithmetic right shift accumulator
    │
    ▼
HDL Coder — CUSTOM_DA_FIR_final.slx
    │   Target: ASIC/FPGA, fixed-step discrete solver
    │   Generated: Verilog RTL + testbench + validation model
    │
    ▼
Synthesizable Verilog — da_fir_bandpass.v
```

---

## Filter Specifications

| Parameter | Value | Derivation |
|-----------|-------|------------|
| Sample Rate | 160 Hz | PhysioNet native |
| Passband | 8.36 – 12.42 Hz | Data-driven from C3 PSD |
| Stopband Attenuation | ≥ 60 dB | Kaiser β parameterized |
| Passband Ripple | ≤ 1 dB | Verified via compliance audit |
| Filter Order | 157 taps | Kaiser window design |
| Group Delay | 78 samples (constant) | Linear phase — Type I FIR |
| Coefficient Format | float64 → int16 (Q15) | Fixed-point for FPGA |
| LUT Architecture | 40 chunks × 16 states | Partitioned DA, 4 taps/chunk |

---

## Quantization Analysis

- All 157 per-tap absolute errors bounded within Q15 LSB step (Δ = 3.05e-05)
- High relative error taps identified at near-zero coefficient locations: [0, 5, 28, 128, 151, 156]
- Frequency response deviation within ±0.0025 dB across passband
- Float vs Q15 magnitude responses visually indistinguishable in passband

---

## RTL Notes

The synthesizable Verilog was generated from the Simulink DA FIR model via MATLAB HDL Coder. The Simulink model implements:
- 4-tap input delay line (hdlsllib Delay blocks)
- 40 partitioned Direct Lookup Tables with precomputed fi(1,16,15) states
- 6-stage balanced pipelined adder tree
- Arithmetic right shift scaling accumulator

**Known limitation:** Simulink-level output verification revealed a scaling discrepancy in the final accumulator stage, attributed to bit-shift configuration between the partitioned DA architecture and Q15 output format. Filter coefficients and frequency response are fully verified at the MATLAB and Python levels. RTL scaling resolution is noted as future work.

---

## Tech Stack

| Tool | Role |
|------|------|
| Python + NumPy | DA FIR class, manual Q15 fixed-point arithmetic |
| SciPy | Kaiser window FIR coefficient design |
| MNE-Python | PhysioNet EEG loading, Surface Laplacian |
| Matplotlib | All analysis plots |
| MATLAB DSP Toolbox | Filter verification objects, 5-panel analysis |
| MATLAB Simulink + HDL Coder | Automated DA FIR model + RTL generation |
| Vivado (target) | Synthesis target for generated Verilog |

---

## Dataset

PhysioNet EEG Motor Movement/Imagery Dataset  
Goldberger et al. PhysioBank, PhysioToolkit, PhysioNet. *Circulation* 101(23), 2000.  
Available at: https://physionet.org/content/eegmmidb/1.0.0/

---

## References

1. Proakis, J.G. & Manolakis, D.G. — *Digital Signal Processing* (4th ed.)
2. Oppenheim, A.V. & Schafer, R.W. — *Discrete-Time Signal Processing*
3. MathWorks — HDL Coder: Distributed Arithmetic for FIR Filters
4. Kayser, C. & Logothetis, N.K. — Current Source Density (CSD) analysis in EEG
