## ---- ADAS Pricing Paradox — GLM Analysis & Paradox Investigation ----
## Pipeline: ham_data.csv -> SQL_Islem_Gormus_Veri.csv -> [THIS SCRIPT] -> outputs

rm(list = ls())

# Set working directory to project root (one level up from src/)
script_dir <- tryCatch(
  dirname(dirname(normalizePath(sys.frame(1)$ofile))),
  error = function(e) dirname(getwd())
)
setwd(script_dir)
cat("Calisma dizini:", getwd(), "\n")

required_pkgs <- c("dplyr", "statmod", "MASS", "ggplot2", "jsonlite",
                   "corrplot", "gridExtra", "scales")
for (pkg in required_pkgs) {
  if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
    install.packages(pkg, repos = "https://cran.r-project.org")
    library(pkg, character.only = TRUE)
  }
}

dir.create("outputs/figures", recursive = TRUE, showWarnings = FALSE)

## ---- 1: Data Load ----

file_path  <- "SQL_Islem_Gormus_Veri.csv"
first_line <- readLines(file_path, n = 1)
data <- if (grepl(";", first_line)) read.csv2(file_path) else read.csv(file_path)

data$Safety_Package_Level <- as.factor(data$Safety_Package_Level)
data$City                 <- as.factor(data$City)

ham_path <- "ham_data.csv"
if (file.exists(ham_path)) {
  ham        <- read.csv(ham_path)
  extra_cols <- c("Driver_Age", "Vehicle_Age", "Traffic_Density",
                  "NCD_Level", "Vehicle_Brand", "Vehicle_Segment")
  for (col in extra_cols) {
    if (col %in% names(ham) && !(col %in% names(data)))
      data[[col]] <- ham[[col]][1:nrow(data)]
  }
  if ("Vehicle_Brand"   %in% names(data)) data$Vehicle_Brand   <- as.factor(data$Vehicle_Brand)
  if ("Vehicle_Segment" %in% names(data)) data$Vehicle_Segment <- as.factor(data$Vehicle_Segment)
}

## ---- 2: Exploratory Data Analysis (EDA) ----

cat("\n===== EDA =====\n")

num_vars   <- data %>% dplyr::select(where(is.numeric), -Policy_ID)
cor_matrix <- cor(num_vars, use = "complete.obs")
png("outputs/figures/eda_correlation.png", width = 800, height = 800, res = 120)
corrplot::corrplot(cor_matrix, method = "color", type = "upper",
                   tl.col = "black", tl.srt = 45, addCoef.col = "black",
                   number.cex = 0.7, main = "Korelasyon Matrisi", mar = c(0, 0, 2, 0))
dev.off()
cat("  eda_correlation.png kaydedildi.\n")

png("outputs/figures/eda_distributions.png", width = 1000, height = 400, res = 120)
par(mfrow = c(1, 2))
hist(data$Driver_Age,
     main = "Surucu Yasi Dagilimi", xlab = "Yas",
     col = "skyblue", border = "white")
hist(data$Claim_Amount[data$Claim_Amount > 0],
     main = "Hasar Tutari Dagilimi (Sifir Haric)",
     xlab = "Tutar (TL)", col = "lightcoral", border = "white", breaks = 30)
dev.off()
cat("  eda_distributions.png kaydedildi.\n")

## ---- 3: Train / Test Split ----

set.seed(123)
train_indices <- sample(seq_len(nrow(data)), size = 0.8 * nrow(data))
train_data    <- data[ train_indices, ]
test_data     <- data[-train_indices, ]
cat(sprintf("\nTrain seti: %d gozlem | Test seti: %d gozlem\n",
            nrow(train_data), nrow(test_data)))

## ---- 4: Frequency Model (Poisson GLM) ----

cat("\n===== FREKANS MODELI (Poisson GLM) =====\n")

freq_vars <- "Safety_Package_Level + City"
if ("Driver_Age"       %in% names(data)) freq_vars <- paste(freq_vars, "+ Driver_Age")
if ("Vehicle_Age"      %in% names(data)) freq_vars <- paste(freq_vars, "+ Vehicle_Age")
if ("NCD_Level"        %in% names(data)) freq_vars <- paste(freq_vars, "+ NCD_Level")
if ("Traffic_Density"  %in% names(data)) freq_vars <- paste(freq_vars, "+ Traffic_Density")
if ("Vehicle_Segment"  %in% names(data)) freq_vars <- paste(freq_vars, "+ Vehicle_Segment")

freq_formula <- as.formula(paste("Claim_Count ~", freq_vars, "+ offset(log(Exposure))"))
model_freq   <- glm(freq_formula, data = train_data, family = poisson(link = "log"))

writeLines(capture.output(summary(model_freq)), "outputs/freq_model_summary.txt")

