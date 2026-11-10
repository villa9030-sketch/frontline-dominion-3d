# Modelli 3D candidati per i mezzi (da approvare — NON scaricati nel progetto)

Oggi i mezzi sono generati in codice (`scripts/models/*`, shader `paint.gdshader`). Se si vuole alzare il livello con
modelli esterni, questi sono quelli trovati con licenza libera. Regola: **CC0 preferibile** (nessun obbligo), **CC-BY**
accettabile (va citato l'autore nei crediti del gioco, `PER_INIZIARE.md` o una schermata "Crediti"). Niente "royalty free"
di CGTrader/Sketchfab senza CC: non sono licenze libere.

Tutti sono low-poly stilizzati (lo stile attuale del gioco è low-poly realistico: si integrano con lo shader `paint.gdshader`,
che aggiunge mimetica, usura e fango su qualsiasi mesh). Pesi e poligoni "n.d." = non indicati nella pagina: da verificare
al momento del download (sono tutti sotto i 2 MB per modello, tipicamente 500-3000 triangoli).

| # | Modello | Fonte / URL | Licenza | Formato | Peso | Poligoni | Uso previsto |
|---|---------|-------------|---------|---------|------|----------|--------------|
| 1 | **Animated Tanks Pack** (4 carri animati, torretta e cingoli) — Quaternius | https://quaternius.com/packs/animatedtanks.html | **CC0** | FBX, OBJ, Blend | n.d. (pack ~10 MB) | n.d. (low-poly, ~1-2k/carro) | carri delle 4 fazioni (colori dallo shader) |
| 2 | **Tank** — Quaternius (su Poly Pizza) | https://poly.pizza/m/FA5daiyZQq | **CC0** | glTF, FBX | n.d. | n.d. (low-poly) | carro alternativo / carro leggero |
| 3 | **Tank** (varianti) — Quaternius | https://poly.pizza/m/cW3zvvkMOM · https://poly.pizza/m/jWS1CLA0RO · https://poly.pizza/m/Dc4k4CooN3 | **CC0** | glTF, FBX | n.d. | n.d. | varianti per fazione |
| 4 | **Light Tank** — Zsky | https://poly.pizza/m/S1jUTRmAjD | CC-BY 3.0 | glTF, FBX | n.d. | n.d. | carro leggero / semovente |
| 5 | **Helicopter** — Zsky | https://poly.pizza/m/hG2Qr0A3zR | CC-BY 3.0 | glTF, FBX | n.d. | n.d. | elicottero d'attacco (rotore separato) |
| 6 | **Helicopter** — jeremy | https://poly.pizza/m/eb7b31pjGtQ | CC-BY 3.0 | glTF, OBJ | n.d. | n.d. | elicottero da trasporto |
| 7 | **Jet** — jeremy | https://poly.pizza/m/6fyLMORhgGK | CC-BY 3.0 | glTF, OBJ | n.d. | n.d. | caccia |
| 8 | **Military Boat** — Zsky | https://poly.pizza/m/wouBxOe3CD | CC-BY 3.0 | glTF, FBX | n.d. | n.d. | mezzo da sbarco / pattugliatore (costa) |
| 9 | **Low Poly T-72 Tank – Game Ready** — Mr. The Rich | https://sketchfab.com/3d-models/low-poly-t-72-tank-game-ready-8c9d0d6640a244e39082cd9fdf565cef | CC-BY 4.0 | glTF/FBX (download Sketchfab) | n.d. (< 2 MB) | **1.5k tri / 833 vert** | carro Federazione Orientale (stile sovietico) |
| 10 | **Low Poly Abrams Free Model** — Lasha-Georgy Bajadze | https://sketchfab.com/3d-models/low-poly-abrams-free-model-ee925340fd0249bfac6f766c7eb81abd | CC-BY 4.0 | glTF/FBX | n.d. | **15.6k tri / 9.2k vert** (pesante: solo con LOD) | carro Alleanza Atlantica |
| 11 | **Blender models for freeciv units** (tank, helicopter, APC…) — yd | https://opengameart.org/content/blender-models-for-freeciv-units | **CC0** | Blend (da esportare in glTF) | n.d. | n.d. | APC / camion / elicottero |

Note:
- Poly Pizza: i modelli "Poly by Google" sono CC-BY 3.0 (Google Poly, archivio); quelli di Quaternius sono CC0.
- Kenney (kenney.nl) non ha un pacchetto 3D di mezzi militari (solo sprite 2D "Tanks", CC0): i suoi "Car Kit"/"Blocky
  Characters" (CC0) servirebbero solo per auto civili e pedoni.
- Prima di importare: verificare la licenza sulla pagina (può cambiare), scaricare fuori dal progetto, esportare in glTF
  con assi Y-up e avanti = −Z, origine a terra (contratto `UnitModels`: nodi "Turret", "Barrel", "Rotor", "Muzzle").
- Integrazione prevista: `scripts/models/unit_models.gd` carica il glTF se presente in `assets/models/<kind>.glb`, altrimenti
  usa il modello in codice; il materiale viene sostituito con `paint.gdshader` (mimetica di fazione, usura, fango, polvere).
