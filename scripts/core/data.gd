extends Node
## FRONTLINE DOMINION 3D — dati statici di gioco (autoload "Data").
## GENERATO da frontline/js/data.js (regole già bilanciate). Non modificare a mano i valori senza aggiornare SPEC.

const MAP_W = 1600
const MAP_H = 900
const RES_KEYS = ["money","oil","steel","manpower"]
const RES_NAMES = {"money":"Denaro","oil":"Petrolio","steel":"Acciaio","manpower":"Manodopera"}
const RES_ICONS = {"money":"$","oil":"⛽","steel":"⚙","manpower":"👥"}
const CONTINENTS = {"NA":{"name":"Nord America","bonus":3,"perk":"air","perkText":"Mezzi aerei −25% costo"},"SA":{"name":"Sud America","bonus":1,"perk":"steel","perkText":"+30% acciaio"},"EU":{"name":"Europa","bonus":4,"perk":"money","perkText":"+25% denaro"},"AF":{"name":"Africa","bonus":3,"perk":"manpower","perkText":"+30% manodopera"},"AS":{"name":"Asia","bonus":5,"perk":"oil","perkText":"+30% petrolio"},"OC":{"name":"Oceania","bonus":3,"perk":"naval","perkText":"Traversate rapide, difesa +15%"}}
const CONT_KEYS = ["NA","SA","EU","AF","AS","OC"]
const TERRAINS = {"pianura":{"name":"Pianura","def":1,"mul":{"tank":1.1},"ground":"#5d6b3c","ground2":"#4f5c33","obstacle":"bosco","density":0.35},"deserto":{"name":"Deserto","def":1,"mul":{"tank":1.15,"inf":0.9},"ground":"#b59a62","ground2":"#a68a55","obstacle":"roccia","density":0.25},"urbano":{"name":"Urbano","def":1.25,"mul":{"tank":0.8,"inf":1.15,"art":0.9},"ground":"#55585c","ground2":"#4a4d51","obstacle":"edificio","density":1},"montagna":{"name":"Montagna","def":1.3,"mul":{"tank":0.75,"inf":1.1},"ground":"#6e6656","ground2":"#5f5849","obstacle":"roccia","density":0.8},"foresta":{"name":"Foresta","def":1.15,"mul":{"tank":0.85,"heli":0.9,"inf":1.1},"ground":"#34502c","ground2":"#2b4425","obstacle":"bosco","density":0.9},"artico":{"name":"Artico","def":1.1,"mul":{"inf":0.9,"tank":0.9},"ground":"#c9d3da","ground2":"#b8c3cb","obstacle":"ghiaccio","density":0.4}}
const UNITS = {"inf":{"name":"Fanteria","short":"FAN","hp":10,"atk":2,"cost":{"money":15,"manpower":10},"time":3,"tech":1,"build":"caserma","air":false,"speed":1,"upkeep":0,"moveOil":0,"rts":{"range":75,"speed":26,"cd":1,"size":6}},"tank":{"name":"Carri armati","short":"CAR","hp":30,"atk":6,"cost":{"money":35,"steel":45,"oil":10,"manpower":4},"time":6,"tech":1,"build":"fabbrica","air":false,"speed":1.3,"upkeep":0.02,"moveOil":2,"rts":{"range":125,"speed":44,"cd":1.8,"size":10}},"art":{"name":"Artiglieria","short":"ART","hp":14,"atk":7,"cost":{"money":30,"steel":35,"manpower":4},"time":6,"tech":1,"build":"fabbrica","air":false,"speed":0.8,"upkeep":0.01,"moveOil":1,"rts":{"range":340,"minRange":70,"speed":24,"cd":3.2,"size":9,"splash":34}},"aa":{"name":"Contraerea","short":"AA","hp":16,"atk":4,"cost":{"money":25,"steel":30,"manpower":3},"time":5,"tech":2,"build":"fabbrica","air":false,"speed":1,"upkeep":0.01,"moveOil":1,"rts":{"range":240,"speed":32,"cd":0.9,"size":9}},"heli":{"name":"Elicotteri","short":"ELI","hp":20,"atk":8,"cost":{"money":55,"steel":30,"oil":30,"manpower":2},"time":8,"tech":2,"build":"aeroporto","air":true,"speed":1.8,"upkeep":0.03,"moveOil":3,"rts":{"range":165,"speed":78,"cd":1.6,"size":10}},"jet":{"name":"Caccia-bombardieri","short":"JET","hp":24,"atk":11,"cost":{"money":85,"steel":50,"oil":45,"manpower":2},"time":10,"tech":3,"build":"aeroporto","air":true,"speed":2.5,"upkeep":0.04,"moveOil":4,"rts":{"range":200,"speed":135,"cd":2.2,"size":11}},"drone":{"name":"Sciame di droni","short":"DRN","hp":8,"atk":5,"cost":{"money":35,"steel":25},"time":4,"tech":4,"build":"aeroporto","air":true,"speed":2,"upkeep":0.005,"moveOil":0.5,"rts":{"range":115,"speed":98,"cd":0.9,"size":6}}}
const UNIT_KEYS = ["inf","tank","art","aa","heli","jet","drone"]
const MATRIX = {"inf":{"inf":1,"tank":0.6,"art":1.2,"aa":1.2,"heli":0.3,"jet":0.1,"drone":0.4,"bunker":0.4},"tank":{"inf":1.3,"tank":1,"art":1.4,"aa":1.4,"heli":0.2,"jet":0,"drone":0.2,"bunker":1},"art":{"inf":1.4,"tank":0.8,"art":1,"aa":1.2,"heli":0,"jet":0,"drone":0,"bunker":1.6},"aa":{"inf":0.6,"tank":0.3,"art":0.5,"aa":0.5,"heli":3,"jet":2.2,"drone":3,"bunker":0.3},"heli":{"inf":1,"tank":1.6,"art":1.5,"aa":0.5,"heli":0.8,"jet":0.2,"drone":0.6,"bunker":0.8},"jet":{"inf":0.8,"tank":1.2,"art":1.4,"aa":0.6,"heli":1.6,"jet":1,"drone":1,"bunker":1.4},"drone":{"inf":1,"tank":1.3,"art":1.3,"aa":0.5,"heli":0.6,"jet":0.2,"drone":0.8,"bunker":0.7},"bunker":{"inf":1.4,"tank":0.8,"art":1,"aa":1,"heli":0.1,"jet":0,"drone":0.1,"bunker":0}}
const BUNKER_STATS = {"hp":260,"atk":8,"range":155,"cd":1.4,"size":16}
const BUILDINGS = {"caserma":{"name":"Caserma","icon":"C","cost":{"money":60,"steel":20},"time":15,"desc":"Recluta fanteria"},"fabbrica":{"name":"Fabbrica","icon":"F","cost":{"money":110,"steel":100},"time":25,"desc":"Carri, artiglieria, contraerea"},"aeroporto":{"name":"Aeroporto","icon":"A","cost":{"money":150,"steel":120,"oil":40},"time":30,"desc":"Mezzi aerei; ponte aereo (Liv. 2)"},"porto":{"name":"Porto","icon":"P","cost":{"money":90,"steel":60},"time":20,"desc":"Traversate rapide, sbarchi senza penalità","coastal":true},"bunker":{"name":"Fortificazioni","icon":"B","cost":{"money":70,"steel":110},"time":20,"desc":"Difesa +30%, bunker in battaglia"},"impianto":{"name":"Impianto estrattivo","icon":"I","cost":{"money":90,"steel":50},"time":20,"desc":"Produzione locale +60%"}}
const BUILDING_KEYS = ["caserma","fabbrica","aeroporto","porto","bunker","impianto"]
const SLOTS = 3
const HQ_SLOTS = 4
const TECH_LEVELS = [null,{"name":"Guerra Fredda","cost":null,"time":0,"desc":"Fanteria, carri, artiglieria"},{"name":"Moderna","cost":{"money":250,"steel":200,"oil":50},"time":60,"desc":"Contraerea, elicotteri, ponte aereo tra aeroporti"},{"name":"Avanzata","cost":{"money":450,"steel":400,"oil":200},"time":90,"desc":"Caccia-bombardieri, supporto d’artiglieria dai territori adiacenti"},{"name":"Futuristica","cost":{"money":750,"steel":600,"oil":350},"time":120,"desc":"Sciami di droni, missili +50%"}]
const TECH_COMBAT_BONUS = 0.08
const FACTIONS = [{"id":"aan","name":"Alleanza Atlantica del Nord","short":"AAN","color":"#3b82f6","doctrine":"Aviazione e tecnologia","perks":["Mezzi aerei −25% costo","Ricerca −25% costo e tempo"],"mods":{"airCost":0.75,"research":0.75}},{"id":"fo","name":"Federazione Orientale","short":"FO","color":"#ef4444","doctrine":"Corazzati pesanti e artiglieria","perks":["Carri +20% resistenza","Artiglieria +25% potenza","Coscrizione di massa: +2 fanteria a ogni rinforzo","Economia di guerra: +25% denaro"],"mods":{"tankHp":1.2,"artAtk":1.25,"reinforce":2,"moneyMul":1.25}},{"id":"cp","name":"Coalizione del Pacifico","short":"CP","color":"#14b8a6","doctrine":"Marina e droni","perks":["Traversate navali sempre rapide, nessuna penalità di sbarco","Droni disponibili dal livello 2"],"mods":{"naval":true,"droneTech":2}},{"id":"ul","name":"Unione Libera","short":"UL","color":"#f59e0b","doctrine":"Guerriglia e mercenari","perks":["Fanteria −20% costo","Difesa +10% in città e foreste","Mercenari: fanteria istantanea pagando denaro","Forze nascoste in territori urbani"],"mods":{"infCost":0.8,"guerrilla":1.1,"mercs":true,"hidden":true}}]
const NEUTRAL_COLOR = "#6b7280"
const MARKET = {"lot":100,"sell":0.6,"buy":1.6,"step":0.06,"min":0.4,"max":2.5,"recover":0.01,"goods":["oil","steel","manpower"]}
const MERC_OFFER = {"count":5,"cost":{"money":300}}
const CARD_TYPES = {"inf":"Fanteria","tank":"Corazzati","air":"Aviazione","jolly":"Jolly"}
const SET_VALUES = [4,6,8,10,12,15]
const CARD_COOLDOWN = 25
const HAND_MAX = 5
## target: "own" = nessun bersaglio (vale per te), "enemy" = territorio nemico, "self" = un tuo territorio
const OPS = {"rinforzi":{"name":"Rinforzi","target":"own","desc":"Truppe in base al tris, da schierare"},"missile":{"name":"Attacco missilistico","target":"enemy","desc":"Distrugge il 35% delle forze nemiche in un territorio (50% al Liv. 4)"},"sabotaggio":{"name":"Sabotaggio","target":"enemy","desc":"Blocca produzione, reclutamento e fortificazioni per 2 turni"},"golpe":{"name":"Golpe","target":"enemy","desc":"Un territorio nemico debole (≤ 8 unità, non QG) passa a te"},
	"finta":{"name":"Divisione falsa","target":"self","desc":"Per 2 round i nemici vedono questo tuo territorio solo come stima, gonfiata di 8 unità"},
	"ricognizione":{"name":"Ricognizione","target":"enemy","desc":"Per 2 round vedi forze, edifici e fortificazioni esatte di un territorio nemico e dei suoi vicini"},
	"silenzio":{"name":"Silenzio radio","target":"self","desc":"Per 2 round i nemici non sanno nulla delle forze in questo tuo territorio"}}
