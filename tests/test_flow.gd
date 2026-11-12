extends SceneTree
## FASE 6 (primo round): turni dall'interfaccia → rifornimento (schiera, fortifica) → attacco dal pannello (auto) → spostamento
## → Invio = fine turno → turni IA → salvataggio automatico → attacco IA con prompt di difesa → salva/carica a turni.
## Flusso completo headless: menu → partita (nebbia attiva) → battaglia comandata → ritorno → patto (proposta e offerta IA)
## → veterani → salva/carica (vet, nebbia e patti devono sopravvivere) → fine → menu, più volte.
## Stampa "[flow] ERRORE ..." per ogni controllo fallito e "[flow] FINE errori=N".

var main
var phase := 0
var frame := 0
var round_i := 0
var log_obj := []
var errors := 0
var D: Node
# scenari da collaudare: [id, fazione del giocatore, frase attesa nel motivo della vittoria]
const SCN_TESTS := [["corsa_petrolio", 3, "territori chiave"], ["assedio_pacifico", 2, "ha resistito"], ["guerra_lampo", 1, "territori"]]
var scn_i := 0
var turn_r0 := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	main = ps.instantiate()
	root.add_child(main)
	D = root.get_node("Data")

func check(ok: bool, what: String) -> void:
	if ok:
		print("[flow] ok  ", what)
	else:
		errors += 1
		print("[flow] ERRORE ", what)

