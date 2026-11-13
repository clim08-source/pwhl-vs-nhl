# Section 5: shot type and shot angle
#
# Distance alone doesn't capture how dangerous a shot is. This section asks two
# more questions about why PWHL shots go in less often:
#   1. Do PWHL players take different kinds of shots (wrist, slap, tip, ...)?
#   2. Do they shoot from worse angles?
# Then it estimates how much of the shooting % gap these explain, by scoring
# PWHL shots with a model of NHL conversion rates.

source("R/00_setup.R")

shots <- readRDS("data/shots.rds") |>
  filter(!empty_net, x > 0) |>   # offensive half, goalie in net
  add_shot_features()

# Types both leagues record. "Other" (wrap-arounds, bats, pokes) only exists in
# the NHL data and "Unknown" is mostly PWHL, so both are left out of comparisons.
# PWHL shots with no recorded type go in more often than its wrist shots, so
# they aren't a random sample of shots and can't be ignored silently.
common_types <- c("Wrist/snap", "Slap", "Backhand", "Tip/deflection")

shots |>
  count(league, type_group) |>
  group_by(league) |>
  mutate(share = n / sum(n)) |>
  write_csv("output/shot_type_coverage.csv")

# ---- Shot type: mix and shooting % ------------------------------------------

by_type <- shots |>
  filter(type_group %in% common_types) |>
  mutate(type_group = fct_drop(type_group)) |>
  group_by(league, type_group) |>
  summarise(shots = n(), goals = sum(goal), avg_distance = mean(distance),
            .groups = "drop_last") |>
  mutate(
    shot_share   = shots / sum(shots),
    shooting_pct = goals / shots,
    se           = sqrt(shooting_pct * (1 - shooting_pct) / shots)
  ) |>
  ungroup()

by_type
write_csv(by_type, "output/shots_by_type.csv")

p_type_mix <- ggplot(by_type, aes(type_group, shot_share, fill = league)) +
  geom_col(position = position_dodge(width = 0.85), width = 0.8) +
  scale_fill_manual(values = league_colors) +
  scale_y_continuous(labels = scales::percent) +
  labs(
    title    = "What kinds of shots each league takes",
    subtitle = "Share of shots on goal with a recorded type (about 30% of PWHL shots have none)",
    x = NULL, y = "Share of shots", fill = NULL,
    caption  = data_caption
  ) +
  theme_project() +
  theme(panel.grid.major.x = element_blank())

save_fig(p_type_mix, "11_shot_type_mix")

p_type_sh <- ggplot(by_type, aes(type_group, shooting_pct, color = league)) +
  geom_errorbar(aes(ymin = shooting_pct - 1.96 * se, ymax = shooting_pct + 1.96 * se),
                width = 0.15, alpha = 0.6, position = position_dodge(width = 0.4)) +
  geom_point(size = 3, position = position_dodge(width = 0.4)) +
  scale_color_manual(values = league_colors) +
  scale_y_continuous(labels = scales::percent, limits = c(0, NA)) +
  labs(
    title    = "Shooting percentage by shot type",
    subtitle = "Shots on goal with a goalie in net, with 95% confidence intervals",
    x = NULL, y = "Shooting %", color = NULL,
    caption  = data_caption
  ) +
  theme_project() +
  theme(panel.grid.major.x = element_blank())

save_fig(p_type_sh, "12_shooting_by_type")

# ---- Shot angle --------------------------------------------------------------

angle_breaks <- c(0, 15, 30, 45, 60, Inf)
angle_labels <- c("0-15", "15-30", "30-45", "45-60", "60+")

# Overall share of shots by angle (how central each league's shots are)
angle_share <- shots |>
  mutate(angle_bin = cut(angle, angle_breaks, angle_labels, right = FALSE)) |>
  count(league, angle_bin, name = "shots") |>
  group_by(league) |>
  mutate(shot_share = shots / sum(shots)) |>
  ungroup()

angle_share
write_csv(angle_share, "output/shot_share_by_angle.csv")

# Shooting % by angle, split by distance. Wide-angle shots tend to be taken
# close to the net, so without the split the two effects blur together.
by_angle <- shots |>
  mutate(
    angle_bin = cut(angle, angle_breaks, angle_labels, right = FALSE),
    dist_band = cut(distance, c(0, 20, 40, Inf),
                    c("Within 20 ft", "20-40 ft", "40+ ft"), right = FALSE)
  ) |>
  filter(!is.na(dist_band)) |>
  group_by(league, dist_band, angle_bin) |>
  summarise(shots = n(), goals = sum(goal), .groups = "drop") |>
  mutate(
    shooting_pct = goals / shots,
    se           = sqrt(shooting_pct * (1 - shooting_pct) / shots)
  )

