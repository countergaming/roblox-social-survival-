# MVP Spec

## Product Guardrails

- Target audience: kids and younger teens, with enough depth for 13+ players
- Session length: 6-10 minutes
- Concurrency target: 8-12 players
- Device target: mobile-first, then desktop
- Scope guardrail: one map, one core loop, one progression track

## Player Journeys

### Journey 1: Join And Understand The Game Fast

As a new player, I can join the lobby and understand the objective in under 15 seconds so that I can start playing without a tutorial wall.

Acceptance checks:

- The HUD shows the current phase and next objective.
- The first round begins automatically once enough players are present.
- The player always knows whether to gather, defend, or wait.

### Journey 2: Contribute During The Day

As a player, I can collect supplies and help charge the lantern during the day so that I feel useful even if I am not good at combat.

Acceptance checks:

- The day phase communicates a clear collection goal.
- Team progress is visible.
- The activity works with simple movement and one-tap interactions.

### Journey 3: Feel Tension At Night

As a player, I can feel the night getting more dangerous each round so that replaying feels exciting.

Acceptance checks:

- Threat intensity scales by round number and player count.
- The team can fail if they ignore objectives.
- The night phase is readable on mobile.

### Journey 4: Earn Persistent Progress

As a player, I earn coins and XP at dawn so that losing still feels worthwhile.

Acceptance checks:

- Rewards are shown at the end of each round.
- Rewards scale with objectives completed and survival.
- The system supports later DataStore persistence.

## Out Of Scope For MVP

- battle royale
- weapon rarity loot systems
- ranked PvP
- voice-driven coordination
- large open-world exploration
- advanced crafting trees
- multiple classes or hero abilities

