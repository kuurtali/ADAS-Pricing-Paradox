library(shiny)
library(bslib)
library(ggplot2)
library(dplyr)
library(scales)

# ==========================================
# 1. GLM COEFFICIENTS (Hardcoded from VOL 1)
# ==========================================
# Frequency Model (Poisson, log link)
freq_intercept <- -2.6133187
freq_coefs <- list(
  Safety_Package_Level1 = -0.0882522,
  Safety_Package_Level2 = -0.2896135,
  CityAntalya           = -0.0840771,
  CityBursa             = 0.0125243,
  CityDiger             = -0.1362371,
  CityIstanbul          = -0.0057503,
  CityIzmir             = 0.0573768,
  CityAnkara            = 0, # Baseline
  Driver_Age            = -0.0003040,
  Vehicle_Age           = 0.0101679,
  NCD_Level             = -0.0491666,
  Traffic_Density       = 0.1504389,
  Vehicle_SegmentSedan  = 0.0159799,
  Vehicle_SegmentSUV    = -0.0028765,
  Vehicle_SegmentHatchback = 0 # Baseline
)

# Severity Model (Gamma, log link)
sev_intercept <- 10.5078010
sev_coefs <- list(
  Safety_Package_Level1 = 0.1138915,
  Safety_Package_Level2 = 0.2558499,
  Vehicle_Age           = 0.0008097,
  Driver_Age            = 0.0004951,
  Vehicle_BrandFiat     = -0.9376817,
  Vehicle_BrandFord     = -0.7102261,
  Vehicle_BrandHonda    = -0.5953654,
  Vehicle_BrandMercedes = 0.1194875,
  Vehicle_BrandRenault  = -0.8016100,
  Vehicle_BrandToyota   = -0.6862997,
  Vehicle_BrandBMW      = 0, # Baseline
  Vehicle_SegmentSedan  = 0.0009174,
  Vehicle_SegmentSUV    = 0.0158277,
  Vehicle_SegmentHatchback = 0 # Baseline
)

# ==========================================
# 2. CALCULATION FUNCTION
# ==========================================
calculate_premium <- function(city, driver_age, vehicle_age, ncd_level, traffic, segment, brand) {
  results <- data.frame(ADAS_Level = c("0", "1", "2"), Frequency = 0, Severity = 0, Premium = 0)
  
  for (i in 1:nrow(results)) {
    adas <- results$ADAS_Level[i]
    
    # Frekans Hesaplama (Linear Predictor)
    lp_freq <- freq_intercept +
      (driver_age * freq_coefs$Driver_Age) +
      (vehicle_age * freq_coefs$Vehicle_Age) +
      (ncd_level * freq_coefs$NCD_Level) +
      (traffic * freq_coefs$Traffic_Density)
    
    if (adas == "1") lp_freq <- lp_freq + freq_coefs$Safety_Package_Level1
    if (adas == "2") lp_freq <- lp_freq + freq_coefs$Safety_Package_Level2
    
    city_key <- paste0("City", city)
    if (city_key %in% names(freq_coefs)) lp_freq <- lp_freq + freq_coefs[[city_key]]
    
    seg_key <- paste0("Vehicle_Segment", segment)
    if (seg_key %in% names(freq_coefs)) lp_freq <- lp_freq + freq_coefs[[seg_key]]
    
    freq_val <- exp(lp_freq)
    
    # Siddet Hesaplama (Linear Predictor)
    lp_sev <- sev_intercept +
      (vehicle_age * sev_coefs$Vehicle_Age) +
      (driver_age * sev_coefs$Driver_Age)
    
    if (adas == "1") lp_sev <- lp_sev + sev_coefs$Safety_Package_Level1
    if (adas == "2") lp_sev <- lp_sev + sev_coefs$Safety_Package_Level2
    
    brand_key <- paste0("Vehicle_Brand", brand)
    if (brand_key %in% names(sev_coefs)) lp_sev <- lp_sev + sev_coefs[[brand_key]]
    
    if (seg_key %in% names(sev_coefs)) lp_sev <- lp_sev + sev_coefs[[seg_key]]
    
    sev_val <- exp(lp_sev)
    
    # Kayit
    results$Frequency[i] <- freq_val
    results$Severity[i]  <- sev_val
    results$Premium[i]   <- freq_val * sev_val
  }
  
  return(results)
}

