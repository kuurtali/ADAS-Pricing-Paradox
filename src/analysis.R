###############################################################################
# ADAS Pricing Paradox — GLM Analysis & Paradox Investigation
# Pipeline: ham_data.csv → SQL_Islem_Gormus_Veri.csv → [THIS SCRIPT] → outputs
###############################################################################

rm(list = ls())

# --- Paketler ---
required_pkgs <- c("dplyr", "statmod", "MASS", "ggplot2", "jsonlite")
for (pkg in required_pkgs) {
  if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
    install.packages(pkg, repos = "https://cran.r-project.org")
    library(pkg, character.only = TRUE)
  }
}

# --- Dizin Ayarlari ---
dir.create("outputs/figures", recursive = TRUE, showWarnings = FALSE)

# --- Veri Yukle ---
file_path <- "SQL_Islem_Gormus_Veri.csv"
first_line <- readLines(file_path, n = 1)
if (grepl(";", first_line)) {
  data <- read.csv2(file_path)
  cat("Veri noktalı virgül ayracıyla yüklendi.\n")
} else {
  data <- read.csv(file_path)
  cat("Veri virgül ayracıyla yüklendi.\n")
}

cat(sprintf("Toplam gozlem: %d\n", nrow(data)))
cat(sprintf("Degiskenler: %s\n", paste(names(data), collapse = ", ")))

# --- Faktor Donusumleri ---
data$Safety_Package_Level <- as.factor(data$Safety_Package_Level)
data$City <- as.factor(data$City)
if ("Driver_Segment" %in% names(data)) data$Driver_Segment <- as.factor(data$Driver_Segment)
if ("Vehicle_Segment_Age" %in% names(data)) data$Vehicle_Segment_Age <- as.factor(data$Vehicle_Segment_Age)

# Orijinal ham veriden ek degiskenleri al (varsa)
ham_path <- "ham_data.csv"
if (file.exists(ham_path)) {
  ham <- read.csv(ham_path)
  extra_cols <- c("Driver_Age", "Vehicle_Age", "Traffic_Density", 
                  "NCD_Level", "Vehicle_Brand", "Vehicle_Segment")
  for (col in extra_cols) {
    if (col %in% names(ham) && !(col %in% names(data))) {
      data[[col]] <- ham[[col]][1:nrow(data)]
      cat(sprintf("  + %s ham veriden eklendi.\n", col))
    }
  }
  if ("Vehicle_Brand" %in% names(data)) data$Vehicle_Brand <- as.factor(data$Vehicle_Brand)
  if ("Vehicle_Segment" %in% names(data)) data$Vehicle_Segment <- as.factor(data$Vehicle_Segment)
}

###############################################################################
# BOLUM 1: FREKANS MODELI (Poisson GLM)
###############################################################################
cat("\n===== FREKANS MODELI (Poisson GLM) =====\n")

freq_vars <- "Safety_Package_Level + City"
if ("Driver_Age" %in% names(data)) freq_vars <- paste(freq_vars, "+ Driver_Age")
if ("Driver_Segment" %in% names(data) && !("Driver_Age" %in% names(data))) {
  freq_vars <- paste(freq_vars, "+ Driver_Segment")
}
if ("Vehicle_Age" %in% names(data)) freq_vars <- paste(freq_vars, "+ Vehicle_Age")
if ("NCD_Level" %in% names(data)) freq_vars <- paste(freq_vars, "+ NCD_Level")
if ("Traffic_Density" %in% names(data)) freq_vars <- paste(freq_vars, "+ Traffic_Density")
if ("Vehicle_Segment" %in% names(data)) freq_vars <- paste(freq_vars, "+ Vehicle_Segment")

freq_formula <- as.formula(paste("Claim_Count ~", freq_vars, "+ offset(log(Exposure))"))
cat("Formula:", deparse(freq_formula), "\n\n")

model_freq <- glm(freq_formula, data = data, family = poisson(link = "log"))

