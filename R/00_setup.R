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

league_colors <- c(NHL = "#FF4C00", PWHL = "#200256")

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

# Adds shot angle and a shot-type group that means the same thing in both leagues.
#   angle: degrees off the line straight out from the net (0 = dead centre,
#          90 = level with the goal line, over 90 = from behind the net)
#   type_group: the two leagues label shot types differently. Wrist and snap are
#          combined because scorers separate them inconsistently; tips and
#          deflections are combined because the PWHL only records "tip".
#          About 30% of PWHL shots have no recorded type ("default"); these are
#          kept as "Unknown".
add_shot_features <- function(shots) {
  shots |>
    mutate(
      angle      = atan2(abs(y), 89 - x) * 180 / pi,
      type_group = case_when(
        shot_type %in% c("wrist", "snap")                 ~ "Wrist/snap",
        shot_type == "slap"                               ~ "Slap",
        shot_type == "backhand"                           ~ "Backhand",
        shot_type %in% c("tip", "tip-in", "deflected")    ~ "Tip/deflection",
        shot_type %in% c("bat", "between-legs", "cradle",
                         "poke", "wrap-around")           ~ "Other",
        TRUE                                              ~ "Unknown"
      ),
      type_group = factor(type_group, c("Wrist/snap", "Slap", "Backhand",
                                        "Tip/deflection", "Other", "Unknown"))
    )
}
