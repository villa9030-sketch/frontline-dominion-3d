class_name BattleRules
extends RefCounted
## FRONTLINE DOMINION 3D — regole tattiche della battaglia (Fase 5, scala R.U.S.E.).
## Sostituiscono in battaglia i valori `Data.UNITS[*].rts` (che restano per il resto del gioco). Tutto in px del piano sim
## (4800 × 2700; 1 px ≈ 0.25 m di vista). Velocità in px/s già finali (niente moltiplicatore SPEED).
##
## Campi per tipo:
##  speed       velocità in terreno aperto
##  range       gittata (fuoco diretto; artiglieria: indiretto)      min_range  gittata minima (artiglieria)
##  view        raggio di vista in aperto (aria: vista dei velivoli × AIR_SEEN)
##  acc_far     moltiplicatore del danno a gittata massima (1 a bruciapelo, interpolato in modo quadratico)
##  move_fire   moltiplicatore del danno sparando in movimento
##  armor       [fronte, fianco, retro] (moltiplicatori del danno subito dal fuoco diretto) o [] = nessuna corazza direzionale
##  conceal     "inf" (si nasconde bene in copertura), "veh" (mezzo: si nasconde poco), "" (mai: velivoli)
##  turret      rotazione torretta (rad/s)      hull  rotazione dello scafo (rad/s)
##  forest_speed/city_speed, forest_view/city_view   moltiplicatori in bosco / in città
##  recon       vede le unità nascoste più lontano (× RECON_CONCEAL)
##  splash      raggio del danno ad area (artiglieria)          deploy  s per piazzarsi dopo un movimento (artiglieria)

const STATS := {
	"inf":   {"speed": 30.0, "range": 360.0, "view": 720.0, "acc_far": 0.55, "move_fire": 0.8, "armor": [],
		"conceal": "inf", "turret": 8.0, "hull": 8.0, "forest_speed": 0.85, "city_speed": 0.95, "forest_view": 0.7, "city_view": 0.7, "recon": false},
	"tank":  {"speed": 44.0, "range": 1400.0, "view": 850.0, "acc_far": 0.5, "move_fire": 0.85, "armor": [1.0, 1.6, 2.5],
		"conceal": "veh", "turret": 0.6, "hull": 1.1, "forest_speed": 0.45, "city_speed": 0.75, "forest_view": 0.55, "city_view": 0.65, "recon": false},
	"art":   {"speed": 30.0, "range": 3800.0, "min_range": 500.0, "view": 550.0, "acc_far": 1.0, "move_fire": 0.0, "armor": [1.0, 1.25, 1.5],
		"conceal": "veh", "turret": 0.5, "hull": 1.0, "forest_speed": 0.5, "city_speed": 0.8, "forest_view": 0.6, "city_view": 0.7, "recon": false,
		"splash": 50.0, "deploy": 4.0},
	"aa":    {"speed": 52.0, "range": 1100.0, "view": 900.0, "acc_far": 0.65, "move_fire": 0.75, "armor": [1.0, 1.25, 1.5],
		"conceal": "veh", "turret": 2.5, "hull": 2.0, "forest_speed": 0.55, "city_speed": 0.8, "forest_view": 0.6, "city_view": 0.7, "recon": false},
	"heli":  {"speed": 130.0, "range": 750.0, "view": 1500.0, "acc_far": 0.7, "move_fire": 0.9, "armor": [],
		"conceal": "", "turret": 3.0, "hull": 3.0, "forest_speed": 1.0, "city_speed": 1.0, "forest_view": 1.0, "city_view": 1.0, "recon": true},
	"jet":   {"speed": 260.0, "range": 550.0, "view": 1000.0, "acc_far": 0.8, "move_fire": 1.0, "armor": [],
		"conceal": "", "turret": 5.0, "hull": 1.9, "forest_speed": 1.0, "city_speed": 1.0, "forest_view": 1.0, "city_view": 1.0, "recon": false},
	"drone": {"speed": 140.0, "range": 500.0, "view": 1800.0, "acc_far": 0.7, "move_fire": 1.0, "armor": [],
		"conceal": "", "turret": 5.0, "hull": 4.0, "forest_speed": 1.0, "city_speed": 1.0, "forest_view": 1.0, "city_view": 1.0, "recon": true},
	"bunker": {"speed": 0.0, "range": 800.0, "view": 1000.0, "acc_far": 0.6, "move_fire": 1.0, "armor": [],
		"conceal": "", "turret": 1.5, "hull": 0.0, "forest_speed": 1.0, "city_speed": 1.0, "forest_view": 1.0, "city_view": 1.0, "recon": false},
}

## Moltiplicatori della matrice di danno che cambiano in battaglia (il resto come Data.MATRIX).
const MATRIX_OVERRIDE := {
	"aa": {"inf": 0.45, "tank": 0.2, "art": 0.4, "aa": 0.4},     # contraerea: ottima contro i velivoli, debole a terra
	"inf": {"tank": 0.6, "art": 1.2, "aa": 1.0},
}