# Summary kaydet
freq_summary <- capture.output(summary(model_freq))
writeLines(freq_summary, "outputs/freq_model_summary.txt")
cat("Frekans AIC:", AIC(model_freq), "\n")
cat("Frekans BIC:", BIC(model_freq), "\n")

# Overdispersion kontrolu
pearson_chi2 <- sum(residuals(model_freq, type = "pearson")^2)
disp_ratio <- pearson_chi2 / model_freq$df.residual
cat(sprintf("Overdispersion orani: %.3f (>1.5 ise Neg.Binom. dusun)\n", disp_ratio))

# Negative Binomial alternatifi
if (disp_ratio > 1.5) {
  cat("\n>> Overdispersion tespit edildi. Negative Binomial deneniyor...\n")
  model_freq_nb <- MASS::glm.nb(
    as.formula(paste("Claim_Count ~", freq_vars, "+ offset(log(Exposure))")),
    data = data
  )
  nb_summary <- capture.output(summary(model_freq_nb))
  writeLines(nb_summary, "outputs/freq_model_nb_summary.txt")
  cat("NB AIC:", AIC(model_freq_nb), "vs Poisson AIC:", AIC(model_freq), "\n")
  if (AIC(model_freq_nb) < AIC(model_freq)) {
    cat(">> Negative Binomial daha iyi. Bu model kullanilacak.\n")
    model_freq <- model_freq_nb
  }
}

###############################################################################
# BOLUM 2: SIDDET MODELI (Gamma GLM)
###############################################################################
cat("\n===== SIDDET MODELI (Gamma GLM) =====\n")

data_sev <- subset(data, Claim_Count > 0 & Claim_Amount > 0)
cat(sprintf("Hasarli gozlem sayisi: %d\n", nrow(data_sev)))

sev_vars <- "Safety_Package_Level"
if ("Vehicle_Age" %in% names(data)) sev_vars <- paste(sev_vars, "+ Vehicle_Age")
if ("Vehicle_Segment_Age" %in% names(data) && !("Vehicle_Age" %in% names(data))) {
  sev_vars <- paste(sev_vars, "+ Vehicle_Segment_Age")
}
if ("Driver_Age" %in% names(data)) sev_vars <- paste(sev_vars, "+ Driver_Age")
if ("Vehicle_Brand" %in% names(data)) sev_vars <- paste(sev_vars, "+ Vehicle_Brand")
if ("Vehicle_Segment" %in% names(data)) sev_vars <- paste(sev_vars, "+ Vehicle_Segment")

sev_formula <- as.formula(paste("Claim_Amount ~", sev_vars))
cat("Formula:", deparse(sev_formula), "\n\n")

model_sev <- glm(sev_formula, data = data_sev, family = Gamma(link = "log"))

sev_summary <- capture.output(summary(model_sev))
writeLines(sev_summary, "outputs/sev_model_summary.txt")
cat("Siddet AIC:", AIC(model_sev), "\n")

###############################################################################
# BOLUM 3: DIAGNOSTIK GRAFIKLER
###############################################################################
cat("\n===== DIAGNOSTIK GRAFIKLER =====\n")

# Frekans modeli diagnostik
png("outputs/figures/freq_residuals.png", width = 900, height = 400)
par(mfrow = c(1, 2), mar = c(4, 4, 3, 1))
plot(fitted(model_freq), residuals(model_freq, type = "pearson"),
     xlab = "Fitted Values", ylab = "Pearson Residuals",
     main = "Frequency Model: Residuals vs Fitted", pch = 20, col = rgb(0, 0, 0, 0.15))
abline(h = 0, col = "red", lwd = 2)
qqnorm(residuals(model_freq, type = "pearson"), main = "Frequency Model: QQ-Plot",
       pch = 20, col = rgb(0, 0, 0, 0.15))
qqline(residuals(model_freq, type = "pearson"), col = "red", lwd = 2)
dev.off()
cat("  freq_residuals.png kaydedildi.\n")

