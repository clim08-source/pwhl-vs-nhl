# Section 1: scoring and game scores

source("R/00_setup.R")
games <- readRDS("data/games.rds")

games <- games |>
  mutate(
    # The shootout winner gets +1 goal in the final score; take it back out
    total_goals = home_score + away_score - (ended_in == "Shootout"),
    margin      = abs(home_score - away_score),
    one_goal    = margin == 1
  )

# ---- Summary table ----------------------------------------------------------

scoring_summary <- games |>
  group_by(league) |>
  summarise(
    games            = n(),
    goals_per_game   = mean(total_goals),
    avg_winner_score = mean(pmax(home_score, away_score)),
    avg_loser_score  = mean(pmin(home_score, away_score)),
    one_goal_games   = mean(one_goal),
    went_to_ot       = mean(ended_in != "Regulation"),
    shootouts        = mean(ended_in == "Shootout"),
    shutouts         = mean(pmin(home_score, away_score) == 0),
    home_win_pct     = mean(home_score > away_score)
  )

scoring_summary
write_csv(scoring_summary, "output/scoring_summary.csv")

# By season, to check the pattern holds every year
games |>
  group_by(league, season) |>
  summarise(goals_per_game = mean(total_goals),
            one_goal_games = mean(one_goal),
            went_to_ot     = mean(ended_in != "Regulation"),
            .groups = "drop") |>
  write_csv("output/scoring_by_season.csv")

# ---- Figure: distribution of total goals per game ---------------------------

goal_dist <- games |>
  mutate(total_goals = pmin(total_goals, 11)) |>   # lump 11+ together
  count(league, total_goals) |>
  group_by(league) |>
  mutate(share = n / sum(n)) |>
  ungroup()

p_goals <- ggplot(goal_dist, aes(total_goals, share, fill = league)) +
  geom_col(position = position_dodge(width = 0.85), width = 0.8) +
  scale_fill_manual(values = league_colors) +
  scale_x_continuous(breaks = 0:11, labels = c(0:10, "11+")) +
  scale_y_continuous(labels = scales::percent) +
  labs(
    title    = "PWHL games are lower scoring",
    subtitle = "Share of games by total goals (shootout winners excluded)",
    x = "Total goals in the game", y = "Share of games", fill = NULL,
    caption  = data_caption
  ) +
  theme_project() +
  theme(panel.grid.major.x = element_blank())

save_fig(p_goals, "01_goals_per_game")

# ---- Figure: how games end --------------------------------------------------

game_endings <- games |>
  mutate(result = case_when(
    ended_in == "Shootout"           ~ "Shootout",
    ended_in == "Overtime"           ~ "Overtime",
    margin == 1                      ~ "Regulation, 1 goal",
    margin == 2                      ~ "Regulation, 2 goals",
    TRUE                             ~ "Regulation, 3+ goals"
  ),
  result = factor(result, levels = c("Regulation, 3+ goals", "Regulation, 2 goals",
                                     "Regulation, 1 goal", "Overtime", "Shootout"))) |>
  count(league, result) |>
  group_by(league) |>
  mutate(share = n / sum(n)) |>
  ungroup()

p_endings <- ggplot(game_endings, aes(share, result, fill = league)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.75) +
  geom_text(aes(label = scales::percent(share, accuracy = 1)),
            position = position_dodge(width = 0.8), hjust = -0.15, size = 3.5,
            color = "grey25") +
  scale_fill_manual(values = league_colors) +
  scale_x_continuous(labels = scales::percent, expand = expansion(mult = c(0, 0.12))) +
  labs(
    title    = "How games are decided",
    subtitle = "Share of regular-season games by final margin",
    x = NULL, y = NULL, fill = NULL, caption = data_caption
  ) +
  theme_project() +
  theme(panel.grid.major.y = element_blank())

save_fig(p_endings, "02_game_endings")
