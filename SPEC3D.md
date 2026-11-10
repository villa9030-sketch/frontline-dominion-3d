# FRONTLINE DOMINION 3D — contratto tra i moduli (Godot 4.6, GDScript)

Porting 3D del prototipo browser `C:\Users\villa\frontline` (regole, economia, IA e battaglie GIÀ BILANCIATE e collaudate:
**si portano 1:1**, cambia la presentazione). Due livelli, entrambi 3D:
1. **Tabellone strategico**: mondo in rilievo 3D (stile sala operativa ma realistico), 42 territori, pedine-miniature, divisioni in movimento.
2. **Battaglia tattica**: scena 3D separata con terreno vero, mezzi 3D, telecamera RTS, comandi RTS.
Stile: **realistico militare**, modelli **generati in codice** (nessun asset esterno). Testi in **italiano**.
Riferimento di genere: RTS strategici moderni con zoom (tipo R.U.S.E.) — NON copiare nomi/asset di giochi esistenti.

## Regole per tutti gli agenti
- Lavora SOLO sui tuoi file (tabella sotto). Se il contratto non basta, scegli la soluzione più semplice compatibile e segnalala nel resoconto.
- **Godot si lancia SOLO tramite** `node tools/godot_run.js [--timeout=S] -- <argomenti>` (semaforo globale: un solo Godot alla volta,
  il PC dell'utente va in crash sotto carico). Mai lanciare Godot direttamente, mai browser, mai npm install.
  - Headless: `node tools/godot_run.js -- --headless --path . --script tests/xxx.gd` (lo script estende SceneTree e chiama quit()).
  - Dopo aver aggiunto/rinominato un `class_name`: `node tools/godot_run.js --timeout=180 -- --headless --path . --import`.
  - Screenshot: `node tools/godot_run.js -- --path . res://scenes/xxx.tscn --resolution 960x540 -- --shot=docs/screens/nome.png --frames=90`
    (autoload `Shot`, vedi `scripts/core/shot.gd`; le tue scene possono leggere argomenti propri con `Shot.arg("demo")`).
    Risoluzione massima per i test 960x540. **Guarda le tue immagini** (sono il collaudo visivo) e migliora finché sono belle.
- Cartella di lavoro dei comandi: `C:\Users\villa\frontline3d`. Script di prova temporanei: nella scratchpad, non nel progetto
  (`C:\Users\villa\AppData\Local\Temp\claude\abe4d5ab4778192a\4d9b6ddb-387c-42c7-9142-f6ace78febaf\scratchpad`); test permanenti in `tests/`.
- GDScript 4 con tipi dove possibile. Niente `await` nella logica di gioco. La logica (core, battle_sim) non tocca nodi/scene: gira headless.
- Prestazioni: PC con GTX 1070. Forward+, ombre su 1 luce direzionale, MultiMesh per alberi/erba, LOD semplice, niente SDFGI/volumetric fog pesanti.
- Il prototipo JS è la fonte di verità per regole e numeri: `frontline/js/*.js`, `frontline/SPEC.md`.

## Proprietà dei file
| Agente | File |
|---|---|
| (fatto) | `project.godot`, `scripts/core/data.gd` (autoload **Data**), `scripts/core/shot.gd` (autoload **Shot**), `tools/godot_run.js` |
| A — Nucleo | `scripts/core/combat.gd`, `scripts/core/game.gd`, `tests/test_core.gd` |
| B — IA | `scripts/core/ai.gd`, `tests/sim.gd` |
| C — Battaglia 3D | `scripts/battle/*`, `scenes/battle.tscn`, `tests/test_battle.gd` |
| D — Tabellone 3D | `scripts/map/*`, `scenes/world_map.tscn` |
| E — Interfaccia e flusso | `scripts/ui/*`, `scripts/main.gd`, `scenes/main.tscn`, `scripts/core/sfx.gd` (autoload **Sfx**, da registrare in project.godot), `scenes/menu*.tscn` |
| F — Modelli e effetti | `scripts/models/*`, `scenes/model_gallery.tscn` |
Solo E può modificare `project.godot` (aggiungere l'autoload Sfx, input map). Gli altri chiedono nel resoconto.

## Convenzioni di porting dal JS
- Metodi e proprietà delle classi: **camelCase JS → snake_case** (`sendDivision` → `send_division`, `pendingBattle` → `pending_battle`,
  `humanIdx` → `human_idx`, `nextReinforce` → `next_reinforce`, `cardCd` → `card_cd`, `lowOil` → `low_oil`).
- **Chiavi dei dizionari di dati restano come in JS** (es. `Data.ECON["baseMoney"]`, `Data.UNITS["tank"]["rts"]["range"]`,
  `Data.CONTINENTS["EU"]["perkText"]`, forze `{"inf":..,"tank":..}`, risorse `{"money","oil","steel","manpower"}`).
- `Data.TERRITORIES[i]` = `{id, name, c, ter, spec, amt, idx, x, y, blobs_px:[[x,y,r]], adj:[idx], sea:[idx marittimi], coastal}`;
  coordinate x,y nel piano mappa 0..1600 × 0..900 (come il JS). `Data.is_sea_link(a,b)`.
- Helper: `Data.empty_forces()`, `Data.total_units(f)`, `Data.add_forces(a,b)`, `Data.clone_forces(f)`, `Data.faction_color(i)` (−1 = neutrale).
- RNG: `RandomNumberGenerator` con seed (non serve identità numerica col JS).

## Nucleo — `class_name Game extends RefCounted` (Agente A)
Porta fedelmente `frontline/js/game.js` + `combat.js` (inclusi: tregua, milizia QG e locale, occupazione, riorganizzazione, mercato,
carte e OPS, obiettivi, rifornimenti, petrolio, ponte aereo, cattura QG, vittoria).
```gdscript
Game.new(opts: Dictionary)  # opts = {players:[{faction:int, human:bool, difficulty:String}], mode:"conquista"|"obiettivo",
                            #         distribution:"regionale"|"casuale", seed:int, ask_defense:bool, auto_battles:bool}
signal event(name: String, data: Dictionary)   # stessi nomi segnale del JS: capture, battle, built, recruited, researched, card,
                                               # missile, eliminated, hqLost, victory, pending, reinforce, sabotage, golpe, trade
# stato pubblico (sola lettura per gli altri): time, speed, paused, over (null|{winner,reason}), human_idx,
#   players[i] = {idx, faction, fac, name, color:Color, human, difficulty, res:{..}, rates:{..}, tech, research, hq, alive, cards,
#                 card_cd, sets_traded, pool, next_reinforce, objective, low_oil, stats, market}
#   terr[i] = {idx, owner, forces, buildings:Array, building, queue:Array, sabotage, unrest, regroup, supplied}
#   divisions[] = {id, owner, from, to, forces, t, total, sea, airlift, retreat, x, y}   # x,y piano mappa
#   events[] = {time, text, type, player}, effects[] = {type, x, y, x2, y2, born, dur}, pending_battle (null|Dictionary), ais
func update(real_dt: float) -> void ; func step(dt: float) -> void
# interrogazioni e comandi: snake_case del SPEC JS (cost_for, can_afford, unit_available, can_recruit, can_build, valid_targets,
#   travel_time, owns_continent, continent_owner, territories_of, visible_forces, income_of, reinforce_amount, find_set, is_valid_set,
#   research_cost, set_value, market_price, send_division, recruit, build, research, place_pool, hire_mercs, play_cards, trade)
#   i comandi restituiscono {ok: bool, reason: String}
func resolve_pending_auto() ; func start_manual_battle() -> Dictionary ; func finish_manual_battle(result: Dictionary)
```
Le IA: `Game` crea `ai.gd` per i non umani **caricandolo dinamicamente** se il file esiste
(`if ResourceLoader.exists("res://scripts/core/ai.gd"): ais[i] = load(...).new(self, i)`), e chiama `ais[i].update(dt)` in `step`.
`class_name Combat extends RefCounted` con funzioni **static**: `combat_mods(game, p, role, terr, opts) -> Dictionary`,
`resolve_battle(att, def, mods_a, mods_d, rng) -> Dictionary`, `predict_battle(att, def, mods_a, mods_d) -> Dictionary`, `force_power(f) -> float`.

## IA — `ai.gd` (`class_name AIController extends RefCounted`) (Agente B)
Porta fedelmente `frontline/js/ai.js` (`_init(game, idx)`, `update(dt)`, `stats`). `tests/sim.gd`: partite tutte IA headless nelle
modalità come `frontline/tests/sim.js`; deve stampare vincitore, minuti, errori.

## BattleSetup / BattleResult (Dictionary, come il JS)
```
setup = {terrIdx, terrain (chiave TERRAINS), terrName, sea, seed,
         att:{player, name, color:Color, forces, mods, human}, def:{player, name, color:Color, forces, mods, human, bunkers}, support:{att, def}}
result = {att: forces, def: forces, winner: "att"|"def", retreated: bool, autoRest: bool}
```

## Battaglia 3D (Agente C)
- `scripts/battle/battle_sim.gd` (`class_name BattleSim extends RefCounted`): **porting di `frontline/js/battle.js`** (logica, IA interna,
  costanti già tarate, piano 1600×900) senza disegno: `_init(setup)`, `step(dt)`, `done`, `result`, elenco unità/proiettili/eventi leggibile
  dalla vista, comandi (`select_*`, `order_move`, `order_attack`, `order_attack_move`, `stop`, `barrage`, `retreat`, `auto_resolve`).
- `scenes/battle.tscn` radice `Node3D` con script `Battle3D`: `func start(setup: Dictionary)`, `signal finished(result: Dictionary)`.
  Terreno 3D (rilievi per tipo di terreno, materiali/shader realistici, strade, alberi/edifici/rocce), unità 3D che seguono la sim
  (altezza dal terreno, torrette che ruotano, rotori, ombre), effetti (traccianti, vampate, esplosioni, fumo, crateri, relitti),
  telecamera RTS (pan WASD/bordi/tasto centrale, zoom rotella con inclinazione, rotazione Q/E), selezione a riquadro con proiezione,
  ordini con tasto destro, HUD propria (CanvasLayer: forze per lato, selezione, pulsanti Seleziona tutto / Sbarramento / Risolvi in
  automatico / Ritirata / Pausa). Esc NON chiude. A fine battaglia: messaggio, poi `finished`.
- Scala vista: 1 px sim = 0.25 m (campo 400 × 225 m), entro un terreno più grande per non vedere il bordo.
- Demo per screenshot: se `Shot.arg("demo") != ""` la scena si avvia da sola con un setup di prova (es. `--demo=urbano`).

## Tabellone 3D (Agente D)
- `scenes/world_map.tscn` radice `Node3D` script `WorldMap`:
  `func bind(game)`, `func map_to_world(x: float, y: float) -> Vector3` (scala 0.1: mondo 160 × 90 unità, centro all'origine),
  `func set_selection(idx: int)`, `func set_targets(list: Array)` (dizionari {idx, sea, airlift}), `func set_marks(idxs: Array, color: Color)`,
  `func set_drag(from_idx: int, to_world: Vector3)` / `clear_drag()`, `func focus(idx: int)`;
  segnali `territory_clicked(idx: int, button: int, shift: bool)`, `territory_hovered(idx: int)`, `drag_released(from_idx: int, to_idx: int)`.
  Il `WorldMap` NON chiama comandi di gioco: li chiama l'interfaccia (E) sui segnali.
- Terreno: rilievo generato dai `blobs_px` (come `frontline/js/mapgen.js`: domain warp, distanza normalizzata), coste, catene montuose
  secondo il terreno (montagna/artico/deserto/foresta...), oceano con shader acqua; colore dei territori per proprietario
  (texture/ImageTexture aggiornata al cambio proprietà), confini, nomi (Label3D), rotte marittime tratteggiate (Bering passa dal bordo).
- Su ogni territorio: miniatura 3D (UnitModels) + numero unità (o "?"), stella QG, icone edifici, anello costruzione/coda, segnale
  sabotaggio/senza rifornimenti/occupazione. Divisioni in viaggio come colonne di mezzi in movimento (archi sul mare).
  Effetti `game.effects` (esplosioni, missili, catture). Telecamera RTS (pan, zoom fino a vedere da vicino il rilievo, rotazione).
- Demo per screenshot: `--demo=1` crea una partita solo IA e la fa avanzare (se `Game` esiste).

## Interfaccia e flusso (Agente E)
- `scenes/main.tscn` + `scripts/main.gd`: menu iniziale → partita (WorldMap + HUD) → battaglia (istanzia `battle.tscn`, nasconde/sospende
  la mappa) → ritorno. Ciclo: `game.update(delta)` in `_process` (non durante la battaglia).
- UI con Control (tema scuro militare coerente, font leggibili, 1600×900 adattivo): barra risorse, ricerca, velocità (½×,1×,2×,3×),
  pausa, pannello giocatori/continenti/rinforzi/tregua/mercato/obiettivo, pannello territorio (forze, edifici, reclutamento ×1/×5,
  coda, quota invio, mercenari, schiera qui), carte e OPS con selezione bersaglio sulla mappa, pool rinforzi, registro eventi, toast,
  modale battaglia (previsione + Automatica/Comanda), riepilogo, vittoria/sconfitta, menu di pausa, guida F1. Tutto come il prototipo
  (`frontline/js/ui.js`), ma con look curato.
- `Sfx` autoload: suoni sintetizzati (AudioStreamGenerator o campioni generati in codice) con gli stessi nomi del JS.
- Demo per screenshot: `--demo=menu`, `--demo=game` (partita avviata con pannello aperto).

## Modelli ed effetti (Agente F) — API da consegnare SUBITO (anche provvisoria), poi migliorare
```gdscript
class_name UnitModels   # static
static func build(kind: String, color: Color, lod: int = 0) -> Node3D
#  kind: "inf" (squadra 4–5 soldati), "tank", "art", "aa", "heli", "jet", "drone", "bunker", "truck"; dimensioni reali in metri,
#  avanti = -Z, origine a terra. Nodi figli con nome (se esistono): "Turret" (yaw), "Barrel" (pitch), "Rotor" e "TailRotor" (spin),
#  "Muzzle" (Marker3D in punta alla canna), "Body". Colori: vernice militare con tinta/insegne della fazione ben riconoscibili.
static func miniature(kind: String, color: Color) -> Node3D   # versione "pedina" per il tabellone, con basetta
static func wreck(kind: String) -> Node3D                      # relitto bruciato
class_name Props        # static: tree(kind: "pine"|"broadleaf"|"palm"|"dead", rng) -> Node3D, tree_mesh(kind) -> Mesh (per MultiMesh),
#   rock_mesh(rng) -> Mesh, building(size: Vector3, style: String, rng) -> Node3D ("block"|"house"|"industrial"), crater() -> Node3D
class_name Vfx          # static, nodi auto-liberanti: explosion(parent, pos, size), muzzle_flash(parent, pos, dir),
#   tracer(parent, from, to, color), smoke(parent, pos, duration), dust(parent, pos), shell_trail(parent, from, to, time)
```
`scenes/model_gallery.tscn`: galleria di tutti i modelli ed effetti (per screenshot e controllo qualità).

---
# FASE 2 — rifinitura, funzionalità, design (dalle 13:15)
Stesse regole operative (semaforo Godot, un processo alla volta, screenshot ≤ 960x540, guarda le immagini). Stessa proprietà dei file
della fase 1 (A2 = file di A, C2 = file di C, ecc.), con le aggiunte sotto. Prima di modificare, rileggi i file attuali: sono cambiati.
Nuove interfacce condivise (rispettale alla lettera; se l'altro agente non le ha ancora consegnate, il tuo codice deve funzionare lo stesso
usando `get_node_or_null("/root/...")` / `ResourceLoader.exists` / `has_method`):

- **A2 — Salvataggi e cronologia** (`game.gd`, `ai.gd`, `combat.gd`, `tests/`):
  `game.serialize() -> Dictionary` (solo tipi JSON: niente Color/oggetti; include stato IA), `static func Game.deserialize(d: Dictionary) -> Game`,
  `game.history: Array` di istantanee ogni 10 s di gioco `{t, terr:[n per giocatore], power:[...], units:[...], income:[...]}` per i grafici,
  `game.stats_summary() -> Dictionary` per la schermata finale.
- **E2 — Impostazioni** autoload `Settings` (`scripts/core/settings.gd`, lo registra E2): `Settings.get_value(key)`, `set_value(key, v)`,
  `signal changed(key)`; chiavi: `quality` ("basso"|"medio"|"alto"), `fullscreen`, `vol_master`, `vol_sfx`, `vol_music`, `camera_speed`,
  `edge_scroll`, `show_names`, `autosave` (min). Salvate in `user://settings.cfg`. Mappa e battaglia devono leggere `quality`
  (ombre, MSAA, SSAO, densità vegetazione, risoluzione terreno) e reagire a `changed`.
- **F2 — Musica** `scripts/core/music.gd` (lo registra E2 come autoload `Music`): `Music.play(mood)` con mood "menu"|"map"|"tension"|"battle"|"victory"|"defeat",
  dissolvenza incrociata, `set_volume(v)`; musica generata in codice (niente file). **Navi**: `UnitModels.build("ship"|"transport", color)`
  e `UnitModels.miniature("ship", color)`.
- **E2** gestisce `project.godot` (autoload Settings e Music, finestra, icona) e il lanciatore `Gioca.bat` nella radice del progetto.

---
# FASE 3 — nuove funzionalità di gioco (dalle 14:05)
Stesse regole. Interfacce condivise (nucleo = A3; mappa D3, interfaccia E3 le consumano con controlli `has_method`/`has(...)` finché mancano):
- **Veterani**: `game.terr[i]["vet"]` int 0..3 (stelle), `division["vet"]`. Una vittoria (attacco o difesa) dà esperienza al territorio vincitore;
  fusioni = media pesata per unità (arrotondata per difetto); conquista porta la vet della divisione. +6% attacco per stella (dentro `combat_mods`
  tramite opts `vet`, quindi vale anche in battaglia manuale: `setup.att.vet` / `setup.def.vet`). Annuncio quando si guadagna una stella.
- **Nebbia di guerra**: `opts.fog` (bool, default true dal menu). `game.is_visible(viewer, t) -> bool` (propri + adiacenti ai propri; AAN +1 anello di
  adiacenza "radar"; divisioni visibili se partono o arrivano in territori visibili). `visible_forces(viewer, t)` → null se non visibile;
  `game.estimate_forces(viewer, t) -> int` stima arrotondata (multipli di 5, -1 se ignota). L'IA rispetta la nebbia (usa già le stime).
  Neutrali sempre visibili come forza approssimativa.
- **Diplomazia**: patti di non aggressione di 300 s. `game.pacts: Array[{a, b, until}]`, `game.has_pact(a, b) -> bool`,
  `game.propose_pact(from, to) -> {ok, reason, accepted}` (se `to` è IA decide subito: accetta se il proponente non è il leader e l'IA ha minacce
  maggiori altrove; ricarica 120 s per coppia), `game.answer_pact(ai_idx, human_idx, accept)` per le offerte delle IA al giocatore
  (segnale `event("pact_offer", {from, to})`; l'IA propone quando è in difficoltà), segnali `event("pact", {a, b, until})` e `event("pact_end", {a, b})`.
  Durante il patto `send_division` verso territori del partner è rifiutato ("Patto di non aggressione con X fino a mm:ss"); le carte OPS sul partner pure.
  Serializzazione: vet, fog e patti vanno in `serialize()`.

---
# FASE 4 — design e contenuti (dalle 15:16)
Stesse regole e proprietà dei file (A4 nucleo, C4 battaglia, D4 tabellone, E4 interfaccia, F4 modelli). Il gioco è collaudato e pulito
(vedi test nel README): ogni agente rilancia i test dei propri file prima di finire e non deve introdurre errori di script.
Nuove interfacce:
- **Mezzi per fazione** (F4): `UnitModels.build(kind, color, lod = 0, faction: int = -1)` e `UnitModels.miniature(kind, color, faction = -1)`;
  faction 0 AAN, 1 FO, 2 CP, 3 UL, -1 generico (neutrali). Ogni fazione ha sagome riconoscibili (UL: mezzi improvvisati/tecniche).
  Stessi nodi con nome (Turret, Barrel, Muzzle, Rotor...). C4 e D4 passano la fazione appena F4 consegna (controlla il numero di argomenti
  con `UnitModels.get_script_method_list()` o semplicemente chiama con 4 argomenti dopo aver verificato che F4 abbia finito: in alternativa
  controlla la costante `UnitModels.FACTION_STYLES` se esiste).
- **Fazione nel setup di battaglia** (A4): `setup.att.faction`, `setup.def.faction` (int, -1 neutrale).
- **Scenari** (A4 nucleo, E4 interfaccia): `scripts/core/scenarios.gd` con `class_name Scenarios` e `const LIST := [{id, name, desc, ...}]`;
  `Game.new(opts)` con `opts.scenario = id` (stringa; assente o "" = partita normale). Lo scenario può fissare partenze, forze iniziali,
  numero di giocatori, obiettivi, durata o regole speciali, ma sempre nel motore esistente.

---
# FASE 5 — battaglia tattica (scala R.U.S.E., visibilità, imboscate, corazze)
Proprietà: **sim/regole/IA/auto-risoluzione** = `scripts/battle/battle_sim.gd`, `scripts/battle/battle_rules.gd` (nuovo, `class_name BattleRules`,
statistiche per unità che sostituiscono `Data.UNITS[*].rts` in battaglia), `scripts/battle/battle_ai.gd` (eventuale), `scripts/core/combat.gd`,
`tests/test_battle.gd`, `tests/test_tactics.gd`. **Vista** (battle3d/hud/camera/terrain/props/fx/orders/coast) = agente vista.
`game.gd`, `ai.gd`, `scenarios.gd`, `data.gd` NON vengono toccati da questa fase.

## Contratto sim → vista (implementato alla lettera)
- **Dimensioni**: `sim.W`, `sim.H`, `sim.TOP`, `sim.BOTTOM` sono **variabili d'istanza** (non più costanti di classe):
  `W = 4800`, `H = 2700`, `TOP = 138`, `BOTTOM = 2544` (3× il vecchio piano 1600×900). La vista legge SEMPRE `sim.W/H/TOP/BOTTOM`
  (le espressioni `BattleSim.TOP` ecc. non compilano più). Raggi delle unità `u.r` invariati (in px, stessa taglia fisica): il campo è 3× più grande.
  Costanti di classe rimaste: `BARRAGE_R` (ora 160), `AIR_R` (ora 150), `SMOKE_*`, `AIR_*`, `BARRAGE_*`, `NO_DMG_HUMAN`, `IDLE/MOVE/ATTACK/AMOVE`.
- **Boschi attraversabili**: gli ostacoli `kind == "bosco"` NON bloccano più il movimento (sono aree di copertura, raggio `R`); le unità vi entrano
  (carri rallentati). La vista non deve spingere fuori le unità dai boschi; gli alberi in `o.trees` restano solo grafici (ora ~R²/200 alberi per bosco).
  Rocce/ghiaccio (`pts`) ed edifici (`rect`) restano bloccanti. Urbano: isolati 2× più grandi (`blocks`), strade larghe 60 px.
- **Unità** (`BattleSim.Unit`), nuovi campi:
  `spotted := [false, false]` (visibile al lato 0 / lato 1, aggiornato ogni ~0.25 s), `concealed := false` (ora nascosta dalla copertura),
  `view: float` (raggio di vista in px), `cover := 0` (0 aperto, 1 leggera: bosco/terreno accidentato, 2 pesante: città/bunker),
  `reveal_t := 0.0` (> 0: rivelata perché ha sparato), `ambush_t := 0.0` (> 0: bonus imboscata attivo), `deploy_t := 0.0` (artiglieria: > 0 si sta piazzando).
- `func visible_to(si: int, u) -> bool` (le proprie unità sempre true; con `si < 0` true). La vista mostra le unità nemiche solo se
  `visible_to(sim.hs if sim.hs >= 0 else 0, u)`; altrimenti al più il fantasma.
- `func cover_at(x: float, y: float) -> int` (0/1/2).
- `var ghosts := [[], []]`: per lato, ultime posizioni note dei nemici non più avvistati: `{id, type, x, y, t, g}` (`t` = istante in cui è stato perso),
  scadono dopo 20 s o quando l'unità torna visibile/muore.
- **Eventi fx** (array `sim.fx`, chiave `"e"` come gli altri eventi; la vista li consuma e li svuota):
  - colpo diretto (esistente): `{"e":"fire", "u":Unit, "t":Unit, "tx", "ty", "tair", "flank":"front"|"side"|"rear"|"", "ambush":bool, "cover":int, "rocket":bool}`
    (`rocket` = fanteria che usa l'arma anticarro contro un mezzo corazzato entro 380 px: vista e audio mostrano il razzo)
    (`flank` = lato del bersaglio colpito, "" per fanteria/velivoli/bunker; `cover` = copertura del bersaglio). Artiglieria: `{"e":"fire","u":Unit,"art":true}` invariato.
  - `{"e":"spotted", "u":Unit, "id":int, "side":int, "x", "y", "first":bool}`: un'unità nemica diventa visibile al lato umano (`hs`, oppure lato 0
    se nessun umano); emesso a ogni passaggio nascosta→visibile, `first` = prima volta nella battaglia. `side` = lato dell'unità avvistata.
  - `{"e":"ambush", "u":Unit, "id":int, "side":int, "x", "y"}`: un'unità nascosta apre il fuoco e inizia un'imboscata (bonus ×2 per 4 s).
  - invariati: `kill`, `impact` (ora anche `"scatter": float` raggio di dispersione del colpo), `barrage`, `smoke`, `airstrike`, `bomb`.
- **Artiglieria**: stessa classe `Shell`; la dispersione è calcolata nella sim (`x1/y1` la includono già). Spara solo su bersagli avvistati
  (dal proprio lato) oppure su un punto: `func order_fire_area(x, y)` (selezione umana, solo artiglieria: fuoco d'area con dispersione larga,
  finché non riceve un altro ordine). Dopo ogni spostamento deve piazzarsi (`deploy_t`, 4 s) prima di sparare; torretta lenta.
- **Ordini umani**: API invariate (`select_*`, `order_move`, `order_attack`, `order_attack_move`, `stop`, `hold_position`, `human_barrage`,
  `human_smoke`, `human_air_strike`, `deploy_zone`, `deploy_place`, `retreat`, `auto_resolve`, gruppi). `order_attack` su un nemico non visibile
  → movimento d'attacco verso il punto. `unit_at(x, y, side)` ignora i nemici non visibili al lato umano.
- `auto_resolve()` ora **simula davvero** il resto della battaglia (entrambi i lati IA, senza fx, passo grosso) e mette in `result` l'esito vero
  (`autoRest: false`): la vista deve solo leggere `sim.done`/`sim.result` come prima.
- Regole (per HUD/guida; valori esatti in `BattleRules`):
  copertura contro il fuoco diretto: fanteria ×0.65 (bosco/rocce) / ×0.5 (città, trincea, bunker), e ×0.6 in più se spara un carro/contraerea;
  mezzi ×0.9 / ×0.8. Artiglieria e bombe sulla fanteria in copertura ×0.8 / ×0.6 (trincea ×0.4).
  Fanteria ferma (o lenta) in copertura: scoperta solo entro 240 px (bosco) / 190 px (città), mezzi entro 350/300, fumo 160;
  elicotteri e droni scoprono da 3× più lontano; la fanteria dentro boschi/città vede a 0.7×. Chi spara è rivelato per 4 s: fanteria in
  copertura solo entro 420/380 px, fanteria allo scoperto a vista × 1.5, cannoni di mezzi/bunker ad almeno 1600 px.
  Imboscata: il primo colpo da nascosta (dopo ≥ 12 s nascosta) dà ×1.6 per 5 s. Fanteria anticarro entro 380 px: ×5 contro mezzi corazzati
  se in copertura, ×1.4 allo scoperto (`fire.rocket = true`). Corazza: carri fronte ×1 / fianco ×1.6 / retro ×2.5; artiglieria e contraerea
  ×1 / ×1.25 / ×1.5; fanteria, velivoli, bunker nessuna. I mezzi che arretrano davanti al bersaglio vanno in retromarcia (`u.reverse`).
  Precisione del fuoco diretto che cala con la distanza (a gittata massima ×0.5–0.8), in movimento ×0.8–0.9. Artiglieria: dispersione
  25 px + 5.5% della distanza (fuoco d'area ×1.6), mira dove il bersaglio È (chi si muove spesso schiva), danno per colpo ×0.7, schegge 50 px,
  gittata minima 500, 4 s per piazzarsi dopo ogni spostamento, spara solo su bersagli avvistati (o sulle coperture: fuoco di preparazione).
  Carri in bosco: velocità ×0.45, vista ×0.55 (città ×0.75 / ×0.65). Letalità: scala del danno `K = 0.3` (×2.9 rispetto al JS) e cannone
  dei carri ×1.8 contro i mezzi corazzati (un colpo sul fianco/retro toglie ~1/3–1/2 di un carro): una battaglia 20 contro 20 dura 2–4 minuti.
  "Condizioni del giorno": ogni lato ±10% di danno (dal seed); iniziativa dell'attaccante ×1.4 sul danno (taratura: a forze pari su terreno
  misto il difensore vince ~60–70%, con 1.5× l'attaccante vince quasi sempre).
  Stallo (nessun danno per 90 s IA / 180 s con umano) o tempo scaduto: vince il difensore, salvo attaccante 1.1× più forte di ciò che resta
  (difensori in copertura contati ×1.5); un attaccante senza fanteria non può prendere un terreno tenuto da fanteria in copertura.

| Unità | Vel. px/s | Gittata | Vista | Corazza F/L/R | Note |
|---|---|---|---|---|---|
| Fanteria | 30 | 360 (AT 380) | 720 (in copertura 500) | — | si nasconde in copertura, imboscate, anticarro |
| Carri | 44 (bosco 20) | 1400 | 850 (bosco 470) | 1 / 1.6 / 2.5 | torretta 0.6 rad/s, scafo fermo 0.28 rad/s |
| Artiglieria | 30 | 500–3800 | 550 | 1 / 1.25 / 1.5 | dispersione, piazzamento 4 s, torretta 0.5 rad/s |
| Contraerea | 52 | 1100 | 900 (2200 contro velivoli) | 1 / 1.25 / 1.5 | debole a terra (matrice ×0.2–0.45) |
| Elicotteri | 130 | 750 | 1500 | — | ricognizione |
| Caccia | 260 | 550 | 1000 | — | passaggi d'attacco |
| Droni | 140 | 500 | 1800 | — | ricognizione |
| Bunker | — | 800 | 1000 | — | copertura pesante |

---
# FASE 6 — turni (strategia a turni stile Risiko; battaglie 3D restano in tempo reale)
Design: `docs/TURNS_DESIGN.md`. Proprietà: **nucleo** (`game.gd`, `ai.gd`, `scenarios.gd`, `data.gd`, test core/save/fase3/scenarios/sim) = agente nucleo;
**UI/mappa/main** = agente interfaccia; `combat.gd`/`battle_*` = agenti battaglia. Contratto (implementato alla lettera, aggiornato dal nucleo):

## Stato dei turni (sola lettura)
```gdscript
var round: int             # 1.. ; un round = ogni giocatore vivo ha giocato una volta
var current: int           # indice del giocatore di turno
var phase: String          # "rifornimento" | "attacco" | "spostamento"
var attack_used: bool      # attacco del turno già fatto (max 1)
var move_used: bool        # spostamento del turno già fatto (max 1)
var truce_rounds: int      # tregua: niente attacchi/OPS contro altri giocatori finché round <= truce_rounds (default 2)
var round_limit: int       # limite di round: scenari dal LIST; partite normali Game.ROUND_CAP (120) → vince il punteggio
var ai_step_delay: float   # s reali tra due azioni dell'IA (opts.ai_step_delay, default 0.8; 0 = istantaneo)
var time: float            # SOLO orologio di animazione (s reali, avanza in update se non in pausa): effetti, divisioni animate
var speed, paused          # compatibilità: paused ferma il ritmo IA; speed moltiplica il ritmo IA. Spazio = skip_ai_turn()
```
## Interrogazioni
- `is_human_turn() -> bool`, `current_player() -> int`
- `turn_status() -> {round, player, phase, attack_used, move_used, truce_rounds_left, human_turn: bool, next_player: int,
   round_limit: int, rounds_left: int (-1 senza limite), ai_turn: bool, waiting: "" | "battle"}`
- `can_attack(from, to) -> {ok, reason}` (giocatore = proprietario di `from`; deve essere di turno, fase rifornimento o attacco)
- `attack_targets(p, from) -> Array[{idx, sea}]` (confinanti via terra o rotta marittima, non propri, attaccabili adesso)
- `can_move(from, to) -> {ok, reason}`, `move_targets(p, from) -> Array[int]` (propri, collegati da territori propri; ponte aereo tra aeroporti a Tech 2)
- `can_fortify(p, t, kind) -> {ok, reason}`, `fort_cost(t, kind) -> Dictionary | null` (null = livello massimo), `fort_level(t, kind) -> int`
- `predict_attack(from, to, forces) -> {winner, attLeft, defLeft}` (pannello d'attacco; usa le forze visibili o stimate del difensore)
- invariati: `cost_for, can_afford, unit_available, can_recruit, can_build, research_cost, market_price, income_of` (ora **per turno**),
  `upkeep_of` (per turno), `reinforce_amount` (ogni turno), `visible_forces, estimate_forces, is_visible, territories_of, owns_continent, has_pact,
  pact_until (→ ROUND fino al quale vale, incluso), pact_cooldown (→ round mancanti), scenario_status, stats_summary, battle_mods`
## Comandi (tutti `{ok, reason, ...}`; rifiutati se non è il turno di quel giocatore)
- **Rifornimento** (solo `phase == "rifornimento"`): `recruit(p, t, unit, count)`, `build(p, t, key)`, `research(p)`, `place_pool(p, t, forces = null)`
  (null = tutto il pool, oppure un Dictionary di forze parziale), `hire_mercs(p, t)`, `trade(p, res, dir)`, `play_cards(p, idxs, op, target)`,
  `fortify(p, t, kind)` con kind `"trench" | "mines" | "bunker"`, livelli 0..3 (istantaneo, si paga).
- `end_phase() -> {ok, reason, phase}`: rifornimento → attacco → spostamento → fine turno (come `end_turn()`).
- **Attacco** `attack(from, to, forces: Dictionary) -> {ok, reason, pending: bool, result}`: 1 per turno; dalla fase rifornimento passa da sola ad "attacco";
  `forces` ≤ presidio e **almeno 1 unità resta** a casa; consuma petrolio (moveOil). Bersaglio vuoto: conquista immediata.
  Umano coinvolto (attaccante o difensore) e `opts.auto_battles == false` → `pending_battle` (vedi sotto) e la partita aspetta;
  altrimenti si risolve subito (`result` = esito di Combat.resolve_battle). Conquista: i superstiti entrano, `regroup` 1 turno, `unrest` 2 turni, carta.
  Sconfitta: i superstiti tornano subito in `from`.
- **Spostamento** `move(from, to, forces) -> {ok, reason}`: 1 per turno, tra territori propri collegati da territori propri (o ponte aereo); ≥1 unità resta;
  dopo uno spostamento non si attacca più (fase → spostamento). Da un territorio appena conquistato (`regroup > 0`) non si parte.
- `end_turn() -> {ok, reason}`: chiude il turno (da qualsiasi fase) e passa al prossimo giocatore vivo.
- `skip_ai_turn()`: completa subito il turno IA in corso (si ferma a una battaglia contro l'umano).
- `send_division(p, from, to, what)`: **stub di compatibilità** → `move` se `to` è proprio, altrimenti `attack` (what: frazione o forze).
- Battaglie: `resolve_pending_auto()`, `start_manual_battle() -> setup`, `finish_manual_battle(result)` invariati.
## pending_battle (null | Dictionary)
`{id, attacker, defender, terr, from, forces, sea, vet, xp, human_side: "att" | "def", [manual: true]}`. `human_side == "def"`: un'IA attacca
l'umano (prompt da difensore: "Difendi in prima persona" = start_manual_battle, con `setup.def.human = true`; "Risoluzione automatica" =
resolve_pending_auto). Durante un turno IA la battaglia ferma l'IA finché non è risolta; poi l'IA prosegue.
`opts.ask_defense = false` → le difese dell'umano si risolvono in automatico (default true).
## Fortificazioni `terr[i]["fort"] = {"trench": 0..3, "mines": 0..3, "bunker": 0..3}`
Costo del livello L (1..3) = `Data.FORT[kind]["cost"]` × L. Sabotaggio blocca. Alla conquista: trincee e mine a 0, bunker −1.
Battaglia: `setup.def.fort = {"bunker", "trench", "mines"}` (livelli); `setup.def.bunkers` = 3 se c'è l'edificio Fortificazioni (come prima;
la sim usa `max(bunkers, [0,2,3,5][fort.bunker])`). L'edificio "bunker" (Fortificazioni) resta come prima (+30% difesa nei mods) e si somma ai
livelli. Con BattleSim (battaglia 3D e auto-risoluzione tattica) i livelli li gestisce la sim; con la formula (previsioni, `Combat.tactical = false`,
battaglie oltre `TACTICAL_MAX_UNITS`) entrano nei mods tramite `Game.fort_mods` (per livello: trincee +6% hp di fanteria/artiglieria/contraerea
del difensore, mine −3% attacco dell'attaccante, bunker +4% attacco del difensore). `battle_mods(info, manual, fort = true)`.
Costi per livello (× L): trincee 40 denaro + 15 manodopera; mine 50 denaro + 40 acciaio; bunker 80 denaro + 90 acciaio.
## Produzione in turni (avanza a FINE turno del proprietario; il reddito arriva all'inizio del turno)
`terr.queue[] = {unit, t, total}` (t = turni fatti, total = turni; tutte le voci avanzano in parallelo), `terr.building = {key, t, total}`,
`player.research = {level, t, total}`. Turni in `Data.TURNS` (unità: inf 1, drone 1, tank/art/aa/heli 2, jet 3; edifici 1–3; ricerca 2/3/4).
`terr.regroup`, `terr.unrest`, `terr.sabotage` = turni rimanenti (int). `player.next_reinforce` = 0 (rinforzi a ogni turno nel pool).
## Eventi (segnale `event(name, data)`, oltre a quelli di prima)
- `turn_start {player, round}`, `phase {player, phase}`, `turn_end {player, round}`, `round {round}`
- `move {type:"move", player, from, to, forces}`, `attack {type:"attack", player, from, to, forces, defender}`,
  `fortify {player, terr, kind, level}`, `deploy {player, terr, forces}`, `pending {battle}` (come prima)
- `game.divisions`: ora solo **record di animazione** (stessi campi di prima `{id, owner, from, to, forces, t, total, sea, airlift, retreat, x, y}`,
  ~1.2 s reali, avanzano in update e spariscono): nessun effetto di gioco.
- `events[]` (log) ora `{time, round, text, type, player}`; `history[]` un'istantanea per round `{t: round, round, terr, power, units, income}`;
  `stats.eliminatedAt` = round.
## Scenari
`Scenarios.LIST[*].round_limit` (round; sostituisce time_limit), `rules.truce_rounds`, `rules.hold.rounds` (round consecutivi da tenere).
`scenario_status()` → `{text, progress, rounds_left (-1 senza limite), time_left (= rounds_left, compatibilità), [hold_owner, hold_left (round)]}`.
## Salvataggi
`SAVE_VERSION = 2`. `Game.deserialize(d)` → null per i salvataggi vecchi; `Game.last_load_error` (static String) contiene il messaggio in italiano
(«Salvataggio di una versione precedente (tempo reale): non compatibile con la modalità a turni»). Si salva anche a metà turno IA.

### Fase 5 — aggiunte (preparazione del difensore, fortificazioni, auto-risoluzione)
- **Setup** (retrocompatibile): `setup.def.bunkers` (int, come prima) e il nuovo `setup.def.fort = {"bunker": 0..3, "trench": 0..3, "mines": 0..3}`
  (livelli costruiti dal giocatore). Bunker = `max(def.bunkers, [0,2,3,5][fort.bunker])`; trincee = `fort.trench` linee spezzate davanti al
  fronte del difensore; campi minati = `2 × fort.mines`, sulle vie d'accesso nella metà del difensore. Chiave solo per test: `setup.clear = true`
  (campo aperto senza ostacoli). Con `mods.ctx` (vedi Combat) il bonus forfettario di difesa del terreno viene tolto: lo dà la copertura.
- **Stato leggibile dalla vista**: `sim.trenches = [{x0,y0,x1,y1}]` (trincea larga ~60 px: copertura 2, artiglieria sulla fanteria ×0.4),
  `sim.mines = [{x, y, r, charges, spotted:[bool,bool]}]` (il difensore li vede sempre; l'attaccante quando `spotted[0]`: da vicino,
  140 px oltre il raggio, 420 px con elicotteri/droni, o alla prima esplosione), `sim.forests` (i boschi, sottoinsieme di `obs`),
  `sim.cover_spots` (Vector2), `sim.fort`, `u.trench` (bool), `func in_trench(x,y)`, `func known_mine_at(si, x, y)`, `func zone_at(x,y)`
  (0 aperto, 1 bosco, 2 città), `func add_forest(x, y, R)`.
- **Nuovi eventi fx**: `{"e":"mine", "x", "y", "id"}` (esplosione sotto un mezzo), `{"e":"mines_spotted", "i", "x", "y", "r"}` (l'attaccante
  scopre il campo `sim.mines[i]`).
- **Schieramento**: `deploy_zone(si) -> Rect2` per entrambi i lati: attaccante `Rect2(120, TOP+42, 1680, …)` (il suo bordo), difensore
  **tutta la sua metà** `Rect2(W/2+150, TOP+42, W/2−270, …)`. `deploy_place(list, x, y)` funziona per il lato umano qualunque esso sia
  (anche il difensore: può mettere la fanteria nei boschi/città/trincee). Il difensore guidato dall'IA parte **già schierato**:
  fanteria nelle coperture davanti alla linea (preferendo quelle vicino alle strade: anticarro sulle vie d'accesso), carri e contraerea
  defilati in copertura dietro, artiglieria in fondo; tutti in "mantieni posizione".
- **Ordine `FIRE` (4)**: artiglieria in fuoco d'area su `(ox, oy)` (`order_fire_area(x, y)`); la vista può disegnarlo come un bersaglio d'area.
- **Auto-risoluzione** (`Combat.resolve_battle`, firma invariata): se i mods hanno `ctx` (li aggiunge `Combat.combat_mods`: `{ter, role, terr,
  sea, human, faction, bunkers, support, fort}` — `fort` letto da `game.terr[i].fort` se esiste) la battaglia viene **simulata con BattleSim**
  (IA contro IA, passo 1 s, niente fx, tetto 450 s di battaglia); il risultato ha `engine: "tactical"`, `ms`, `time`. Formula vecchia
  (`engine: "formula"`) per mods senza `ctx`, `ctx.engine == "formula"`, `Combat.tactical = false`, o oltre 240 unità totali.
  **Scelta misurata**: tempi tipici 100–200 ms (15 vs 10), 300–350 ms urbano 20 vs 14 e 60 vs 60; una partita IA a 4 completa
  (sim.gd) costa ~30–55 s reali invece di ~3 s ma resta fluida (≤ 1 battaglia per giocatore per turno): quindi tattica per TUTTE le
  battaglie, anche IA contro IA lontane dal giocatore (stesse regole ovunque); la formula resta come ripiego e per `predict_battle`.
  `predict_battle` resta la formula (stime veloci dell'IA strategica). `BattleSim.auto_resolve()` (pulsante in battaglia) simula il resto
  della battaglia e dà l'esito definitivo (`autoRest: false`).

## Fase 6 — interfaccia (consegnato dall'agente interfaccia)
- `WorldMap.turn_arrow(from, to, owner, kind = "attack"|"move", dur, forces = null)`: freccia animata che si allunga + colonna di pedine
  (nascosta se `game.divisions` ha già il record d'animazione della stessa mossa); `clear_turn_anims()`. Il giorno/notte a turni mette
  il mezzogiorno sul QG del giocatore di turno (transizione morbida), `game.time` resta solo orologio delle animazioni.
- `Settings`: `ai_follow` (bool, telecamera sulle mosse IA visibili), `ai_speed` ("lenta"|"normale"|"veloce"|"istantanea") →
  `Settings.ai_step_delay()` = 1.6/0.9/0.4/0 s, passato in `opts.ai_step_delay` e aggiornato live su `game.ai_step_delay`.
- Spazio nel turno IA: prima accelera (dt ×6 in `update`), di nuovo → `skip_ai_turn()`. Invio = `end_turn()`.
- Salvataggi: metadato `round`; `Game.last_load_error` mostrato come toast.
## Fase 6 — interfaccia chiara (UX, agente interfaccia; piano in `docs/ux_plan.md`)
- HUD: riquadro **ORDINI** in basso al centro (`hud.guide`, testo da `main.guide_state()`, pulsante principale contestuale
  `hud.g_main`: «Fase successiva: Attacco ›» / «Salta attacco ›» / «Fine turno ✓» / «Accelera»), esito delle azioni con `main.feedback()`.
  Barra a icone a sinistra (`hud.rail`, `hud.toggle_tab(k)`, k = obj|players|cards|market|conts|log) con cassetto chiuso di default;
  niente più barra inferiore. Pannello territorio a schede (`hud.rtab` = recruit|build|fort, solo rifornimento sui propri territori).
- Tabellone: `set_marks` evidenzia ciò che è cliccabile adesso (verde schieramento, ambra origini d'attacco, azzurro spostamenti:
  `main.click_marks()`). Nel rifornimento con rinforzi lo schieramento è attivo da solo (un clic = `place_pool` tutto).
- Tutorial guidato `scripts/ui/coach.gd` (`main.coach`, `main.start_tutorial()`, Settings `tutorial_done`); `tutorial.gd` resta
  per i suggerimenti di battaglia/carte/ricerca. Toast max 2.
## Fase 6 — richieste UI
- (nessuna bloccante) Gradito: `predict_attack` con un campo `estimate: bool` quando usa forze stimate nella nebbia (oggi l'interfaccia lo deduce da `is_visible`).
## Valori delle regole a turni (nucleo, FASE 6)
- Reddito e mantenimento per turno = tassi "al secondo" del prototipo × `Data.TURN_SECS` (45). Rinforzi ogni turno: max(4, territori/2) + bonus
  continenti (+3 FO). Milizia QG +2 FAN (fino a 6 unità), presidio locale +1 FAN (sotto 3, rifornito, non occupato).
- Tregua 2 round; occupazione 2 turni (niente reddito); riorganizzazione fino a fine turno; sabotaggio 2 turni; patti 5 round, ricarica 3 round,
  offerte valide fino al round successivo; limite di 120 round (vince chi ha più territori).
- Carte: una a ogni conquista per attacco (non per golpe); chi elimina un giocatore ne prende le carte. Il golpe lascia almeno 1 FAN.
- Bilanciamento FASE 6 (data.gd): Oceania bonus 3, Sud America bonus 1; UL fanteria −10% e difesa +10% in città/foreste; mercenari 300 $;
  FO +3 FAN a ogni rinforzo e +25% denaro (mod `moneyMul`).

---
# Fase 7 — rilievo dei campi di battaglia (agente terreno)
Proprietà: `scripts/battle/battle_relief.gd` (nuovo, `class_name BattleRelief`), `battle_terrain.gd`, `battle_props.gd`, `battle_coast.gd`,
`terrain_ground.gdshader`; nella sim solo generazione mappa/quote/linee di vista; costanti `LOS_*`, `HIGH_VIEW_*`, `WADE_*` in `BattleRules`.
Test: `tests/test_tactics.gd` (`t_relief`: creste, posizione dominante, fuoco diretto, fiumi), `tests/bench_relief.gd` (tempi), `tests/dump_relief.gd`.

## Funzione d'altezza condivisa (sim e vista)
- `BattleRelief.new(tkey, seed, W, H, TOP, BOTTOM, sea, coast_ph, flat, roads)` è costruita in `BattleSim._gen_map` (`sim.relief`) e la vista
  la riusa (`BattleTerrain.build` → `relief = s.relief`): **stessa quota** per regole e grafica. `flat` (= `setup.clear`, test) o
  `BattleRelief.disabled = true` (confronti, `--flat=1` in test_tactics) → campo piano.
- `relief.h(x, y)` quota esatta in metri nel punto (px sim, anche fuori campo); `relief.height(x, y)` bilineare sulla griglia `G = 60 px` (15 m)
  usata dalla sim; `sim.height_at(x, y)`. Vista: `terrain.height(X, Z)` (mondo) = `relief._pre` + micro-ondulazioni + rilievi fuori campo
  + cumuli degli ostacoli + costa (`shore`), campionata su una mesh a passo 3 m (chunk 110×90 vertici, colori dei vertici: AO/cresta/alveo/ghiaccio).
- Rilievi per terreno: **pianura** colline dolci (13 m noise + 2 colline 12–19 m) e un **fiume** a meandri (alveo 34 px, valle 470 px, 1.6 m);
  **foresta** ondulata + torrente; **montagna** due creste trasversali 42–56 m con **valichi** sulle strade (+ ridged noise 8 m);
  **deserto** dune asimmetriche, 3–4 **mesas** 16–25 m (mai sulle strade) e un **uadi** asciutto; **artico** cumuli di neve + **lago ghiacciato**
  (ellisse, passabile); **urbano** quasi piano + **terrapieno** 3.4 m davanti alla città; **costa** (`sea`): spiaggia, poi falesie con varchi
  sulle strade. Quote tipiche in campo: pianura −5–34 m, montagna 4–97 m, deserto −2–37 m, artico −2–41 m; pendenze fino a 20–37°.
  Parametri in `BattleRelief._generate` (ampiezze `a1/a2/ad`, `_hill/_ridge/_mesa/_lake/_river`); `tests/dump_relief.gd` stampa i profili.
- Fiumi: `relief.rivers[i]` = `{x, a1, f1, p1, a2, f2, p2, cw, vw, depth, water, bed, fords, xings}`; `river_x(rv, y)`, `river_dist(rv, x, y)`,
  `river_floor(rv, y)` statiche. **Attraversamenti** `rv.xings = [{k: "bridge"|"ford", x, y, dir, half}]`: un ponte dove passa ogni strada
  (max 2 per strada), un guado (fondo alzato: `fords`). `relief.water_at(x, y)` / `sim.water_at` = 0 asciutto o su ponte/guado, altrimenti 0..1.

## Regole (BattleRules)
- **Linee di vista**: `relief.los(x0, y0, x1, y1)` (cache per celle 60 px, raggio a passi di 45 px, occhi a `LOS_EYE = 2.2 m`, tolleranza
  `LOS_TOL = 0.25 m`). In `_upd_vis` un nemico a terra entro il raggio di vista è avvistato **solo se la linea è libera** (velivoli: sempre);
  `_find_target` e il fuoco diretto (non artiglieria) richiedono la linea di vista: un carro dietro una cresta non spara e non è ingaggiato
  anche se un elicottero lo vede. `sim.has_los(x0,y0,x1,y1)`, `sim.los_units(a, b)`.
- **Posizione dominante**: chi guarda da `dh` m più in alto vede più lontano verso il basso: vista × `(1 + min(0.3, dh × 0.015))` (+30% a 20 m).
- **Fiumi**: fuori da ponti e guadi fanteria × `WADE_INF = 0.4`, mezzi × `WADE_VEH = 0.15` (quasi fermi). I **mezzi** che devono passare
  il fiume puntano da soli all'attraversamento più comodo (`relief.crossing_target(x0, y0, x1, y1)` in `_move_to`: imbocco sulla
  propria sponda, poi uscita sull'altra); la fanteria guada dove si trova. Uadi e lago ghiacciato: nessuna penalità.
- Tempi misurati (`bench_relief.gd`, `test_tactics --only=timing`): costruzione griglia 6–14 ms per battaglia; costo per passo di simulazione
  invariato (~0.55 ms/passo 15v10, cache LOS: ~90 raggi per battaglia); le battaglie in pianura durano ~1.3–1.6× di più (avvicinamenti coperti),
  quindi `Combat.resolve_battle` tipico 15v10 ≈ 125–150 ms (era ≈ 95–100), 60v60 ≈ 290 ms (era 240).

## Vista (BattleTerrain)
- Shader `terrain_ground.gdshader`: materiali per pendenza (`rock_slope` per terreno: roccia da ~17–25°), neve sopra `snow_line`, variazione
  macro del colore, campi coltivati (`field_tex` in riferimento ruotato `field_xf`, 5 colture, bordi siepe/capezzagna), alvei (fango/ghiaia),
  lago ghiacciato, strade sterrate con bordi, crateri (`scorch_tex`), AO cotta + ombreggiatura del rilievo sempre attiva, **vista d'insieme**
  (`overview` 0..1, impostato da `update_view(cam_dist, dt)`: hillshade, curve di livello ogni 5 m, strade marcate), nebbia tattica, anelli.
- Pianura/foresta: patchwork di campi (`_build_fields`), siepi di cespugli con alberi, staccionate, capezzagne (nella maschera strade);
  `terrain.hedges` = `[a, b, kind]` (0 siepe, 1 capezzagna, 2 staccionata). Fiumi: nastro d'acqua (`_river_water`), **ponti** (`terrain.bridges`,
  impalcato + pila, spalle nel rilievo), guadi con pista sterrata. Punti di riferimento (`_build_landmarks`, MultiMesh di `BattleProps.landmark_mesh`):
  fattorie (casa, fienile, silo, staccionata), borghi (case/baite/case di fango), rovine ai margini, linea elettrica lungo la strada principale;
  margini dei boschi con cespugli e alberelli; cespugli sparsi in campo. Fuori dal campo (14 m di margine) gli edifici non toccano la sim.
- Prestazioni: mesh a blocchi (culling), MultiMesh per tutto (erba fino a 125 m, siepi/staccionate/fili fino a 520 m, alberi 1400 m),
  nessuna ombra sul suolo salvo montagna.

## Hook per l'agente FX/meteo/distruzione (Fase 8)
- `terrain.deform_crater(x_sim, y_sim, r_px, depth_m = 0.7)`: cratere **vero** nella mesh (conca + bordo rialzato), aggiorna `terrain.height()`
  (unità/relitti seguono il buco), ricostruisce i blocchi toccati uno per frame in `update_view`. Solo vista (la quota della sim non cambia).
  Abbinare a `terrain.paint_crater(x, y, r)` (bruciatura nella texture). Dentro la zona regolare (`INNER_HX/HZ`).
- `terrain.surface_at(X, Z) -> String`: "water", "ice", "mud", "gravel", "sand", "snow", "rock", "asphalt", "concrete", "dirt", "field",
  "forest", "grass" (polvere/fango/neve sollevata, schizzi d'acqua, suoni dei passi).
- `terrain.landmarks` = `[{kind, pos, yaw, size}]` (house/barn/silo/hut/chalet/ruin/bridge): per distruzione/incendi; `terrain.bridges`;
  `terrain.hedges`; `terrain.woods` (`{c, r, h, nodes}`); `sim.relief.rivers` / `relief.lake`; `terrain.normal(X, Z)` per orientare decalcomanie.
- `terrain.update_view(cam_dist, dt)` è chiamata ogni frame da `Battle3D._process` (sostituisce `update_scorch`): aggiungere lì eventuali
  aggiornamenti del suolo. Il materiale è `terrain.terrain_mat` (ShaderMaterial): parametri `fog_tex/fog_on`, `rings`, `overview`, `scorch_tex`.
- `BattleProps.ext(cls)` ora ignora le classi esterne che non compilano (segnaposto al loro posto): si può lavorare su `scripts/models/*`
  senza bloccare le battaglie.

---
# Fase 8 — meteo, ora, segni della battaglia, distruzione, modalità foto (agente FX)
Proprietà: `scripts/battle/battle_weather.gd` (nuovo, `class_name BattleWeather`), `scripts/battle/battle_marks.gd` (nuovo,
`class_name BattleMarks`), `battle_fx.gd`, `battle_camera.gd` (modalità foto), `battle_hud.gd` (pulsante Foto, pannello),
`battle3d.gd` (ambiente, eventi fx, foto, demo), parametri di `terrain_ground.gdshader`, `scripts/core/sfx.gd` + `battle_audio.gd`
(ambiente), aggiunte minime a `battle_sim.gd`/`battle_rules.gd`. Test: `tests/test_weather.gd`.

## Meteo nella sim (regole)
- `setup.weather`: assente/"" → **sereno fisso** (test, `Combat.resolve_battle` strategico: il meteo non tocca la formula né
  l'auto-risoluzione dal tabellone); `"auto"` → piano dal seed (`BattleRules.weather_plan(seed, tkey)` → `{start, changes:[[t_s, kind]]}`,
  al più un cambiamento tra 70 e 200 s: nebbia che si dirada, pioggia che arriva/smette, temporale→pioggia, neve→sereno);
  oppure il nome di una condizione. **La vista 3D imposta sempre `"auto"`** se la chiave manca (`Battle3D.start`), quindi la
  battaglia giocata e il suo pulsante «Risolvi in automatico» (stessa sim) hanno lo stesso meteo, deterministico dal seed.
- Condizioni e moltiplicatore **unico** della vista di tutte le unità (`BattleRules.WEATHER_VIEW`): sereno 1 · pioggia 0.72 ·
  temporale 0.6 · nebbia 0.42 · neve 0.68 · notte 0.55. Applicato in `_upd_vis` (`u.view = view0 × meteo × bosco/città`,
  velivoli compresi). Pesi per terreno in `WEATHER_W` (artico: niente pioggia, neve 44%; deserto: sereno 66%).
- Stato leggibile: `sim.weather` (kind), `sim.weather_view_mul`, `sim.weather_sched`, `sim.flares`, `sim.rubble`;
  `sim.set_weather(kind, announce = true)` → evento fx `{"e":"weather","kind"}`.
- **Notte**: ogni lato lancia un **razzo illuminante** ogni 22–34 s (`FLARE_CD`, RNG della mappa: deterministico) sul nemico
  avvistato più vicino, su un fantasma o davanti al proprio fronte: `sim.add_flare(x, y, side)` → evento `{"e":"flare","x","y","side","t"}`;
  per `FLARE_T` = 16 s entro `FLARE_R` = 620 px la vista sui bersagli torna piena (`lit_at`), poi il buio ricade.
- **Macerie**: `sim.add_rubble(x, y, r_px)` (chiamata dalla vista quando un edificio crolla in campo) alza la griglia di copertura
  a `RUBBLE_COVER` = 2 nelle celle toccate (copertura pesante per la fanteria; costo trascurabile).

## Vista (BattleWeather / BattleMarks / Battle3D)
- `Battle3D._build_env` sceglie l'atmosfera (`mood`: mattino, pomeriggio, tramonto, coperto, **notte** se il meteo è notte;
  con pioggia/temporale/neve → coperto) e salva i valori di base in `_env_base`; `BattleWeather` li modula con dissolvenza (~6 s)
  secondo `MOD[kind]` (foschia ×, sole ×, ambiente ×, saturazione, colori di cielo/foschia, `hold` = quanto la nebbia resta anche
  nella vista d'insieme), gestisce pioggia/neve (GPUParticles sulla telecamera, schizzi a terra vicino), fulmini (`thunder_queue`
  per l'audio), razzi illuminanti (OmniLight con ombre solo sul più vicino, bagliore, discesa col paracadute e deriva col vento),
  `wetness` (sale in 25 s di pioggia, asciuga in 3 min) e `snow_cover` (si accumula in 2 min) → shader del suolo; `fx.wind`.
- Shader `terrain_ground.gdshader`, nuovi parametri: `track_tex/track_on` (solchi: r terra smossa, g fango/neve pressata),
  `wetness` (suolo scuro e lucido, pozzanghere nelle conche), `snow_cover`, `relief_k` (ombreggiatura del rilievo e AO più
  marcate: 1.2 di giorno, 1.35 coperto/notte, 1.5 artico). Grading in `_build_env`: contrasto 1.12–1.2, saturazione 0.9–1.22 per atmosfera.
- `BattleMarks`: texture dei solchi (0.25 m/texel sul campo) dipinta ogni 0.2 s sotto i mezzi in movimento (anche durante
  l'avanzamento rapido delle demo); fango/neve sollevata dietro i cingoli; coda dei **crateri veri** (`terrain.deform_crater`, uno ogni
  0.12 s) per colpi d'artiglieria, bombe, mezzi distrutti; indice spaziale dei distruttibili costruito dai MultiMesh del terreno
  (edifici `LM_*`, isolati urbani, alberi, siepi, staccionate): `blast(p, r, dmg, silent)` → edifici a 3 stadi (annerito e fumante →
  crollo parziale → macerie con nube di polvere, detriti, eventuale incendio di 60–100 s, `sim.add_rubble`), alberi abbattuti
  (anche dai carri che li travolgono; restano a terra), siepi e staccionate schiacciate. `marks.fires` (focolai) per l'audio.
- `BattleFx`: `night_k` (di notte luci di spari/esplosioni ×2.4 e traccianti più larghi), `wet/snowy` (polvere → fango/neve),
  esplosioni più grandi e luminose (OmniLight 9×s per 0.34 s, 8 luci in pool), `collapse`, `tree_fall`, `mud_splash`, `snow_spray`, `splash_drop`.
- **Modalità foto** (F10, pulsante «Foto»): `Battle3D.set_photo` mette in pausa, nasconde l'HUD (`hud.set_photo`), telecamera
  libera (`BattleCamera.set_photo`: WASD, Q/E, tasto destro + mouse, Maiusc veloce, rotella FOV), pannello con cursori Sfocatura
  (CameraAttributesPractical, fuoco sul terreno al centro) e Vignetta, «Scatta» (Invio/F12) → `user://screenshots/foto_<data>.png`
  (toast col percorso), Esc esce. Solo da input: i test non la attivano.
- Audio (`battle_audio.gd`, banchi in `sfx.gd`): pioggia (`amb_rain`, livello dall'intensità), grilli di notte (`amb_crickets`, non nel
  deserto/artico: lì vento più forte e grave), uccelli al mattino quando è tranquillo (`amb_birds`), risacca vicino alla costa
  (`amb_surf`), 2 sorgenti posizionali di incendio (`amb_fire`) sui relitti/macerie più vicini, tuoni (`amb_thunder`, 3 varianti)
  1–5 s dopo il lampo, vento modulato dal meteo. Tutto in loop sintetizzati nel thread di lavoro (22,05 kHz, giunte pulite).
- Demo/screenshot: `--weather=kind --wet=1 --snowcover=1 --flare=1 --boom=t1,t2 --boomf=f1,f2 --cam=farm --photo=1`.
