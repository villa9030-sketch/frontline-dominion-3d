# Piano notte 2 (2026-11-10 → 11) — "un solo mondo" + regole che legano campagna e battaglia

Decisioni dell'utente: implementare TUTTO stanotte; a fine notte commit + push (solo se tutti i test passano);
agenti pesanti con Fable, se si fermano per limite si riprende con Opus.

## Regole comuni (valgono per tutti gli agenti)
- Godot SOLO con `node tools/godot_run.js [--timeout=S] -- <args>` (semaforo globale: un processo alla volta, il PC si
  blocca sotto carico). Le finestre dei test si aprono già fuori dallo schermo (non rubano la vista all'utente).
- Screenshot: `-- --path . res://scenes/battle.tscn --resolution 960x540 -- --demo=<tipo> --shot=docs/screens/notte2/<nome>.png --frames=N`
  (guardare SEMPRE le immagini prodotte). Misure: `--fps=1 --prof=1` stampa `[gpu] media X ms`; per le misure usare
  `--resolution 1920x1080`. Interruttori di confronto: `--quality=basso|medio|alto|ultra`, `--tex=0`, `--decor=0`, `--far=0`,
  `--dof=0`, `--cam=overview --dist=1600` (vista strategica), `--cam=army --dist=N`.
- I test e le demo non devono MAI scrivere in %APPDATA%\FrontlineDominion (salvataggi e impostazioni dell'utente).
- Testi del gioco in italiano. Leggere SPEC3D.md prima di toccare un modulo e aggiornarlo con quello che si cambia.
- NON fare commit/push (lo fa il coordinatore a fine notte).
- Proprietà dei file (due agenti lavorano in parallelo sullo stesso albero):
  - **Agente REGOLE**: scripts/core/*, scripts/battle/battle_sim.gd, battle_rules.gd, battle_ai.gd, battle_orders.gd,
    scripts/ui/* (pannelli del tabellone), tests/*.
  - **Agente GRAFICA**: scripts/battle/battle_terrain.gd, battle_landscape.gd, battle_decor.gd, battle_props.gd,
    battle_fx.gd, battle_weather.gd, battle_marks.gd, *.gdshader, scripts/models/*, scripts/map/*.
  - Condivisi (modifiche piccole e mirate, rileggere il file subito prima di ogni modifica): scripts/battle/battle3d.gd,
    battle_hud.gd, battle_strategic.gd, scripts/main.gd.
- A fine lavoro: riassunto in `docs/notte2_<regole|grafica>.md` (cosa, file, numeri, cosa resta), suite di test verde.

## Stato di partenza (non committato, già funzionante)
Passata grafica "R.U.S.E.": texture CC0 del terreno (assets/textures/terrain), BattleDecor, BattleStrategic (Tab, fronte,
frecce, obiettivi grafici), fumo/effetti, gettoni unità, qualità ultra + FSR2/TAA, paesaggio esteso (BattleLandscape:
montagne lontane, mosaico campi, boschi dipinti, strade, paesi, nuvole; camera alta inclinata).
Problema aperto: vista strategica a 1080p Media = 19,2 ms GPU (obiettivo < 14), vista di gioco 11,0 ms.
Backup: scratchpad/backup_fase1/frontline3d_notte2_inizio.tar.

## Lavori GRAFICA
1. Prestazioni vista strategica (prima di tutto).
2. Paesaggio su tutte le mappe (foresta, deserto, artico, città, laghi/fiumi lontani; via le righe curve viste dall'alto).
3. Paesi più leggibili, cittadine a isolati, finestre accese e luci dei lampioni di notte.
4. Mezzi e soldati: usura/mimetiche/sporco procedurali; lista di modelli 3D con licenza libera (NON aggiungerli).
5. Transizione continua tabellone → battaglia → tabellone.
6. Piccoli: gettone mancante su un elicottero (occlusione), deserto troppo arancione.

## Lavori REGOLE (vedi docs/omogeneita.md, scritto dall'agente REGOLE come primo passo)
1. Obiettivi di battaglia dal contesto + limite di 5 minuti.
2. La campagna decide la battaglia: edifici del territorio sul campo, rinforzi dai territori vicini, supporto aereo/navale
   legato ad aeroporti/flotte vicini.
3. Bonus del comando manuale visibile (e utile).
4. Logoramento delle truppe dopo la battaglia.
5. Carte inganno (divisione falsa, ricognizione, silenzio radio) + nebbia leggera; IA che usa ciò che "vede".
6. Ritirata ordinata.
Tutto nella simulazione (la risoluzione automatica usa la stessa BattleSim). Bilanciamento: difensore ~60-65% a forze pari.
