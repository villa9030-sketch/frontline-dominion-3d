# Omogeneità campagna ↔ battaglia — regole e numeri (notte 2, agente REGOLE)

Scopo: la campagna a turni decide com'è la battaglia e la battaglia lascia tracce sulla campagna.
Tutto vale sia nella battaglia comandata (3D) sia nella risoluzione automatica, che usa la stessa BattleSim.
Le costanti sono in `scripts/battle/battle_rules.gd` (sezione «Omogeneità») e in `scripts/core/game.gd`.

> **Aggiornamento notte 3** (`docs/notte3_battaglia.md`, SPEC3D «Notte 3 — battaglia»): gli obiettivi sono 3–4 e almeno 2
> stanno nella **fascia centrale** del campo (neutri: ponti/guadi, altura, crocevia, località); il primo edificio del
> territorio è al 60 % del campo; la conquista richiede **30 s** (non 60); i rinforzi entrano a **90 s** (difensore) /
> **105 s** (attaccante) con 20 s di preavviso; stallo dell'IA dopo 60 s senza danni; l'IA attaccante si ritira da 80 s
> sotto il 40 % della potenza del difensore; iniziativa dell'attaccante ×1.2; i nemici si vedono come contatti «?».
> Dove questo documento dice altro, vale l'aggiornamento.

## 1. Durata e obiettivi di battaglia
- **Limite: 5 minuti** di battaglia (`BattleRules.BATTLE_T = 300` s), anche per la risoluzione automatica
  (`AUTO_MAX_TIME = 300`). L'HUD mostra il **tempo rimanente** (rosso sotto i 60 s).
