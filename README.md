# FRONTLINE DOMINION 3D

Strategico moderno di conquista mondiale in **Godot 4.6**: tabellone strategico 3D **a turni** stile Risiko (42 territori,
economia, carte, diplomazia, nebbia di guerra) e **battaglie tattiche 3D in tempo reale** comandabili, in stile realistico militare.
Tutti i modelli, gli effetti, i suoni e la musica sono generati in codice.

## Avvio
Doppio clic su **`Gioca.bat`** (usa Godot 4.6.2 in `Downloads\Godot_v4.6.2-stable_win64.exe\`).
Primo avvio: il gioco parte in **finestra massimizzata** (più leggera per il PC); **Alt+Invio** o le Impostazioni passano allo
schermo intero, e la scelta viene ricordata. La mappa del mondo viene generata (~3 s), poi resta in cache.
In gioco **F1** apre la guida completa; le **Impostazioni** (qualità grafica, schermo intero, ciclo giorno/notte, volumi,
telecamera, salvataggio automatico, suggerimenti) sono nel menu.

## Come si gioca: i turni
Il tabellone si gioca **a turni**: prima tu, poi ogni IA (un *round* = tutti i giocatori vivi hanno giocato una volta).
La schermata è pensata per dire sempre **cosa fare adesso** (piano e schizzo: `docs/ux_plan.md`):
- **Riquadro ORDINI** (in basso al centro): fase attuale («Turno 3 · Fase 1 di 3 · Rifornimento»), l'istruzione del momento
  (es. «Hai 6 rinforzi: clicca un tuo territorio evidenziato in verde»), l'esito dell'ultima azione («✓ Rinforzi schierati in…»)
  e un **pulsante principale** che cambia con la fase: «Fase successiva: Attacco ›», «Salta attacco ›», «Fine turno ✓»
  (durante le IA: «Accelera»). Sotto, un pulsante secondario (es. «Fine turno ⏎»).
- **Sul tabellone pulsa ciò che si può cliccare**: verde = dove schierare, ambra = territori che possono attaccare,
  rosso = bersagli, azzurro = spostamenti.
- **Barra dei turni** in alto al centro: «Turno 7 · Tocca a te», le fasi 1 Rifornimento › 2 Attacco › 3 Spostamento e la tregua.
- **Barra a icone a sinistra**: Obiettivo, Potenze (patti), Carte, Mercato, Continenti, Registro. Aprono un pannello
  (chiuso di default, uno alla volta); i badge segnalano carte in mano (lampeggia se c'è un tris), notizie non lette, turni rimasti.
- **Pannello del territorio** (a destra, al clic): riassunto (proprietario, terreno, forze); sui tuoi territori nel rifornimento
  «Schiera qui» e le schede **Recluta / Edifici / Fortifica**.
- **Recluta** mostra per ogni unità costo, turni e a cosa serve («Carri: sfondano in campo aperto…»); se non è disponibile, il motivo
  esatto («🔒 Serve una Fabbrica in questo territorio», «🔒 Serve Tech 2 — ricerca dal pulsante in alto», «Risorse insufficienti: mancano 20 acciaio»).
  **Edifici** dice in una riga cosa abilita ogni edificio. La **ricerca** (pulsante in alto) vale per tutti i territori; gli edifici solo dove
  li costruisci; le unità reclutate nascono nel territorio scelto.
- All'inizio del tuo turno il riquadro ORDINI riassume il turno: «Questo turno: +172 $ … · 6 rinforzi (fanteria) · Fabbrica completata a …».
- Il pannello d'attacco aggiunge consigli sulla composizione (es. «Solo fanteria contro un nemico in città: rischioso»).
- Notifiche brevi (al massimo due), banner d'inizio turno breve; tooltip in italiano su icone e valori.

**Come formare l'esercito**: i rinforzi gratuiti sono fanteria (difesa); per attaccare recluta carri e artiglieria nel QG o dove hai
una Fabbrica (aerei con l'Aeroporto); un esercito misto batte uno numeroso di un solo tipo; lo spostamento non ha limiti di distanza
tra territori tuoi collegati (uno per turno). Il tutorial ha un passo dedicato e la guida F1 una sezione.

1. **Rifornimento**: entrate e rinforzi del turno. Lo **schieramento è già attivo**: un clic su un tuo territorio (verde)
   mette lì tutti i rinforzi (Esc o «Annulla schieramento» per guardare prima il tabellone; «Schiera» per riprendere).
   Poi si recluta (1–3 turni), si costruisce, si **fortifica** (trincee, campi minati, bunker, livelli 0–3), si ricerca, si commercia,
   si giocano le carte, si assoldano mercenari. Passando all'attacco con rinforzi non schierati il gioco chiede conferma.
2. **Attacco** (uno per turno, facoltativo): clic su un tuo territorio che pulsa in ambra, poi su un bersaglio rosso
   (confinanti nemici o neutrali, rotte marittime con porto) → **pannello d'attacco** con un cursore per ogni tipo di unità
   (almeno una resta a presidio), previsione dell'esito, terreno, fortificazioni e veterani del difensore (stimati nella nebbia).
   Poi **«Attacca: comando diretto (3D)»** o **«Attacca: risoluzione automatica»**. Oppure «Salta attacco».
3. **Spostamento** (uno per turno, facoltativo): da un tuo territorio a un altro tuo territorio collegato, con i cursori e **«Sposta»**.
   Poi **Fine turno** (Invio).

**Tutorial guidato**: alla prima campagna (o dal menu **Tutorial**) un riquadro con una freccia sull'elemento vero guida il primo
turno passo per passo e aspetta che tu lo faccia: schierare i rinforzi, reclutare, passare all'attacco, scegliere origine e
bersaglio, il pannello d'attacco (3D o automatico), lo spostamento, la fine del turno, il turno delle IA e la difesa.
Si può saltare in ogni momento («Salta tutorial»).

Durante i turni delle IA un banner col colore della fazione annuncia chi gioca; attacchi e spostamenti compaiono come frecce
animate sul tabellone e la telecamera può seguirli (Impostazioni: **«Segui le mosse dell'IA»**, **«Velocità turni IA»**
lenta/normale/veloce/istantanea). **Spazio** (o il pulsante del riquadro ORDINI) accelera le animazioni, di nuovo salta il resto del turno IA.
Se un'IA ti attacca compare il **prompt di difesa** (forze nemiche stimate, i tuoi difensori e le fortificazioni):
**«Difendi in prima persona (3D)»** o **«Risoluzione automatica»**. Il salvataggio automatico avviene all'inizio di ogni tuo turno;
i salvataggi mostrano «Turno N». I salvataggi della versione in tempo reale non sono compatibili.

## Menu iniziale
- **Continua** riprende l'ultimo salvataggio; **Nuova campagna** sceglie fazione, avversari, difficoltà, modalità, nebbia
  (nessuna / **leggera** (consigliata: lontano solo stime «circa 10–15») / totale).
- **Scenari**: operazioni già impostate con forze di partenza, regole e obiettivi propri (vedi sotto).
- Le **quattro potenze** in alto a destra mostrano il mezzo tipico di ogni fazione in 3D (passa il mouse per farlo ruotare,
  clic per iniziare una campagna con quella fazione); anche le schede fazione della nuova campagna hanno l'anteprima 3D.

## Scenari
Dal menu **Scenari**: scheda con mappa della situazione iniziale, descrizione, obiettivo, fazione consigliata (★), durata
massima (in turni), avversari e nebbia; si può giocare con qualunque fazione e scegliere la difficoltà dell'IA. All'avvio un **briefing**,
poi il **pannello dell'operazione** in alto a sinistra mostra obiettivo, avanzamento e turni rimasti;
la schermata finale riporta lo scenario e il motivo della vittoria.

| Scenario | Fazione consigliata | Obiettivo |
|---|---|---|
| Guerra lampo | FO | 60% del mondo entro il limite di turni; arsenali pieni e tregua minima |
| Assedio del Pacifico | CP | CP resiste fino all'ultimo turno nella fortezza d'isole; gli altri devono eliminarla per primi |
| Blocco d'acciaio | FO | FO (Europa + Asia del nord) resiste fino all'ultimo turno contro un'alleanza che deve ridurla a 3 territori |
| Corsa al petrolio | UL | tenere 3 dei 5 giacimenti per alcuni turni consecutivi |
| Mondo diviso | AAN | duello a due su un mondo spartito a caso, con nebbia: 60% del mondo o eliminare il rivale |

## Comandi
**Tabellone**
| Azione | Comando |
|---|---|
| Telecamera | WASD / frecce / bordi schermo, tasto centrale = trascina, rotella = zoom, Q/E = ruota |
| Seleziona territorio | clic sinistro |
| Attacca / sposta | tuo territorio → clic (o clic destro, o trascina) su un bersaglio evidenziato → pannello con i cursori |
| Schiera i rinforzi | clic su un tuo territorio verde (schieramento già attivo nel rifornimento), N = attiva/disattiva |
| Fase successiva / fine turno | pulsante principale del riquadro ORDINI, Invio = fine turno |
| Obiettivo, potenze, carte, mercato, continenti, registro | barra a icone a sinistra |
| Turno delle IA | Spazio = accelera, di nuovo = salta l'animazione |
| Guida, menu | F1 o H, Esc |
| Salvataggio rapido / caricamento | F5 / F9 |
| Schermo intero | Alt+Invio |

**Battaglia 3D**
| Azione | Comando |
|---|---|
| Telecamera | WASD / frecce / bordi, rotella, Q/E, Home = torna all'esercito |
| Seleziona | clic, riquadro, doppio clic = stesso tipo, Ctrl+A = tutti |
| Ordini | tasto destro = muovi/attacca, G = attacco in movimento, H = alt, X = fuoco d'area, B = sbarramento |
| Gruppi | Ctrl+1..9 crea, 1..9 richiama (doppio tocco = centra) |
| Abilità | F = cortina fumogena (ricarica), J = supporto aereo (una volta per battaglia), T = mantieni posizione |
| Altro | C = centra la selezione, V = vai all'allarme, P/Spazio = pausa, Invio = inizia/continua |
| Modalità foto | F10 (o pulsante «Foto»): pausa, interfaccia nascosta, telecamera libera (WASD, Q/E quota, tasto destro + mouse, rotella zoom); Invio = scatta (PNG in `%APPDATA%\Godot\app_userdata\Frontline Dominion\screenshots`), Esc = esci |

## Funzionalità principali
- 4 fazioni con vantaggi diversi, IA in 3 difficoltà, modalità Conquista mondiale e Obiettivo segreto, spettatore.
- Economia (denaro, petrolio, acciaio, manodopera), 6 edifici, 4 livelli tecnologici, mercato internazionale.
- **Tabellone a turni** (Rifornimento › Attacco › Spostamento), un attacco e uno spostamento per turno, fortificazioni a livelli.
- Rifornimenti, petrolio, tregua iniziale, milizia, occupazione e riorganizzazione dopo le conquiste.
- Carte Comando (rinforzi, missile, sabotaggio, golpe) e **carte inganno** (divisione falsa, silenzio radio, ricognizione); bonus dei continenti.
- **La campagna decide la battaglia** (`docs/omogeneita.md`): battaglie di 5 minuti con **obiettivi** dal territorio (QG, edifici, ponti, alture),
  **rinforzi** dai territori vicini a metà battaglia, supporto aereo solo con aeroporto, tiro navale con porto, **ritirata ordinata**,
  comando diretto +10% ed esperienza doppia, **logoramento** (−15% per un turno dopo ogni battaglia).
- **Veterani** (fino a 3 stelle), **nebbia di guerra**, **patti di non aggressione** con le IA.
- Battaglie 3D: schieramento iniziale, minimappa, terreni diversi (città, foresta, deserto, montagna, artico, pianura, costa),
  ora del giorno e meteo, esplosioni, fumo, relitti, danni visibili sui mezzi.
- Salvataggi su più slot, salvataggio automatico, schermata finale con grafici, guida alla prima partita, musica dinamica.
- **Scenari** con briefing iniziale, pannello dell'operazione (obiettivo, avanzamento, turni rimasti) e schermata finale dedicata.
- **Abilità di battaglia**: cortina fumogena (F), supporto aereo (J), mantieni posizione (T).
- **Mezzi diversi per fazione** (sagome riconoscibili; l'Unione Libera usa mezzi improvvisati), ciclo giorno/notte sul tabellone.
- Termini uniformi in tutta l'interfaccia (es. livelli tecnologici sempre come «Tech 2 · Moderna»).
- Tutti i modelli, gli effetti, la musica e i suoni sono generati proceduralmente in codice: nessun asset esterno.

## Struttura
```
scripts/core/   data.gd (dati e bilanciamento), game.gd, combat.gd, ai.gd, settings.gd, sfx.gd, music.gd, shot.gd
scripts/map/    tabellone 3D (generazione mondo, shader terreno/acqua/nuvole, telecamera, distintivi)
scripts/battle/ battaglia (battle_sim.gd = logica, battle3d.gd = vista, terreno, effetti, HUD, telecamera)
scripts/models/ modelli procedurali (UnitModels, NavalModels, Props, Vfx, ModelKit)
scripts/ui/     menu, HUD, finestre, salvataggi, impostazioni, grafici, guida
scenes/         main.tscn, world_map.tscn, battle.tscn, model_gallery.tscn
tests/          test headless (vedi sotto)
tools/godot_run.js  lancia Godot con un semaforo (un solo processo alla volta)
SPEC3D.md       contratto tra i moduli
docs/screens/   screenshot
```

## Test (headless)
```
node tools/godot_run.js --timeout=600 -- --headless --path . --script tests/test_core.gd
node tools/godot_run.js --timeout=600 -- --headless --path . --script tests/test_save.gd
node tools/godot_run.js --timeout=600 -- --headless --path . --script tests/test_fase3.gd
node tools/godot_run.js --timeout=600 -- --headless --path . --script tests/test_scenarios.gd
node tools/godot_run.js --timeout=600 -- --headless --path . --script tests/test_battle.gd
node tools/godot_run.js --timeout=600 -- --headless --path . --script tests/test_omogeneita.gd
node tools/godot_run.js --timeout=900 -- --headless --path . --script tests/test_tactics.gd
node tools/godot_run.js --timeout=900 -- --headless --path . --script tests/sim.gd
node tools/godot_run.js --timeout=900 -- --headless --path . --script tests/sim.gd -- --fog=1
node tools/godot_run.js --timeout=900 -- --path . --script tests/test_flow.gd
```
`test_flow.gd` gioca anche alcuni turni dall'interfaccia: attacco con risoluzione automatica, spostamento, fine turno, turni IA,
prompt di difesa, salvataggio automatico e salva/carica a turni.
I test lanciati con `--script` (e gli screenshot con `--shot`/`--quit-after`) non toccano salvataggi e impostazioni del giocatore.
