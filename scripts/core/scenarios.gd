class_name Scenarios
extends RefCounted
## FRONTLINE DOMINION 3D — scenari (FASE 4). Dati puri: le regole li applica Game (opts.scenario = id).
##
## Campi di ogni voce di LIST (quelli marcati * sono letti anche dall'interfaccia):
##   id*            String   identificativo (opts.scenario)
##   name*          String   nome
##   desc*          String   descrizione breve per il menu
##   objective*     String   obiettivo in una riga (pannello operazione / briefing)
##   faction*       int      fazione consigliata al giocatore (0 AAN, 1 FO, 2 CP, 3 UL)
##   opp*           int      numero di avversari IA (le altre fazioni, in ordine)
##   mode*          String   "conquista" (le regole di vittoria speciali sono in rules)
##   distribution*  String   "regionale" | "casuale"
##   fog*           bool     nebbia di guerra
##   round_limit*   int      FASE 6: round massimi; alla fine dell'ultimo round la partita finisce (0 = limite normale, 120)
##   focus*         Array    indici dei territori chiave da evidenziare
##   rules          Dictionary, regole per Game:
##     truce_rounds    round di tregua iniziale (default Data.TURN_RULES.truce_rounds = 2)
##     victory_share   quota del mondo per vincere (default Data.ECON.victoryShare)
##     res_mul         moltiplicatore delle risorse iniziali di tutti i giocatori
##     forces_mul      moltiplicatore delle forze iniziali dei giocatori
##     neutral_mul     moltiplicatore delle forze neutrali
##     fac             {id fazione ("aan","fo","cp","ul"): {start: [id territori], hq: id, res_mul, forces_mul, income_mul}}
##                     start: territori iniziali fissi (gli altri giocatori scelgono attorno a questi)
##     siege           {faction: int, pacts: bool, collapse: int}: la fazione assediata vince se resiste fino a round_limit;
##                     gli altri hanno l'obiettivo di eliminarla (o di ridurla a <= collapse territori).
##                     pacts = true: gli assedianti sono alleati (patti fino alla fine) e vincono insieme.
##     hold            {terrs: [id territori], need: int, rounds: int}: vince chi tiene `need` di questi territori per `rounds` round
##     time_win        allo scadere: "siege" (l'assediata se viva), "hold" (più territori chiave), "territories" (più territori)

const LIST := [
	{
		"id": "guerra_lampo",
		"name": "Guerra lampo",
		"desc": "Arsenali pieni, divisioni già schierate al confine e un solo round di tregua. Nessuno ha tempo per costruire: si colpisce per primi e si colpisce forte. Chi esita è perduto.",
		"objective": "Controlla il 60% del mondo entro 25 round (allo scadere vince chi ha più territori)",
		"faction": 1, "opp": 3, "mode": "conquista", "distribution": "regionale", "fog": false,
		"round_limit": 25,
		"focus": [],
		"rules": {"truce_rounds": 1, "victory_share": 0.6, "res_mul": 2.0, "forces_mul": 1.75, "time_win": "territories"},
	},
	{
		"id": "assedio_pacifico",
		"name": "Assedio del Pacifico",
		"desc": "La Coalizione del Pacifico si è chiusa nella sua fortezza d'isole con forzieri traboccanti e una flotta pronta. Tutto il mondo vuole la sua testa: chi la abbatte per primo prende tutto.",
		"objective": "CP: resisti 30 round. Gli altri: elimina la Coalizione del Pacifico per primo",
		"faction": 2, "opp": 3, "mode": "conquista", "distribution": "regionale", "fog": false,
		"round_limit": 30,
		"focus": [38, 39, 40, 41],
		"rules": {
			"victory_share": 0.8,
			"fac": {"cp": {"start": ["ausest", "ausovest", "guinea", "indonesia"], "hq": "ausest",
				"res_mul": 1.25, "forces_mul": 1.0, "income_mul": 1.1}},
			"siege": {"faction": 2, "pacts": false, "collapse": 0},
			"time_win": "siege",
		},
	},
	{
		"id": "blocco_acciaio",
		"name": "Blocco d'acciaio",
		"desc": "La Federazione Orientale ha unito l'Europa e l'Asia settentrionale in un solo blocco corazzato. Atlantici, Pacifico e Unione Libera firmano un'alleanza di ferro: abbatterla prima che diventi invincibile.",
		"objective": "FO: resisti 30 round. Alleati: riducete la Federazione a 3 territori",
		"faction": 1, "opp": 3, "mode": "conquista", "distribution": "regionale", "fog": false,
		"round_limit": 30,
		"focus": [20],
		"rules": {
			"fac": {"fo": {"start": ["russia", "polonia", "germania", "francia", "italia", "scandinavia", "britannia", "iberia",
				"urali", "asiacentrale", "siberia", "mongolia", "estremo"], "hq": "russia", "forces_mul": 1.6, "res_mul": 1.5, "income_mul": 1.2}},
			"victory_share": 0.8,
			"siege": {"faction": 1, "pacts": true, "collapse": 3},
			"time_win": "siege",
		},
	},
	{
		"id": "corsa_petrolio",
		"name": "Corsa al petrolio",
		"desc": "Le riserve mondiali sono agli sgoccioli e cinque giacimenti decidono il futuro. Il primo che ne tiene tre per due round interi detta legge a tutti gli altri.",
		"objective": "Tieni 3 dei 5 giacimenti petroliferi per 2 round",
		"faction": 3, "opp": 3, "mode": "conquista", "distribution": "regionale", "fog": false,
		"round_limit": 40,
		"focus": [0, 21, 28, 31, 38],
		"rules": {
			"hold": {"terrs": ["alaska", "maghreb", "medioriente", "siberia", "indonesia"], "need": 3, "rounds": 2},
			"time_win": "hold",
		},
	},
	{
		"id": "mondo_diviso",
		"name": "Mondo diviso",
		"desc": "Due potenze, un pianeta spartito a caso e una nebbia fitta su ogni confine. Niente alleati né scuse: solo tu, il tuo rivale e il 60% del mondo da strappargli.",
		"objective": "Controlla il 60% del mondo o elimina il rivale",
		"faction": 0, "opp": 1, "mode": "conquista", "distribution": "casuale", "fog": true,
		"round_limit": 50,
		"focus": [],
		"rules": {"victory_share": 0.6, "time_win": "territories"},
	},
]


## Voce di LIST con quell'id ({} se non esiste)
static func find(id: String) -> Dictionary:
	for S in LIST:
		if S["id"] == id:
			return S
	return {}


static func ids() -> Array:
	var o: Array = []
	for S in LIST:
		o.append(S["id"])
	return o


## Giocatori pronti per Game.new: il giocatore (umano o spettatore se human_faction < 0) e le IA dello scenario.
static func make_players(id: String, human_faction: int = -1, difficulty: String = "veterano") -> Array:
	var S := find(id)
	var opp: int = int(S.get("opp", 3)) if not S.is_empty() else 3
	var fac := human_faction if human_faction >= 0 else int(S.get("faction", 0))
	var out: Array = [{"faction": fac, "human": human_faction >= 0, "difficulty": difficulty}]
	for f in 4:
		if f != fac and out.size() <= opp:
			out.append({"faction": f, "human": false, "difficulty": difficulty})
	return out