- Lo stallo resta: nessun danno per 90 s (IA) / 180 s (umano) chiude lo scontro con la stessa regola del tempo scaduto.
- **Obiettivi** (`sim.objectives`, al massimo 4, scelti dal contesto del territorio, in quest'ordine):
  1. **Quartier generale** — solo se il territorio è la capitale del difensore (`setup.hq = true`); sta nel fondo del campo del difensore.
  2. **Edifici del territorio** (fabbrica, aeroporto, porto, raffineria/impianto, caserma; max 2): luoghi nella metà del difensore,
     copertura pesante per la fanteria (come un isolato).
  3. **Attraversamenti**: ponti e guadi del fiume (max 2, i più centrali).
  4. **Alture**: la quota più alta del campo (max 1, se c'è un vero rilievo ≥ 6 m).
  5. **Linea dei bunker** (se ci sono bunker e meno di 4 obiettivi).
  Se il terreno è «pulito» (test) non ci sono obiettivi e vale la vecchia regola di stallo.
- **Controllo**: raggio `OBJ_R = 260` px. Un lato **conquista** un obiettivo se ha unità di terra nel raggio e il nemico no,
  per `OBJ_HOLD = 60` s continuativi (il contatore si azzera se entra il nemico). Gli obiettivi nella metà del difensore partono
  **suoi**; quelli a cavallo del centro (ponti/guadi/alture) partono **neutri**.
- **Allo scadere** (tempo o stallo): vince l'attaccante se ha **annientato** il difensore oppure se controlla **più obiettivi** del
  difensore (`att_held > def_held`); in ogni altro caso **tiene il difensore** (stile Risiko). Il QG vale doppio: se c'è il QG e
  l'attaccante non lo tiene, serve comunque la maggioranza.
- HUD: sotto il timer una riga per obiettivo (nome, colore di chi lo tiene, barra del contatore di conquista); le stesse bandierine
  della vista strategica (`BattleStrategic`) ora leggono `sim.objectives`.
- **Resistere fino ai rinforzi**: i rinforzi (§2) arrivano a metà battaglia; l'HUD avvisa «Rinforzi in arrivo tra N s».
- **Ritirata ordinata**: il pulsante Ritirata (solo attaccante) non chiude più la battaglia di colpo: le unità ricevono l'ordine di
  tornare al proprio bordo (`x < RETREAT_EDGE = 150` px); ogni reparto che raggiunge il bordo è **salvo** (torna a casa intero),
  chi resta sul campo continua a combattere. La battaglia finisce quando l'attaccante non ha più unità sul campo (`retreated: true`,
  vince il difensore). Anche l'IA attaccante si ritira quando è ormai battuta (potenza < 45% del difensore dopo 100 s).

## 2. La campagna decide la battaglia
- **Edifici** del territorio → `setup.buildings` (chiavi `Data.BUILDINGS`) → luoghi/obiettivi sul campo (§1).
- **Rinforzi dai territori vicini** (`setup.att.reinf` / `setup.def.reinf`, calcolati da `Game`):
  - per ogni territorio **confinante dello stesso proprietario**, rifornito e non in riorganizzazione, parte il **20 %** delle sue
    unità di terra (fanteria, carri, artiglieria, contraerea; arrotondato per difetto, almeno 1 unità resta a presidio);
    per l'attaccante NON conta il territorio di partenza (ha già mandato ciò che l'attaccante ha scelto);
  - tetto: in tutto al massimo il **50 %** dell'esercito iniziale di quel lato (unità);
  - entrano a **`REINF_T = 150` s** (difensore) / **165 s** (attaccante) dal **proprio bordo**, nel terzo del campo nord o sud
    secondo la posizione del territorio di provenienza sulla mappa (più a nord → bordo alto);
  - **sopravvissuti**: a fine battaglia i rinforzi superstiti **tornano nei territori da cui sono partiti** (qualunque sia l'esito);
    le perdite sono scalate dai territori di origine nell'ordine di arrivo. In attesa della battaglia i rinforzi restano scritti nel
    territorio di origine (sono «in viaggio» solo durante lo scontro).
- **Supporto aereo (tasto J)**: solo con un **aeroporto proprio nel territorio o in un territorio confinante** (`setup.X.air = true`).
  Senza aeroporto il pulsante non c'è, anche se l'esercito ha caccia.
- **Tiro navale**: attacco dal mare con **porto** nel territorio di partenza (o fazione navale CP) → l'attaccante riceve
  **3 batterie di supporto** (sbarramenti, tasto B) «dalla flotta»; difensore con **porto** in un territorio costiero attaccato →
  **2 batterie**. Si sommano al supporto d'artiglieria (Tech 3) dai territori vicini.
- Nebbia della campagna → stesso meteo/vista della battaglia (già dal seed).

## 3. Comando manuale
- **+10 % attacco** per il lato comandato dal giocatore (già in `Combat.combat_mods`), ora **scritto** nel pannello d'attacco, nel
  prompt di difesa e nell'HUD della battaglia («Comando diretto +10 %»).
- **Esperienza doppia**: dopo una battaglia comandata il presidio guadagna **2 punti** di veterania invece di 1 (`Game._gain_xp`).

## 4. Logoramento
- Dopo ogni battaglia il territorio del difensore e quello da cui è partito l'attacco (o quello conquistato) sono **logorati**:
  `terr.worn = 2` (turni). Effetto: **−15 % attacco** (`WORN_MUL = 0.85`) per chi combatte **da** quel territorio (difesa o attacco).
- **Recupero**: all'inizio di ogni turno del proprietario, se il territorio è **rifornito**, `worn` scende di 1; a 0 il presidio è
  fresco. Un territorio non rifornito non recupera. Un nuovo scontro riporta `worn` a 2.
- Visibile: scheda del territorio («Truppe logorate −15 % · recupero tra N turni»), tooltip sul tabellone, pannello d'attacco.
- Salvataggi: `SAVE_VERSION = 3`; i salvataggi v2 si caricano (worn = 0, nebbia dal vecchio bool).

## 5. Carte inganno e nebbia leggera
- **Nebbia**: tre modalità per le nuove campagne (`opts.fog_mode`): **nessuna** (predefinita dalla notte 3), **leggera**, **totale**.
  - nessuna: forze esatte ovunque;
  - leggera: esatte nei territori propri e confinanti (AAN +1 anello col radar); altrove una **stima** «circa 10–15»
    (`estimate_range`: ±25 %, arrotondata a 5, mai sconosciuta); edifici lontani sconosciuti;
  - totale: come prima (lontano = «?»).
  `game.fog` resta vero per leggera/totale (compatibilità).
- **Nuove operazioni dei tris** (`Data.OPS`), stesso sistema delle carte:
  - **Divisione falsa** (`finta`, bersaglio proprio): per **2 round** i nemici vedono quel territorio solo come stima, gonfiata di
    **+8 unità** (anche se confinanti). Dalla notte 3 le tre carte inganno si giocano **solo con la nebbia attiva**
    (`game.op_available`): senza nebbia non c'è nulla da nascondere.
  - **Ricognizione** (`ricognizione`, bersaglio nemico): per **2 round** vedi esattamente forze, edifici e fortificazioni di quel
    territorio e dei suoi confinanti; annulla divisioni false e silenzi radio lì.
  - **Silenzio radio** (`silenzio`, bersaglio proprio): per **2 round** i nemici vedono «?» (forze sconosciute) e la previsione
    d'attacco non è disponibile.
  I contatori scendono a ogni nuovo round (`_new_round`).
- **IA strategica**: decide **solo su ciò che vede** (`visible_forces`/`estimate_forces` → stime gonfiate o «?» → stima prudente
  14 di potenza), quindi subisce gli inganni. Usa le carte nuove: ricognizione sul bersaglio migliore non visibile, silenzio radio sul
  proprio territorio più minacciato quando è debole, divisione falsa su una frontiera debole; altrimenti golpe/rinforzi come prima.

## 6. Bilanciamento (obiettivo: difensore 60–65 % a forze pari; fazioni entro ±8 punti)
- Leve: `ATT_INITIATIVE`, la regola degli obiettivi allo scadere (l'attaccante non deve più annientare: basta tenere gli obiettivi),
  `REINF_*`, `WORN_MUL`. I numeri finali e le serie di prova (`tests/test_tactics.gd --only=balance`, più seed) sono in
  `docs/notte2_regole.md`.
- Fazioni: serie «specchio con i modificatori di fazione» (FO carri +20 % hp e artiglieria +25 %; UL guerriglia; AAN/CP neutri in
  battaglia) misurata in attacco e in difesa.

## 7. Test
- `tests/test_omogeneita.gd`: obiettivi (scelta, conquista a tempo, esito allo scadere), ritirata al bordo, rinforzi (arrivo, tetto,
  rientro dei superstiti), supporto aereo/navale, logoramento (applicazione, recupero, modificatori), carte inganno e stime,
  modalità di nebbia, IA ingannata, salvataggio v3 e migrazione v2.
- Suite completa: test_core, test_save, test_fase3, test_scenarios, test_battle, test_weather, test_tactics, test_sfx, test_music,
  test_flow (senza --headless, --resolution 960x540).

## 8. Guida e tutorial
- F1 (`scripts/ui/modal.gd`): sezioni «Battaglie» (obiettivi, 5 minuti, ritirata, rinforzi, aereo/navale, comando diretto),
  «Nebbia» (tre modalità, carte inganno), «Logoramento». Tutorial (`coach.gd`): passo sul pannello d'attacco con bonus e logoramento.
