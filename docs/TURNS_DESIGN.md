# Phase 6 — turn-based strategic layer (Risiko-style)

The user's decision, 2026-11-09: the strategic map becomes **turn-based**. The 3D battles stay real-time.
Reason: the AI was launching about 20 attacks at once while the player commanded one battle.

## Turn order
- Turns are sequential, as in Risiko. Order: the human, then each AI in seat order. One round = every live player has played once.
- An AI turn plays animated on the map. Each phase of an AI turn should take about 1–3 s of map animation.
  - A "Salta animazioni" setting makes AI turns near-instant.
  - Space speeds up the AI turn being played.
- If an AI attacks the human, the battle prompt appears for the human as DEFENDER, with these choices:
  - **Difendi in prima persona**: a 3D battle in which the human deploys first.
  - **Risoluzione automatica**: uses the same headless BattleSim; see Phase 5 in SPEC3D.md.
- Spectator mode (no human): AI turns run back to back.

## Phases of a turn
1. **RIFORNIMENTO** (supply):
   - Income is collected once per turn: money, oil, steel, manpower. Upkeep and supply are applied.
   - Continent bonuses and periodic reinforcements are added to the pool once per turn.
   - The player may, in any number:
     - build (6 buildings) and research tech;
     - recruit, with a production time of 1–3 turns depending on the unit (e.g. inf 1, tank 2, jet 3) instead of seconds;
     - trade on the market, play a card set, hire mercenaries;
     - deploy the pool onto own territories;
     - **fortify** a territory: trench, mines, bunker, each with levels 0–3. These cost resources and appear in the battle as `setup.def.fort`.
2. **ATTACCO** (attack), at most **one** per turn and optional:
   - Pick an own territory and an adjacent enemy one, or a sea link if the source has a port.
   - Choose how many units of each type to send. At least 1 unit must stay behind.
   - Resolve it with a 3D battle (manual) or automatically.
   - On conquest, the survivors move in. Occupation and regroup become N turns of reduced production. The player draws a card.
   - Truce: no attacks during each player's first 2 turns (configurable).
   - Pacts: last N rounds, and attacking a partner is forbidden.
3. **SPOSTAMENTO** (movement), **one** per turn and optional:
   - Move units from one own territory to another own territory connected through own territories.
   - At least 1 unit must stay behind.
4. **FINE TURNO** (end of turn): press the button or Enter. Production queues advance by one turn.

## What becomes turns instead of seconds
| Before (real time) | After (turns) |
|---|---|
| Divisions travelling on the map | Instant moves, shown with a short animation |
| Truce of N seconds | First 2 rounds |
| Build and recruit timers | N turns |
| Periodic reinforcements | Every turn |
| Pact duration and cooldown | Rounds |
| Occupation and regroup | Turns |
| Scenario time limits | Round limits; roughly 1 minute ≈ 1 round, tune for fun |

- Victory conditions and secret objectives are unchanged.
- Fog of war, veterans and pacts stay.

## Save files
- Bump SAVE_VERSION.
- Old saves may be refused with a clear Italian message.

## UI (Italian text)
- **Turn bar** at top center, for example «Turno 7 · Tocca a te · Fase: ATTACCO». It shows:
  - the three phase chips (Rifornimento › Attacco › Spostamento);
  - the «Fine fase» and «Fine turno» buttons;
  - who plays next.
- During an AI turn, a banner «Turno della Federazione Orientale…» and the AI's moves in the log.
  - The camera may follow the AI attack (this can be turned off).
- **Attack panel**: sliders per unit type and the predicted outcome. A Predict API already exists; it should use the new auto-resolve estimate.
- **Fortify panel** in the territory panel.
- **Battle prompt** for both attack and defence. The defender prompt shows the incoming forces as estimated under fog.
- Remove or hide the real-time controls (speed 0/1/2/3, pause) on the map; keep Space for "skip AI animation".
- Update the F1 guide, tutorial and tips for the turn flow.