## Iniziativa dell'attaccante (sceglie dove e quando colpire): moltiplica il danno inflitto dal lato 0.
## Tarata perché a forze pari il difensore vinca ~60–65% (vedi tests/test_tactics.gd).
const ATT_INITIATIVE := 1.4
const LUCK := 0.1                 # deviazione standard delle "condizioni del giorno" per lato (danno inflitto)

# ---- visibilità e copertura
const SPOT_DT := 0.25             # intervallo di aggiornamento della visibilità (s)
const AIR_SEEN := 1.25            # i velivoli si vedono da più lontano (vista × AIR_SEEN)
const AA_AIR_VIEW := 2200.0       # radar della contraerea contro i velivoli
const CONCEAL_INF := [0.0, 240.0, 190.0]   # distanza massima a cui si scopre fanteria ferma in copertura [aperto, leggera, pesante]
const CONCEAL_VEH := [0.0, 350.0, 300.0]   # idem per un mezzo fermo in copertura
const CONCEAL_SMOKE := 160.0      # unità nel fumo: scoperte solo da vicino
const RECON_CONCEAL := 1.8        # elicotteri/droni scoprono le unità nascoste da più lontano
const SLOW_FRAC := 0.35           # "ferma o lenta": velocità sotto questa frazione del massimo
const REVEAL_T := 4.0             # dopo aver sparato un'unità resta visibile per questi secondi
const REVEAL_OPEN := 1.5          # ... allo scoperto: vista del nemico × questo (vampate visibili da lontano)
const REVEAL_COVER := [0.0, 420.0, 380.0]   # ... in copertura: solo entro questa distanza (fanteria)
const REVEAL_GUN := 1600.0        # cannoni dei mezzi/bunker che sparano: visibili ad almeno questa distanza (vampa, polvere)
const GHOST_T := 20.0             # durata dei fantasmi (ultima posizione nota)

# ---- rilievo (Fase 7, BattleRelief): linee di vista e posizione dominante
const LOS_EYE := 2.2              # m: altezza degli occhi/dell'ottica delle unità a terra (anche del bersaglio: linea simmetrica)
const LOS_TOL := 0.25             # m: il terreno deve superare la linea di almeno tanto per nasconderla
const HIGH_VIEW_K := 0.015        # vista × (1 + dislivello in m × questo) contro bersagli più in basso...
const HIGH_VIEW_MAX := 0.3        # ... fino a +30% (20 m di dislivello)
const WADE_INF := 0.4             # fanteria che guada un fiume fuori da ponti e guadi: velocità × questo
const WADE_VEH := 0.15            # mezzi a terra nell'acqua: quasi fermi (conviene passare da ponti e guadi)

# ---- danno
const COVER_INF := [1.0, 0.65, 0.5]        # fuoco diretto su fanteria in copertura
const VEH_VS_COVER_INF := 0.6     # in più, se a sparare è un mezzo (carro/contraerea): l'alto esplosivo si disperde tra alberi e macerie
const COVER_VEH := [1.0, 0.9, 0.8]       # fuoco diretto su mezzi in copertura
const COVER_ART_INF := [1.0, 0.8, 0.6]     # artiglieria/bombe su fanteria in copertura
const TANK_GUN_VS_ARMOR := 1.8    # cannone del carro contro mezzi corazzati: un colpo sul fianco/retro ne mette fuori uso ~1/3–1/2
const AMBUSH_MUL := 1.6           # bonus dei primi colpi da posizione nascosta
const AMBUSH_T := 5.0             # durata dell'imboscata
const AMBUSH_REARM := 12.0        # secondi di nuovo nascosta prima di poter tendere un'altra imboscata
const AT_RANGE := 380.0           # fanteria anticarro: distanza utile (lanciarazzi/missili, oltre la gittata dei fucili)
const AT_COVER_MUL := 5.0         # ... in copertura contro mezzi corazzati
const AT_OPEN_MUL := 1.4          # ... allo scoperto
const ARMORED := {"tank": true, "art": true, "aa": true}
const FLANK_FRONT := 0.7854       # |angolo| < 45° = fronte
const FLANK_REAR := 2.356         # |angolo| > 135° = retro

# ---- fortificazioni del difensore (setup.def.fort)
const TRENCH_ART := 0.4           # artiglieria/bombe su fanteria in trincea
const MINE_R := 120.0             # raggio di un campo minato
const MINE_CHARGES := 6           # esplosioni per campo
const MINE_P := 0.35              # probabilità per mezzo ogni 0.5 s dentro il campo
const MINE_DMG := 9.0             # danno per esplosione (x min(2, mezzi nel gruppo))
const MINE_SPOT := 140.0          # distanza (oltre il raggio) a cui l'attaccante scopre il campo
const MINE_SPOT_RECON := 420.0    # ... con elicotteri/droni

# ---- artiglieria
const ART_DMG := 0.7               # danno per colpo dei cannoni in battaglia (imprecisi, di supporto: non decisivi da soli)
const SCATTER_BASE := 25.0        # raggio di dispersione a distanza 0
const SCATTER_K := 0.055          # + px per px di distanza (a 3000 px ≈ 190 px)
const AREA_SCATTER := 1.6         # fuoco d'area / su un fantasma: dispersione × questo
const SHELL_T0 := 1.2             # tempo di volo minimo del colpo
const SHELL_TK := 0.0012          # + s per px


