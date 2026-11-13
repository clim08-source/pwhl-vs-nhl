# Section 2: league-wide rates, on a per-team, per-60-minute basis
#
# Only regulation periods are used for rates (every game has exactly 60 regulation
# minutes), which avoids having to measure overtime length.
# Shots = shots on goal including goals. The PWHL doesn't publish missed shots,
# so shots on goal is the fairest shared measure.

source("R/00_setup.R")
games     <- readRDS("data/games.rds")
shots     <- readRDS("data/shots.rds")
penalties <- readRDS("data/penalties.rds")

games_per_season <- games |> count(league, season, name = "games")

reg_shots <- shots |> filter(regulation)

# Per-team per-60: each game has two teams playing 60 regulation minutes
team_hours <- games_per_season |> mutate(team_hours = games * 2)

rates_season <- reg_shots |>
  group_by(league, season) |>
  summarise(
    shots        = n(),
    goals        = sum(goal),
    en_goals     = sum(empty_net),
    pp_goals     = sum(power_play),
    .groups = "drop"
  ) |>
  left_join(team_hours, by = c("league", "season")) |>
  left_join(
    penalties |> filter(minor) |> count(league, season, name = "minors"),
    by = c("league", "season")
  ) |>
  mutate(
    shots_per_60      = shots / team_hours,
    goals_per_60      = goals / team_hours,
    shooting_pct      = (goals - en_goals) / (shots - en_goals),
    pp_goal_share     = pp_goals / goals,
    minors_per_game   = minors / games
  )

rates_season
write_csv(rates_season, "output/rates_by_season.csv")

# Pooled across seasons
rates_pooled <- rates_season |>
  group_by(league) |>
  summarise(across(c(shots, goals, en_goals, pp_goals, team_hours, minors, games), sum)) |>
  mutate(
    shots_per_60    = shots / team_hours,
    goals_per_60    = goals / team_hours,
    shooting_pct    = (goals - en_goals) / (shots - en_goals),
    pp_goal_share   = pp_goals / goals,
    minors_per_game = minors / games
  )

rates_pooled
write_csv(rates_pooled, "output/rates_pooled.csv")

# ---- Figure: small multiples, one panel per stat ----------------------------
# Each stat has its own scale, so each gets its own panel (never a dual axis).

rate_long <- rates_season |>
  select(league, season, shots_per_60, goals_per_60, shooting_pct,
         pp_goal_share, minors_per_game) |>
  pivot_longer(-c(league, season), names_to = "stat") |>
  mutate(
    stat = factor(stat,
      levels = c("shots_per_60", "goals_per_60", "shooting_pct",
                 "minors_per_game", "pp_goal_share"),
      labels = c("Shots on goal per team per 60", "Goals per team per 60",
                 "Shooting % (excl. empty net)", "Minor penalties per game",
                 "Share of goals on the power play")),
    season_label = paste0(season - 1, "-", str_sub(season, 3, 4))
  )

p_rates <- ggplot(rate_long, aes(season_label, value, color = league, group = league)) +
  geom_line(linewidth = 1) +
  geom_point(size = 2.8) +
  facet_wrap(~stat, scales = "free_y", ncol = 3) +
  scale_color_manual(values = league_colors) +
  scale_x_discrete(expand = expansion(add = 0.3)) +
  # percent labels on the panels that are proportions, plain numbers elsewhere
  scale_y_continuous(labels = \(x) if (max(x, na.rm = TRUE) <= 1)
                       scales::percent(x, accuracy = 1) else scales::number(x)) +
  expand_limits(y = 0) +
  labs(
    title    = "League-wide rates, PWHL vs NHL",
    subtitle = "Regulation time only, regular season",
    x = NULL, y = NULL, color = NULL, caption = data_caption
  ) +
  theme_project(base_size = 12) +
  theme(panel.grid.major.x = element_blank())

save_fig(p_rates, "03_league_rates", width = 11, height = 6.5)