# Siddet modeli diagnostik
png("outputs/figures/sev_residuals.png", width = 900, height = 400)
par(mfrow = c(1, 2), mar = c(4, 4, 3, 1))
plot(fitted(model_sev), residuals(model_sev, type = "pearson"),
     xlab = "Fitted Values", ylab = "Pearson Residuals",
     main = "Severity Model: Residuals vs Fitted", pch = 20, col = rgb(0, 0, 0, 0.15))
abline(h = 0, col = "red", lwd = 2)
qqnorm(residuals(model_sev, type = "pearson"), main = "Severity Model: QQ-Plot",
       pch = 20, col = rgb(0, 0, 0, 0.15))
qqline(residuals(model_sev, type = "pearson"), col = "red", lwd = 2)
dev.off()
cat("  sev_residuals.png kaydedildi.\n")

###############################################################################
# BOLUM 4: TAHMIN + RISK PRIMI
###############################################################################
cat("\n===== TAHMIN & RISK PRIMI =====\n")

data$Pred_Frequency <- predict(model_freq, newdata = data, type = "response")
data$Pred_Severity  <- predict(model_sev, newdata = data, type = "response")
data$Risk_Premium   <- data$Pred_Frequency * data$Pred_Severity

cat(sprintf("Ortalama Pred. Frekans: %.4f\n", mean(data$Pred_Frequency)))
cat(sprintf("Ortalama Pred. Siddet:  %.2f TL\n", mean(data$Pred_Severity)))
cat(sprintf("Ortalama Risk Primi:    %.2f TL\n", mean(data$Risk_Premium)))

###############################################################################
# BOLUM 5: PARADOKS ANALIZI
###############################################################################
cat("\n===== ADAS FIYATLAMA PARADOKSU ANALIZI =====\n")

# ADAS seviyesine gore frekans, siddet, prim
paradox <- data %>%
  group_by(Safety_Package_Level) %>%
  summarise(
    Police_Sayisi   = n(),
    Ort_Frekans     = mean(Pred_Frequency),
    Ort_Siddet      = mean(Pred_Severity),
    Ort_Risk_Primi  = mean(Risk_Premium),
    Gercek_Hasar_Orani = mean(Claim_Count > 0),
    Gercek_Ort_Tutar = mean(Claim_Amount[Claim_Amount > 0]),
    .groups = "drop"
  )

# Baseline (ADAS 0) oranlarini hesapla
baseline_freq <- paradox$Ort_Frekans[paradox$Safety_Package_Level == "0"]
baseline_sev  <- paradox$Ort_Siddet[paradox$Safety_Package_Level == "0"]
baseline_prem <- paradox$Ort_Risk_Primi[paradox$Safety_Package_Level == "0"]

paradox$Freq_vs_Baseline <- paradox$Ort_Frekans / baseline_freq
paradox$Sev_vs_Baseline  <- paradox$Ort_Siddet / baseline_sev
paradox$Prim_vs_Baseline <- paradox$Ort_Risk_Primi / baseline_prem

cat("\n--- PARADOKS OZET TABLOSU ---\n")
print(as.data.frame(paradox))

# Paradoks var mi?
adas2_freq_change <- (paradox$Freq_vs_Baseline[paradox$Safety_Package_Level == "2"] - 1) * 100
adas2_sev_change  <- (paradox$Sev_vs_Baseline[paradox$Safety_Package_Level == "2"] - 1) * 100
adas2_prem_change <- (paradox$Prim_vs_Baseline[paradox$Safety_Package_Level == "2"] - 1) * 100

cat(sprintf("\n>> ADAS 2 vs ADAS 0:\n"))
cat(sprintf("   Frekans degisimi:  %+.1f%%\n", adas2_freq_change))
cat(sprintf("   Siddet degisimi:   %+.1f%%\n", adas2_sev_change))
cat(sprintf("   Risk Primi degisimi: %+.1f%%\n", adas2_prem_change))

if (adas2_freq_change < 0 && adas2_sev_change > 0) {
  cat("\n>> PARADOKS DOGRULANDI: Frekans dusuyor ama siddet artiyor!\n")
  if (adas2_prem_change > 0) {
    cat(">> Siddet etkisi baskin — ADAS'a ragmen prim ARTIYOR.\n")
  } else {
    cat(">> Frekans etkisi baskin — ADAS ile prim DUSUYOR (ama beklentiden az).\n")
  }
} else {
  cat("\n>> Bu veride klasik paradoks deseni gorulmuyor.\n")
}

