# Notte 3 — TABELLONE: perché non coinvolge, cosa ho cambiato, cosa decidere al mattino

Agente TABELLONE, 2026-11-11/12. Regole e interfacce nuove: `SPEC3D.md` § «Notte 3 — ritmo del tabellone». File toccati in fondo.

**In una riga:** stanotte il tabellone ha smesso di nascondere (nebbia spenta, attacchi delle IA annunciati, rapporto di ciò
che è successo) e ha guadagnato traguardi vicini (ordini del comando, eventi mondiali). **Non** ho invece cambiato il ritmo di
fondo: resta un attacco per turno e la partita dura quanto prima. Quello è il vero nodo e richiede una scelta (proposte A, C, D).

## 1. Diagnosi (misurata)
Strumenti: `tests/diag_tabellone.gd` (nuovo: partite complete tutte IA, 4 veterani, conquista, battaglie tattiche vere, misurate
**dal posto 0** come sostituto del giocatore) e `tests/sim.gd --bal=conquista` (vittorie per fazione). `--classic=1` = regole di
prima di stanotte. Il flusso dell'interfaccia l'ho letto nel codice e provato con `tests/test_flow.gd` e gli screenshot.

**Attenzione al rumore:** le partite divergono molto (con gli stessi seed, durate da 23 a 94 round). Su 8 partite contano solo
le differenze grosse; dove serviva ho usato 40–80 partite (risoluzione a formula, più veloce).

| Misura | Prima | Dopo | Affidabile? |
|---|---|---|---|
| Round in cui succede qualcosa di nuovo (titoli, operazioni, eventi) | 62 % | 83 % | sì |
| Attacchi subiti dal posto 0 annunciati un turno prima | 0 % | 46 % | sì |
| Obiettivi a breve termine per partita (4 giocatori) | 0 | 59 assegnati, 22 eseguiti | sì |
| Eventi mondiali per partita | 0 | 10 | sì |
| Territori nemici di cui la nebbia predefinita dà solo una stima | 63–77 % | 0 % | sì |
| Attesa dei turni IA per round (3 IA, velocità normale; stima: azioni × attesa) | ~9,5 s | ~6,5 s | sì |
| Battaglie / conquiste per round (tutto il mondo) | 2,3 / 2,4 | 2,6 / 2,7 | forse |
| Durata, 8 partite tattiche (round) | 46 (23–94) | 41 (24–63) | no: rumore |
| Durata, 80 partite a formula (round) | 42 | 41 | sì: **invariata** |
| Turni del posto 0 con 0 / 1 / 2+ attacchi vincibili | 7 % / 7 % / 87 % | 9 % / 9 % / 82 % | invariato |
| Turni in cui il posto 0 attacca | 86 % | 72 % | invariato (rumore) |
| Primi 5 round: attacchi del posto 0 / territori al round 6 | 4,4 / 7,3 | 4,5 / 7,8 | invariato |

Altri numeri della situazione di partenza:
- **23 territori su 42 sono neutrali** all'inizio (5 a testa ai giocatori) e la tregua dura 2 round: il primo attacco del posto 0
  a un giocatore arriva al round 3–11. I primi turni sono «un neutrale per turno».
- **Un turno del giocatore**: 1 clic per schierare, ~3 per reclutare, 1 cambio fase, 3 per l'attacco (origine, bersaglio,
  «Attacca»), 1 cambio fase, 3 per lo spostamento, 1 fine turno = **~13 clic (3 al minimo)**, 40–60 s con la risoluzione
  automatica. Il turno non è lento: è **povero** (un attacco e uno spostamento su 42 territori).