by_angle
write_csv(by_angle, "output/shots_by_angle.csv")

p_angle <- ggplot(by_angle, aes(angle_bin, shooting_pct, color = league, group = league)) +
  geom_line(linewidth = 1) +
  geom_errorbar(aes(ymin = pmax(shooting_pct - 1.96 * se, 0),
                    ymax = shooting_pct + 1.96 * se),
                width = 0.15, alpha = 0.6) +
  geom_point(size = 2.5) +
  facet_wrap(~dist_band) +
  scale_color_manual(values = league_colors) +
  scale_y_continuous(labels = scales::percent, limits = c(0, NA)) +
  labs(
    title    = "Shooting percentage by angle and distance",
    subtitle = "Angle in degrees off straight in front of the net, with 95% confidence intervals",
    x = "Shot angle (degrees)", y = "Shooting %", color = NULL,
    caption  = data_caption
  ) +
  theme_project() +
  theme(axis.text.x = element_text(size = rel(0.8)))

save_fig(p_angle, "13_shooting_by_angle", width = 11)

# ---- How much of the gap do location and type explain? ----------------------
# Fit a model of NHL conversion rates, then use it to score PWHL shots: "if these
# PWHL shots went in at NHL rates, what would PWHL shooting % be?"
#   Location only:   distance, distance^2, angle          (all shots)
#   Location + type: the same plus shot type              (shots with a common type)

nhl_rate_gap <- function(df, formula, label) {
  fit   <- glm(formula, data = filter(df, league == "NHL"), family = binomial)
  pwhl  <- filter(df, league == "PWHL")
  tibble(
    model                 = label,
    pwhl_shots            = nrow(pwhl),
    nhl_actual            = mean(df$goal[df$league == "NHL"]),
    pwhl_at_nhl_rates     = mean(predict(fit, newdata = pwhl, type = "response")),
    pwhl_actual           = mean(pwhl$goal)
  )
}

typed_shots <- shots |>
  filter(type_group %in% common_types) |>
  mutate(type_group = fct_drop(type_group))

shot_quality <- bind_rows(
  nhl_rate_gap(shots, goal ~ distance + I(distance^2) + angle,
               "Location (distance + angle)"),
  nhl_rate_gap(typed_shots, goal ~ distance + I(distance^2) + angle + type_group,
               "Location + shot type")
) |>
  mutate(
    raw_gap         = nhl_actual - pwhl_actual,
    # positive = PWHL shots are, by location/type, easier than the NHL's average shot
    shot_mix_effect = pwhl_at_nhl_rates - nhl_actual,
    # what's left once shot location/type is held equal: the conversion gap
    conversion_gap  = pwhl_at_nhl_rates - pwhl_actual
  )

shot_quality
write_csv(shot_quality, "output/shot_quality_gap.csv")

quality_long <- shot_quality |>
  select(model, `NHL, actual` = nhl_actual,
         `PWHL shots at NHL rates` = pwhl_at_nhl_rates,
         `PWHL, actual` = pwhl_actual) |>
  pivot_longer(-model, names_to = "measure", values_to = "shooting_pct") |>
  mutate(measure = fct_inorder(measure))

p_quality <- ggplot(quality_long, aes(shooting_pct, measure, color = measure)) +
  geom_point(size = 4) +
  geom_text(aes(label = scales::percent(shooting_pct, accuracy = 0.1)),
            vjust = -1.2, size = 3.5, show.legend = FALSE) +
  facet_wrap(~model, ncol = 1) +
  scale_color_manual(values = c(league_colors[["NHL"]], "grey55",
                                league_colors[["PWHL"]]),
                     guide = "none") +
  scale_x_continuous(labels = scales::percent, expand = expansion(mult = 0.15)) +
  labs(
    title    = "PWHL shots aren't worse shots",
    subtitle = "PWHL shots scored with an NHL model of shooting % by distance, angle and type",
    x = "Shooting %", y = NULL,
    caption  = data_caption
  ) +
  theme_project() +
  theme(panel.grid.major.y = element_blank())

save_fig(p_quality, "14_shot_quality_gap", height = 5)
