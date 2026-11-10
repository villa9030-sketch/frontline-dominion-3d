# Notte 2 — agente GRAFICA (2026-11-10/11): "un solo mondo, due scale"

Riferimento: R.U.S.E. (paesaggio, non marchio). Tutto misurato a 1920×1080, demo `campale`, `--weather=sereno`, GTX 1070,
`--fps=1 --prof=1` (riga `[gpu]`, media di 2 campioni da 5 s). Screenshot in `docs/screens/notte2/` (prefissi: `base_` partenza,
`p*` prestazioni, `q_`/`r_`/`s_`/`t_` passi del paesaggio).

## 1. Prestazioni (obiettivo: strategica < 14 ms, gioco ≤ 10,5 ms a Media)

Dove andava il tempo (vista strategica, Media): `--dbg=lighting` (materiali bianchi) 8,1 ms contro 19,0 → ~11 ms di shader;
`--far=0` −1,8, `--tex=0` −1,0, `--decor=0` 0, `--trees=0` −1,6, 960×540 8,8 ms. Il wireframe (`dbg_wireframe.png`) ha mostrato
la causa principale: la mesh del campo a passo 2 m vista da 1,6 km dà triangoli di 1-2 px su metà schermo e lo shader del suolo
(40+ letture) girava 3-4 volte per pixel.

| Passo | Strategica (`--cam=overview --dist=1600`) | Gioco (`--cam=army`) |
|---|---|---|
| Partenza | 19,0 ms | 11,0 ms |
| Shader: oltre 1 km niente texture fini/normal map/roccia triplanare (`near_px`) | 18,3 | 10,7 |
| Suolo a due livelli (blocchi a passo 8 m con gonna oltre 760 m) | **15,0** | 10,9 |
| Alberi a due livelli (20 triangoli oltre 480 m, stesso shader di luce) | **13,0** | 11,0 |
| Ombre degli alberi dalla sagoma a 20 triangoli; fogliame 2 letture oltre 320 m | 13,5 | 11,2 |
| + bosco fitto su maschera, paesi grandi, periferie, laghi, luci (v6) | vedi tabella finale | vedi tabella finale |

Tabella finale per qualità (1080p, dopo tutti i lavori): vedi in fondo ("Misure finali").

Note: la vista di gioco resta ~11 ms. Con `--lod=lo` (tutti gli alberi a 20 tri) scende a 9,75: il costo che resta è il bosco
vicino alla telecamera (900 tri/albero + ombre) e lo shader del suolo a piena risoluzione (`--dbg=lighting` 5,4-6,1 ms).
Piste non percorse per non perdere resa: LOD alberi a 320 m (−0 ms misurati: il costo è nei 150 m più vicini), MSAA 2× → FXAA,
`tex_two=0` su Media.

Nuovi interruttori (solo demo): `--trees=0`, `--lod=hi|lo|<m>`, `--dbg=overdraw|wireframe|lighting|unshaded`.

## 2. Paesaggio su tutte le mappe
- **Maschera dei boschi condivisa CPU/shader** (`terrain.forest_at`): alberi 3D veri dove il paesaggio è bosco, fitti vicino al campo
  e radi lontano (`_scatter(..., mask_k)`); niente coltivi nei boschi; chiome dipinte oltre ~120 m. Foresta: 24 000 alberi
  (3 MultiMesh per blocco: modello, sagoma, ombra), `s_foresta_strat.png`, `t_foresta_colline.png`.
- **Via le "curve di livello"**: erano i confini del mosaico dei campi lontani, disegnati anche sui versanti e con un angolo di
  rotazione che variava con continuità (si piegavano in curve). Ora mosaico solo su terreno dolce, orientamento costante per
  regione; strati di roccia solo da vicino; fuori campo roccia solo sui versanti ripidi.