## Carte inganno e nebbia leggera (docs/omogeneita.md §5)
const DECEIT_ROUNDS = 2
const DECOY_UNITS = 8
const FOG_MODES = {"none": "Nessuna", "light": "Leggera", "full": "Totale"}
const WORN_ROUNDS = 2        # turni di logoramento dopo una battaglia
const WORN_MUL = 0.85        # −15% attacco per le truppe logorate
const GOLPE_MAX = 8
const SABOTAGE_TIME = 60
const ECON = {"baseMoney":0.7,"baseManpower":0.35,"baseSteel":0.15,"baseOil":0.1,"specRate":0.8,"passive":0.6,"hqMul":1.6666666666666667,"impiantoMul":1.6,"unsupplied":0.5,"startRes":{"money":600,"oil":200,"steel":250,"manpower":150},"militiaEvery":12,"militiaCap":6,"garrisonEvery":30,"garrisonCap":3,"truce":240,"regroup":20,"occupation":90,"reinforceEvery":40,"reinforceMin":4,"travelSpeed":22,"seaSlow":0.4,"airliftSpeed":4,"seaLandingPenalty":0.75,"bunkerDef":1.3,"hqDef":1.5,"unsuppliedCombat":0.8,"lowOilCombat":0.7,"hqCaptureSteal":0.3,"victoryShare":0.7}
const DIFFICULTY = {"recluta":{"name":"Recluta","income":0.8,"think":4.5,"margin":1.6,"noise":0.35},"veterano":{"name":"Veterano","income":1,"think":3.2,"margin":1.3,"noise":0.15},"generale":{"name":"Generale","income":1.25,"think":2,"margin":1.15,"noise":0.05}}
const CONT_TERR = {"NA":[0,1,2,3,4,5,6,7],"SA":[8,9,10,11,12],"EU":[13,14,15,16,17,18,19,20],"AF":[21,22,23,24,25,26,27],"AS":[28,29,30,31,32,33,34,35,36,37],"OC":[38,39,40,41]}
const TERR_INDEX = {"alaska":0,"yukon":1,"quebec":2,"groenlandia":3,"pacifica":4,"pianure":5,"atlantica":6,"messico":7,"istmo":8,"amazzonia":9,"ande":10,"brasile":11,"patagonia":12,"britannia":13,"scandinavia":14,"francia":15,"iberia":16,"germania":17,"italia":18,"polonia":19,"russia":20,"maghreb":21,"egitto":22,"sahel":23,"corno":24,"congo":25,"australe":26,"madagascar":27,"medioriente":28,"urali":29,"asiacentrale":30,"siberia":31,"estremo":32,"mongolia":33,"cina":34,"india":35,"indocina":36,"giappone":37,"indonesia":38,"guinea":39,"ausovest":40,"ausest":41}
const LAND_LINKS = [["alaska","yukon"],["yukon","quebec"],["yukon","pacifica"],["yukon","pianure"],["quebec","pianure"],["quebec","atlantica"],["pacifica","pianure"],["pianure","atlantica"],["pacifica","messico"],["pianure","messico"],["messico","istmo"],["istmo","amazzonia"],["istmo","ande"],["amazzonia","ande"],["amazzonia","brasile"],["ande","brasile"],["ande","patagonia"],["brasile","patagonia"],["francia","iberia"],["francia","germania"],["francia","italia"],["germania","italia"],["germania","polonia"],["germania","scandinavia"],["polonia","russia"],["polonia","italia"],["scandinavia","russia"],["russia","urali"],["russia","asiacentrale"],["italia","medioriente"],["russia","medioriente"],["maghreb","egitto"],["maghreb","sahel"],["egitto","sahel"],["egitto","corno"],["sahel","congo"],["corno","congo"],["congo","australe"],["corno","australe"],["egitto","medioriente"],["medioriente","asiacentrale"],["medioriente","india"],["asiacentrale","urali"],["asiacentrale","cina"],["asiacentrale","india"],["urali","siberia"],["siberia","estremo"],["siberia","mongolia"],["estremo","mongolia"],["mongolia","cina"],["cina","india"],["cina","indocina"],["india","indocina"],["cina","giappone"],["estremo","cina"],["ausovest","ausest"]]
const SEA_LINKS = [["alaska","estremo"],["groenlandia","quebec"],["groenlandia","britannia"],["brasile","sahel"],["britannia","francia"],["britannia","scandinavia"],["iberia","maghreb"],["italia","maghreb"],["madagascar","australe"],["madagascar","corno"],["corno","medioriente"],["giappone","estremo"],["indocina","indonesia"],["indonesia","guinea"],["indonesia","ausovest"],["guinea","ausest"]]
const WRAP_LINKS = [["alaska","estremo"]]
## TERRITORIES[i] = {id,name,c,ter,spec,amt,idx,x,y (coordinate mappa 0..MAP_W/0..MAP_H),blobs_px:[[x,y,r]],adj:[idx],sea:[idx collegati via mare],coastal}
const TERRITORIES = [{"id":"alaska","name":"Alaska","c":"NA","ter":"artico","spec":"oil","amt":1,"idx":0,"x":79.992,"y":123.2,"blobs_px":[[79.992,123.2,38],[35.552,144,20],[133.32,112.8,25]],"adj":[1,32],"sea":[32],"coastal":true},{"id":"yukon","name":"Canada Ovest","c":"NA","ter":"foresta","spec":"oil","amt":1.2,"idx":1,"x":231.088,"y":133.60000000000002,"blobs_px":[[231.088,133.60000000000002,45],[288.86,154.4,40],[199.98,170,30],[311.08,112.8,30]],"adj":[0,2,4,5],"sea":[],"coastal":false},{"id":"quebec","name":"Canada Est","c":"NA","ter":"foresta","spec":"steel","amt":0.8,"idx":2,"x":399.96,"y":164.8,"blobs_px":[[399.96,164.8,36],[435.512,190.8,34],[364.408,190.8,28],[479.952,196,20],[422.18,133.60000000000002,24]],"adj":[1,5,6,3],"sea":[3],"coastal":true},{"id":"groenlandia","name":"Groenlandia","c":"NA","ter":"artico","spec":"steel","amt":0.5,"idx":3,"x":568.832,"y":71.2,"blobs_px":[[568.832,71.2,40],[568.832,112.8,26],[524.3919999999999,92,22],[622.16,50.4,24]],"adj":[2,13],"sea":[2,13],"coastal":true},{"id":"pacifica","name":"Costa Pacifica","c":"NA","ter":"urbano","spec":"money","amt":1.4,"idx":4,"x":222.2,"y":227.20000000000002,"blobs_px":[[222.2,227.20000000000002,30],[231.088,268.8,28],[248.864,248,24]],"adj":[1,5,7],"sea":[],"coastal":true},{"id":"pianure","name":"Grandi Pianure","c":"NA","ter":"pianura","spec":"oil","amt":1.3,"idx":5,"x":311.08,"y":227.20000000000002,"blobs_px":[[311.08,227.20000000000002,35],[319.968,279.20000000000005,34],[284.416,248,28]],"adj":[1,2,4,6,7],"sea":[],"coastal":false},{"id":"atlantica","name":"Costa Atlantica","c":"NA","ter":"urbano","spec":"money","amt":1.6,"idx":6,"x":395.516,"y":248,"blobs_px":[[395.516,248,28],[377.74,279.20000000000005,26],[426.624,232.4,20],[391.072,310.40000000000003,14]],"adj":[2,5],"sea":[],"coastal":true},{"id":"messico","name":"Messico","c":"NA","ter":"deserto","spec":"manpower","amt":1,"idx":7,"x":293.304,"y":326,"blobs_px":[[293.304,326,28],[319.968,357.2,24],[262.19599999999997,300,18],[355.52,367.6,15]],"adj":[4,5,8],"sea":[],"coastal":true},{"id":"istmo","name":"Colombia e Venezuela","c":"SA","ter":"foresta","spec":"oil","amt":1.4,"idx":8,"x":391.072,"y":404,"blobs_px":[[391.072,404,14],[426.624,424.8,28],[466.62,419.6,22]],"adj":[7,9,10],"sea":[],"coastal":true},{"id":"amazzonia","name":"Amazzonia","c":"SA","ter":"foresta","spec":"steel","amt":0.8,"idx":9,"x":479.952,"y":476.8,"blobs_px":[[479.952,476.8,36],[519.948,466.40000000000003,26],[444.4,487.2,22]],"adj":[8,10,11],"sea":[],"coastal":false},{"id":"ande","name":"Ande","c":"SA","ter":"montagna","spec":"steel","amt":1.2,"idx":10,"x":417.736,"y":508,"blobs_px":[[417.736,508,22],[439.956,549.6,20],[444.4,591.2,16]],"adj":[8,9,11,12],"sea":[],"coastal":true},{"id":"brasile","name":"Brasile","c":"SA","ter":"pianura","spec":"manpower","amt":1.2,"idx":11,"x":551.056,"y":518.4000000000001,"blobs_px":[[551.056,518.4000000000001,32],[542.168,565.2,28],[577.72,492.40000000000003,20],[519.948,601.6,18]],"adj":[9,10,12,23],"sea":[23],"coastal":true},{"id":"patagonia","name":"Argentina e Cile","c":"SA","ter":"pianura","spec":"money","amt":0.9,"idx":12,"x":471.064,"y":632.8000000000001,"blobs_px":[[471.064,632.8000000000001,28],[453.288,674.4,22],[444.4,716,16]],"adj":[10,11],"sea":[],"coastal":true},{"id":"britannia","name":"Isole Britanniche","c":"EU","ter":"urbano","spec":"money","amt":1.4,"idx":13,"x":746.592,"y":180.4,"blobs_px":[[746.592,180.4,19],[737.704,159.60000000000002,14],[719.928,180.4,10]],"adj":[3,15,14],"sea":[3,14,15],"coastal":true},{"id":"scandinavia","name":"Scandinavia","c":"EU","ter":"foresta","spec":"steel","amt":1,"idx":14,"x":822.14,"y":133.60000000000002,"blobs_px":[[822.14,133.60000000000002,26],[871.024,123.2,26],[799.92,144,16],[844.36,102.4,24]],"adj":[17,20,13],"sea":[13],"coastal":true},{"id":"francia","name":"Francia e Benelux","c":"EU","ter":"urbano","spec":"money","amt":1.2,"idx":15,"x":764.3679999999999,"y":211.6,"blobs_px":[[764.3679999999999,211.6,24],[773.256,190.8,14]],"adj":[16,17,18,13],"sea":[13],"coastal":true},{"id":"iberia","name":"Iberia","c":"EU","ter":"pianura","spec":"manpower","amt":0.8,"idx":16,"x":737.704,"y":248,"blobs_px":[[737.704,248,24],[719.928,242.8,14]],"adj":[15,21],"sea":[21],"coastal":true},{"id":"germania","name":"Germania","c":"EU","ter":"urbano","spec":"steel","amt":1.6,"idx":17,"x":799.92,"y":190.8,"blobs_px":[[799.92,190.8,20],[813.252,206.4,14]],"adj":[15,18,19,14],"sea":[],"coastal":true},{"id":"italia","name":"Italia e Balcani","c":"EU","ter":"montagna","spec":"money","amt":0.9,"idx":18,"x":808.808,"y":232.4,"blobs_px":[[808.808,232.4,13],[826.584,248,11],[848.804,232.4,17],[862.136,253.20000000000002,11]],"adj":[15,17,19,28,21],"sea":[21],"coastal":true},{"id":"polonia","name":"Polonia e Ucraina","c":"EU","ter":"pianura","spec":"manpower","amt":1,"idx":19,"x":844.36,"y":180.4,"blobs_px":[[844.36,180.4,20],[871.024,164.8,16],[884.356,201.20000000000002,18]],"adj":[17,20,18],"sea":[],"coastal":false},{"id":"russia","name":"Russia Europea","c":"EU","ter":"pianura","spec":"oil","amt":1.4,"idx":20,"x":933.24,"y":164.8,"blobs_px":[[933.24,164.8,38],[955.46,201.20000000000002,26],[915.4639999999999,133.60000000000002,28],[977.68,128.4,26]],"adj":[19,14,29,30,28],"sea":[],"coastal":true},{"id":"maghreb","name":"Maghreb e Libia","c":"AF","ter":"deserto","spec":"oil","amt":1,"idx":21,"x":733.26,"y":289.6,"blobs_px":[[733.26,289.6,22],[777.7,300,26],[826.584,305.2,22]],"adj":[22,23,16,18],"sea":[16,18],"coastal":true},{"id":"egitto","name":"Egitto e Sudan","c":"AF","ter":"deserto","spec":"manpower","amt":1,"idx":22,"x":888.8,"y":320.8,"blobs_px":[[888.8,320.8,26],[893.244,367.6,22]],"adj":[21,23,24,28],"sea":[],"coastal":true},{"id":"sahel","name":"Africa Occidentale","c":"AF","ter":"pianura","spec":"oil","amt":1.2,"idx":23,"x":711.04,"y":378,"blobs_px":[[711.04,378,24],[764.3679999999999,383.2,30],[817.696,383.2,24],[782.144,419.6,18]],"adj":[21,22,25,11],"sea":[11],"coastal":true},{"id":"corno","name":"Corno d'Africa","c":"AF","ter":"montagna","spec":"manpower","amt":1,"idx":24,"x":933.24,"y":409.2,"blobs_px":[[933.24,409.2,22],[959.904,424.8,16],[915.4639999999999,445.6,18]],"adj":[22,25,26,27,28],"sea":[27,28],"coastal":true},{"id":"congo","name":"Congo","c":"AF","ter":"foresta","spec":"steel","amt":1.4,"idx":25,"x":853.248,"y":466.40000000000003,"blobs_px":[[853.248,466.40000000000003,28],[831.028,497.6,18],[879.912,492.40000000000003,20]],"adj":[23,24,26],"sea":[],"coastal":true},{"id":"australe","name":"Africa Australe","c":"AF","ter":"pianura","spec":"steel","amt":1.2,"idx":26,"x":866.58,"y":580.8000000000001,"blobs_px":[[866.58,580.8000000000001,26],[853.248,612,20],[893.244,544.4000000000001,20],[835.472,560,16]],"adj":[25,24,27],"sea":[27],"coastal":true},{"id":"madagascar","name":"Madagascar","c":"AF","ter":"foresta","spec":"money","amt":0.5,"idx":27,"x":964.348,"y":554.8000000000001,"blobs_px":[[964.348,554.8000000000001,13],[959.904,580.8000000000001,10]],"adj":[26,24],"sea":[24,26],"coastal":true},{"id":"medioriente","name":"Medio Oriente","c":"AS","ter":"deserto","spec":"oil","amt":2,"idx":28,"x":951.016,"y":310.40000000000003,"blobs_px":[[951.016,310.40000000000003,24],[911.02,258.4,17],[986.568,289.6,20],[968.792,346.8,16]],"adj":[18,20,22,30,35,24],"sea":[24],"coastal":true},{"id":"urali","name":"Urali","c":"AS","ter":"montagna","spec":"steel","amt":1.4,"idx":29,"x":1026.564,"y":154.4,"blobs_px":[[1026.564,154.4,30],[1031.008,190.8,22],[1044.34,118,24]],"adj":[20,30,31],"sea":[],"coastal":false},{"id":"asiacentrale","name":"Asia Centrale","c":"AS","ter":"deserto","spec":"oil","amt":1,"idx":30,"x":1053.228,"y":232.4,"blobs_px":[[1053.228,232.4,30],[1013.232,237.6,18],[1088.78,248,18]],"adj":[20,28,29,34,35],"sea":[],"coastal":false},{"id":"siberia","name":"Siberia","c":"AS","ter":"artico","spec":"oil","amt":1.2,"idx":31,"x":1164.328,"y":123.2,"blobs_px":[[1164.328,123.2,42],[1226.544,144,34],[1128.776,154.4,28],[1244.32,92,28]],"adj":[29,32,33],"sea":[],"coastal":false},{"id":"estremo","name":"Estremo Oriente","c":"AS","ter":"artico","spec":"steel","amt":0.7,"idx":32,"x":1355.42,"y":133.60000000000002,"blobs_px":[[1355.42,133.60000000000002,36],[1422.08,123.2,26],[1333.2,180.4,20],[1466.52,138.8,18]],"adj":[31,33,34,0,37],"sea":[0,37],"coastal":true},{"id":"mongolia","name":"Mongolia","c":"AS","ter":"pianura","spec":"steel","amt":0.6,"idx":33,"x":1217.656,"y":216.8,"blobs_px":[[1217.656,216.8,28],[1168.772,216.8,18],[1270.984,216.8,16]],"adj":[31,32,34],"sea":[],"coastal":false},{"id":"cina","name":"Cina","c":"AS","ter":"urbano","spec":"steel","amt":1.6,"idx":34,"x":1248.764,"y":289.6,"blobs_px":[[1248.764,289.6,32],[1208.768,294.8,24],[1275.4279999999999,320.8,20],[1284.316,258.4,16]],"adj":[30,33,35,36,37,32],"sea":[],"coastal":true},{"id":"india","name":"India","c":"AS","ter":"pianura","spec":"manpower","amt":1.8,"idx":35,"x":1102.112,"y":341.6,"blobs_px":[[1102.112,341.6,26],[1111,383.2,18],[1137.664,331.2,16],[1075.448,310.40000000000003,14]],"adj":[28,30,34,36],"sea":[],"coastal":true},{"id":"indocina","name":"Indocina","c":"AS","ter":"foresta","spec":"manpower","amt":1,"idx":36,"x":1204.324,"y":367.6,"blobs_px":[[1204.324,367.6,20],[1226.544,393.6,14],[1186.548,346.8,14],[1208.768,430,9]],"adj":[34,35,38],"sea":[38],"coastal":true},{"id":"giappone","name":"Giappone e Corea","c":"AS","ter":"urbano","spec":"money","amt":1.6,"idx":37,"x":1368.752,"y":268.8,"blobs_px":[[1368.752,268.8,15],[1382.084,242.8,11],[1337.644,284.4,9],[1319.868,263.6,11]],"adj":[34,32],"sea":[32],"coastal":true},{"id":"indonesia","name":"Indonesia","c":"OC","ter":"foresta","spec":"oil","amt":1.2,"idx":38,"x":1208.768,"y":461.2,"blobs_px":[[1208.768,461.2,13],[1253.208,461.2,13],[1244.32,492.40000000000003,9],[1297.648,466.40000000000003,11]],"adj":[36,39,40],"sea":[36,39,40],"coastal":true},{"id":"guinea","name":"Nuova Guinea","c":"OC","ter":"foresta","spec":"steel","amt":0.6,"idx":39,"x":1386.528,"y":482,"blobs_px":[[1386.528,482,17],[1355.42,471.6,10]],"adj":[38,41],"sea":[38,41],"coastal":true},{"id":"ausovest","name":"Australia Occidentale","c":"OC","ter":"deserto","spec":"steel","amt":1.4,"idx":40,"x":1297.648,"y":580.8000000000001,"blobs_px":[[1297.648,580.8000000000001,30],[1333.2,565.2,24],[1279.872,612,16]],"adj":[41,38],"sea":[38],"coastal":true},{"id":"ausest","name":"Australia Orientale","c":"OC","ter":"pianura","spec":"money","amt":1,"idx":41,"x":1399.86,"y":586,"blobs_px":[[1399.86,586,24],[1404.304,632.8000000000001,17],[1386.528,539.2,15],[1368.752,612,17]],"adj":[40,39],"sea":[39],"coastal":true}]

