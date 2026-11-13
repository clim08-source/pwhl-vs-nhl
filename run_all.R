# Runs the whole project in order. Open the project folder in Positron and run:
#   source("run_all.R")
#
# The first step downloads the data and takes a few minutes. After that, you can
# run any single script on its own.

scripts <- c(
  "R/01_load_data.R",
  "R/02_scoring.R",
  "R/03_rates.R",
  "R/04_shot_maps.R",
  "R/05_goaltending.R"
)

for (s in scripts) {
  message("\n==== ", s, " ====")
  source(s, echo = FALSE)
}

message("\nDone. Figures are in figures/, tables in output/.")
