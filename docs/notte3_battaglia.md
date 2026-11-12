# Notte 3 — agente BATTAGLIA: da "nascondino" a scontro (stile R.U.S.E.)

Contratto aggiornato in `SPEC3D.md` (sezione «Notte 3 — battaglia»). Richieste e accordi con GRAFICA/TABELLONE in
`docs/notte3_richieste.md`. Nessun commit.

## Cosa è cambiato (in breve)
1. **Gettoni «?»**: ogni nemico ha due livelli, *contatto* (`u.known[si]`: posizione nota, tipo ignoto) e *identificato*
   (`u.spotted[si]`). È un contatto chiunque sia allo scoperto, in movimento o abbia appena sparato — ovunque sul campo —
   e chi è fermo in copertura entro 1500 px da una nostra unità (ricognizione ×1.6). Il fuoco diretto vuole
   l'identificazione; l'**artiglieria tira anche sui «?»** (dispersione ×1.7), da sola e su ordine (clic sul gettone).
   L'IA usa le stesse informazioni. Un lato ridotto sotto il 35 % è «allo sbando»: non può più nascondersi (niente caccia
   agli ultimi superstiti).
2. **Chi spara si rivela** per 6 s: posizione nota ovunque, tipo identificato entro 1.5× la sua gittata (carri 2100 px,
   artiglieria tutto il campo; fanteria allo scoperto 700 px; fanteria che spara da una copertura solo entro 420/380 px:
   resta un «?» da stanare). Imboscata ridotta a ×1.25 e **solo sul primo colpo** (era ×1.6 per 5 s).
3. **Contatto rapido**: schieramenti a 1560 px dai bordi (erano 1150: la terra di nessuno scende da 2500 a 1680 px);
   **obiettivi al centro e contesi**: 3–4 per battaglia, almeno 2 neutri nella fascia 42–66 % del campo (ponti/guadi, altura,
   crocevia, località del terreno; in città piazze/incroci), il primo edificio del territorio al 60 % (non più in fondo);
   conquista in **30 s** (era 60); punteggio «tu N · nemico M» nell'HUD.
4. **IA attiva**: entrambi i lati mandano distaccamenti sugli obiettivi (presidio, conquista, riconquista, contrattacco dove
   il nemico mette piede); il difensore parte con i presidi già sugli obiettivi dalla sua parte, i suoi carri stanno in linea
   con la fanteria e manovrano (non più «tutti fermi nel bosco»); chi sta perdendo ai punti dopo 45 s butta tutto sugli
   obiettivi; nei tempi morti (8 s senza danni) o col nemico allo sbando fanteria e carri vanno sul contatto più vicino;
   il difensore passa all'attacco se è più forte. L'IA chiama l'**attacco aereo annunciato** (7 s di preavviso) sul gruppo
   di contatti più denso.