## FASE 6 — strategia a turni. Tempi in turni del proprietario (la produzione avanza a fine turno).
const TURNS = {
	"units": {"inf": 1, "tank": 2, "art": 2, "aa": 2, "heli": 2, "jet": 3, "drone": 1},
	"buildings": {"caserma": 1, "fabbrica": 2, "aeroporto": 3, "porto": 2, "bunker": 2, "impianto": 2},
	"tech": [0, 0, 2, 3, 4],
}
## Reddito e mantenimento: secondi di produzione "in tempo reale" equivalenti a un turno
const TURN_SECS := 45.0
## Regole a turni
const TURN_RULES = {"truce_rounds": 2, "occupation": 2, "regroup": 1, "sabotage": 2, "militia": 2, "garrison": 1,
	"pact_rounds": 5, "pact_cd": 3, "market_recover": 0.15, "round_cap": 120,
	"attacks": 1, "truce_attacks": 2}   # attacchi per turno; durante la tregua iniziale (solo neutrali attaccabili) 2: avvio più rapido

## Notte 3 — ritmo del tabellone (docs/notte3_tabellone.md)
## Carte che hanno senso solo con la nebbia di guerra (senza nebbia non c'è nulla da nascondere o scoprire)
const FOG_OPS = ["finta", "silenzio", "ricognizione"]
## Ordini del comando: obiettivo a breve termine per ogni giocatore (conquista X entro N round → premio)
const MISSION_ROUNDS = 3
const MISSION_REWARDS = {
	"card": {"name": "una carta Comando"},
	"reinf": {"name": "4 unità di fanteria di rinforzo", "inf": 4},
	"money": {"name": "150 $", "money": 150},
}
## Eventi mondiali: uno ogni WORLD_EVENT_EVERY round a partire da WORLD_EVENT_FIRST, visibili a tutti
const WORLD_EVENT_FIRST = 3
const WORLD_EVENT_EVERY = 4
const WORLD_EVENT_HOLD = 2      # round entro cui va tenuto il territorio premio
const WORLD_EVENTS = {
	"convoglio": {"name": "Convoglio di aiuti", "kind": "prize", "reward": {"money": 250}, "rtext": "250 $"},
	"giacimento": {"name": "Giacimento scoperto", "kind": "prize", "reward": {"oil": 80, "steel": 120}, "rtext": "80 petrolio e 120 acciaio"},
	"archivio": {"name": "Archivi dei servizi segreti", "kind": "prize", "reward": {"card": 1}, "rtext": "una carta Comando"},
	"diserzioni": {"name": "Diserzioni", "kind": "instant"},
	"offensiva": {"name": "Finestra di bel tempo", "kind": "timed", "rounds": 1, "attacks": 1},
}
## Presidi dei territori neutrali all'inizio: 4-8 FAN, 0-2 CAR, 35% di avere 1-2 ART.
## Notte 3: provati presidi piu' leggeri (NEUTRAL_START_LIGHT) per accelerare l'avvio, SCARTATI: su 40 partite la FO passava
## dal 38% allo 0-10% di vittorie (perde il vantaggio della fanteria in piu'). Vedi docs/notte3_tabellone.md.
const NEUTRAL_START = {"inf_min": 4, "inf_var": 5, "tank_var": 3, "art_chance": 0.35}
const NEUTRAL_START_LIGHT = {"inf_min": 3, "inf_var": 4, "tank_var": 2, "art_chance": 0.2}
## Fortificazioni del territorio (livelli 0..3): costo del livello L = cost × L
const FORT_KEYS = ["trench", "mines", "bunker"]
const FORT_MAX := 3
const FORT = {
	"trench": {"name": "Trincee", "cost": {"money": 40, "manpower": 15}, "desc": "Fanteria e artiglieria del difensore più resistenti"},
	"mines": {"name": "Campi minati", "cost": {"money": 50, "steel": 40}, "desc": "Mine anticarro sulle vie d'accesso"},
	"bunker": {"name": "Bunker", "cost": {"money": 80, "steel": 90}, "desc": "Postazioni fortificate che sparano sugli attaccanti"},
}

