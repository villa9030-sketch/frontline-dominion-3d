# Per iniziare — Frontline Dominion 3D

Benvenuto nel progetto! Qui trovi cosa serve per far girare il gioco, come è fatto e come lavoriamo insieme.

## Il gioco in breve
RTS moderno che unisce **Risiko** e **Age of Empires**. Due livelli:
- **Tabellone strategico 3D, a turni.** 42 territori, 4 potenze con caratteristiche diverse. Ogni turno ha tre fasi:
  1. **Rifornimento**: entrate, rinforzi, reclutamento, edifici, fortificazioni, ricerca.
  2. **Attacco**: al massimo uno.
  3. **Spostamento**: al massimo uno.
- **Battaglie tattiche 3D in tempo reale**, stile R.U.S.E.
  - Campo grande con rilievo e meteo.
  - Visibilità e occultamento, imboscate, corazza frontale/laterale/posteriore.
  - Puoi comandarle tu, oppure risolverle in automatico: la risoluzione automatica simula la stessa battaglia.

**Tutto è generato in codice**: modelli 3D, effetti, terreno, musica e suoni. Non c'è nessun asset esterno.

## Cosa installare
1. **Godot 4.6.2** (versione standard, non .NET): https://godotengine.org/download/archive/4.6.2-stable/
2. **Git**, e un client se ti è comodo (GitHub Desktop va benissimo).
3. *(Facoltativo)* **Node.js**, per lo script `tools/godot_run.js` che lancia test e screenshot.

## Scaricare e avviare
```
git clone https://github.com/villa9030-sketch/frontline-dominion-3d.git
```
- Apri Godot, scegli **Importa**, seleziona `project.godot` e premi **Esegui** (F5).
- `Gioca.bat` usa il percorso di Godot sul PC di Villa: per usarlo sul tuo, modifica il percorso al suo interno.
- Al primo avvio la mappa del mondo viene generata in circa 3 secondi, poi resta in cache.

## Dove sta cosa
| Cartella | Contenuto |
|---|---|
| `scripts/core/` | regole del gioco: `game.gd` (turni, economia, attacchi), `ai.gd` (IA strategica), `combat.gd`, `data.gd` (dati e bilanciamento), `scenarios.gd`, `settings.gd`, `sfx.gd` / `music.gd` (audio procedurale) |
| `scripts/battle/` | battaglia: `battle_sim.gd` (logica), `battle_rules.gd` (statistiche e regole), `battle_ai.gd`, `battle3d.gd` (vista), `battle_terrain.gd` / `battle_relief.gd` (terreno e rilievo), `battle_weather.gd`, `battle_marks.gd`, `battle_fx.gd`, `battle_hud.gd`, `battle_audio.gd` |
| `scripts/map/` | tabellone 3D: `world_map.gd`, `map_gen.gd`, `map_decor.gd` (alberi, città, edifici, fronte), shader |
| `scripts/models/` | modelli procedurali di mezzi, soldati, navi, aerei, oggetti ed effetti |
| `scripts/ui/` + `scripts/main.gd` | interfaccia: HUD, riquadro ORDINI, pannelli, tutorial (`coach.gd`), guida F1 |
| `tests/` | test automatici headless |
| `docs/` | piani, screenshot (`docs/screens`), galleria (`docs/galleria.html`) |
| `SPEC3D.md` | **il contratto tra i moduli**: API, eventi, regole di ogni fase. Leggilo prima di toccare un modulo |

## Test
Il PC di Villa si blocca sotto carico, quindi i test si lanciano **uno alla volta** tramite il semaforo:
```
node tools/godot_run.js --timeout=600 -- --headless --path . --script tests/test_core.gd
```
Gli altri test sono elencati nel `README.md`: `test_save`, `test_fase3`, `test_scenarios`, `test_battle`, `test_tactics`, `test_weather`, `test_sfx`, `test_music` e `test_flow`. Quest'ultimo prova l'interfaccia e non va lanciato con `--headless`.

I test non toccano salvataggi e impostazioni del giocatore.

## Come lavoriamo insieme
- **Non lavorare direttamente su `main`.** Crea un ramo per ogni lavoro, per esempio `git checkout -b marco/nome-modifica`, poi apri una **Pull Request** su GitHub così la guardiamo insieme.
- **Prima della Pull Request**: lancia i test della parte che hai toccato, e il gioco deve partire senza `SCRIPT ERROR`.
- **Testi del gioco in italiano**, nomi nel codice coerenti con quelli che già ci sono.
- **Idee, bug e feedback**: aprili come **Issue** su GitHub.

## Prossimi passi del progetto
- Il tuo **feedback dopo la prima prova**: cosa ti piace, cosa non si capisce, cosa manca.
- **Multigiocatore online**: il prossimo grande lavoro.
