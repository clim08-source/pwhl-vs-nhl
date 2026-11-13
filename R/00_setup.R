# Shared settings for every script. Each script runs source("R/00_setup.R") first.

suppressPackageStartupMessages({
  library(tidyverse)
  library(fastRhockey)
})

# fastRhockey labels seasons by the year they end: 2024 = 2023-24, 2026 = 2025-26.
# The PWHL's first season was 2023-24, so 2024 is the earliest season for both leagues.
seasons <- 2024:2026

# The NHL play-by-play files are large; R's default 60-second download timeout
# is too short and makes load_nhl_pbp() silently return an empty table.
options(timeout = max(1800, getOption("timeout")))

dir.create("data", showWarnings = FALSE)
dir.create("figures", showWarnings = FALSE)
dir.create("output", showWarnings = FALSE)

league_colors <- c(NHL = "#2a78d6", PWHL = "#eb6834")

theme_project <- function(base_size = 13) {
  theme_minimal(base_size = base_size) +
    theme(
      legend.position  = "top",
      panel.grid.minor = element_blank(),
      plot.title       = element_text(face = "bold"),
      plot.caption     = element_text(color = "grey40", size = rel(0.75)),
      plot.title.position   = "plot",
      plot.caption.position = "plot",
      strip.text       = element_text(face = "bold")
    )
}

save_fig <- function(plot, name, width = 9, height = 5.5) {
  ggsave(file.path("figures", paste0(name, ".png")), plot,
         width = width, height = height, dpi = 300, bg = "white")
}

data_caption <- "Data: PWHL (HockeyTech) and NHL APIs via fastRhockey. Regular season, 2023-24 to 2025-26."
