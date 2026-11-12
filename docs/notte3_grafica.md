# Notte 3 — agente GRAFICA (2026-11-11/12): mezzi veri e scontro leggibile

Misure a 1920×1080, GTX 1070, demo `campale` (60 contro 60), `--weather=sereno`, `--fps=1 --prof=1` (riga `[gpu]`).
Screenshot in `docs/screens/notte3/`. Contratto aggiornato in `SPEC3D.md` (sezione «Notte 3 — grafica»).

## 1. Modelli 3D veri dei mezzi
Scaricati fuori dal progetto, licenza riletta sulla pagina di ogni modello, convertiti con `tools/modelli/convert.py`
(+ `glbkit.py`: Python e numpy, **senza Blender** che su questo PC non c'è): trasformazioni e skin cotte a riposo, assi Y su /
avanti −Z, origine a terra, parti rinominate `Body / Turret / Barrel / Muzzle / Rotor`, superfici per ruolo (vernice, metallo,
cingoli, vetro, colore di fazione). Nel gioco: `assets/models/<kind>[_f<fazione>].glb` con ripiego sul modello in codice
(`UnitModels.ext_path`), vernice e mimetica della fazione con `paint.gdshader`, cingoli che scorrono, usura, fango, relitto;
insegne di fazione generate (pannello sul tetto, fascia sulla torretta, strisce sui parafanghi); livelli di dettaglio
automatici (`ImporterMesh.generate_lods`). Crediti: `assets/models/LICENZA.txt`, `PER_INIZIARE.md`; la voce «Crediti»
nell'interfaccia è chiesta a TABELLONE in `docs/notte3_richieste.md` (**obbligo CC-BY: da fare prima di distribuire**).

| File | Modello | Autore, licenza | Triangoli | Usato per |
|---|---|---|---|---|
| `tank_f0.glb` | Tank (poly.pizza/m/FA5daiyZQq) | Quaternius, CC0 | 7 222 | carro AAN |
| `tank.glb` | Tank (poly.pizza/m/jWS1CLA0RO) | Quaternius, CC0 | 6 064 | carro FO e neutrali |
| `tank_f3.glb` | Tank (poly.pizza/m/cW3zvvkMOM) | Quaternius, CC0 | 6 544 | carro UL |
| `aa.glb` | Light Tank (poly.pizza/m/S1jUTRmAjD) | Zsky, CC-BY 3.0 | 3 088 | contraerea semovente AAN, FO, neutrali |
| `heli.glb` | Helicopter (poly.pizza/m/hG2Qr0A3zR) | Zsky, CC-BY 3.0 | 1 088 | elicottero, tutte le fazioni |
| `jet.glb` | Jet (poly.pizza/m/6fyLMORhgGK) | jeremy, CC-BY 3.0 | 1 434 | caccia, tutte le fazioni |

Scartati o non scaricabili (dalla lista di `docs/modelli_candidati.md`):
- **Abrams (15k) e T-72 di Sketchfab**: il download richiede l'accesso con un account Sketchfab → non scaricati.
- **Modelli freeciv (.blend)**: servirebbe Blender per esportarli → non usati.
- Tank Quaternius n. 4 (`Dc4k4CooN3`): stile giocattolo, stona. Helicopter di jeremy: elicottero civile. Military Boat di
  Zsky: è un gommone, le nostre navi sono lunghe 120 m. Restano in codice: fanteria, artiglieria, camion, droni, navi, bunker,
  il carro e i mezzi su ruote della Coalizione del Pacifico, la contraerea su ruote di CP e UL.

Prima/dopo ravvicinati: `prima_mezzi.png` / `dopo_mezzi.png` (tutte le fazioni), `confronto_carri.png` e
`confronto_aa_eli_caccia.png` (dietro il modello in codice, davanti quello esterno).
Giudizio onesto: i carri esterni hanno cingoli e ruote modellati e sagome più credibili da vicino; elicottero e caccia
esterni sono più semplici dei nostri in codice e uguali per tutte le fazioni (si distinguono solo per la vernice): se al
mattino si preferiscono quelli in codice basta togliere `heli.glb` / `jet.glb` (o `UnitModels.use_ext = false`).

Costo misurato (obiettivo: non oltre +0,5 ms a Media in 60 contro 60):
- galleria `--demo=crowd` (120 mezzi, 1080p, Media): modelli in codice 6,42 / 6,59 ms → esterni 6,27 / 6,28 ms;
- battaglia campale ferma allo schieramento (1080p, Media): `--ext=0` 13,05 ms → esterni 12,97 ms.
I modelli esterni **non costano niente in più** (−0,1 ms): i carri hanno più triangoli (6–7 mila contro 4–6,5 mila) ma i
livelli di dettaglio automatici li alleggeriscono a distanza di gioco, ed elicottero e caccia sono più leggeri dei nostri.

## 2. Gettoni «?», rivelazione, eventi (richieste di BATTAGLIA)
File nuovo `scripts/battle/battle_signs.gd` (`BattleSigns`), creato da `BattleMarks.setup`: **nessuna modifica** a
battle3d / battle_hud. Legge la sim ogni frame:
- contatti «?» (`is_contact_unit`): sagoma generica traslucida con righe di scansione nel colore del lato (`segni_contatti.png`);
- rivelazione (`reveal_t`): lampo e anello tratteggiato che si stringe e si spegne in 6 s (rosso nemici, ambra le proprie);
- `sim.pending`: attacco aereo = cerchio rosso che pulsa sempre più in fretta + fumogeno rosso; rinforzi = frecce a spina
  dal bordo + polvere (`segni_rinforzi.png`);
- obiettivo minacciato: anello che si riempie con il tempo di conquista.

## 3. Notte, paesi, artico
- **Paesi con strade interne**: via principale, traverse e parallele (maglia nelle cittadine), case affacciate sulle vie
  (`sereno_cittadina.png`); lampioni con palo lungo la via principale.
- **Luci notturne**: punti luce che non scendono mai sotto ~3 px (un paese lontano è una manciata di luci), pozze di luce
  più forti, finestre più luminose; le strade a strisce di notte si spengono con il suolo (`notte_cittadina.png`,
  `notte_strategica.png`).
- **Artico**: fuori dal campo roccia scura sui versanti, tundra sulle dorsali, lastre di ghiaccio azzurro, ombre fredde
  (`artico_strategica.png`).

## 4. Prestazioni
Fatto: **livelli di dettaglio automatici degli alberi** (pista della notte 2: livello intermedio tra 150 e 480 m). Il modello
vicino porta i LOD di `ImporterMesh`, il motore li sceglie blocco per blocco; `lod_bias` 0,8 / 0,35 / 0,25 su alto / medio /
basso. Confronto: `--treelod=0`.

Vista di gioco (`--cam=army`), GPU ms per finestre di 5 s dall'inizio della battaglia; «prima» = stessa battaglia di stanotte
con `--treelod=0 --ext=0` (resa della notte 2), «dopo» = resa attuale:

| Qualità | Prima (0–5 s / 5–10 s / 10–15 s) | Dopo (0–5 s / 5–10 s / 10–15 s / 15–20 s) | Differenza |
|---|---|---|---|
| Basso | 7,13 / 7,79 / 6,49 | 6,08 / 6,68 / 5,93 | **−1,0 ms** |
| Medio | 12,07 / 13,64 / 11,28 | 11,58 / 13,05 / 10,65 — ripetuta: 11,57 / 12,77 / 11,33 / 9,65 | **−0,5 ms** |
| Alto | 15,04 / 16,34 / 14,12 | 14,12 / 15,44 / 14,06 | **−0,6 ms** |

Stessa scena ferma allo schieramento (misura ripetibile a ±0,1 ms), Media: 13,44 → **12,97 ms** (alberi −0,45; modelli −0,1).

**Obiettivo «≤ 10,5 ms a Media» — non dimostrato.** Il 10,7 della notte 2 era misurato sulla battaglia di ieri; con le
regole nuove di BATTAGLIA gli schieramenti sono più vicini e lo scontro parte subito, quindi nei primi 10 secondi
l'inquadratura `army` ha più mezzi, ombre ed effetti: oggi la stessa misura dà 11,6–13,0 ms nei primi 10 s e 9,7–10,7 ms
dopo. A parità di scena la resa è più leggera di 0,5 ms (10,7 → ~10,2 equivalenti), ma il numero assoluto dipende dal
momento. Controlli fatti: senza fumo e bagliori (`--fxoff=1`) cambia 0,1–0,2 ms, senza i segni nuovi (`--segni=0`) niente
di misurabile, una sola scala di texture del suolo (`--textwo=0`) niente → non sono loro. Il costo in più dei primi secondi
è nel numero di unità inquadrate (modelli, ombre, fanteria animata): è il prossimo punto dove cercare.

## 5. Tabellone (richieste di TABELLONE)
`world_map.gd`: `set_threats(list)` (frecce persistenti tratteggiate e pulsanti + anello sul bersaglio) e segno di
logoramento sulla pedina (`terr.worn`: anello arancione tratteggiato, cerotto a X, pedina sporca) — `tabellone_segni.png`.

## File toccati
`scripts/models/unit_models.gd`, `model_gallery.gd`; `assets/models/*` (6 glb + LICENZA.txt); `tools/modelli/*`;
`scripts/battle/battle_signs.gd` (nuovo), `battle_marks.gd`, `battle_terrain.gd`, `battle_landscape.gd`, `battle_decor.gd`,
`battle_props.gd`, `terrain_ground.gdshader`; `scripts/map/world_map.gd`; `PER_INIZIARE.md`, `SPEC3D.md`,
`docs/notte3_richieste.md`. Condivisi (battle3d, battle_hud, battle_strategic) e `main.gd`: **non toccati**.

## Test
A fine lavoro, con il codice definitivo (uno alla volta, tramite il semaforo):
- `tests/test_battle.gd` (headless): **OK**, 0 errori di script;
- `tests/test_weather.gd` (headless): **esito OK**, 0 errori di script;
- `tests/test_flow.gd` (960×540, con finestra): **FINE errori=0**, 0 errori di script.
Tutti gli script toccati compilano (controllo dopo ogni modifica). Durante la notte due mie modifiche hanno lasciato per
qualche minuto un errore di compilazione in `unit_models.gd` e poi in `world_map.gd` (variabili senza tipo): corretti subito,
ma in quelle finestre gli altri agenti possono aver visto fallire un lancio.

## Cosa resta
- **Crediti nell'interfaccia** (obbligo CC-BY per elicottero, caccia, contraerea): chiesti a TABELLONE; finché non ci sono,
  i crediti stanno solo in `assets/models/LICENZA.txt` e `PER_INIZIARE.md`.
- **Prestazioni**: capire il costo dei primi 10 s di battaglia a Media (unità inquadrate: ombre dei mezzi, fanteria).
- Modelli: artiglieria, camion e droni restano in codice (nella lista approvata non c'erano modelli adatti); niente numeri
  tattici sui mezzi esterni; ruote dei carri esterni ferme (i cingoli scorrono). Abrams e T-72 richiedono un account
  Sketchfab: se l'utente li scarica a mano, `tools/modelli/convert.py` li converte (l'Abrams da 15k va bene: i LOD ci sono).
- La galleria dei modelli (`model_gallery.tscn`) non esce da sola dopo lo scatto quando ci sono elicotteri (già prima di
  stanotte): tiene il semaforo fino al timeout → usare `--timeout=60`.
- Tabellone: l'anello di logoramento è arancione come l'Unione Libera (si distingue per il tratteggio e il cerotto);
  stella/rombo per missione ed evento mondiale non fatti.
- Battaglia: nessun oggetto 3D sugli obiettivi nuovi (`road`, `site`); il lampo di rivelazione è un anello a terra, non
  una luce vera.
- Artico: più contrasto fuori dal campo (tundra, ghiaccio, roccia), ma le montagne lontane restano chiare.