func _process(_dt: float) -> bool:
	frame += 1
	if frame % 600 == 0:
		print("[flow] tick phase=", phase, " frame=", frame, " ms=", Time.get_ticks_msec())
	if frame < 5:
		return false
	match phase:
		0:
			print("[flow] round ", round_i, " objects=", Performance.get_monitor(Performance.OBJECT_COUNT), " nodes=", Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
			log_obj.append(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
			main.menu_opts["faction"] = round_i % 4
			# notte 3: la nebbia predefinita è «nessuna»; nei round successivi del test si gioca con la nebbia leggera
			if round_i == 0:
				check(not bool(main.menu_opts.get("fog", true)) and String(main.menu_opts.get("fog_mode", "")) == "none", "nebbia spenta di default nel menu")
			else:
				main.menu_opts["fog"] = true
				main.menu_opts["fog_mode"] = "light"
			main.start_game(false)
			assert(main.game != null)
			if round_i == 0:
				check(not bool(main.game.fog) and String(main.game.fog_mode) == "none", "partita predefinita senza nebbia")
				var far0 := _far_territory()
				if far0 >= 0:
					check(main.is_vis(far0) and main.gcall("visible_forces", [main.h(), far0], null) != null, "senza nebbia le forze si vedono ovunque")
				main.hud.refresh(true)
				check(main.game.mission_of(main.h()) is Dictionary and main.goal_text().find("ORDINE DEL COMANDO") >= 0 and main.hud.g_goal.visible, "ordine del comando nel riquadro ORDINI")
				check(main.attacks_max() == 2 and main.attacks_left() == 2, "tregua iniziale: due attacchi per turno")
				var ops_txt := _texts(main.hud)
				check(ops_txt.find("Divisione falsa") < 0 and ops_txt.find("Silenzio radio") < 0, "carte inganno assenti senza nebbia")
			elif "fog" in main.game:
				check(bool(main.game.fog), "opts.fog arriva al nucleo")
				# territorio lontano dal QG: deve risultare nella nebbia
				var far := _far_territory()
				if far >= 0 and main.game.has_method("is_visible"):
					check(not main.is_vis(far), "territorio lontano nella nebbia (%s)" % D.TERRITORIES[far]["name"])
					check(main.gcall("visible_forces", [main.h(), far], 0) == null, "visible_forces null nella nebbia")
					main.select(far)
					main.hud.refresh(true)
					print("[flow] stima ", D.TERRITORIES[far]["name"], " = ", main.fog_text(far))
					main.select(-1)
			else:
				print("[flow] (nucleo senza nebbia)")
			root.get_node("Settings").set_value("tips", true)
			root.get_node("Settings").reset_tips()
			phase = 20 if round_i == 0 else 1
			frame = 0
		20:
			# ---- FASE 6: turni giocati dall'interfaccia (solo nel primo round del test)
			if not main.turn_mode():
				print("[flow] (nucleo senza turni)")
				phase = 1; frame = 0
				return false
			root.get_node("Settings").set_value("ai_speed", "istantanea")
			main._apply_ai_delay()
			check(main.my_turn() and main.phase_key() == "supply", "partita a turni: inizia il giocatore in rifornimento")
			main.hud.refresh(true)
			check(main.hud.turn_bar.visible and main.hud.guide.visible and main.hud.g_main.visible, "barra dei turni e riquadro ORDINI con il pulsante principale")
			check(main.hud.g_main.text.find("Attacco") >= 0, "pulsante principale «Fase successiva: Attacco» (%s)" % main.hud.g_main.text)
			check(not main.hud.left.visible, "cassetto a sinistra chiuso di default")
			main.hud.toggle_tab("cards")
			check(main.hud.left.visible and main.hud.lp["cards"].visible and not main.hud.lp["market"].visible, "scheda Carte aperta dalla barra a icone")
			main.hud.toggle_tab("cards")
			check(not main.hud.left.visible, "scheda Carte richiusa")
			check(not main.hud.speed_seg.visible and not main.hud.pause_btn.visible, "controlli di velocità/pausa nascosti")
			check(_texts(main.hud.turn_bar).find("TURNO 1") >= 0 and _texts(main.hud.turn_bar).find("Tocca a te") >= 0, "testo «Turno 1 · Tocca a te»")
			var hq := int(main.game.players[main.h()]["hq"])
			var pool0: int = D.total_units(main.game.players[main.h()]["pool"])
			if pool0 > 0:
				check(main.mode != null and main.mode["type"] == "deploy", "schieramento attivo con rinforzi in attesa")
				check(_texts(main.hud.guide).find("rinforzi") >= 0, "ORDINI: «Hai N rinforzi…»")
				main.act("end-phase")
				check(main.phase_key() == "supply" and main.hud.g_main.text.find("Sì") >= 0, "fase successiva con rinforzi non schierati chiede conferma")
				# un clic sul QG schiera tutto (come sul tabellone)
				main._on_map_clicked(hq, MOUSE_BUTTON_LEFT, false)
				check(D.total_units(main.game.players[main.h()]["pool"]) == 0 and main.sel == hq, "rinforzi schierati con un clic (%d)" % pool0)
				main.hud.refresh(true)
				check(_texts(main.hud.guide).find("Rinforzi schierati") >= 0, "ORDINI: esito «Rinforzi schierati…»")
			main.select(hq)
			main.hud.refresh(true)
			check(main.hud.rp["tabs"].visible and main.hud.rp["recruit"].visible and not main.hud.rp["fort"].visible, "pannello territorio: schede, Recluta visibile")
			main.hud.rtab = "fort"
			main.hud.refresh(true)
			check(main.hud.rp["fort"].visible and not main.hud.rp["recruit"].visible, "scheda Fortifica")
			main.hud.rtab = "recruit"
			main.act("fortify", {"k": "trench"})
			var fl: Dictionary = main.fort_levels(hq)
			print("[flow] fortificazioni QG ", fl)
			check(int(fl["trench"]) >= 1 or not main.gcall("can_afford", [main.h(), main.fort_cost(hq, "trench")], false), "trincea costruita nel QG")
			phase = 21; frame = 0
		21:
			# fase d'attacco: senza selezione pulsano le origini possibili, poi attacco con risoluzione automatica
			main.act("end-phase")
			check(main.phase_key() == "attack", "fase d'attacco")
			main.select(-1)
			check(main.click_marks().size() > 0 or main.demo_attack_pair().is_empty(), "origini d'attacco evidenziate (%d)" % main.click_marks().size())
			check(main.hud.g_main.text.find("Salta attacco") >= 0, "pulsante «Salta attacco»")
			var pair: Array = main.demo_attack_pair()
			print("[flow] attacco ", pair)
			check(pair.size() == 2, "c'è un bersaglio d'attacco")
			if pair.size() == 2:
				main.select(pair[0])
				check(main.target_set.has(pair[1]), "bersaglio evidenziato sul tabellone")
				main._on_map_clicked(pair[1], MOUSE_BUTTON_LEFT, false)
				check(main.modal_kind == "attack", "pannello d'attacco aperto")
				check(_texts(main.modal).find("Attacca: risoluzione automatica") >= 0 and _texts(main.modal).find("comando diretto (3D)") >= 0, "pulsanti del pannello d'attacco")
				main.modal._fp_fill(1.0)
				var sent: int = D.total_units(main._force_sel)
				check(sent == D.total_units(main.game.terr[pair[0]]["forces"]) - 1, "cursori: tutto tranne un'unità (%d)" % sent)
				main.act("atk-auto")
				check(main.modal_kind == "" and main.attacked_any(), "attacco eseguito e risolto in automatico")
				main.hud.refresh(true)
				check(main.attacks_left() == 1 and not main.attack_used() and main.hud.g_main.text.find("Basta attacchi") >= 0, "tregua: resta un secondo attacco facoltativo (%s)" % main.hud.g_main.text)
				print("[flow] esito: proprietario ", main.game.terr[pair[1]]["owner"], " toasts=", main._recent_toasts.size())
			main.act("end-phase")
			if main.phase_key() == "attack":
				main.act("end-phase")
			check(main.phase_key() == "move", "fase di spostamento")
			main.act("research")
			check(main.toasted_recently(main.ONLY_SUPPLY) or main.game.players[main.h()]["research"] != null, "ricerca vietata fuori dal rifornimento")
			var mp: Array = main.demo_move_pair()
			if mp.size() == 2:
				main.select(mp[0])
				main._on_map_clicked(mp[1], MOUSE_BUTTON_LEFT, false)
				check(main.modal_kind == "move", "pannello di spostamento")
				var n0: int = D.total_units(main.game.terr[mp[1]]["forces"])
				main.act("mv-go")
				if not main.move_used():
					print("[flow] spostamento rifiutato: ", main._recent_toasts.back() if main._recent_toasts.size() else "")
				check(main.move_used() and D.total_units(main.game.terr[mp[1]]["forces"]) > n0, "spostamento eseguito")
			else:
				print("[flow] (nessuno spostamento possibile)")
			turn_r0 = main.round_n()
			var ev := InputEventKey.new()
			ev.keycode = KEY_ENTER
			ev.pressed = true
			main._unhandled_input(ev)
			check(not main.my_turn(), "Invio termina il turno")
			phase = 22; frame = 0
		22:
			if main.modal_kind == "battle":
				main.battle_auto()
			if main.modal_kind == "summary":
				main.close_modal(true)
			if main.my_turn() and frame > 5:
				check(main.round_n() == turn_r0 + 1, "turni IA giocati, di nuovo il tuo turno (turno %d)" % main.round_n())
				check(FileAccess.file_exists(main.SaveStore.path("auto", "sav")), "salvataggio automatico all'inizio del turno")
				main.hud.refresh(true)
				check(_texts(main.hud.turn_bar).find("TURNO %d" % main.round_n()) >= 0, "barra: nuovo numero di turno")
				# notte 3: rapporto «Dall'ultimo turno» (righe cliccabili) e minacce annunciate
				print("[flow] rapporto del round visibile=", main.hud.recap != null and main.hud.recap.visible)
				main.hud.show_recap([{"text": "FO ammassa 12 unità in Polonia contro Germania (8 in difesa)", "kind": "threat", "terr": 17},
					{"text": "CP conquista Indonesia", "kind": "info", "terr": 38}], 2)
				check(main.hud.recap.visible and _texts(main.hud.recap).find("DALL'ULTIMO TURNO") >= 0 and _texts(main.hud.recap).find("altre 2 nel Registro") >= 0, "rapporto del round mostrato")
				main.act("focus-terr", {"t": 17})
				check(main.sel == 17, "clic su una riga del rapporto: territorio inquadrato")
				main.act("recap-close")
				check(not main.hud.recap.visible, "rapporto chiuso")
				main.select(-1)
				var foe := -1
				var foe_t := -1
				var my_t := -1
				for t in main.gcall("territories_of", [main.h()], []):
					for j in D.TERRITORIES[int(t)]["adj"]:
						var o: int = int(main.game.terr[j]["owner"])
						if o >= 0 and o != main.h():
							foe = o; foe_t = j; my_t = int(t)
				if foe >= 0:
					main.game.set_intent(foe, foe_t, my_t)
					main.refresh(true)
					check(main.threats.size() == 1 and main.hud.threat_btn.visible and main.hud.threat_lbl.text.find("MINACCIA") >= 0, "minaccia annunciata nel pulsante rosso (%s)" % main.hud.threat_lbl.text)
					check(main.recap_lines().size() >= 1 and String(main.recap_lines()[0]["kind"]) == "threat", "la minaccia apre il rapporto del round")
					main.game.intents[foe] = null
					main.refresh(true)
					check(main.threats.is_empty() and not main.hud.threat_btn.visible, "minaccia tolta")
				else:
					print("[flow] (nessun confine con un giocatore: minaccia non provata)")
				phase = 23; frame = 0
			elif frame > 1500:
				check(false, "i turni IA non finiscono (cur=%d fase=%s modal=%s)" % [main.cur_player(), main.phase_key(), main.modal_kind])
				phase = 23; frame = 0
		23:
			# un'IA attacca il giocatore: prompt da difensore
			if "truce_rounds" in main.game:
				main.game.truce_rounds = 0
			main.select(-1)
			main.end_turn()
			var ai: int = main.cur_player()
			var pair := []
			for t in main.gcall("territories_of", [ai], []):
				for j in D.TERRITORIES[int(t)]["adj"]:
					if int(main.game.terr[int(j)]["owner"]) == main.h():
						pair = [int(t), int(j)]
						break
				if pair.size():
					break
			if pair.size() and ai != main.h():
				D.add_forces(main.game.terr[pair[0]]["forces"], {"inf": 5, "tank": 2})
				var r = main.game.attack(pair[0], pair[1], main.movable_forces(pair[0]))
				print("[flow] attacco IA ", pair, " -> ", r)
				check(main.game.pending_battle != null and String(main.game.pending_battle.get("human_side", "")) == "def", "battaglia in attesa con human_side=def")
			else:
				print("[flow] (nessun confine con l'IA di turno)")
			phase = 24; frame = 0
		24:
			if frame == 6:
				if main.game.pending_battle != null:
					check(main.modal_kind == "battle", "prompt di difesa mostrato")
					check(_texts(main.modal).find("Difendi in prima persona (3D)") >= 0, "pulsante «Difendi in prima persona (3D)»")
					main.battle_auto()
					check(main.game.pending_battle == null, "difesa risolta in automatico")
			if frame > 6:
				if main.modal_kind == "battle":
					main.battle_auto()
				if main.my_turn():
					phase = 25; frame = 0
				elif frame > 1500:
					check(false, "turno IA dopo la difesa non concluso")
					phase = 25; frame = 0
		25:
			# salva/carica a turni
			var r0: int = main.round_n()
			var ok: bool = main.save_to_slot("turntest", "Prova turni")
			check(ok, "salvataggio a turni")
			var meta = main.SaveStore._read_meta("turntest")
			if meta is Dictionary:
				check(int(meta.get("round", 0)) == r0, "metadati: turno %d" % r0)
			main.load_slot("turntest")
			check(main.turn_mode() and main.round_n() == r0 and main.my_turn() and main.phase_key() == "supply", "caricamento: stesso turno, tocca a te")
			check(not main.coach.active, "nessun tutorial su una partita caricata")
			phase = 26; frame = 0
		26:
			# tutorial guidato dal menu: primi passi del primo turno
			main.act("tutorial")
			var C = main.coach
			check(C.active and C.step == "intro", "tutorial avviato dal menu (passo %s)" % C.step)
			C._on_next()
			check(C.step == "deploy", "tutorial: schiera i rinforzi")
			var hq2 := int(main.game.players[main.h()]["hq"])
			main._on_map_clicked(hq2, MOUSE_BUTTON_LEFT, false)
			C.update()
			check(C.step == "army", "tutorial: come formare l'esercito (passo %s)" % C.step)
			C._on_next()
			check(C.step == "recruit", "tutorial: recluta (passo %s)" % C.step)
			main.act("recruit", {"u": "inf", "n": 1})
			C.update()
			check(C.step == "endphase" or not main.gcall("can_recruit", [main.h(), hq2, "inf"], {"ok": false})["ok"], "tutorial: fine fase (passo %s)" % C.step)
			if C.step == "recruit":
				C._on_next()
			main.hud.refresh(true)
			main.hud._guide_act("main")
			C.update()
			check(C.step == "source" or C.step == "target" or C.step == "skipatk", "tutorial: scegli l'origine (passo %s)" % C.step)
			C.skip()
			check(not C.active and bool(root.get_node("Settings").get_value("tutorial_done")), "tutorial saltato e segnato come fatto")
			root.get_node("Settings").set_value("ai_speed", "normale")
			main._apply_ai_delay()
			phase = 1; frame = 0
		1:
			var hq := int(main.game.players[main.h()]["hq"])
			main._demo_make_battle(hq)
			print("[flow] pending=", main.game.pending_battle != null, " t=", main.game.time)
			if main.game.pending_battle != null:
				main.show_battle_prompt()
				check(main.modal_kind == "battle", "modale di battaglia")
				main.battle_manual()
				print("[flow] battle node=", main.battle)
			phase = 2; frame = 0
		2:
			if frame == 10 and main.battle != null and main.battle.has_method("end_intro"):
				main.battle.end_intro()   # salta l'introduzione cinematica (poi parte lo schieramento)
			if frame == 20 and main.battle != null and "deploying" in main.battle:
				check(bool(main.battle.deploying), "fase di schieramento della battaglia")
				main.battle._on_button("start")
			if frame > 40 and frame % 20 == 0 and main.battle != null and main.battle.has_method("continue_now"):
				main.battle.continue_now()   # pulsante "Continua" del riepilogo
			if frame == 30:
				if main.battle != null and main.battle.has_method("_on_button"):
					main.battle._on_button("auto")
				elif main.battle != null:
					main._on_battle_finished({"att": {}, "def": {"inf": 1}, "winner": "def", "retreated": false, "autoRest": false})
			if frame > 30 and main.battle == null:
				print("[flow] battle returned, modal=", main.modal_kind, " tip=", main.tutorial.cur)
				main.close_modal(true)
				phase = 3; frame = 0
			if frame > 2000:
				print("[flow] ERRORE battaglia non terminata")
				errors += 1
				main._on_battle_finished(null)
				phase = 3; frame = 0
		3:
			for i in 600:
				main.game.step(0.1)
				main._record_history(false)
				if main.game.pending_battle != null:
					main.gcall("resolve_pending_auto")
			_diplomacy_checks()
			phase = 31; frame = 0
		31:
			# offerta IA mostrata dal ciclo di main._process
			if frame == 8:
				check(main.modal_kind == "pact" or not main.game.has_method("answer_pact"), "modale offerta di patto (modal=%s)" % main.modal_kind)
				if main.modal_kind == "pact":
					main.act("pact-yes")
					check(main.modal_kind == "", "modale chiusa dopo Accetta")
				phase = 4; frame = 0
		4:
			_vet_checks()
			print("[flow] save_available=", main.save_available(), " load_available=", main.load_available())
			var ok: bool = main.save_to_slot("flowtest", "Prova flusso")
			var t0: float = main.game.time
			var terr0 := str(main.gcall("territories_of", [main.h()], []))
			var vet0 := _vets()
			var pacts0 := _pacts_str()
			var fog0 = main.game.fog if "fog" in main.game else null
			main.load_slot("flowtest")
			check(ok, "salvataggio")
			check(absf(t0 - float(main.game.time)) < 0.01, "tempo dopo il caricamento")
			check(terr0 == str(main.gcall("territories_of", [main.h()], [])), "territori dopo il caricamento")
			check(main.game.event.is_connected(main._on_signal), "segnali ricollegati")
			if "terr" in main.game and main.game.terr[0].has("vet"):
				check(vet0 == _vets(), "veterani dopo il caricamento")
			if fog0 != null:
				check(main.game.fog == fog0, "nebbia dopo il caricamento")
			if pacts0 != "":
				check(pacts0 == _pacts_str(), "patti dopo il caricamento (%s / %s)" % [pacts0, _pacts_str()])
			main.game.over = {"winner": main.h(), "reason": "test"}
			phase = 5; frame = 0
		5:
			if frame == 8:
				print("[flow] end modal=", main.modal_kind, " hist=", main.get_history().size())
				check(main.modal_kind == "end", "schermata finale")
				main.act("new-game")
				print("[flow] menu page=", main.menu.page, " game=", main.game)
				round_i += 1
				phase = 0 if round_i < 3 else 7
				frame = 0
		7:
			# ---- scenari (FASE 4): pagina del menu, avvio, briefing, pannello, vittoria, schermata finale
			if scn_i >= SCN_TESTS.size() or not ResourceLoader.exists("res://scripts/core/scenarios.gd"):
				phase = 6; frame = 0
				return false
			var T: Array = SCN_TESTS[scn_i]
			main.back_to_menu("scenari")
			check(main.menu.page == "scenari" and main.menu.content.get_child_count() > 2, "pagina Scenari nel menu")
			main.act("scn-start", {"id": T[0], "faction": T[1]})
			check(main.game != null and main.game.scenario != null and String(main.game.scenario["id"]) == T[0], "scenario %s avviato" % T[0])
			check(main.modal_kind == "briefing" and main.game.paused, "briefing dello scenario (partita in pausa)")
			main.act("resume")
			check(main.modal_kind == "" and not main.game.paused, "briefing chiuso, partita in corso")
			main.hud.refresh(true)
			check(main.hud.lp["scn"].get_child_count() > 0, "pannello dell'operazione nell'HUD")
			check(int(main.game.players[main.h()]["faction"]) == T[1], "fazione scelta nello scenario")
			phase = 8; frame = 0
		8:
			if frame == 5:   # (i primi 4 fotogrammi di ogni fase sono saltati)
				_force_scenario_win(String(SCN_TESTS[scn_i][0]))
			if frame > 5 and main.game.over == null and frame < 400:
				for i in 50:
					if main.turn_mode():
						if main.game.pending_battle != null:
							main.gcall("resolve_pending_auto")
						elif main.my_turn():
							main.game.end_turn()
						else:
							main.game.skip_ai_turn()
					else:
						main.game.step(0.1)
					if main.game.pending_battle != null:
						main.gcall("resolve_pending_auto")
					if main.game.over != null:
						break
			if frame == 420 or (main.game.over != null and main.modal_kind == "end" and frame > 4):
				var T: Array = SCN_TESTS[scn_i]
				var ov = main.game.over
				print("[flow] scenario ", T[0], " over=", ov, " modal=", main.modal_kind)
				check(ov != null and int(ov["winner"]) == main.h(), "scenario %s vinto dal giocatore" % T[0])
				check(ov != null and String(ov["reason"]).find(T[2]) >= 0, "motivo della vittoria («%s»)" % T[2])
				check(main.modal_kind == "end", "schermata finale dello scenario")
				var txt := _texts(main.modal)
				check(txt.find(T[2]) >= 0 and txt.find("Scenario: " + String(main.game.scenario["name"])) >= 0 and txt.find("VITTORIA") >= 0, "testo della schermata finale (%s)" % T[0])
				main.act("quit")
				scn_i += 1
				phase = 7; frame = 0
		6:
			print("[flow] nodi per round: ", log_obj)
			print("[flow] FINE errori=", errors)
			quit()
	return false

func _far_territory() -> int:
	var hh: int = main.h()
	var mine := {}
	for t in main.gcall("territories_of", [hh], []):
		mine[int(t)] = true
	for i in D.TERRITORIES.size():
		if mine.has(i):
			continue
		var near := false
		for j in D.TERRITORIES[i]["adj"]:
			if mine.has(int(j)):
				near = true
			for k in D.TERRITORIES[int(j)]["adj"]:
				if mine.has(int(k)):
					near = true
		if not near:
			return i
	return -1

## Patti come testo con numeri interi (il JSON del salvataggio restituisce float).
func _pacts_str() -> String:
	if not ("pacts" in main.game):
		return ""
	var a := []
	for pc in main.game.pacts:
		a.append("%d-%d-%d" % [int(pc["a"]), int(pc["b"]), int(pc["until"])])
	return str(a)

func _vets() -> String:
	var a := []
	for tr in main.game.terr:
		a.append(int(tr.get("vet", 0)))
	return str(a)

func _diplomacy_checks() -> void:
	var g = main.game
	var hh: int = main.h()
	if not g.has_method("propose_pact"):
		print("[flow] (nucleo senza diplomazia)")
		return
	main.hud.refresh(true)
	var ai := -1
	for P in g.players:
		if int(P["idx"]) != hh and P["alive"]:
			ai = int(P["idx"])
			break
	var r = g.propose_pact(hh, ai)
	print("[flow] proposta a ", g.players[ai]["fac"]["short"], " -> ", r)
	check(r is Dictionary and r.has("ok") and r.has("reason"), "propose_pact restituisce {ok, reason}")
	main.propose_pact(ai)   # stessa via del pulsante (toast con esito)
	if main.pact_between(hh, ai) != null:
		# comando bloccato verso il partner
		var tgt := -1
		var src := -1
		for t in main.gcall("territories_of", [hh], []):
			for j in D.TERRITORIES[int(t)]["adj"]:
				if int(g.terr[int(j)]["owner"]) == ai and D.total_units(g.terr[int(t)]["forces"]) > 0:
					src = int(t); tgt = int(j)
		if tgt >= 0:
			var sr = g.send_division(hh, src, tgt, 0.5)
			print("[flow] attacco al partner -> ", sr)
			check(not sr["ok"] and String(sr["reason"]).find("Patto") >= 0, "attacco al partner rifiutato con motivo")
	# offerta di un'altra IA: simulata con il segnale del nucleo
	var other := -1
	for P in g.players:
		if int(P["idx"]) != hh and P["alive"] and main.pact_between(hh, int(P["idx"])) == null:
			other = int(P["idx"])
	if other >= 0 and g.has_method("answer_pact"):
		var r2 = g.propose_pact(other, hh)   # l'IA propone al giocatore: diventa un'offerta + segnale pact_offer
		print("[flow] offerta da ", g.players[other]["fac"]["short"], " -> ", r2)

func _vet_checks() -> void:
	var g = main.game
	var hh: int = main.h()
	if not g.terr[0].has("vet"):
		print("[flow] (nucleo senza veterani)")
		return
	var hq := int(g.players[hh]["hq"])
	main.hud.refresh(true)
	var v0 := int(g.terr[hq]["vet"])
	if g.has_method("_gain_xp"):
		for i in 30:
			g._gain_xp(hq)
			if int(g.terr[hq]["vet"]) > v0 or v0 >= 3:
				break
	else:
		main._check_vet()
		g.terr[hq]["vet"] = mini(3, v0 + 1)
		main._check_vet()
	main.select(hq)
	main.hud.refresh(true)
	var found := false
	for r in main._recent_toasts:
		if String(r["text"]).begins_with("Il presidio di " + D.TERRITORIES[hq]["name"]):
			found = true
	check(found or v0 >= 3, "toast stella veterano (vet %d -> %d)" % [v0, int(g.terr[hq]["vet"])])

## Porta lo scenario a un passo dalla vittoria del giocatore (le regole le applica il nucleo).
func _force_scenario_win(id: String) -> void:
	var g = main.game
	var hh: int = main.h()
	match id:
		"corsa_petrolio":
			# il giocatore prende 3 territori chiave e li tiene per 60 s
			var n := 0
			for t in g.hold_terrs:
				if n >= int(g.hold_need):
					break
				g.terr[int(t)]["owner"] = hh
				g.terr[int(t)]["forces"] = {"inf": 60, "tank": 30, "art": 10, "aa": 0, "heli": 0, "jet": 0, "drone": 0}
				n += 1
		"assedio_pacifico":
			# la CP del giocatore resiste fino allo scadere
			if "round_limit" in g and int(g.round_limit) > 0:
				g.round = int(g.round_limit)
			else:
				g.time = float(g.time_limit) - 3.0
		_:
			# il giocatore raggiunge la quota del mondo
			var need := int(ceil(float(g.victory_share) * g.terr.size()))
			var k := 0
			for tr in g.terr:
				if int(tr["owner"]) == hh:
					k += 1
			for tr in g.terr:
				if k >= need:
					break
				if int(tr["owner"]) != hh and (int(tr["owner"]) < 0 or int(g.players[int(tr["owner"])]["hq"]) != int(tr["idx"])):
					tr["owner"] = hh
					tr["forces"] = {"inf": 30, "tank": 10, "art": 0, "aa": 0, "heli": 0, "jet": 0, "drone": 0}
					k += 1

func _texts(n: Node) -> String:
	var out := ""
	if n is Label:
		out += (n as Label).text + " | "
	elif n is Button:
		out += (n as Button).text + " | "
	elif n is RichTextLabel:
		out += (n as RichTextLabel).get_parsed_text() + " | "
	for c in n.get_children():
		out += _texts(c)
	return out