# ==========================================
# 3. UI (CYBERPUNK THEME)
# ==========================================
ui <- page_sidebar(
  theme = bs_theme(version = 5, bootswatch = "cyborg", primary = "#00ffcc"),
  title = "ADAS Pricing Paradox (Vol 1)",
  
  sidebar = sidebar(
    title = "Risk Profilini Belirle",
    bg = "#111111",
    
    selectInput("city", "Sehir:", 
                choices = c("Istanbul", "Ankara", "Izmir", "Bursa", "Antalya", "Diger"), 
                selected = "Istanbul"),
    
    sliderInput("driver_age", "Surucu Yasi:", min = 18, max = 80, value = 35),
    sliderInput("vehicle_age", "Arac Yasi:", min = 0, max = 20, value = 5),
    sliderInput("ncd_level", "Hasarsizlik Kadamesi (NCD):", min = 1, max = 7, value = 4),
    sliderInput("traffic", "Trafik Yogunlugu (1-10):", min = 1, max = 10, value = 7),
    
    selectInput("segment", "Arac Segmenti:", 
                choices = c("Hatchback", "Sedan", "SUV"), 
                selected = "Sedan"),
    
    selectInput("brand", "Arac Markasi:", 
                choices = c("BMW", "Mercedes", "Audi", "Fiat", "Ford", "Honda", "Renault", "Toyota"), 
                selected = "Fiat"),
    
    radioButtons("adas_selection", "Kiyaslanacak ADAS Seviyesi:",
                 choices = list("ADAS 1 (Temel)" = "1", "ADAS 2 (Ileri)" = "2"),
                 selected = "2")
  ),
  
  layout_columns(
    col_widths = c(12, 12),
    
    # INFO BOXES
    card(
      card_header("Secili Profil Icin Sonuclar (ADAS 0 vs Secilen ADAS)", class = "bg-primary text-dark"),
      layout_columns(
        col_widths = c(4, 4, 4),
        uiOutput("info_freq"),
        uiOutput("info_sev"),
        uiOutput("info_prem")
      )
    ),
    
    # WATERFALL CHART
    card(
      card_header("Fiyatlama Paradoksu: Saf Risk Primi Nasil Degisiyor?"),
      plotOutput("waterfall_plot", height = "400px")
    )
  )
)

