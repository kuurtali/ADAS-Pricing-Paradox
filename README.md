# 🚗 ADAS Pricing Paradox

**An End-to-End Actuarial Project** analyzing the trade-off between crash frequency reduction and repair cost inflation in modern vehicles equipped with Advanced Driver Assistance Systems (ADAS).

---

## 📌 Research Question

> *Do ADAS-equipped vehicles actually cost less to insure — or does the rising repair cost of sensor-laden cars cancel out the safety benefit?*

This is the **ADAS Pricing Paradox**: while ADAS reduces accident frequency, the sophisticated sensors and components (LiDAR, radar, cameras embedded in windshields) dramatically increase repair costs per claim.

## 🔍 Key Findings

| ADAS Level | Frequency Change | Severity Change | Net Premium Effect |
|:----------:|:----------------:|:---------------:|:------------------:|
| ADAS 0 (None) | Baseline | Baseline | Baseline |
| ADAS 1 (Basic) | **−9.7%** | **+12.8%** | +1.9% |
| ADAS 2 (Advanced) | **−24.7%** | **+28.6%** | −3.0% |

**The paradox is confirmed:**
- ADAS **reduces crash frequency** by up to 24.7%
- But **increases repair costs** by up to 28.6%
- The net effect on insurance premium is **nearly zero** — the safety benefit is almost entirely offset by higher repair costs

![Paradox Visualization](outputs/figures/paradox_main.png)

## 🛠️ Pipeline

```
Python (Data Generation)  →  SQL (Feature Engineering)  →  R (GLM Modeling)  →  Power BI (Dashboard)
```

| Step | Tool | Script | Output |
|------|------|--------|--------|
| 1. Data Generation | Python | `src/FirstCodeWithKaggle.py` | `ham_data.csv` |
| 2. Feature Engineering | SQL (via Python) | *(embedded in step 1)* | `SQL_Islem_Gormus_Veri.csv` |
| 3. GLM Analysis | R | `src/analysis.R` | `R_Islem_Gormus_Veri.csv` + outputs |
| 4. Visualization | Power BI | `ADAS_Actuarial_Pricing.pbix` | Interactive dashboard |

## 📊 Methodology

### Frequency Model (Poisson GLM)
```
Claim_Count ~ Safety_Package_Level + Driver_Age + Vehicle_Age 
              + City + Vehicle_Segment + NCD_Level + Traffic_Density
              + offset(log(Exposure))
```

### Severity Model (Gamma GLM)
```
Claim_Amount ~ Safety_Package_Level + Vehicle_Age + Driver_Age
               + Vehicle_Brand + Vehicle_Segment
```

### Risk Premium
```
Risk_Premium = Predicted_Frequency × Predicted_Severity
```

Model diagnostics (residual analysis, QQ-plots, overdispersion tests) are included in the R output.

## 📁 Project Structure

```
ADAS-Pricing-Paradox/
├── src/
│   ├── FirstCodeWithKaggle.py    # Data generation + SQL processing
│   └── analysis.R                # GLM modeling + paradox analysis
├── outputs/
│   ├── figures/                  # Diagnostic & paradox charts (PNG)
│   │   ├── paradox_main.png      # Main paradox visualization
│   │   ├── paradox_city.png      # City-level breakdown
│   │   ├── freq_residuals.png    # Frequency model diagnostics
│   │   └── sev_residuals.png     # Severity model diagnostics
│   ├── paradox_summary.csv       # ADAS-level summary statistics
│   ├── segment_city.csv          # City × ADAS breakdown
│   ├── segment_age.csv           # Age group × ADAS breakdown
│   ├── segment_vehicle.csv       # Vehicle type × ADAS breakdown
│   ├── freq_model_summary.txt    # Frequency model coefficients
│   ├── sev_model_summary.txt     # Severity model coefficients
│   └── results.json              # All results (machine-readable)
├── ham_data.csv                  # Raw synthetic dataset (100K policies)
├── SQL_Islem_Gormus_Veri.csv     # SQL-processed data
├── R_Islem_Gormus_Veri.csv       # Final enriched output
├── ADAS_Actuarial_Pricing.pbix   # Power BI dashboard
├── Rcode.R                       # Original R script (v1)
├── .gitignore
├── LICENSE
└── README.md
```

## 🚀 How to Run

### Prerequisites
- Python 3.x
- R 4.x with packages: `dplyr`, `statmod`, `MASS`, `ggplot2`, `jsonlite`
- Power BI Desktop (optional, for interactive dashboard)

### Steps
```bash
# 1. Data is already generated (ham_data.csv)
# 2. SQL processing (if needed to regenerate)
python src/FirstCodeWithKaggle.py

# 3. Run GLM analysis + paradox investigation
Rscript src/analysis.R

# 4. Open Power BI dashboard (optional)
# Open ADAS_Actuarial_Pricing.pbix in Power BI Desktop
```

## 📈 Data

Synthetic insurance portfolio with **100,000 policies** and 12 features:

| Feature | Description |
|---------|-------------|
| `Safety_Package_Level` | ADAS level: 0 (none), 1 (basic), 2 (advanced) |
| `Driver_Age` | Driver age (18–80) |
| `Vehicle_Age` | Vehicle age (0–23 years) |
| `City` | Istanbul, Ankara, Izmir, Bursa, Antalya, Other |
| `Vehicle_Brand` | Fiat, Toyota, Renault, Ford, Honda, BMW |
| `Vehicle_Segment` | Hatchback, Sedan, SUV |
| `Traffic_Density` | Traffic density index (2–10) |
| `NCD_Level` | No-Claim Discount level (0–6) |
| `Exposure` | Policy exposure in years (0–1) |
| `Claim_Count` | Number of claims |
| `Claim_Amount` | Total claim amount (TL) |

## 📜 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