## Testi d'aiuto (solo interfaccia): a cosa serve ogni unità, in una riga
const UNIT_ROLE = {
	"inf": "Tiene boschi e città, letale contro i carri da vicino",
	"tank": "Sfondano in campo aperto, colpiscono da lontano; deboli sui fianchi e nei boschi",
	"art": "Colpisce da lontanissimo ma imprecisa; serve qualcuno che avvisti. Ottima contro bunker",
	"aa": "Abbatte elicotteri, caccia e droni; debole contro le truppe di terra",
	"heli": "Cacciacarri veloci e potenti; temono la contraerea",
	"jet": "Bombardano carri, artiglieria e bunker; dominano il cielo",
	"drone": "Sciame economico che logora i mezzi; fragile contro la contraerea",
}
## A cosa serve ogni edificio (vale solo nel territorio dove lo costruisci)
const BUILDING_ROLE = {
	"caserma": "Permette di reclutare fanteria in questo territorio",
	"fabbrica": "Permette di reclutare carri, artiglieria e contraerea qui",
	"aeroporto": "Recluta elicotteri, caccia e droni qui; da Tech 2 ponte aereo tra aeroporti",
	"porto": "Attacchi via mare da qui senza penalità di sbarco",
	"bunker": "Difesa +30% stabile di questo territorio, bunker in battaglia",
	"impianto": "Produzione di questo territorio +60%",
}

func empty_forces() -> Dictionary:
	return {"inf": 0, "tank": 0, "art": 0, "aa": 0, "heli": 0, "jet": 0, "drone": 0}

func total_units(f: Dictionary) -> int:
	var s := 0
	for k in UNIT_KEYS:
		s += int(f.get(k, 0))
	return s

func add_forces(a: Dictionary, b: Dictionary) -> Dictionary:
	for k in UNIT_KEYS:
		a[k] = int(a.get(k, 0)) + int(b.get(k, 0))
	return a

func clone_forces(f: Dictionary) -> Dictionary:
	var o := empty_forces()
	for k in UNIT_KEYS:
		o[k] = int(f.get(k, 0))
	return o

func is_sea_link(a: int, b: int) -> bool:
	return TERRITORIES[a]["sea"].has(b)

func faction_color(i: int) -> Color:
	return Color(FACTIONS[i]["color"]) if i >= 0 else Color(NEUTRAL_COLOR)