# Paradox summary CSV
write.csv(as.data.frame(paradox), "outputs/paradox_summary.csv", row.names = FALSE)
cat("\n  paradox_summary.csv kaydedildi.\n")

###############################################################################
# BOLUM 6: SEGMENT KIRILIMI
###############################################################################
cat("\n===== SEGMENT ANALIZI =====\n")

# Sehir x ADAS kirilimi
segment_city <- data %>%
  group_by(City, Safety_Package_Level) %>%
  summarise(
    Ort_Frekans    = mean(Pred_Frequency),
    Ort_Siddet     = mean(Pred_Severity),
    Ort_Risk_Primi = mean(Risk_Premium),
    .groups = "drop"
  )

# Arac segmenti (varsa)
if ("Vehicle_Segment" %in% names(data)) {
  segment_vehicle <- data %>%
    group_by(Vehicle_Segment, Safety_Package_Level) %>%
    summarise(
      Ort_Frekans    = mean(Pred_Frequency),
      Ort_Siddet     = mean(Pred_Severity),
      Ort_Risk_Primi = mean(Risk_Premium),
      .groups = "drop"
    )
  write.csv(segment_vehicle, "outputs/segment_vehicle.csv", row.names = FALSE)
}

# Yas grubu (varsa)
if ("Driver_Age" %in% names(data)) {
  data$Age_Group <- cut(data$Driver_Age,
    breaks = c(18, 25, 40, 60, 100),
    labels = c("18-25", "26-40", "41-60", "60+"),
    right = FALSE
  )
  segment_age <- data %>%
    group_by(Age_Group, Safety_Package_Level) %>%
    summarise(
      Ort_Frekans    = mean(Pred_Frequency),
      Ort_Siddet     = mean(Pred_Severity),
      Ort_Risk_Primi = mean(Risk_Premium),
      .groups = "drop"
    )
  write.csv(segment_age, "outputs/segment_age.csv", row.names = FALSE)
}

write.csv(segment_city, "outputs/segment_city.csv", row.names = FALSE)
cat("  Segment CSV'leri kaydedildi.\n")

###############################################################################
# BOLUM 7: PARADOKS GRAFIKLERI
###############################################################################
cat("\n===== PARADOKS GRAFIKLERI =====\n")

# Ana paradoks grafigi: 3 panel yan yana
png("outputs/figures/paradox_main.png", width = 1200, height = 450, res = 120)
par(mfrow = c(1, 3), mar = c(5, 5, 4, 2), family = "sans")

# Renk paleti
cols <- c("#2ecc71", "#f39c12", "#e74c3c")

# Panel 1 — Frekans
barplot(paradox$Ort_Frekans, names.arg = paste("ADAS", paradox$Safety_Package_Level),
        col = cols, border = NA, main = "Hasar Frekansı",
        ylab = "Ort. Tahmin Edilen Frekans", ylim = c(0, max(paradox$Ort_Frekans) * 1.3))
text(x = seq(0.7, by = 1.2, length.out = 3), y = paradox$Ort_Frekans,
     labels = sprintf("%.4f", paradox$Ort_Frekans), pos = 3, cex = 0.9, font = 2)

# Panel 2 — Siddet
barplot(paradox$Ort_Siddet, names.arg = paste("ADAS", paradox$Safety_Package_Level),
        col = cols, border = NA, main = "Hasar Şiddeti",
        ylab = "Ort. Tahmin Edilen Şiddet (TL)", ylim = c(0, max(paradox$Ort_Siddet) * 1.3))
text(x = seq(0.7, by = 1.2, length.out = 3), y = paradox$Ort_Siddet,
     labels = sprintf("%.0f TL", paradox$Ort_Siddet), pos = 3, cex = 0.9, font = 2)

