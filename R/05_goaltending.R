# Section 4: goaltending
#
# Raw save % depends on how hard the shots were, so this section also builds a
# simple expected-goals model from shot distance, then measures each goalie's
# goals saved above expected (GSAx):
#
#   xG for a shot = that league's goal rate for shots from that distance
#   GSAx          = expected goals against - actual goals against

source("R/00_setup.R")

shots <- readRDS("data/shots.rds") |>
  filter(!empty_net, !is.na(goalie_id), goalie_id != "0", !is.na(distance))

# ---- League save % ----------------------------------------------------------

league_sv <- shots |>
  group_by(league, season) |>
  summarise(shots = n(), goals = sum(goal), .groups = "drop") |>
  mutate(save_pct = 1 - goals / shots)

league_sv
write_csv(league_sv, "output/league_save_pct.csv")

# ---- Simple expected-goals model by distance ---------------------------------
# Logistic regression on distance (with a squared term for the curve), fit
# separately for each league so each goalie is compared with her/his own league.
#
#   P(goal) = 1 / (1 + exp(-(b0 + b1*distance + b2*distance^2)))

fit_xg <- function(df) glm(goal ~ distance + I(distance^2), data = df, family = binomial)

shots <- shots |>
  group_by(league) |>
  group_modify(\(df, key) {
    model <- fit_xg(df)
    df |> mutate(xg = predict(model, newdata = df, type = "response"))
  }) |>
  ungroup()

# ---- Goalie table -----------------------------------------------------------

goalies <- shots |>
  group_by(league, goalie_id) |>
  summarise(
    goalie    = first(na.omit(goalie)),
    seasons   = n_distinct(season),
    shots     = n(),
    goals     = sum(goal),
    xg        = sum(xg),
    .groups   = "drop"
  ) |>
  mutate(
    save_pct       = 1 - goals / shots,
    expected_sv    = 1 - xg / shots,
    gsax           = xg - goals,
    gsax_per_100   = 100 * gsax / shots
  )

# Same minimum workload in both leagues so the spreads are comparable
min_shots <- 500
qualified <- goalies |> filter(shots >= min_shots)

qualified |> count(league, name = "goalies_with_500_shots")
write_csv(arrange(goalies, league, desc(gsax)), "output/goalies.csv")

# Top 5 per league by GSAx
qualified |>
  group_by(league) |>
  slice_max(gsax, n = 5) |>
  select(league, goalie, shots, save_pct, gsax, gsax_per_100)

# ---- Figure: save % by distance ---------------------------------------------

sv_by_dist <- shots |>
  mutate(dist_bin = cut(distance, c(0, 10, 20, 30, 40, 50, 60, Inf),
                        c("0-10", "10-20", "20-30", "30-40", "40-50", "50-60", "60+"),
                        right = FALSE)) |>
  group_by(league, dist_bin) |>
  summarise(shots = n(), save_pct = 1 - mean(goal), .groups = "drop") |>
  mutate(se = sqrt(save_pct * (1 - save_pct) / shots))

p_sv_dist <- ggplot(sv_by_dist, aes(dist_bin, save_pct, color = league, group = league)) +
  geom_line(linewidth = 1) +
  geom_errorbar(aes(ymin = save_pct - 1.96 * se, ymax = save_pct + 1.96 * se),
                width = 0.15, alpha = 0.6) +
  geom_point(size = 3) +
  scale_color_manual(values = league_colors) +
  scale_y_continuous(labels = scales::label_number(accuracy = 0.001)) +
  labs(
    title    = "Save percentage by shot distance",
    subtitle = "Excludes empty-net goals; 95% confidence intervals",
    x = "Distance from net (feet)", y = "Save %", color = NULL,
    caption  = data_caption
  ) +
  theme_project()

save_fig(p_sv_dist, "08_save_pct_by_distance")

# ---- Figure: spread of goalie quality ---------------------------------------
# GSAx per 100 shots puts goalies with different workloads on one scale.

p_spread <- ggplot(qualified, aes(gsax_per_100, league, color = league)) +
  geom_vline(xintercept = 0, color = "grey60") +
  geom_jitter(height = 0.15, width = 0, size = 2.6, alpha = 0.7) +
  geom_boxplot(aes(group = league), width = 0.45, fill = NA, color = "grey30",
               outlier.shape = NA) +
  scale_color_manual(values = league_colors, guide = "none") +
  labs(
    title    = "How much do goalies differ from each other?",
    subtitle = paste0("Goals saved above expected per 100 shots, goalies with ",
                      min_shots, "+ shots faced (2023-24 to 2025-26)"),
    x = "GSAx per 100 shots (right = better)", y = NULL,
    caption  = paste(data_caption, "Expected goals from a distance-only model.")
  ) +
  theme_project() +
  theme(panel.grid.major.y = element_blank())

save_fig(p_spread, "09_goalie_spread", height = 4.5)

# ---- Figure: PWHL goalie leaderboard ----------------------------------------

pwhl_board <- qualified |>
  filter(league == "PWHL") |>
  mutate(goalie = fct_reorder(goalie, gsax))

p_board <- ggplot(pwhl_board, aes(gsax, goalie)) +
  geom_vline(xintercept = 0, color = "grey60") +
  geom_col(aes(fill = gsax > 0), width = 0.7) +
  geom_text(aes(label = scales::number(gsax, accuracy = 0.1),
                hjust = if_else(gsax > 0, -0.2, 1.2)),
            size = 3.3, color = "grey25") +
  scale_fill_manual(values = c(`TRUE` = "#eb6834", `FALSE` = "grey70"), guide = "none") +
  scale_x_continuous(expand = expansion(mult = 0.15)) +
  labs(
    title    = "PWHL goalies: goals saved above expected",
    subtitle = paste0("Goalies with ", min_shots, "+ shots faced, 2023-24 to 2025-26"),
    x = "Goals saved above expected", y = NULL,
    caption  = paste(data_caption, "Expected goals from a distance-only model.")
  ) +
  theme_project() +
  theme(panel.grid.major.y = element_blank())

save_fig(p_board, "10_pwhl_goalie_gsax", height = 6)