pearson_chi2 <- sum(residuals(model_freq, type = "pearson")^2)
disp_ratio   <- pearson_chi2 / model_freq$df.residual
cat(sprintf("Overdispersion orani: %.3f\n", disp_ratio))

## ---- 5: Severity Model (Gamma GLM) ----

cat("\n===== SIDDET MODELI (Gamma GLM) =====\n")

train_sev <- subset(train_data, Claim_Count > 0 & Claim_Amount > 0)

sev_vars <- "Safety_Package_Level"
if ("Vehicle_Age"     %in% names(data)) sev_vars <- paste(sev_vars, "+ Vehicle_Age")
if ("Driver_Age"      %in% names(data)) sev_vars <- paste(sev_vars, "+ Driver_Age")
if ("Vehicle_Brand"   %in% names(data)) sev_vars <- paste(sev_vars, "+ Vehicle_Brand")
if ("Vehicle_Segment" %in% names(data)) sev_vars <- paste(sev_vars, "+ Vehicle_Segment")

sev_formula <- as.formula(paste("Claim_Amount ~", sev_vars))
model_sev   <- glm(sev_formula, data = train_sev, family = Gamma(link = "log"))

writeLines(capture.output(summary(model_sev)), "outputs/sev_model_summary.txt")

## ---- 6: RMSE Test & Full-Data Predictions ----

cat("\n===== TEST SETI PERFORMANSI (RMSE) =====\n")

test_data$Pred_Freq <- predict(model_freq, newdata = test_data, type = "response")
test_data$Pred_Sev  <- predict(model_sev,  newdata = test_data, type = "response")

rmse_freq <- sqrt(mean((test_data$Claim_Count - test_data$Pred_Freq)^2))
cat(sprintf("Frekans Modeli RMSE: %.4f\n", rmse_freq))

test_sev <- subset(test_data, Claim_Count > 0)
if (nrow(test_sev) > 0) {
  rmse_sev <- sqrt(mean((test_sev$Claim_Amount - test_sev$Pred_Sev)^2))
  cat(sprintf("Siddet Modeli RMSE:  %.2f TL\n", rmse_sev))
}

data$Pred_Frequency <- predict(model_freq, newdata = data, type = "response")
data$Pred_Severity  <- predict(model_sev,  newdata = data, type = "response")
data$Risk_Premium   <- data$Pred_Frequency * data$Pred_Severity

## ---- 7: Diagnostic Plots ----

png("outputs/figures/freq_residuals.png", width = 900, height = 400)
par(mfrow = c(1, 2), mar = c(4, 4, 3, 1))
plot(fitted(model_freq), residuals(model_freq, type = "pearson"),
     main = "Frequency Residuals vs Fitted",
     pch = 20, col = rgb(0, 0, 0, 0.15))
abline(h = 0, col = "red", lwd = 2)
qqnorm(residuals(model_freq, type = "pearson"),
       pch = 20, col = rgb(0, 0, 0, 0.15))
qqline(residuals(model_freq, type = "pearson"), col = "red", lwd = 2)
dev.off()

png("outputs/figures/sev_residuals.png", width = 900, height = 400)
par(mfrow = c(1, 2), mar = c(4, 4, 3, 1))
plot(fitted(model_sev), residuals(model_sev, type = "pearson"),
     main = "Severity Residuals vs Fitted",
     pch = 20, col = rgb(0, 0, 0, 0.15))
abline(h = 0, col = "red", lwd = 2)
qqnorm(residuals(model_sev, type = "pearson"),
       pch = 20, col = rgb(0, 0, 0, 0.15))
qqline(residuals(model_sev, type = "pearson"), col = "red", lwd = 2)
dev.off()

## ---- 8: Paradox Analysis — ggplot2 with Confidence Intervals ----

cat("\n===== ADAS FIYATLAMA PARADOKSU ANALIZI =====\n")

paradox <- data %>%
  group_by(Safety_Package_Level) %>%
  summarise(
    Police_Sayisi  = n(),
    Ort_Frekans    = mean(Pred_Frequency),
    SE_Frekans     = sd(Pred_Frequency)  / sqrt(n()),
    Ort_Siddet     = mean(Pred_Severity),
    SE_Siddet      = sd(Pred_Severity)   / sqrt(n()),
    Ort_Risk_Primi = mean(Risk_Premium),
    SE_Risk_Primi  = sd(Risk_Premium)    / sqrt(n()),
    .groups = "drop"
  )

baseline_freq <- paradox$Ort_Frekans[paradox$Safety_Package_Level == "0"]
baseline_sev  <- paradox$Ort_Siddet[paradox$Safety_Package_Level  == "0"]
baseline_prem <- paradox$Ort_Risk_Primi[paradox$Safety_Package_Level == "0"]

