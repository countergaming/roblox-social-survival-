# Lantern Keep

Lantern Keep is a fresh Roblox game project started inside this workspace.

The concept is a mobile-friendly social survival game for 8-12 players:

- day phase: collect supplies, fuel the team lantern, repair defenses
- night phase: survive escalating creature waves, route pressure across lanes, and protect the lantern
- dawn phase: earn coins and XP, then replay with a higher threat level

This is a better first Roblox project than an Apex-style battle royale because it keeps the session short, the controls simple, the map small, and the content loop easy to update.

## Why This Game

- It matches Roblox demand around social survival and short-session co-play.
- It is realistic for a solo developer or a very small team.
- It can monetize through cosmetics, boosts, and progression without needing AAA shooter polish.
- It avoids the hardest first-project problems: large matchmaking pools, complex gunfeel, anti-cheat, spectating, and streaming huge maps.

## Current Project State

This starter includes:

- a Roblox-native MVP concept
- a skill-gap assessment
- a Rojo project file
- Aftman tool declarations
- Luau skeletons for the round loop, threat scaling, rewards, remote setup, HUD, persistent progression, day-phase objectives, lane defenses, and night threats

## Project Structure

```text
roblox-social-survival/
  aftman.toml
  default.project.json
  selene.toml
  stylua.toml
  docs/
    mvp-spec.md
    skill-gap.md
  src/
    shared/
    server/
    client/
```

## Setup

1. Install Aftman.
2. Run `aftman install` inside this folder.
3. Start Rojo with `rojo serve`.
4. Open Roblox Studio and connect Rojo to the local project.

## MVP Goals

- 1 map
- 1 safe camp
- 1 resource loop
- 1 night threat type
- 1 reward loop
- 1 basic HUD
- 1 lantern objective

## What To Build Next

1. Add resource nodes and lantern charge gameplay.
2. Add one enemy AI and one barricade repair objective.
3. Add thumbnails, icon, and first-time user onboarding.
4. Add one cosmetic shop and one returning-player reward.
