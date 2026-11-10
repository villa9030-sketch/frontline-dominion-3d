# Notte 2 — agente REGOLE: resoconto (omogeneità campagna ↔ battaglia)

Regole e numeri di progetto: `docs/omogeneita.md` (scritto per primo, poi implementato). Contratto aggiornato in `SPEC3D.md`
(sezione finale «Omogeneità»). Nessun commit.

## Cosa è stato fatto
1. **Limite di 5 minuti e obiettivi di battaglia** (`battle_rules.gd`, `battle_sim.gd`, `battle_ai.gd`)
   - `BATTLE_T = 300` s anche in risoluzione automatica; timer dell'HUD in conto alla rovescia (rosso sotto 60 s).
   - Obiettivi dal contesto (max 4): QG (capitale), edifici del territorio (max 2, siti con copertura pesante nella metà del
     difensore), ponti/guadi (max 2), altura (1, se ≥ 6 m sopra la quota minima), linea dei bunker. Raggio 260 px, conquista con
     60 s di presenza esclusiva; QG/edifici/bunker partono del difensore, ponti/guadi/alture neutri.
   - Allo scadere o nello stallo: più obiettivi → attaccante; parità → difensore; 0–0 → vecchia regola di forza (`_stall_winner`).
   - Riquadro OBIETTIVI nell'HUD (nome, colore di chi lo tiene, barra del contatore, «tuo tra N s / perso tra N s / conteso»,
     rinforzi in arrivo); le bandierine della vista strategica (`BattleStrategic`) leggono `sim.objectives`.
   - L'IA attaccante punta all'obiettivo non tenuto più vicino quando non vede nemici (settore d'attacco = obiettivo).
2. **Ritirata ordinata**: il pulsante non chiude più la battaglia; i reparti ripiegano al bordo (150 px), chi lo raggiunge è salvo
   (`escaped`), chi resta combatte; fine quando l'attaccante non ha più unità in campo. L'IA attaccante si ritira da sola dopo
   120 s se la sua potenza è sotto il 35 % del difensore. Eventi fx `retreat`/`escape`, HUD «RITIRATA IN CORSO».
3. **La campagna decide la battaglia** (`combat.gd` ctx, `game.gd`, `battle_sim.gd`)
   - `setup.buildings`, `setup.hq`, `setup.X.air` (aeroporto proprio nel territorio o accanto → tasto J; senza aeroporto il
     pulsante non c'è nemmeno con i caccia), `setup.X.naval` (porto nel territorio di partenza o fazione navale → 3 batterie;
     porto in un territorio costiero difeso → 2), `setup.X.reinf`.
   - Rinforzi: 20 % delle unità di terra di ogni confinante dello stesso proprietario (rifornito, non in riorganizzazione; il
     territorio di partenza dell'attaccante NON contribuisce), tetto 50 % dell'esercito iniziale, arrivo a 150 s (dif.) / 165 s
     (att.) dal proprio bordo (terzo nord o sud secondo la mappa). Le perdite si scalano a fine battaglia dai territori d'origine
     (`Game.reinf_plan` / `_reinf_settle`); nulla è tolto prima, così i salvataggi a battaglia in attesa restano coerenti.
   - Il risultato della sim porta `attReinf`/`defReinf`, `objectives`, `time`, `why`.
4. **Comando manuale visibile**: +10 % (già esistente) ora scritto nel pannello d'attacco, nel prompt di difesa e nell'HUD;
   esperienza doppia (`_gain_xp(t, 2)` con `info.manual`). Riga «Dal territorio: supporto aereo, tiro navale, N rinforzi, edifici».
5. **Logoramento**: `terr.worn = 2` per difensore e territorio di partenza dopo ogni battaglia; −15 % (`Data.WORN_MUL`) in
   `Combat.combat_mods` (anche nelle previsioni); −1 a ogni inizio turno del proprietario se rifornito. Chip nel pannello del
   territorio, tooltip sul tabellone, note nel pannello d'attacco. `SAVE_VERSION = 3`, i v2 si caricano (migrazione).
6. **Carte inganno e nebbia leggera**: `Data.OPS` + `finta` (proprio, +8 unità alla stima per 2 round), `silenzio` (proprio,
   «?» per 2 round), `ricognizione` (nemico + vicini esatti per 2 round, supera gli inganni). `fog_mode` none/light/full
   (menu a tre voci, **leggera** predefinita; gli scenari tengono il loro bool). `forces_view`/`estimate_text` («circa 10–15»).
   L'IA strategica usa solo `visible_forces`/`estimate_forces` (quindi è ingannata) e gioca le carte nuove (`_do_deceit`).
7. **Bilanciamento** (`ATT_INITIATIVE` 1.4 → **1.6**, regola 0–0 → forza): vedi numeri sotto.
8. **Test**: nuovo `tests/test_omogeneita.gd` (70 verifiche); aggiornati `test_battle` (ritirata ordinata), `test_save`
   (v3 + migrazione v2), `test_tactics` (serie «fazioni»). Guida F1 e tutorial aggiornati; README e SPEC3D aggiornati.

## Numeri di bilanciamento (tests/test_tactics.gd --only=balance --quick=1, 8 seed per caso)
| Caso | Prima | Dopo |
|---|---|---|
| specchio 6f3c1a pianura | att 1/8 | att 2/8 |
| specchio 10f5c2a pianura | att 1/8 | att 2/8 |
| specchio 10f5c foresta | att 3/8 | att 5/8 |
| **difensore a forze pari** | **79 %** | **63 %** (obiettivo 60–65) |
| 1.5× attaccante | 5/8 | 6/8 |
| 2× in campo aperto | 8/8 | 8/8 |
| 1.3× soli carri vs armi combinate (foresta) | 3/8 | 3/8 |
Serie completa (`test_tactics` intero, 16 seed per caso): difensore **71 %** a forze pari (le serie lunghe includono i seed più
favorevoli al difensore; la serie corta dà 63 %). Il valore è tra il vecchio 79 % e l'obiettivo: una leva ulteriore è
`ATT_INITIATIVE` (1.6 → 1.7) o `OBJ_HOLD` (60 → 45 s), da decidere con l'utente dopo qualche battaglia vera.
**Fazioni** (specchio 8f4c2a in foresta, 12 seed, attacco + difesa): AAN 50 %, FO 58 %, CP 50 %, UL 54 % → forbice 8 punti
(FO resta la più forte per i carri +20 % hp, UL recupera in difesa con la guerriglia).

## Suite di test (fine notte)
test_core 609/609 · test_save 149/149 · test_fase3 122/122 · test_scenarios OK · test_battle OK · test_weather OK ·
test_omogeneita 70/70 · test_sfx OK · test_music OK · test_tactics OK (serie balance + fazioni) · test_flow OK (finestra 960x540).

## File toccati
- Nucleo: `scripts/core/data.gd` (OPS, costanti), `game.gd`, `combat.gd`, `ai.gd`.
- Battaglia: `scripts/battle/battle_rules.gd`, `battle_sim.gd`, `battle_ai.gd`; condivisi (modifiche mirate): `battle_hud.gd`
  (riquadro obiettivi, timer, ritirata, bonus), `battle_strategic.gd` (obiettivi dalla sim), `battle3d.gd` (eventi fx, demo args
  `--buildings= --hq=1 --reinf=1`).
- Interfaccia: `scripts/ui/modal.gd` (bonus/contesto nei pannelli, guida F1), `hud.gd` (logoramento, inganni, stime), `menu.gd`
  (nebbia a tre voci), `coach.gd`; `scripts/main.gd` (fog_mode, carte su proprio territorio, testi stima, `worn_of`).
- Test: `tests/test_omogeneita.gd` (nuovo), `test_battle.gd`, `test_save.gd`, `test_tactics.gd`. Documenti: `docs/omogeneita.md`,
  `SPEC3D.md`, `README.md`.

## Screenshot (docs/screens/notte2)
`regole_hud_obiettivi.png` (HUD: riquadro OBIETTIVI con QG/Fabbrica/Porto/Guado, timer in conto alla rovescia, «Comando diretto:
+10% attacco · esperienza doppia», rinforzi in arrivo), `regole_strategica_obiettivi.png` (vista strategica: bandierine degli
obiettivi veri della sim con nome e colore), `regole_pannello_attacco.png` (pannello d'attacco con la riga dei bonus e del contesto).
Demo: `--demo=pianura --human=1 --side=0 --buildings=fabbrica,porto --hq=1 --reinf=1`.

## Nota per il coordinatore
Alle 23:20 `scripts/main.gd` (condiviso) non compilava: l'agente GRAFICA aveva inserito `_cinematic_ok()` in mezzo a
`_after_battle` (la coda della funzione era finita dopo). Ho spostato la funzione sotto, senza cambiare nulla del suo codice;
il gioco riparte. Da segnalare all'agente GRAFICA.

## Cosa resta / dubbi
- Gli edifici sul campo (`sim.landmarks`) sono per ora «siti» con copertura pesante e bandierina: la vista 3D non li disegna ancora
  (dominio GRAFICA: `battle_props`/`battle_decor` possono leggere `sim.landmarks` {key, name, x, y, w, h}).
- Il logoramento sul **tabellone** è nel tooltip del territorio e nel pannello; un segno grafico sulla pedina è lavoro di `scripts/map`.
- Il bilanciamento è misurato su serie corte (8–16 seed): la forbice tra le fazioni è informativa (controllo ≤ 30 punti).
- I rinforzi dell'IA: l'IA strategica non li considera nelle previsioni (volutamente: «decide su ciò che vede»).
