# Section 3: where shots come from, and where they go in
#
# Coordinates are in feet from centre ice, with every shot attacking the net at
# x = 89. Both leagues play on NHL-sized rinks, so sportyR's "nhl" rink fits both.

source("R/00_setup.R")
library(sportyR)

shots <- readRDS("data/shots.rds") |>
  filter(!empty_net, x > 0)   # offensive half, goalie in net

# ---- Distance bins: shot share and shooting % -------------------------------

dist_breaks <- c(0, 10, 20, 30, 40, 50, 60, Inf)
dist_labels <- c("0-10", "10-20", "20-30", "30-40", "40-50", "50-60", "60+")

by_distance <- shots |>
  mutate(dist_bin = cut(distance, dist_breaks, dist_labels, right = FALSE)) |>
  group_by(league, dist_bin) |>
  summarise(shots = n(), goals = sum(goal), .groups = "drop_last") |>
  mutate(
    shot_share   = shots / sum(shots),
    shooting_pct = goals / shots,
    se           = sqrt(shooting_pct * (1 - shooting_pct) / shots)
  ) |>
  ungroup()

by_distance
write_csv(by_distance, "output/shots_by_distance.csv")

p_dist <- ggplot(by_distance, aes(dist_bin, shooting_pct, color = league, group = league)) +
  geom_line(linewidth = 1) +
  geom_errorbar(aes(ymin = shooting_pct - 1.96 * se, ymax = shooting_pct + 1.96 * se),
                width = 0.15, alpha = 0.6) +
  geom_point(size = 3) +
  scale_color_manual(values = league_colors) +
  scale_y_continuous(labels = scales::percent) +
  labs(
    title    = "Shooting percentage by distance",
    subtitle = "Shots on goal with a goalie in net, with 95% confidence intervals",
    x = "Distance from net (feet)", y = "Shooting %", color = NULL,
    caption  = data_caption
  ) +
  theme_project()

save_fig(p_dist, "04_shooting_by_distance")

p_share <- ggplot(by_distance, aes(dist_bin, shot_share, fill = league)) +
  geom_col(position = position_dodge(width = 0.85), width = 0.8) +
  scale_fill_manual(values = league_colors) +
  scale_y_continuous(labels = scales::percent) +
  labs(
    title    = "Where shots come from",
    subtitle = "Share of each league's shots on goal by distance",
    x = "Distance from net (feet)", y = "Share of shots", fill = NULL,
    caption  = data_caption
  ) +
  theme_project() +
  theme(panel.grid.major.x = element_blank())

save_fig(p_share, "05_shot_share_by_distance")

# ---- Shot maps --------------------------------------------------------------
# Hexagons coloured by each league's share of shots from that spot, so the two
# leagues are comparable even though the NHL has ~15x more shots.

hex_counts <- shots |>
  group_by(league) |>
  mutate(weight = 1 / n()) |>
  ungroup()

p_map <- geom_hockey("nhl", display_range = "offense") +
  geom_hex(data = hex_counts, aes(x = x, y = y, weight = weight),
           binwidth = c(4, 4), alpha = 0.85) +
  facet_wrap(~league) +
  scale_fill_gradient(low = "#cde2fb", high = "#0d366b",
                      labels = scales::percent, name = "Share of shots") +
  labs(
    title    = "Shot locations, PWHL vs NHL",
    subtitle = "Each hexagon shows the share of that league's shots on goal taken from that spot",
    caption  = data_caption
  ) +
  theme(
    plot.title      = element_text(face = "bold", size = 15),
    strip.text      = element_text(face = "bold", size = 13),
    legend.position = "bottom",
    legend.key.width = unit(1.5, "cm")
  )

save_fig(p_map, "06_shot_maps", width = 11, height = 5.5)

# Where goals are scored: shooting % by hexagon (only hexes with enough shots)
hex_sh <- shots |>
  mutate(hx = round(x / 6) * 6, hy = round(y / 6) * 6) |>
  group_by(league, hx, hy) |>
  summarise(shots = n(), sh = mean(goal), .groups = "drop") |>
  group_by(league) |>
  filter(shots >= if_else(league == "PWHL", 20, 200)) |>
  ungroup()

p_sh_map <- geom_hockey("nhl", display_range = "offense") +
  geom_tile(data = hex_sh, aes(x = hx, y = hy, fill = sh),
            width = 5.6, height = 5.6, alpha = 0.9) +
  facet_wrap(~league) +
  # cap the colour scale at 30% so a few tiny crease areas don't wash out the rest
  scale_fill_gradient(low = "#fde0d2", high = "#a3300c", limits = c(0, 0.3),
                      oob = scales::squish, labels = scales::percent,
                      name = "Shooting %") +
  labs(
    title    = "Where shots go in",
    subtitle = "Shooting % by 6x6 ft area (areas with at least 20 PWHL / 200 NHL shots)",
    caption  = data_caption
  ) +
  theme(
    plot.title      = element_text(face = "bold", size = 15),
    strip.text      = element_text(face = "bold", size = 13),
    legend.position = "bottom",
    legend.key.width = unit(1.5, "cm")
  )

save_fig(p_sh_map, "07_shooting_pct_map", width = 11, height = 5.5)
