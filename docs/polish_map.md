# Polish tabellone strategico — note per l'agente UI/mappa (Agente F)

## Già fatto (solo nei file shader di F, nessuna uniform nuova o rimossa: `world_map.gd` non va toccato)
- `terrain.gdshader`: **ombreggiatura del rilievo da carta topografica** (luce fissa da nord-ovest, più marcata nella vista
  d'insieme dove il sole reale appiattisce tutto) e **isoipse sottili** ogni 1/6 di quota, visibili da vicino/medio,
  sfumate sotto la neve e quando diventano troppo fitte. Usa solo `height_tex`, `zoom`, `detail` già impostate.
- `water.gdshader`: **isobate** chiare sulla piattaforma continentale (effetto carta nautica), solo da vicino/medio.
- Miniature: ereditano i nuovi materiali dei mezzi (mimetica + usura, cingoli a maglie, dischi dei rotori).
- `Vfx.explosion` (usata dal tabellone per i combattimenti) ora lascia una colonna di fumo più lunga e una bruciatura
  (Decal) che sbiadisce in 20 s.

## Proposte che richiedono `world_map.gd` (opzionali)
1. **Boschi in miniatura**: oggi sono coni scuri molto piccoli che da medio zoom sembrano puntini. Usare
   `Props.tree_mesh("pine")` / `Props.tree_mesh("broadleaf")` nel MultiMesh (scala ~0.012–0.02) dà sagome vere con il nuovo
   shader del fogliame (luce avvolgente, vento): per disattivare il vento sulla mappa
   `mesh.surface_get_material(1).set_shader_parameter("wind", 0.0)` (attenzione: il materiale è condiviso con la battaglia →
   meglio `duplicate()` prima). Raggruppare 3–5 alberi per ciuffo invece di sparsi uniformi.
2. **Velatura del proprietario**: con l'hillshade il rilievo resta leggibile anche con più tinta; si può alzare `tint`
   nella vista d'insieme (es. da 0.40 a 0.5) senza perdere la morfologia.
3. **Luce del tabellone**: un secondo `DirectionalLight3D` debolissimo (energia 0.15, senza ombre) da nord-ovest rafforza
   l'effetto "plastico sul tavolo"; oppure `Environment.ssao_enabled = true` con raggio 0.4 per far "posare" le pedine.

## Notte 2026-11-10 — "Tabellone più ricco" (fatto, `scripts/map/map_decor.gd` + shader)
- **MapDecor** (nodo figlio di WorldMap, legge `game.terr`/`players` a ogni refresh, niente agganci a main.gd):
  boschi in ciuffi per bioma (conifere a nord/montagna, innevate ai margini artici, latifoglie temperate, palme ai tropici/deserti),
  città 3D (MultiMesh unico, `city.gdshader`: finestre accese di notte, più grandi per territori urbani/di valore),
  strutture quando costruite (`MapProps.structure`: porto sulla costa con gru e nave, aeroporto con pista/hangar/torre, fabbrica
  con ciminiere fumanti, caserma, bunker di comando, impianto con torcia; cantiere con gru per `terr.building`), compound del QG
  con bandiera della fazione, anelli di trincee/mine/bunker per i livelli `terr.fort`, fronte animato sui confini ostili
  (`specks.gdshader`: fuoco, fumo, vampate; calore per coppia = confine + attacco recente + truppe) e fumo sui territori conquistati.
- Terreno: `front_tex` (calore per territorio) → filo arancione pulsante e terra bruciata lungo il fronte. Strutture/alberi/città
  si spengono sul lato notturno (`map_struct/map_tree.gdshader`, include daynight).
- LOD: boschi < 50, strutture < 64, città < 110 unità di distanza; MultiMesh ovunque. 1600×900 qualità media:
  vista d'insieme ~104 fps / ~440 draw (invariato), vicino ~155 fps / ~260 draw.
- Demo (`world_map.tscn --demo=1`): `--buildings=1`, `--capture=idx`, `--cam=hq|front|at`, `--sunat=hq|cam|idx --sunoff=rad`,
  `--nodecor=Forest,...`, `--decor_debug=1`. Screenshot `docs/screens/board_before_*.png` / `board_after_*.png`.