# ---- Fase 8: meteo (vista × moltiplicatore unico; la vista 3D lo legge per pioggia/nebbia/neve/notte)
## kind -> moltiplicatore del raggio di vista di TUTTE le unità (anche velivoli e radar).
const WEATHER_VIEW := {"sereno": 1.0, "pioggia": 0.72, "temporale": 0.6, "nebbia": 0.42, "neve": 0.68, "notte": 0.55}
const WEATHER_KINDS := ["sereno", "pioggia", "temporale", "nebbia", "neve", "notte"]
## pesi per terreno (dal seed); "notte" è una condizione a sé (il mattino/pomeriggio li sceglie la vista)
const WEATHER_W := {
	"pianura":  {"sereno": 0.42, "pioggia": 0.2, "temporale": 0.06, "nebbia": 0.14, "neve": 0.0, "notte": 0.18},
	"foresta":  {"sereno": 0.3, "pioggia": 0.24, "temporale": 0.06, "nebbia": 0.26, "neve": 0.0, "notte": 0.14},
	"montagna": {"sereno": 0.32, "pioggia": 0.12, "temporale": 0.06, "nebbia": 0.2, "neve": 0.18, "notte": 0.12},
	"deserto":  {"sereno": 0.66, "pioggia": 0.0, "temporale": 0.04, "nebbia": 0.08, "neve": 0.0, "notte": 0.22},
	"artico":   {"sereno": 0.3, "pioggia": 0.0, "temporale": 0.0, "nebbia": 0.16, "neve": 0.44, "notte": 0.1},
	"urbano":   {"sereno": 0.4, "pioggia": 0.26, "temporale": 0.06, "nebbia": 0.1, "neve": 0.0, "notte": 0.18},
}
const FLARE_CD := [22.0, 34.0]     # s tra due razzi illuminanti dello stesso lato (notte)
const FLARE_T := 16.0              # durata della luce
const FLARE_R := 620.0             # px: raggio illuminato (≈155 m): dentro, la vista torna piena
const RUBBLE_COVER := 2            # macerie di un edificio crollato: copertura pesante per la fanteria


## Piano meteo deterministico dal seed: {"start": kind, "changes": [[t_s, kind], ...]} (al più un cambiamento, tra 70 e 200 s).
## Cambi plausibili: nebbia che si dirada, pioggia che arriva o smette, temporale che cala a pioggia, neve che si placa.
static func weather_plan(seed: int, tkey: String) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = (seed & 0x7fffffff) * 977 + 41
	var w: Dictionary = WEATHER_W.get(tkey, WEATHER_W["pianura"])
	var tot := 0.0
	for k in WEATHER_KINDS:
		tot += float(w.get(k, 0.0))
	var x := r.randf() * tot
	var start := "sereno"
	for k in WEATHER_KINDS:
		x -= float(w.get(k, 0.0))
		if x <= 0.0:
			start = k
			break
	var changes := []
	var nxt := ""
	match start:
		"nebbia": nxt = "sereno" if r.randf() < 0.75 else "pioggia"
		"sereno": nxt = ["pioggia", "nebbia", "temporale"][r.randi() % 3] if tkey != "artico" else "neve"
		"pioggia": nxt = "sereno" if r.randf() < 0.6 else "temporale"
		"temporale": nxt = "pioggia"
		"neve": nxt = "sereno"
		"notte": nxt = ""
	if nxt != "" and float(w.get(nxt, 0.0)) > 0.0 and r.randf() < (0.8 if start == "nebbia" else 0.45):
		changes.append([70.0 + r.randf() * 130.0, nxt])
	return {"start": start, "changes": changes}


static func stat(type: String) -> Dictionary:
	return STATS.get(type, STATS["inf"])


static func matrix(shooter: String) -> Dictionary:
	var base: Dictionary = Data.MATRIX.get(shooter, {})
	if not MATRIX_OVERRIDE.has(shooter):
		return base
	var m := base.duplicate()
	var o: Dictionary = MATRIX_OVERRIDE[shooter]
	for k in o:
		m[k] = o[k]
	return m


## Moltiplicatore della corazza direzionale: `ang` = orientamento dello scafo del bersaglio, (dx, dy) = dal bersaglio al tiratore.
## Restituisce [moltiplicatore, "front"|"side"|"rear"|""].
static func flank(type: String, ang: float, dx: float, dy: float) -> Array:
	var ar: Array = stat(type)["armor"]
	if ar.is_empty():
		return [1.0, ""]
	var d := absf(wrapf(atan2(dy, dx) - ang, -PI, PI))
	if d < FLANK_FRONT:
		return [float(ar[0]), "front"]
	if d > FLANK_REAR:
		return [float(ar[2]), "rear"]
	return [float(ar[1]), "side"]


## Raggio di dispersione dell'artiglieria alla distanza d.
static func scatter(d: float) -> float:
	return SCATTER_BASE + d * SCATTER_K