5. **Eventi**: evento `announce` con conto alla rovescia per rinforzi (20 s prima; arrivano a 90 s il difensore, 105 s
   l'attaccante), attacco aereo, obiettivo minacciato, nemico allo sbando; `sim.pending` per i segnali persistenti. HUD:
   avvisi, frecce ai bordi, conto alla rovescia dell'attacco aereo. GRAFICA li disegna in 3D (`battle_signs.gd`).
6. **HUD** (modifiche piccole): gettone «?» 2D sui contatti (con il simbolo del tipo se già identificati una volta), rombo
   sulla minimappa, lampo accanto a chi è rivelato (arancione le proprie unità in copertura viste dal nemico, giallo i
   nemici visti per il fuoco), stato degli obiettivi «al nemico tra N s».
7. **Bilanciamento** rifatto sul nuovo ritmo: scala del danno `K` 0.3 → 0.18 (il contatto è immediato, lo scontro deve
   durare), iniziativa dell'attaccante 1.6 → 1.2, difesa in città ×1.35 (`DEF_TERRAIN`), anticarro in copertura ×8 (era 5),
   stallo IA dopo 60 s senza danni, ritirata dell'IA attaccante da 80 s sotto il 40 %.

## Numeri prima / dopo
Metrica: `tests/test_tactics.gd --only=fun` — specchio 10 fanterie + 5 carri + 2 artiglierie, 6 terreni × 2 seed (metà con
edifici), IA contro IA a passo reale 0.1 s, misurata dal lato attaccante. «Prima» = stesso test sul commit 254a8b3.

| Misura | Prima (notte 2) | Dopo (notte 3) | Obiettivo |
|---|---|---|---|
| Primo nemico noto (posizione) | 60 s tipico (49–78 s); in città **mai** | **0.1 s** | — |
| Primo scontro diretto (le parti si sparano a vista) | **60 s** fuori città, mai in città (media 102 s) | **9.9 s** (peggiore 17 s) | < 30 s |
| Tempo con uno scontro in corso (colpi mirati negli ultimi 4 s) | 27 % | **96 %** (solo fuoco diretto 54 %) | > 60 % |
| Secondi senza alcun nemico noto, per battaglia | 158 s | **0 s** | — |
| Finestra più lunga senza nemici noti | 91 s | **0.3 s** | ≤ 40 s |
| Cambi di possesso degli obiettivi per battaglia | 0.2 | **3.3** | — |

Prima, il «fuoco» dei primi 60 s era solo artiglieria alla cieca sulle coperture (non conta come scontro); in città le due
IA non si vedevano mai e la battaglia finiva per stallo a 90 s.

**Difensore a forze pari per mappa** (`--only=maps`, specchio 10f5c2a, 16 seed per mappa, risoluzione automatica):

| Mappa | Prima | Dopo |
|---|---|---|
| pianura | 75 % | 62 % |
| foresta | 69 % | 62 % |
| montagna | 69 % | 62 % |
| deserto | 81 % | 69 % |
| artico | 75 % | 81 % |
| urbano | 69 % | 69 % |
| **media** | **73 %** (69–81) | **68 %** (62–81) |

Con 16 seed l'errore su una mappa è ±12 punti: le differenze tra mappe sono dentro il rumore. Altre serie (`--only=balance`):
esercito doppio in campo aperto 16/16 all'attaccante; 1.5× misto 15/16; specchi di composizione diversa: 6f3c1a
attaccante 9/16, 10f5c2a 6/16, 10f5c in foresta 9/16 (media difensore 50 %: gli eserciti piccoli e senza artiglieria
favoriscono chi attacca, quelli con artiglieria chi difende); con contraerea ed elicotteri difensore 56 %.
**Fazioni** (specchio 8f4c2a in foresta, 12 seed in attacco + 12 in difesa): prima 50–58 % (forbice 8), dopo **50–58 % (forbice 8 punti)**: AAN e CP 50 %, UL 54 %, FO 58 %.

Tempi della risoluzione automatica invariati (≈ 90–260 ms per battaglia).

## File toccati
- Miei: `scripts/battle/battle_rules.gd` (costanti notte 3: `CONTACT_*`, `REVEAL_*`, `FRONT_X`, `OBJ_BAND/MID/SEP`,
  `ROUT_FRAC`, `WARN_T`, `AI_AIR_*`, `DEF_TERRAIN`…), `battle_sim.gd` (contatti in `_upd_vis`, rivelazione, bersagli
  dell'artiglieria, obiettivi, schieramenti, annunci, attacco aereo annunciato, sbando), `battle_ai.gd` (`_obj_tasks`,
  `_cap_unit`, pressione, contrattacco, attacco aereo), `tests/test_tactics.gd` (`t_contact`, `t_fun`, `t_maps`, serie
  aggiornate), `tests/test_battle.gd` (supporto aereo), `tests/test_omogeneita.gd` (obiettivi al centro, 30 s, annunci).
- Condivisi (piccolo): `battle3d.gd` (`is_contact_unit`, `_on_announce`, eventi `contact`/`announce`), `battle_hud.gd`
  (`draw_contact`, `_draw_contacts`, lampo "rivelato", minimappa, punteggio, conto alla rovescia), `battle_strategic.gd`
  (i contatti contano per il fronte). `battle_orders.gd` non toccato.
- Documenti: `SPEC3D.md`, `docs/omogeneita.md` (nota di aggiornamento), `docs/notte3_richieste.md`, questo file.

## Suite
test_tactics OK (66 verifiche; serie complete a 16 seed) · test_battle OK · test_omogeneita 79/79 · test_flow OK (135 verifiche, errori = 0; finestra 960×540).
Tutte rilanciate dopo l'ultima taratura (K 0.18, iniziativa 1.2, città ×1.35).

## Screenshot (docs/screens/notte3)
- `battaglia_contatti.png` — vista d'insieme a 4 s dall'inizio (giocatore attaccante): i nemici nei boschi sono rombi «?»,
  quelli identificati dai droni hanno la pedina col tipo; obiettivi al centro con «al nemico tra 28 s»; punteggio «tu 0 · nemico 0».
  Demo: `--demo=pianura --human=1 --side=0 --warp=4 --cam=overview --dist=300`.
- `battaglia_annuncio.png` — rinforzi annunciati (frecce 3D di GRAFICA dal bordo, «rinforzi tra 24 s» nel riquadro obiettivi).
  Demo: `--demo=foresta18 --human=1 --side=1 --reinf=1 --warp=70 --until=announce --dist=170`.

## Cosa resta / dubbi
- **Soli carri contro armi combinate (peggiorato, non risolto)**: in foresta una massa di soli carri batte un difensore
  misto (8 fan, 3 carri, 2 art, 1 contraerea, 1 elicottero) 14/16 a potenza pari e 16/16 a 1.3× (nella notte 2 a 1.3×
  vinceva ≤ 50 %). Con i «?» visibili, gli obiettivi allo scoperto al centro e l'imboscata ridotta la fanteria nei boschi non
  logora più i carri; alzare l'anticarro in copertura da ×5 a ×8 non è bastato. Il controllo del test è diventato
  informativo. Piste: obiettivi dentro le coperture, fanteria che tiene il fuoco fino a distanza utile, carri meno precisi
  sulla fanteria al riparo.
- **La composizione pesa più di prima**: lo specchio con artiglieria (10f5c2a) dà il difensore al 62–81 % secondo la mappa,
  ma eserciti piccoli (6f3c1a) o senza artiglieria (10f5c in foresta) danno l'attaccante al 56 %. La taratura per mappa è
  fatta sul primo caso; l'iniziativa dell'attaccante (1.2) è il compromesso tra i due.
- **Ritmo per un giocatore fermo**: nella demo 16f10c3a contro 16f9c3a un attaccante che non dà ordini perde metà esercito
  in 30 s (e il difensore IA altrettanto), misurato con `K` 0.22; con `K` 0.18 non l'ho rimisurato. In partita c'è la pausa
  di schieramento, ma se sembra troppo svelto la leva è `BattleSim.K`.
- La percentuale di **fuoco diretto** (senza contare l'artiglieria mirata) è 54 %: tra un assalto e l'altro lo
  scontro continua a colpi d'artiglieria sui «?». Con un giocatore vero dipenderà da lui; l'IA ora non aspetta più.
- Le battaglie durano 2–3 minuti (IA contro IA): i rinforzi (90/105 s) arrivano a scontro in corso, non a cose fatte.
- Gli obiettivi nuovi (`road`, `site`) hanno solo la bandierina: GRAFICA non ha fatto in tempo a dar loro un oggetto.
- Testo del pannello di selezione dell'HUD (fanteria «×3 entro 60 m al riparo») è di una fase precedente: da riallineare
  alle regole attuali (anticarro ×8 in copertura entro 95 m) — testo dell'HUD, non regola.
- `Combat.predict_battle` (formula) non conosce il nuovo bilanciamento: le previsioni del pannello d'attacco restano quelle
  di prima (difensore un po' sottostimato o sovrastimato a seconda del terreno). Da riallineare in `combat.gd` (nucleo).