# Panel 3 — Risk Primi
barplot(paradox$Ort_Risk_Primi, names.arg = paste("ADAS", paradox$Safety_Package_Level),
        col = cols, border = NA, main = "Risk Primi (Net Etki)",
        ylab = "Ort. Risk Primi (TL)", ylim = c(0, max(paradox$Ort_Risk_Primi) * 1.3))
text(x = seq(0.7, by = 1.2, length.out = 3), y = paradox$Ort_Risk_Primi,
     labels = sprintf("%.0f TL", paradox$Ort_Risk_Primi), pos = 3, cex = 0.9, font = 2)
dev.off()
cat("  paradox_main.png kaydedildi.\n")

# Sehir kirilim grafigi
png("outputs/figures/paradox_city.png", width = 1000, height = 500, res = 120)
city_plot <- ggplot(segment_city, aes(x = City, y = Ort_Risk_Primi, fill = Safety_Package_Level)) +
  geom_bar(stat = "identity", position = "dodge") +
  scale_fill_manual(values = cols, labels = paste("ADAS", levels(data$Safety_Package_Level))) +
  labs(title = "Şehir Bazında ADAS Risk Primi Karşılaştırması",
       x = "Şehir", y = "Ortalama Risk Primi (TL)", fill = "ADAS Seviyesi") +
  theme_minimal(base_size = 13) +
  theme(plot.title = element_text(face = "bold", hjust = 0.5))
print(city_plot)
dev.off()
cat("  paradox_city.png kaydedildi.\n")

###############################################################################
# BOLUM 8: ZENGINLESTIRILMIS CIKTI
###############################################################################
cat("\n===== CIKTI DOSYALARI =====\n")

# Her policeye paradox flag ekle
baseline_freq_val <- baseline_freq
baseline_sev_val  <- baseline_sev

data$Freq_vs_Baseline <- data$Pred_Frequency / baseline_freq_val
data$Sev_vs_Baseline  <- data$Pred_Severity / baseline_sev_val
data$Paradox_Flag <- ifelse(
  data$Freq_vs_Baseline < 1 & data$Sev_vs_Baseline > 1, "Paradox_Active",
  ifelse(data$Freq_vs_Baseline < 1, "Frequency_Wins", "No_Effect")
)

# Cikti kolonlari
out_cols <- c("Policy_ID", "City", "Safety_Package_Level",
              "Exposure", "Claim_Count", "Claim_Amount",
              "Pred_Frequency", "Pred_Severity", "Risk_Premium",
              "Freq_vs_Baseline", "Sev_vs_Baseline", "Paradox_Flag")
if ("Driver_Segment" %in% names(data)) out_cols <- c(out_cols[1:3], "Driver_Segment", out_cols[4:length(out_cols)])
if ("Vehicle_Segment_Age" %in% names(data)) out_cols <- c(out_cols[1:4], "Vehicle_Segment_Age", out_cols[5:length(out_cols)])

available_cols <- intersect(out_cols, names(data))
write.csv(data[, available_cols], "R_Islem_Gormus_Veri.csv", row.names = FALSE)
cat(sprintf("  R_Islem_Gormus_Veri.csv kaydedildi (%d satir, %d kolon).\n",
            nrow(data), length(available_cols)))

# JSON export (dashboard icin)
results_json <- list(
  meta = list(
    total_policies = nrow(data),
    claim_ratio = mean(data$Claim_Count > 0),
    avg_premium = mean(data$Risk_Premium)
  ),
  paradox = as.data.frame(paradox),
  segment_city = as.data.frame(segment_city),
  freq_model_aic = AIC(model_freq),
  sev_model_aic = AIC(model_sev),
  overdispersion = disp_ratio
)
if (exists("segment_vehicle")) results_json$segment_vehicle <- as.data.frame(segment_vehicle)
if (exists("segment_age")) results_json$segment_age <- as.data.frame(segment_age)

writeLines(jsonlite::toJSON(results_json, pretty = TRUE, auto_unbox = TRUE),
           "outputs/results.json")
cat("  results.json kaydedildi.\n")

cat("\n===== ANALIZ TAMAMLANDI =====\n")
