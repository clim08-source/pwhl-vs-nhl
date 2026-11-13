# Downloads every season once and saves three tidy tables to data/:
#   games.rds     one row per game (both leagues)
#   shots.rds     one row per shot on goal, attacking toward +x (both leagues)
#   penalties.rds one row per penalty (both leagues)
#
# Run this once. It takes a few minutes, mostly for the NHL play-by-play.
# Every other script reads the saved files, so it runs in seconds.

source("R/00_setup.R")

# ---- PWHL -------------------------------------------------------------------

pwhl_sched <- load_pwhl_schedule(seasons = seasons)
pwhl_pbp   <- load_pwhl_pbp(seasons = seasons)

pwhl_games <- pwhl_sched |>
  filter(game_type == "regular", str_detect(game_status, "^Final")) |>
  transmute(
    league     = "PWHL",
    season,
    game_id    = as.integer(game_id),
    home_team,
    away_team,
    home_score = as.integer(home_score),
    away_score = as.integer(away_score),
    ended_in   = case_when(
      str_detect(game_status, "SO") ~ "Shootout",
      str_detect(game_status, "OT") ~ "Overtime",
      TRUE                          ~ "Regulation"
    )
  )

pwhl_pbp <- pwhl_pbp |>
  semi_join(pwhl_games, by = "game_id") |>
  left_join(select(pwhl_games, game_id, season), by = "game_id")

# PWHL goals appear twice: as a "shot" row (goal = TRUE) and as a "goal" row.
# The goal row carries the empty-net and power-play flags, so attach those to the shot.
pwhl_goal_flags <- pwhl_pbp |>
  filter(event == "goal") |>
  distinct(game_id, period_of_game, time_of_period, player_id, .keep_all = TRUE) |>
  transmute(game_id, period_of_game, time_of_period, player_id,
            en_flag = empty_net == "1",
            pp_flag = power_play == "1")

pwhl_shots <- pwhl_pbp |>
  filter(event == "shot") |>
  select(-empty_net, -power_play) |>
  left_join(pwhl_goal_flags,
            by = c("game_id", "period_of_game", "time_of_period", "player_id")) |>
  transmute(
    league     = "PWHL",
    season,
    game_id,
    period     = period_of_game,
    regulation = period_of_game %in% c("1", "2", "3"),
    is_home    = team_id == home_team_id,
    goalie_id  = as.character(goalie_id),
    goalie     = str_squish(paste(goalie_first, goalie_last)),
    x          = x_coord_right,
    y          = y_coord_right,
    shot_type  = str_to_lower(event_type),
    goal       = goal,
    empty_net  = coalesce(en_flag, FALSE),
    power_play = coalesce(pp_flag, FALSE)
  ) |>
  # In a few PWHL games a team's shots for a whole period are recorded at the wrong
  # end of the rink (they have normal shooting %, so they're flipped, not real
  # long-range shots). If most of a team's shots in a period are in its own half,
  # flip that team-period back around.
  group_by(game_id, period, is_home) |>
  mutate(flipped = mean(x < 0) > 0.5) |>
  ungroup() |>
  ungroup() |>
  # Any remaining shot recorded deep in the shooter's own end (x < -25) is also a
  # flipped record, so flip those individually too.
  mutate(flipped = flipped | (!flipped & x < -25),
         x = if_else(flipped, -x, x),
         y = if_else(flipped, -y, y)) |>
  select(-flipped)

pwhl_penalties <- pwhl_pbp |>
  filter(event == "penalty") |>
  transmute(league = "PWHL", season, game_id,
            minutes = as.numeric(penalty_length),
            minor   = minutes == 2)

# ---- NHL --------------------------------------------------------------------

nhl_sched <- load_nhl_schedule(seasons = seasons)

# Load one season at a time and keep only what we need, so memory stays manageable
nhl_events <- map(seasons, \(s) {
  message("Loading NHL ", s, " ...")
  load_nhl_pbp(seasons = s) |>
    filter(season_type == "R",
           event_type %in% c("SHOT", "GOAL", "PENALTY", "PERIOD_START")) |>
    select(game_id, season, event_type, event_team_type, period, period_type,
           x_fixed, y_fixed, secondary_type, event_goalie_id, event_goalie_name,
           empty_net, extra_attacker, home_skaters, away_skaters, penalty_severity) |>
    # column types differ slightly between seasons' files, so standardise them
    mutate(
      season = as.integer(s),
      across(c(game_id, period, home_skaters, away_skaters), as.integer),
      across(c(x_fixed, y_fixed), as.numeric),
      across(c(empty_net, extra_attacker), as.logical),
      across(c(event_goalie_id, event_goalie_name, secondary_type,
               penalty_severity, period_type, event_team_type), as.character)
    )
}) |>
  list_rbind()

nhl_end <- nhl_events |>
  group_by(game_id) |>
  summarise(ended_in = case_when(
    any(period_type == "SHOOTOUT") ~ "Shootout",
    any(period_type == "OVERTIME") ~ "Overtime",
    TRUE                           ~ "Regulation"
  ))

nhl_games <- nhl_sched |>
  filter(game_type == "R") |>
  inner_join(nhl_end, by = "game_id") |>
  transmute(league = "NHL", season, game_id,
            home_team = home_team_name, away_team = away_team_name,
            home_score, away_score, ended_in)

nhl_shots <- nhl_events |>
  filter(event_type %in% c("SHOT", "GOAL"),
         period_type != "SHOOTOUT",
         home_skaters > 1, away_skaters > 1,   # drops penalty shots
         !is.na(x_fixed)) |>
  mutate(
    is_home   = event_team_type == "home",
    team_sk   = if_else(is_home, home_skaters, away_skaters),
    opp_sk    = if_else(is_home, away_skaters, home_skaters),
    # x_fixed has the home team shooting right; flip the away team so everyone attacks +x
    x         = if_else(is_home, x_fixed, -x_fixed),
    y         = if_else(is_home, y_fixed, -y_fixed)
  ) |>
  transmute(
    league     = "NHL",
    season,
    game_id,
    period     = as.character(period),
    regulation = period_type == "REGULAR",
    is_home,
    goalie_id  = as.character(event_goalie_id),
    goalie     = event_goalie_name,
    x, y,
    shot_type  = secondary_type,
    goal       = event_type == "GOAL",
    empty_net  = coalesce(empty_net, FALSE) & event_type == "GOAL",
    # power play = more skaters than the opponent, not counting a pulled goalie
    power_play = event_type == "GOAL" &
                 (team_sk - coalesce(extra_attacker, FALSE)) > opp_sk
  )

nhl_penalties <- nhl_events |>
  filter(event_type == "PENALTY") |>
  transmute(league = "NHL", season, game_id,
            minutes = NA_real_,
            minor   = penalty_severity == "Minor")

# ---- Combine and save -------------------------------------------------------

games     <- bind_rows(pwhl_games, nhl_games)
shots     <- bind_rows(pwhl_shots, nhl_shots) |>
  mutate(distance = sqrt((89 - x)^2 + y^2))   # feet from the net (goal line is 89 ft from centre)
penalties <- bind_rows(pwhl_penalties, nhl_penalties)

saveRDS(games,     "data/games.rds")
saveRDS(shots,     "data/shots.rds")
saveRDS(penalties, "data/penalties.rds")

games |> count(league, season, name = "games")