- **Deserto**: altipiani a cima piatta, colori beige (meno arancio), rare oasi (chiome dipinte).
- **Artico**: masse di conifere scure sulla neve (maschera, 8000 abeti), neve lontana che non copre le chiome, roccia sulle creste.
- **Città**: periferie di case basse sulla maglia degli isolati fino a 1,5 km (`t_urbano_strat.png`).
- **Laghi lontani** (conche nel rilievo + specchio d'acqua) e **fiume fino all'orizzonte** (il rilievo lontano non lo seppellisce).
- Macro-chiazze delle foto non più stirate sui versanti ripidi (artico/montagna).

## 3. Paesi
Cittadine a isolati più frequenti e grandi (90-160 case), villaggi 14-36 case, orti/frutteti a filari attorno; di notte finestre
accese (alcune spente, toni diversi) e chiazze di luce di lampioni (vie dei paesi, piazze, lampioni della città): `t_notte_*.png`.

## 4. Mezzi e soldati
`paint.gdshader`: mimetica a due scale e stinta a chiazze, polvere di strada sulle parti basse, bordi consumati sugli spigoli,
scheggiature; `soldier.gdshader`: stoffa stinta per soldato, fango/polvere su stivali e ginocchia (`t_mezzi.png`).
Modelli esterni candidati (CC0/CC-BY, non scaricati): `docs/modelli_candidati.md`.

## 5. Transizione continua tabellone → battaglia → tabellone
Tabellone: la telecamera scende sul territorio (`world_map.dive_to`), velo nero (`SceneFade`, nuovo `scripts/map/scene_fade.gd`),
la battaglia parte dall'alto con l'introduzione già esistente e riapre; a fine battaglia la telecamera risale verso il cielo
(uscita cinematica `OUTRO_T` 1,6 s in battle3d), nero, il tabellone riparte basso sul territorio e risale (`rise_from`).
Solo con tabellone 3D e fuori dai test (`--script`). Fotogrammi: `t_trans_45/110/200.png`.

## 6. Piccoli
- Velivoli: gettone anche sotto 55 m e mai nascosto dall'occlusione (l'elicottero vicino senza gettone).
- Siti del territorio (`sim.landmarks` dell'agente REGOLE) disegnati: fabbrica, aeroporto, porto, raffineria, caserma, fortino
  (`t_siti.png`), registrati come edifici (occlusione e distruzione).
- Vista tattica: nessuna velatura in più (le luci notturne sono additive e solo di notte); Tab invariato (BattleStrategic non toccato).

## File toccati
battle_terrain.gd, battle_landscape.gd, battle_decor.gd, battle_props.gd, battle_marks.gd, battle_weather.gd, terrain_ground.gdshader,
models/paint.gdshader, models/soldier.gdshader, models/foliage.gdshader, map/scene_fade.gd (nuovo), map/world_map.gd;
condivisi: battle3d.gd (uscita cinematica, gettoni velivoli), main.gd (transizione). SPEC3D.md aggiornato (sezione "Notte 2 — grafica").

## Cosa resta
- Vista di gioco a Media ~11 ms (obiettivo 10,5): servirebbe un livello intermedio degli alberi (~100 tri) a 150-480 m o FXAA al
  posto di MSAA 2× su Media.
- Artico: montagne lontane ancora poco contrastate (tutto neve); laghi ghiacciati lontani.
- Paesi: ancora senza strade interne disegnate (solo la via principale) e senza chiese diverse per regione.
- Modelli esterni: da approvare e integrare (`unit_models.gd` + `paint.gdshader`).

## Misure finali (1080p, demo campale, sereno, GPU ms; "prima" = inizio notte per Media, stime da docs precedenti per le altre)

| Qualità | Strategica prima | Strategica dopo | Gioco prima | Gioco dopo |
|---|---|---|---|---|
| Basso | 9,6 | **6,4** | ~5,5 | **6,1** |
| Medio | 19,0 | **12,9** (obiettivo < 14: OK) | 11,0 | **10,7** (obiettivo 10,5: quasi) |
| Alto | 24,5 | **15,8** | ~12,4 | **13,6** |
| Ultra | — | 17,8 | — | 16,6 |

La vista di gioco a Basso/Alto sale di ~0,6-1 ms perché il bosco attorno al campo è molto più fitto (maschera: 6-24 mila
alberi contro 3-7 mila) e perché ora il bosco ha ombre (dalla sagoma) anche fuori campo; la strategica scende ovunque.

## Test (960×540, senza --headless)
test_flow: FINE errori=0 · test_weather: esito OK · test_battle e test_tactics: nessun errore/fallimento in uscita (completati).
