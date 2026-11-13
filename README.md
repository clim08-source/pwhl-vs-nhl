# PWHL vs NHL: how different is the game?

A comparison of the Professional Women's Hockey League and the National Hockey
League across scoring, league-wide rates, shot locations and goaltending, using
every regular-season game from 2023-24 (the PWHL's first season) to 2025-26.

## Key findings

- **Lower scoring, tighter games.** PWHL games average 4.7 goals compared with
  6.1 in the NHL. Half of PWHL games are decided by one goal (NHL: 40%), and
  27% go past regulation (NHL: 22%).
- **Same shot volume.** Teams in both leagues get about 27-28 shots on goal per
  60 minutes. The scoring gap comes from what happens to those shots.
- **Lower shooting percentage.** 7.8% of PWHL shots go in, compared with 9.9%
  in the NHL. Save % is .921 in the PWHL and .900 in the NHL.
- **It isn't shot location.** PWHL teams take about as many shots from within
  20 feet as NHL teams do (33% vs 31% of shots), but convert fewer of them at
  every distance up to 40 feet.
- **Goalies vary about as much.** After adjusting for shot distance, the
  spread between the best and worst goalies is similar in both leagues.

![League-wide rates](figures/03_league_rates.png)

![Shot locations](figures/06_shot_maps.png)

![Shooting % by distance](figures/04_shooting_by_distance.png)

## Project structure

```
R/
  00_setup.R         shared packages, seasons, colours, chart theme
  01_load_data.R     downloads data once, saves tidy tables to data/
  02_scoring.R       goals per game, margins, overtime and shootouts
  03_rates.R         shots, goals, shooting %, penalties per 60
  04_shot_maps.R     shot location maps, shooting % by distance
  05_goaltending.R   save %, expected goals model, goals saved above expected
run_all.R            runs everything in order
figures/             saved charts
output/              summary tables (CSV)
```

## How to run

1. Install the packages:
   ```r
   install.packages(c("tidyverse", "fastRhockey", "sportyR", "hexbin"))
   ```
2. Open this folder in Positron (or RStudio) and run `source("run_all.R")`.
   The first run downloads about three seasons of NHL play-by-play and takes a
   few minutes. The data is saved to `data/` (not in the repo).

## Methods and caveats

- **Shots means shots on goal** (saves plus goals). The PWHL doesn't publish
  missed shots, so this is the fairest measure both leagues share.
- **Rates use regulation time only**, so every game counts for exactly 60 minutes.
- **Shot distance** is measured from the centre of the net, with the goal line
  89 feet from centre ice:
  $d = \sqrt{(89 - x)^2 + y^2}$.
- **Expected goals** come from a logistic regression on shot distance, fit
  separately for each league:
  $P(\text{goal}) = 1 / (1 + e^{-(\beta_0 + \beta_1 d + \beta_2 d^2)})$.
  Goals saved above expected (GSAx) = expected goals against − actual goals against.
  This ignores shot type, angle and rebounds, so treat it as a rough adjustment.
- **PWHL coordinate cleanup.** In a few PWHL games, a team's shots for a period
  are recorded at the wrong end of the rink. These are flipped back in
  `01_load_data.R`.
- **Sample size.** The PWHL has 282 regular-season games in this period vs
  3,936 for the NHL, so PWHL estimates are much less precise. Charts show 95%
  confidence intervals where relevant.

## Data

Play-by-play and schedules from the PWHL (HockeyTech) and NHL APIs, via the
[fastRhockey](https://fastRhockey.sportsdataverse.org/) R package. Rinks drawn
with [sportyR](https://sportyR.sportsdataverse.org/).
