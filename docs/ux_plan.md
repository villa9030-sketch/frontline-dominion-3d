# Piano UX — schermata strategica (FASE 6, turni)

Feedback del giocatore: «non capisco bene come funziona il gioco, la UI è caotica e non capisco cosa devo fare».
Prima: barra risorse + barra turni + chip, colonna sinistra (potenze, mercato, continenti), pannello territorio lungo
(forze, fortificazioni, edifici, reclutamento), riga in basso (carte, rinforzi, registro), toast e banner. Tutto insieme.

## Principi
1. **Una sola guida "cosa fare adesso"** (riquadro *Ordini* in basso al centro): fase, istruzione grande, esito dell'ultima
   azione, pulsante principale contestuale e grande. Il tabellone fa pulsare ciò che si può cliccare adesso.
2. **Mostrare solo ciò che serve ora**: potenze, carte, mercato, continenti, obiettivo e registro passano in una
   **barra a icone** a sinistra che apre un cassetto (chiuso di default, uno alla volta) con badge quando serve.
   Il pannello del territorio è un riassunto; reclutamento / edifici / fortificazioni sono **schede** visibili solo
   nel Rifornimento e solo sui propri territori.
3. **Gerarchia visiva**: tre corpi (titoli 18–20, testo 14, piccolo 12), spaziature 8/12, meno bordi, stessa palette
   "console militare" (verde-grigio, ambra = azione, rosso = nemico, verde = proprio/schiera, azzurro = spostamento).
   Massimo 2 toast brevi, banner di turno breve.
4. **Tutorial guidato** del primo turno (prima campagna o pulsante «Tutorial» nel menu): freccia sull'elemento vero,
   aspetta l'azione del giocatore, saltabile.
5. **Riscontro**: dopo ogni azione una riga «✓ …» nella guida + passo successivo; tooltip italiani su icone e valori.
6. Nessuna funzione tolta: solo riorganizzata.

## Layout (1600×900 logici; 1920×1080 scala uguale)
```
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│ FRONTLINE DOMINION │ $ 771 +172 │ ⛽ 279 │ ⚙ 290 │ 👥 203 │ TECH 1 [Ricerca → Tech 2]  │ ? │ ♪ │ Menu │
├────┬───────────────────────────┬─────────────────────────────────────────┬───────────────┤
│ ⚑  │                           │ ⧗ TURNO 3 · Tocca a te                  │ CANADA OVEST ✕│
│Obi.│  (cassetto chiuso:        │ ① Rifornimento › ② Attacco › ③ Sposta.  │ N.America·For.│
│ ♜  │   mappa libera)           │   [Tregua: ancora 1 turno]              │ ■ AAN (tu)    │
│Pot.│                           └─────────────────────────────────────────┘ FORZE 12 unità │
│ 🂠3 │                                                                     │ [FAN 9][CAR 3]│
│Car.│            mappa 3D: i territori cliccabili ADESSO pulsano          │ ───────────── │
│ $  │            (verde = schiera, ambra = può attaccare, rosso =         │ [Recluta|Edi- │
│Mer.│             bersagli, azzurro = spostamento)                        │  fici|Fortif.]│
│ ◎  │                                                                     │ (solo Riforn.)│
│Con.│                                                                     │ Fanteria +1 +5│
│ ☰ 2│      toast (max 2, brevi)                                           │ ...           │
│Reg.│  ┌────────────────────── ORDINI ─────────────────────────────────┐  │               │
│    │  │▌FASE 1 DI 3 · RIFORNIMENTO                                    │  │               │
│    │  │▌✓ 6 rinforzi schierati in Grandi Pianure                      │  │               │
│    │  │▌Puoi reclutare, costruire o fortificare nel pannello   [ Fase │  │               │
│    │  │▌del territorio, poi passa all'attacco.                 successiva:│               │
│    │  │▌                                         Fine turno ⏎   Attacco ›]│               │
│    │  └───────────────────────────────────────────────────────────────┘  │               │
└────┴─────────────────────────────────────────────────────────────────────┴───────────────┘
```
Cassetto aperto (es. Carte): pannello largo 330 accanto alla barra a icone, sopra la mappa, con titolo e ✕.

## Guida per fase (testi)
| Situazione | Istruzione | Pulsante principale |
|---|---|---|
| Rifornimento, rinforzi > 0 | «Hai N rinforzi: clicca un tuo territorio (in verde) per schierarli» | Fase successiva: Attacco › (chiede conferma se restano rinforzi) |
| Rifornimento, rinforzi = 0 | «Puoi reclutare, costruire o fortificare nel pannello del territorio, poi passa all'attacco» | Fase successiva: Attacco › |
| Attacco, nessuna selezione | «Scegli un tuo territorio con almeno 2 unità (pulsano in ambra), poi un nemico confinante evidenziato in rosso — oppure salta l'attacco» | Salta attacco › |
| Attacco, origine scelta | «Clicca un bersaglio rosso: si apre il pannello d'attacco» | Salta attacco › |
| Attacco eseguito | «Attacco eseguito. Ora puoi spostare truppe» | Fase successiva: Spostamento › |
| Spostamento | «Facoltativo: clicca un tuo territorio, poi un tuo territorio collegato (in azzurro) per spostare truppe» | Fine turno ✓ |
| Turno IA | «Turno della Federazione Orientale… guarda le frecce sul tabellone» | Accelera (Spazio) / Salta animazione |
| Carta da giocare (bersaglio) | «Missile: clicca un territorio nemico evidenziato» | Annulla |

## Tutorial guidato (primo turno)
1. Benvenuto (cosa sono i turni) → [Inizia] / [Salta tutorial]
2. Schiera: freccia sul QG → attende rinforzi = 0
3. Recluta: freccia sulla scheda Recluta, «+1 Fanteria» → attende una recluta (o Avanti)
4. Fine fase: freccia sul pulsante principale → attende fase Attacco
5. Scegli l'origine: freccia sul territorio consigliato → attende la selezione
6. Scegli il bersaglio: freccia sul bersaglio rosso → attende il pannello d'attacco
7. Pannello d'attacco: cursori, previsione, «comando diretto (3D)» vs «risoluzione automatica» → attende l'attacco
8. Esito + Spostamento: freccia sul pulsante principale → fase Spostamento
9. Sposta (facoltativo) → attende spostamento o Avanti
10. Fine turno: freccia sul pulsante → attende il turno IA
11. Turno IA (Spazio accelera; se ti attaccano scegli difesa 3D o automatica) → attende il tuo turno
12. Difesa (se capita): freccia sui pulsanti del prompt
13. Fine: le schede a sinistra, F1 = guida

## Note tecniche
- `hud.gd`: barra in alto snella, barra turni = solo stato/fasi, `guide` (riquadro Ordini), `rail` + `drawer`,
  pannello territorio a schede. `toasts.gd`: max 2, 3 s. `coach.gd`: tutorial guidato (sostituisce i passi base
  di `tutorial.gd`, che resta per i suggerimenti di battaglia/carte/ricerca).
- `main.gd`: `guide_state()` (testo + pulsante), `click_marks()` (cosa pulsa), schieramento in un clic quando ci sono
  rinforzi, `feedback()` per l'esito delle azioni, `start_tutorial()`. Settings: `tutorial_done`.