- **Battaglie che coinvolgono il giocatore**: ~0,8 attacchi suoi + ~0,6 subiti per turno × ~42 turni ≈ **60 a partita**.
  Giocate tutte in 3D (fino a 5 minuti l'una) sono 4–5 ore di sole battaglie, molte contro neutrali o presidi deboli.
- **Turni IA**: 3,6 azioni per turno × 0,9 s × 3 IA ≈ 10 s per round, tutte con la stessa attesa (anche uno schieramento
  lontano), e alla fine un solo toast («… altre N nel Registro»). All'inizio del turno la telecamera è sul QG.
- **Informazione nascosta**: nebbia leggera predefinita (solo stime su ~70 % dei territori nemici), carte inganno attive anche
  senza nebbia, «?» sulle città dell'Unione Libera e soprattutto **le intenzioni delle IA**: ~0,6 attacchi subiti per turno,
  tutti senza preavviso.
- **Bilanciamento delle fazioni** (80 partite a formula, prima di stanotte): AAN 23 %, FO 30 %, CP 34 %, UL 14 %: non era
  pari nemmeno prima.

### Ipotesi, in ordine di impatto
1. **Poco da decidere per turno, nessun traguardo vicino.** Le opzioni ci sono (87 % dei turni con 2+ attacchi vincibili) ma
   se ne sceglie una sola e nulla le distingue: l'unico obiettivo è «il 70 % del mondo», a 40+ turni di distanza.
   → stanotte: ordini del comando ed eventi mondiali. Resta aperto: più attacchi per turno (proposta A).
2. **Si subisce senza vedere arrivare** (il nascondino del tabellone): attacchi dal nulla, nebbia, inganni.
   → stanotte: nebbia spenta di default, inganni solo con la nebbia, minacce annunciate, rapporto del round.
3. **Troppe battaglie uguali, poche decisive** (~60 a partita). → proposte D e C.
4. **Partita lunga senza fine in vista** (42 round medi, code fino a 90+). → proposte A, C, G.
5. **Inizio lento** (23 neutrali, uno per turno). → stanotte: due attacchi nei round di tregua (aiuta il giocatore; le IA non
   lo sfruttano quasi, vedi tabella). Resta aperto.
6. **Attese e turni IA poco leggibili.** → stanotte: attese pesate e rapporto «Dall'ultimo turno».

## 2. Cosa ho cambiato stanotte (tutto con test)
1. **Nebbia predefinita «nessuna»** (menu e nucleo); leggera e totale restano opzioni. Le **carte inganno** (divisione falsa,
   silenzio radio, ricognizione) si giocano **solo con la nebbia**: senza, non compaiono e il nucleo le rifiuta.
2. **Minacce annunciate.** A fine turno ogni IA dichiara l'attacco a un giocatore che prepara per il turno dopo (stessa
   valutazione degli attacchi veri, contando i rinforzi in arrivo). Il giocatore lo vede: pulsante rosso «MINACCIA ·
   territorio» in alto, riga ⚠ nel rapporto, freccia tratteggiata sul tabellone (disegnata da GRAFICA), tooltip. Può rinforzare,
   fortificare, colpire per primo. Il 44 % delle minacce diventa un attacco (le altre sono dissuase o superate da un'occasione
   migliore); il 46 % degli attacchi subiti è preannunciato. Con la nebbia si vede solo se la partenza è in vista.
3. **Ordini del comando**: sempre un obiettivo a breve termine, «Conquista X entro il round N» (3 turni), premio una carta
   Comando, 4 FAN o 150 $. Riga ★ nel riquadro ORDINI, segnale sul tabellone, tooltip. Anche le IA li ricevono (non li
   inseguono: incassano il premio se capita, altrimenti il bilanciamento si spostava, vedi sotto).
4. **Eventi mondiali** visibili a tutti, dal round 3 ogni 4 round: territorio premio (convoglio 250 $; giacimento 80 petrolio
   + 120 acciaio; archivi = una carta: incassa chi lo controlla due round dopo), diserzioni (un presidio neutrale dimezzato),
   finestra di bel tempo (un attacco in più per tutti in quel round). Riga ◆ nel riquadro ORDINI e titolo «Ultim'ora».
