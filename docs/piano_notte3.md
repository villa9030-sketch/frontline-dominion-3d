# Piano notte 3 (2026-11-11 → 12) — da "nascondino" a scontro: rendere il gioco coinvolgente

Partenza: commit 254a8b3 (notte 2), suite verde.
Giudizio dell'utente: **"il gameplay attuale sembra di giocare a nascondino, non è per niente coinvolgente/divertente"**,
e il problema riguarda **anche il tabellone**. Decisioni: direzione R.U.S.E. per la battaglia approvata; modelli 3D veri
dei mezzi approvati (CC0 **e** CC-BY, con crediti); partenza subito; commit + push a fine notte se la suite è verde.

Causa del "nascondino" in battaglia (misurata nel codice): un nemico fermo in copertura si scopre solo entro 190–350 px
(`CONCEAL_INF/VEH`) su un campo di 4800 px; l'imboscata dà +60% ai primi colpi (`AMBUSH_MUL`); il difensore IA aspetta
nascosto; gli obiettivi stanno nella zona del difensore. L'attaccante passa la battaglia a cercare.

## Regole comuni
- Godot SOLO con `node tools/godot_run.js`, un processo alla volta (il PC si blocca sotto carico); finestre fuori schermo;
  screenshot max 960×540, misure a 1920×1080 con `--fps=1 --prof=1`. Guardare SEMPRE le immagini prodotte.