# ==========================================
# 4. SERVER
# ==========================================
server <- function(input, output, session) {
  
  # Reactive Data
  calc_data <- reactive({
    calculate_premium(
      city = input$city,
      driver_age = input$driver_age,
      vehicle_age = input$vehicle_age,
      ncd_level = input$ncd_level,
      traffic = input$traffic,
      segment = input$segment,
      brand = input$brand
    )
  })
  
  # Info Boxes
  output$info_freq <- renderUI({
    res <- calc_data()
    base_val <- res$Frequency[1]
    adas_val <- res$Frequency[res$ADAS_Level == input$adas_selection]
    pct_change <- ((adas_val / base_val) - 1) * 100
    
    color <- if(pct_change < 0) "#00ffcc" else "#ff3333"
    arrow <- if(pct_change < 0) "⬇" else "⬆"
    
    HTML(sprintf(
      "<div style='text-align:center; padding:15px; border-radius:10px; background:#222;'>
         <h4 style='color:#ccc;'>Kaza Frekansi</h4>
         <h2>%.4f</h2>
         <p style='color:%s; font-size:1.2em;'>%s %%%.1f Değişim</p>
       </div>", adas_val, color, arrow, abs(pct_change)
    ))
  })
  
  output$info_sev <- renderUI({
    res <- calc_data()
    base_val <- res$Severity[1]
    adas_val <- res$Severity[res$ADAS_Level == input$adas_selection]
    pct_change <- ((adas_val / base_val) - 1) * 100
    
    color <- if(pct_change < 0) "#00ffcc" else "#ff3333"
    arrow <- if(pct_change < 0) "⬇" else "⬆"
    
    HTML(sprintf(
      "<div style='text-align:center; padding:15px; border-radius:10px; background:#222;'>
         <h4 style='color:#ccc;'>Ortalama Hasar Siddeti</h4>
         <h2>%s TL</h2>
         <p style='color:%s; font-size:1.2em;'>%s %%%.1f Değişim</p>
       </div>", 
      prettyNum(round(adas_val), big.mark=".", decimal.mark=","), 
      color, arrow, abs(pct_change)
    ))
  })
  
  output$info_prem <- renderUI({
    res <- calc_data()
    base_val <- res$Premium[1]
    adas_val <- res$Premium[res$ADAS_Level == input$adas_selection]
    pct_change <- ((adas_val / base_val) - 1) * 100
    
    color <- if(pct_change < 0) "#00ffcc" else "#ff3333"
    arrow <- if(pct_change < 0) "⬇" else "⬆"
    
    HTML(sprintf(
      "<div style='text-align:center; padding:15px; border-radius:10px; background:#222; border: 1px solid %s;'>
         <h4 style='color:#ccc;'>Net Saf Risk Primi</h4>
         <h2 style='color:%s;'>%s TL</h2>
         <p style='color:%s; font-size:1.2em;'>%s %%%.1f Değişim</p>
       </div>", 
      color, color,
      prettyNum(round(adas_val), big.mark=".", decimal.mark=","), 
      color, arrow, abs(pct_change)
    ))
  })
  
  # Waterfall Plot
  output$waterfall_plot <- renderPlot({
    res <- calc_data()
    base <- res[1, ]
    adas <- res[res$ADAS_Level == input$adas_selection, ]
    
    base_premium <- base$Premium
    final_premium <- adas$Premium
    
    freq_effect <- (adas$Frequency - base$Frequency) * base$Severity
    sev_effect  <- adas$Frequency * (adas$Severity - base$Severity)
    
    wf_data <- data.frame(
      Category = factor(c("1. ADAS Yok (Baz Prim)", "2. Frekans Etkisi (Kaza Azalisi)", "3. Siddet Etkisi (Pahali Sensorler)", paste0("4. ADAS ", input$adas_selection, " Net Prim")), 
                        levels = c("1. ADAS Yok (Baz Prim)", "2. Frekans Etkisi (Kaza Azalisi)", "3. Siddet Etkisi (Pahali Sensorler)", paste0("4. ADAS ", input$adas_selection, " Net Prim"))),
      Value = c(base_premium, freq_effect, sev_effect, final_premium)
    )
    
    wf_data$End <- cumsum(wf_data$Value)
    wf_data$Start <- c(0, wf_data$End[1:2], 0)
    
    wf_data$End[4] <- final_premium
    wf_data$Start[4] <- 0
    
    wf_data$Type <- c("Net", "Decrease", "Increase", "Net")
    if (freq_effect > 0) wf_data$Type[2] <- "Increase"
    if (sev_effect < 0)  wf_data$Type[3] <- "Decrease"
    
    ggplot(wf_data, aes(x = Category, fill = Type)) +
      geom_rect(aes(x = Category, xmin = as.numeric(Category) - 0.4, xmax = as.numeric(Category) + 0.4, 
                    ymin = Start, ymax = End)) +
      scale_fill_manual(values = c("Decrease" = "#00ffcc", "Increase" = "#ff3333", "Net" = "#cccccc")) +
      geom_text(aes(y = pmax(Start, End) + max(final_premium, base_premium)*0.05, 
                    label = paste0(ifelse(Value>0 & Type!="Net", "+", ""), 
                                   prettyNum(round(Value), big.mark=".", decimal.mark=","), " TL")), 
                color = "white", size = 5, fontface = "bold") +
      theme_minimal() +
      labs(x = NULL, y = "Saf Risk Primi (TL)") +
      theme(
        plot.background = element_rect(fill = "#111111", color = NA),
        panel.background = element_rect(fill = "#111111", color = NA),
        panel.grid.major = element_line(color = "#333333"),
        panel.grid.minor = element_blank(),
        text = element_text(color = "#eeeeee"),
        axis.text = element_text(color = "#eeeeee", size = 12),
        axis.title = element_text(color = "#eeeeee", size = 14),
        legend.position = "none"
      )
  })
}

shinyApp(ui, server)