5. **Due attacchi per turno nei round di tregua** (solo i neutrali sono attaccabili), per aprire la partita più in fretta.
6. **Turni IA più rapidi e leggibili**: attesa piena solo dopo un attacco in vista (0,6 dopo uno spostamento, 0,3 dopo
   schieramenti e fortificazioni); all'inizio del turno il **rapporto «Dall'ultimo turno»** in alto a sinistra: fino a 6 righe
   cliccabili che inquadrano il territorio (minacce, territori persi o difesi, missili/sabotaggi/golpe, titoli, conquiste altrui).
7. **Salvataggi v4**; v2 e v3 si caricano (ordini ed eventi partono dal turno dopo).
8. Guida F1: nuova sezione «Ordini, eventi e minacce»; nebbia e «Battaglie» aggiornate (richiesta di BATTAGLIA: contatti «?»,
   chi spara si rivela, obiettivi al centro in 30 s, rinforzi annunciati); voce «Crediti» dei modelli 3D (richiesta di GRAFICA).

**Provato e scartato** (le leve restano, spente):
- *Neutrali iniziali più leggeri* (`Data.NEUTRAL_START_LIGHT`): su 40 partite la FO passava dal 38 % allo 0–10 % di vittorie.
- *IA che insegue il proprio ordine del comando* (`AIController.mission_bonus` 5 o 2): FO dal 38 % al 15–18 %, a favore di UL/CP.
- *IA che evita gli attacchi non annunciati* (`surprise_mul` 0,75): nessun guadagno chiaro (minacce mantenute 51 % contro
  48 % su 6 partite) e AAN penalizzata (dal 28 % all'8 % su 40 partite, a parità del resto).

**Bilanciamento dopo i cambi** (80 partite a formula, `sim.gd --bal=conquista --tactical=0 --seeds=1-80`):

| | AAN | FO | CP | UL | Durata |
|---|---|---|---|---|---|
| Prima (`--classic=1`) | 23 % | 30 % | 34 % | 14 % | 42 round |
| Dopo | 24 % | 19 % | 43 % | 15 % | 41 round |

Le differenze (FO −11, CP +9) sono ai limiti del rumore (±5 punti per fazione); lo squilibrio CP forte / UL debole c'era già
e va tarato a parte. Da sole le regole «eventi mondiali + due attacchi nella tregua» danno esattamente i numeri di prima
(AAN 28, FO 38, CP 25, UL 10 contro 28, 38, 23, 13 sulle stesse 40 partite): lo scarto viene dai premi degli ordini.

Screenshot (`docs/screens/notte3/`): `tab_prima_turno.png` (prima), `tab_dopo_turno.png` (rapporto in alto a sinistra, riga
★ dell'ordine nel riquadro ORDINI), `tab_dopo_minaccia.png` (pulsante MINACCIA, frecce tratteggiate, evento mondiale).

## 3. Proposte per il mattino (NON implementate: serve una scelta)
**A. Più attacchi per turno (ritmo da Risiko).** Oggi 1 (2 nella tregua). L'interruttore c'è già (`Data.TURN_RULES.attacks`
oppure `opts.attacks_per_turn`); misurato su 8 partite tattiche con `diag_tabellone.gd --apt=N`:

| Attacchi per turno | Durata (round) | Battaglie per round | Attacchi subiti dal giocatore per turno | …di cui annunciati |
|---|---|---|---|---|
| 1 (attuale) | 41 (24–63) | 2,6 | 0,50 | 46 % |
| 2 | 24 (15–40) | 3,7 | 0,76 | 20 % |
| 3 | 20 (15–26) | 4,3 | 0,99 | 13 % |

Pro: è l'unica leva misurata che accorcia davvero la partita e dà più iniziativa per turno. Contro: più battaglie per turno
(in 3D il tempo esplode: va insieme a D), difese più fragili, il preavviso copre solo un attacco su cinque (l'IA ne annuncia
uno), fazioni da ritarare. Variante prudente, **«sfondamento»**: un secondo attacco solo dopo una conquista, non dal territorio
appena preso. Costo: mezza notte lo sfondamento, una notte A con taratura di IA e fazioni.

**B. Turni simultanei** (tutti danno gli ordini, poi si risolvono insieme). Pro: zero attese, tensione. Contro: riscrive
nucleo, IA, interfaccia e tutorial (2–3 notti), servono regole per gli scontri incrociati, e riporta incertezza sulle
intenzioni (l'opposto delle minacce annunciate). Lo sconsiglio adesso: prima vedere se A + D bastano.

**C. Partite brevi.** «Partita rapida»: vittoria al 50 % del mondo (oggi 70 %) e limite di 25 round con vittoria a punti; oppure
mondo ridotto (2–3 continenti, 2 avversari). Pro: una partita in una serata, la fine è sempre in vista. Contro: meno epica (la
conquista mondiale resta come modalità lunga). Costo: poche ore (`victory_share` e `round_limit` esistono già per gli
scenari) più una voce nel menu.

**D. In 3D solo le battaglie che contano.** Oggi ogni attacco chiede «3D o automatica». Proposta: il 3D è proposto solo per QG,
territorio dell'ordine del comando, territorio premio, scontri alla pari e difese annunciate; le altre si risolvono da sole con
un'animazione di 2 s sul tabellone e una riga di esito (resta «comanda lo stesso»). Pro: da ~60 a ~10–15 battaglie 3D a
partita, tutte significative. Contro: meno 3D per sfizio. Costo: mezza notte (interfaccia).

**E. Punti azione al posto delle tre fasi** (3 azioni a scelta per turno). Pro: priorità vere. Contro: tutorial, guida e IA da
rifare (1–2 notti); A dà quasi lo stesso con molto meno.

**F. Piccole, da decidere al volo:** (1) le città dell'Unione Libera mostrano «?» anche senza nebbia (privilegio di fazione
«guerriglia urbana»): toglierlo quando la nebbia è spenta? (2) Vista d'insieme all'inizio del turno invece che sul QG.
(3) Presidi neutrali più leggeri solo insieme a un ritocco della FO. (4) Bilanciamento CP/UL (c'era già).

**G. Vittoria a punti sempre visibile** (territori + continenti + ordini eseguiti), classifica nella barra dei turni e fine al
round 25–30. Si sposa con C.

**Consiglio:** D + C subito (poche ore, rischio basso), poi A nella variante «sfondamento» con una notte di taratura.

## 4. File toccati
- Nucleo: `scripts/core/game.gd` (regole del ritmo, salvataggio v4), `scripts/core/ai.gd` (annuncio e mantenimento delle
  minacce, più attacchi nel turno, leve `surprise_mul`/`mission_bonus`), `scripts/core/data.gd` (costanti nuove).
- Interfaccia: `scripts/main.gd` (rapporto del round, minacce, riga degli obiettivi, attacchi rimasti, nebbia predefinita,
  demo `--threat=1`), `scripts/ui/hud.gd` (riquadro del rapporto, riga ★/◆, pulsante MINACCIA, tooltip, carte inganno nascoste
  senza nebbia), `scripts/ui/menu.gd`, `scripts/ui/modal.gd` (guida F1, crediti), `scripts/ui/coach.gd`, `scripts/ui/tutorial.gd`.
- Test: `tests/test_core.gd` (`test_pace`, ritmo IA), `tests/test_save.gd` (`test_save_v4`), `tests/test_flow.gd` (nebbia spenta,
  ordine del comando, secondo attacco nella tregua, rapporto, minaccia), `tests/sim.gd` (leve di confronto),
  `tests/diag_tabellone.gd` (nuovo), `tests/test_omogeneita.gd` (una riga: versione del salvataggio ≥ 3).
- Documenti: `SPEC3D.md`, `README.md`, `docs/omogeneita.md`, `docs/notte3_richieste.md`.
