# Section 7: shooting vs goaltending
#
# Every goal is the result of a shooter and a goalie. This section asks how much
# of the variation in goal-scoring comes from WHO SHOOTS and how much from WHO
# IS IN NET, after allowing for shot quality (distance, angle and type).
#
# Model, fit separately for each league:
#   P(goal) = logistic(shot quality + shooter effect + goalie effect)
# The shooter and goalie effects are "random": each is estimated as a deviation
# from the league average, and shrunk toward zero when a player has few shots.
#
# What this can and cannot tell us:
#   - It CAN say how much shooters differ from each other, and how much goalies
#     differ from each other, within each league. Comparing those two spreads
#     shows which is the bigger source of variation.
#   - It CANNOT split the league-wide gap (PWHL 7.8% vs NHL 9.9%) into shooting
#     and goaltending. Adding a constant to every shooter and subtracting it from
#     every goalie gives identical predictions, so the data can't tell them apart.
#     That split needs an outside benchmark, which is discussed in the write-up.

source("R/00_setup.R")
library(lme4)

shots <- readRDS("data/shots.rds") |>
  filter(!empty_net, x > 0,                       # offensive half, goalie in net
         !is.na(shooter_id), shooter_id != "",
         !is.na(goalie_id), goalie_id != "0",
         !is.na(distance)) |>
  add_shot_features() |>
  mutate(type_group = if_else(league == "NHL" & type_group == "Unknown",
                              factor("Other", levels(type_group)), type_group))

# ---- Fit one model per league -------------------------------------------------

fit_league <- function(df) {
  df <- mutate(df, type_group = fct_drop(type_group))
  glmer(goal ~ distance + I(distance^2) + angle + type_group +
          (1 | shooter_id) + (1 | goalie_id),
        data = df, family = binomial,
        control = glmerControl(optimizer = "bobyqa", autoscale = TRUE))
}

by_league <- split(shots, shots$league)

models <- map(by_league, \(df) {
  message("Fitting shooter/goalie model for ", df$league[1], " (", nrow(df), " shots) ...")
  fit_league(df)
})

# ---- Spread of shooter and goalie effects -----------------------------------
# Random-effect SDs are on the log-odds scale. To make them readable, convert to
# percentage points at that league's average shooting %: a shooter "one standard
# deviation better than average" adds roughly this many points to their shooting %.

spread <- imap_dfr(models, \(m, league) {
  df   <- by_league[[league]]
  p    <- mean(df$goal)
  vc   <- as.data.frame(VarCorr(m))
  sd_of <- \(g) vc$sdcor[vc$grp == g]
  tibble(
    league        = league,
    avg_shoot_pct = p,
    shooter_sd_logit = sd_of("shooter_id"),
    goalie_sd_logit  = sd_of("goalie_id"),
    shooter_sd_pts   = 100 * p * (1 - p) * sd_of("shooter_id"),
    goalie_sd_pts    = 100 * p * (1 - p) * sd_of("goalie_id"),
    shooters = n_distinct(df$shooter_id),
    goalies  = n_distinct(df$goalie_id)
  )
})

spread
write_csv(spread, "output/shooter_vs_goalie_spread.csv")

# ---- Figure: shooters vs goalies ---------------------------------------------

plot_df <- spread |>
  select(league, shooter_sd_pts, goalie_sd_pts) |>
  pivot_longer(-league, names_to = "who", values_to = "sd_pts") |>
  mutate(who = if_else(who == "shooter_sd_pts", "Shooters (finishing)", "Goalies (saves)"),
         who = factor(who, c("Shooters (finishing)", "Goalies (saves)")))

p_sg <- ggplot(plot_df, aes(league, sd_pts, fill = who)) +
  geom_col(position = position_dodge(width = 0.75), width = 0.65) +
  geom_text(aes(label = scales::number(sd_pts, accuracy = 0.1)),
            position = position_dodge(width = 0.75), vjust = -0.4, size = 4) +
  scale_fill_manual(values = c("Shooters (finishing)" = "#E07B39",
                               "Goalies (saves)" = "#4B3F72"), name = NULL) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(
    title    = "Who matters more: the shooter or the goalie?",
    subtitle = "Typical player-to-player difference in shooting %, adjusted for shot quality",
    x = NULL, y = "Typical player-to-player difference (points)",
    caption  = paste0(data_caption, "\nModel: shot distance, angle and type, plus random effects for shooter and goalie.")
  ) +
  theme_project() +
  theme(panel.grid.major.x = element_blank(), plot.caption = element_text(hjust = 0))

save_fig(p_sg, "15_shooters_vs_goalies", width = 8, height = 5.5)