paradox$Freq_vs_Baseline <- paradox$Ort_Frekans    / baseline_freq
paradox$Sev_vs_Baseline  <- paradox$Ort_Siddet     / baseline_sev
paradox$Prim_vs_Baseline <- paradox$Ort_Risk_Primi / baseline_prem

write.csv(as.data.frame(paradox), "outputs/paradox_summary.csv", row.names = FALSE)

adas_colors <- c("0" = "#e74c3c", "1" = "#f39c12", "2" = "#2ecc71")

plot_freq <- ggplot(paradox, aes(x = paste("ADAS", Safety_Package_Level),
                                 y = Ort_Frekans, fill = Safety_Package_Level)) +
  geom_col(width = 0.65) +
  geom_errorbar(aes(ymin = Ort_Frekans - 1.96 * SE_Frekans,
                    ymax = Ort_Frekans + 1.96 * SE_Frekans), width = 0.2) +
  scale_fill_manual(values = adas_colors) +
  scale_y_continuous(labels = scales::number_format(accuracy = 0.001)) +
  labs(title = "Hasar Frekansi (+/-%95 GA)", x = NULL,
       y = "Ort. Tahmin Edilen Frekans") +
  theme_minimal(base_size = 13) + theme(legend.position = "none")

plot_sev <- ggplot(paradox, aes(x = paste("ADAS", Safety_Package_Level),
                                y = Ort_Siddet, fill = Safety_Package_Level)) +
  geom_col(width = 0.65) +
  geom_errorbar(aes(ymin = Ort_Siddet - 1.96 * SE_Siddet,
                    ymax = Ort_Siddet + 1.96 * SE_Siddet), width = 0.2) +
  scale_fill_manual(values = adas_colors) +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "Hasar Siddeti (+/-%95 GA)", x = NULL,
       y = "Ort. Tahmin Edilen Siddet (TL)") +
  theme_minimal(base_size = 13) + theme(legend.position = "none")

plot_prem <- ggplot(paradox, aes(x = paste("ADAS", Safety_Package_Level),
                                 y = Ort_Risk_Primi, fill = Safety_Package_Level)) +
  geom_col(width = 0.65) +
  geom_errorbar(aes(ymin = Ort_Risk_Primi - 1.96 * SE_Risk_Primi,
                    ymax = Ort_Risk_Primi + 1.96 * SE_Risk_Primi), width = 0.2) +
  scale_fill_manual(values = adas_colors) +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "Risk Primi Net Etki (+/-%95 GA)", x = NULL,
       y = "Ort. Risk Primi (TL)") +
  theme_minimal(base_size = 13) + theme(legend.position = "none")

png("outputs/figures/paradox_main.png", width = 1200, height = 450, res = 120)
gridExtra::grid.arrange(plot_freq, plot_sev, plot_prem, ncol = 3)
dev.off()

segment_city <- data %>%
  group_by(City, Safety_Package_Level) %>%
  summarise(Ort_Risk_Primi = mean(Risk_Premium), .groups = "drop")

png("outputs/figures/paradox_city.png", width = 1000, height = 500, res = 120)
p_city <- ggplot(segment_city, aes(x = City, y = Ort_Risk_Primi, fill = Safety_Package_Level)) +
  geom_bar(stat = "identity", position = "dodge") +
  scale_fill_manual(values = adas_colors,
                    labels = paste("ADAS", levels(data$Safety_Package_Level))) +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "Sehir Bazinda ADAS Risk Primi",
       x = "Sehir", y = "Ort. Risk Primi (TL)", fill = "ADAS Seviyesi") +
  theme_minimal(base_size = 13)
print(p_city)
dev.off()

## ---- 9: Enriched Output for Power BI ----

data$Freq_vs_Baseline <- data$Pred_Frequency / baseline_freq
data$Sev_vs_Baseline  <- data$Pred_Severity  / baseline_sev
data$Paradox_Flag <- ifelse(
  data$Freq_vs_Baseline < 1 & data$Sev_vs_Baseline > 1, "Paradox_Active",
  ifelse(data$Freq_vs_Baseline < 1, "Frequency_Wins", "No_Effect")
)

out_cols <- c("Policy_ID", "City", "Safety_Package_Level", "Exposure",
              "Claim_Count", "Claim_Amount", "Pred_Frequency", "Pred_Severity",
              "Risk_Premium", "Freq_vs_Baseline", "Sev_vs_Baseline", "Paradox_Flag")

write.csv(data[, intersect(out_cols, names(data))], "R_Islem_Gormus_Veri.csv", row.names = FALSE)

results_json <- list(
  rmse    = list(freq = rmse_freq, sev = ifelse(exists("rmse_sev"), rmse_sev, NA)),
  paradox = as.data.frame(paradox)
)
writeLines(jsonlite::toJSON(results_json, pretty = TRUE, auto_unbox = TRUE), "outputs/results.json")

cat("\n===== ANALIZ TAMAMLANDI =====\n")