- Mai scrivere in %APPDATA%\FrontlineDominion. Testi del gioco in italiano. Leggere SPEC3D.md e aggiornarlo.
- NON fare commit/push (lo fa il coordinatore). Resoconto finale in `docs/notte3_<battaglia|tabellone|grafica>.md`.
- Tre agenti sullo stesso albero. Proprietà dei file:
  - **BATTAGLIA**: scripts/battle/battle_sim.gd, battle_rules.gd, battle_ai.gd, battle_orders.gd, tests/test_battle.gd,
    tests/test_tactics.gd, tests/test_omogeneita.gd (parte battaglia).
  - **TABELLONE**: scripts/core/*, scripts/ui/*, scripts/main.gd, tests/test_core|save|fase3|scenarios|flow.gd, tests/sim.gd.
  - **GRAFICA**: scripts/battle/battle_terrain|landscape|decor|props|fx|weather|marks.gd, *.gdshader, scripts/models/*,
    scripts/map/*, assets/models/*.
  - Condivisi (modifiche piccole, rileggere subito prima, verificare che compili subito dopo): battle3d.gd, battle_hud.gd,
    battle_strategic.gd. main.gd è di TABELLONE: GRAFICA e BATTAGLIA gli chiedono le modifiche via resoconto/nota.
  - Coordinamento: chi ha bisogno di qualcosa in un file altrui scrive in `docs/notte3_richieste.md` (chi, cosa, perché).

## Agente BATTAGLIA — da nascondino a scontro (stile R.U.S.E.)
1. **Gettoni "?"**: le unità nemiche a terra entro una distanza di "contatto" ampia (es. 1600–2000 px, o sempre per
   quelle in vista da qualsiasi unità senza copertura totale) sono note come **posizione** ma non come **tipo**: nuovo
   stato `u.known[si]` ("contatto": posizione nota, tipo ignoto) oltre a `spotted` ("identificata"). Si può sparare a un
   contatto con l'artiglieria (precisione ridotta), non con il tiro diretto. Identificazione: entro la vista normale, o con
   ricognizione (elicotteri/droni/esploratori) da più lontano. L'IA ragiona con le stesse informazioni.
2. **Chi spara si rivela**: un'unità che fa fuoco diventa identificata per il nemico per ~6 s a qualunque distanza
   di tiro (lampo di bocca). Imboscata ridotta (`AMBUSH_MUL` ~1.25) e solo per il primo colpo.
3. **Contatto rapido**: schieramenti più vicini (contatto entro 20–30 s di gioco), obiettivi **al centro** e contesi
   (almeno 2 su 3-4 nella fascia centrale), tempo di conquista più breve (es. 30 s), punteggio obiettivi visibile.
4. **IA difensore attiva**: contrattacca gli obiettivi persi, manda riserve, fa fuoco e movimento; niente più
   "tutti fermi nel bosco". L'IA attaccante avanza a ondate con supporto d'artiglieria sui contatti.
5. **Eventi**: rinforzi in arrivo con avviso e conto alla rovescia, attacco aereo annunciato; ogni evento ha un `fx`
   (la grafica e l'HUD lo mostrano: segnalarlo in `docs/notte3_richieste.md` per GRAFICA se serve un effetto nuovo).
6. **Metrica del divertimento** (nuovo test o sezione in test_tactics): per battaglie tipiche misurare tempo al primo
   contatto, % di tempo con almeno uno scontro in corso, secondi in cui il giocatore "non vede nessun nemico",
   cambi di possesso degli obiettivi. Obiettivi: primo contatto < 30 s, scontro in corso > 60% del tempo, zero
   finestre > 40 s senza nemici noti. Riportare prima/dopo.
7. **Bilanciamento** dopo i cambi: difensore 60–70% a forze pari su tutte le mappe (oggi foresta ~85%), fazioni con
   forbice ≤ 15 punti; risoluzione automatica coerente (usa la stessa sim). Test aggiornati, suite verde.
8. Nel HUD (condiviso, piccolo): gettone "?" per i contatti, indicatore "rivelato" per chi spara. Se serve grafica 3D
   (sagoma generica), chiederla a GRAFICA in `docs/notte3_richieste.md`.

## Agente TABELLONE — perché il tabellone non coinvolge
L'utente non ha detto cosa lo annoia: prima **diagnosi**, poi correzioni sicure, poi proposte.
1. **Diagnosi**: giocare (in automatico, e leggendo il flusso dell'interfaccia) 4–6 partite; misurare tempo/clic per turno,
   turni in cui il giocatore non ha decisioni interessanti, durata dei turni IA, quante informazioni sono nascoste dalla
   nebbia leggera (stime «circa 10–15»), quanto spesso succede qualcosa di nuovo (carte, eventi, bonus continente).
   Scrivere i risultati in `docs/notte3_tabellone.md` con ipotesi ordinate per impatto.
2. **Correzioni sicure stanotte** (coerenti con la direzione "niente nascondino"):
   - nebbia del tabellone: predefinita **nessuna** (leggera e piena restano opzioni); carte inganno disponibili solo
     con nebbia attiva, oppure ripensate come effetti visibili (es. "finta" = bandierina d'attacco falsa sul confine);
   - turni IA più rapidi e leggibili (riepilogo di cosa è successo, frecce degli attacchi, niente attese morte);
   - ogni turno almeno una decisione interessante: obiettivi a breve termine (es. "conquista X entro 3 turni: +carta"),
     eventi mondiali leggeri, minacce visibili (attacco nemico in preparazione su un confine);
   - inizio partita più rapido (meno turni lenti di sola costruzione).
   Ogni cambio con test; salvataggi compatibili (SAVE_VERSION se serve, con migrazione).
3. **Proposte per il mattino** (NON implementare): cambi grandi al ritmo (es. turni simultanei, partite brevi a
   scenario) con pro/contro, in `docs/notte3_tabellone.md`.
4. Logoramento visibile sulla pedina: chiederlo a GRAFICA (scripts/map) in `docs/notte3_richieste.md`.

## Agente GRAFICA — mezzi veri e leggibilità
1. **Modelli 3D veri dei mezzi** da `docs/modelli_candidati.md` (CC0 e CC-BY approvati): scaricare fuori dal progetto,
   verificare licenza e poligoni sulla pagina, convertire in glTF (Y-up, avanti −Z, origine a terra, nodi
   Turret/Barrel/Rotor/Muzzle), copiare in `assets/models/<kind>.glb`; `unit_models.gd` li carica con ripiego sul modello
   in codice; materiale `paint.gdshader` (colori di fazione, usura). Crediti CC-BY in `assets/models/LICENZA.txt` e in
   PER_INIZIARE.md / schermata crediti. Abrams 15k tri solo con LOD. Misurare il costo per qualità (non deve salire
   più di ~0,5 ms a Media in una battaglia 60 vs 60). Screenshot prima/dopo ravvicinati.
2. **Gettoni "?" e rivelazione** in 3D (in accordo con BATTAGLIA, leggere `docs/notte3_richieste.md` ogni ora):
   sagoma generica/segnale di contatto, lampo di rivelazione, effetti per gli eventi (rinforzi, attacco aereo).
3. **Notte**: luci dei paesi e lampioni ben visibili (oggi si vedono poco). Paesi con strade interne. Artico più contrastato.
4. **Prestazioni**: vista di gioco a Media ≤ 10,5 ms a 1080p (oggi 10,7; pista: LOD intermedio alberi 150–480 m).
5. Pedina del tabellone con segno di logoramento (`terr.worn`).

## Coordinatore
- Avvio subito; controllo ogni ora (:17): riprende gli agenti fermi (Fable, poi Opus), chiude Godot bloccato > 15 min.
- A fine lavori: suite completa (core, save, fase3, scenarios, battle, omogeneita, weather, sfx, music, tactics, flow),
  commit in italiano + push su origin main se verde; altrimenti correzioni o note in `docs/notte3_problemi.md`.
- Pagina di confronto aggiornata e resoconto del mattino (con le proposte del tabellone da decidere).
