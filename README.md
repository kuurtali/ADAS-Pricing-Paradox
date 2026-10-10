# ADAS Pricing Paradox · Vol 1

[Live demo](https://5pax70-mehmet0ali-kurt.shinyapps.io/adas-pricing-paradox/) · [Vol 2](https://github.com/kuurtali/VOL2-ADAS-Pricing-Paradox) · [Portfolio](https://github.com/kuurtali) · [Report an issue](https://github.com/kuurtali/ADAS-Pricing-Paradox/issues)

An actuarial pricing demonstration using a **synthetic portfolio of 100,000 policies**. Poisson and Gamma models explore how lower claim frequency and higher claim cost can offset each other.

These are results under synthetic-data assumptions, not evidence of the real-world effect of ADAS or a production tariff.

## What you can use

- A Shiny interface for exploring the saved pricing model.
- R analysis and saved model summaries, charts and result tables.
- A Python/SQLite transformation for an existing raw input.
- A Power BI report.

## Saved results

The following values come from [outputs/results.json](outputs/results.json). Percent changes use its saved ratios against ADAS level 0, rounded to one decimal place.

| ADAS level | Frequency | Severity | Mean risk premium |
|---|---:|---:|---:|
| 0 · Baseline | — | — | — |
| 1 · Basic | −8.8% | +12.3% | +2.4% |
| 2 · Advanced | −25.7% | +29.3% | −3.8% |

The saved frequency RMSE is **0.3133** and severity RMSE is **20,529.0491 TL**. These are recorded outputs; the models were not retrained for this documentation update.

[Frequency coefficients](outputs/freq_model_summary.txt) · [Severity coefficients](outputs/sev_model_summary.txt) · [Segment tables](outputs)

## Method

The analysis splits the data into training and test subsets, fits a Poisson frequency model with an exposure offset, and fits a Gamma model to positive claim amounts. Predicted frequency and severity are multiplied to form the displayed risk premium.

The meaning of `Claim_Amount` must be kept consistent: aggregate policy loss and per-claim severity are different quantities. Validate this convention before reusing the model with another dataset.

## Run the demo

Install R and the packages requested by `app.R`, then open that file in RStudio and select **Run App**.

The public demo link above is the quickest way to explore the interface. The dashboard is a model demonstration, not an underwriting validation.

## Reproduce the analysis

**The public repository does not currently contain the raw-data generator or the required raw CSV.** A fresh clone alone cannot reproduce the training run.

1. Supply the original `ham_data.csv` with its required fields.
2. From the repository root, run `python src/FirstCodeWithKaggle.py`. This script **reads** the raw CSV, filters positive exposure and writes `SQL_Islem_Gormus_Veri.csv`; it does not generate synthetic policies.
3. In R, from the repository root, run `source("src/analysis.R")`.
4. Inspect the generated files in `outputs/`.

Python requires `pandas`; SQLite is part of Python. The R script lists and installs its package dependencies.

**Known analysis issue:** additional raw columns are currently copied by row position after the SQL step filters rows. If rows were removed, attributes can become misaligned. Join by `Policy_ID` and validate one-to-one matches before using a new input or claiming a reproduced result.

## Files

| File | Purpose |
|---|---|
| `app.R` | Interactive Shiny demo |
| `src/FirstCodeWithKaggle.py` | Existing CSV → SQL-derived features |
| `src/analysis.R` | Modeling, diagnostics and result exports |
| `outputs/results.json` | Saved numerical summary |
| `outputs/figures/` | Saved diagnostic and comparison charts |
| `ADAS_Actuarial_Pricing.pbix` | Power BI report |

## Next improvements

Restore the original synthetic-data generator and input schema; replace positional column copying with an ID join; add a reproducible environment and automated pipeline check. A matched-data comparison is needed before attributing differences between Vol 1 and Vol 2 to model changes.

## License

[MIT](LICENSE) for repository code.
