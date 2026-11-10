# Patch: integrare BattleAudio in Battle3D (audio posizionale della battaglia)

`scripts/battle/battle_audio.gd` (class_name **BattleAudio**, Node3D) suona tutta la battaglia in 3D leggendo
`sim.units`, `sim.shells` e gli eventi `fx`. Battle3D deve solo crearla, passarle la lista degli eventi e chiamare
`update(dt)`. Poi vanno tolte le vecchie chiamate `_sfx(...)` di armi/esplosioni (altrimenti i suoni si sentono due volte:
una in 3D e una 2D "piatta"). I suoni d'interfaccia (`alert`, `order`, `select`...) restano come sono.
Dopo l'aggiunta del file serve una volta `node tools/godot_run.js -- --headless --path . --import` (nuova class_name).

## 1. battle3d.gd — variabile
Accanto a `var coast: BattleCoast` / `var fort: Node3D`:
```gdscript
var audio: BattleAudio
```

## 2. battle3d.gd — `start(s)`: creazione
Subito dopo `fx.dust_color = _dust_color()` (la telecamera e il terreno esistono già):
```gdscript
	audio = BattleAudio.new()
	audio.name = "Audio"
	add_child(audio)                 # prima di setup(): crea un AudioListener3D e lo rende corrente
	audio.setup(self, sim, cam)
```
`setup` legge `sim.tkey`/`sim.sea` (riverbero e vento per terreno) e `self.terrain` (quota dei suoni).

## 3. battle3d.gd — `_consume_fx(silent)`: passare gli eventi
Subito dopo
```gdscript
	var list := sim.fx
	sim.fx = []
```
aggiungere:
```gdscript
	if not silent and audio != null:
		audio.on_fx(list)
```
(Usa solo `.get()` con valori predefiniti: accetta già "spotted"/"ambush" e le chiavi "flank"/"ambush"/"cover".
Un colpo con `"ambush": true` suona +2 dB; "spotted" con `first` e "ambush" nemico danno un breve gracchio radio 2D.)

## 4. battle3d.gd — `_process(delta)`: aggiornamento
Subito dopo `_consume_fx(false)`:
```gdscript
	if audio != null:
		audio.update(dt)
```
(`update` muove l'ascoltatore con la telecamera, avvia i suoni ritardati, sceglie i 4 mezzi + 2 aerei più udibili per i
loop dei motori, fa fischiare i proiettili d'artiglieria in arrivo, muove il caccia del supporto aereo e regola vento e
tappeti di battaglia. Con `sim.paused` o `sim.done` i motori e i tappeti sfumano.)

## 5. battle3d.gd — TOGLIERE queste chiamate (ora le fa BattleAudio, in 3D)
| Funzione | Riga da eliminare |
|---|---|
| `_consume_fx`, ramo `"impact"` | `_sfx("explosion", 0.09)` |
| `_on_smoke` | `_sfx("missile", 0.25)` |
| `_update_jets` | `_sfx("missile", 0.0)` (si può togliere anche `j["snd"]`) |
| `_on_bomb` | `_sfx("explosion", 0.06)` |
| `_on_fire`, ramo `art` | `_sfx("cannon", 0.14)` |
| `_on_fire`, `"inf"` | `_sfx("gun", 0.07)` |
| `_on_fire`, `"tank"` | `_sfx("cannon", 0.12)` |
| `_on_fire`, `"aa"` | `_sfx("missile", 0.09)` e `_sfx("gun", 0.09)` |
| `_on_fire`, `"heli", "jet"` | `_sfx("missile", 0.16)` |
| `_on_fire`, `"drone"` | `_sfx("gun", 0.07)` |
| `_on_fire`, `_:` | `_sfx("gun", 0.07)` |
| `_on_kill` | le tre `_sfx("explosion", 0.1)` |

RESTANO: `_sfx("alert", ...)` (inizio, allarmi, sbarramento, `_start_jet`) e `b._sfx("order", 0.05)` dell'HUD.

## 6. battle3d.gd — `_prewarm()` (facoltativo)
Il blocco "suoni della battaglia" funziona ancora (`Sfx._get_stream` ora mette in coda i banchi senza bloccare), ma è
più chiaro sostituirlo con:
```gdscript
	var sx = get_node_or_null("/root/Sfx")
	if sx != null and sx.has_method("warm_battle"):
		sx.warm_battle()
```

## 7. battle_coast.gd — cannoni navali e impatti (stesso principio)
In fondo alla salva (ora `battle._sfx("cannon", 0.3)`):
```gdscript
	if battle.audio != null:
		battle.audio.play_at("cannon", gun, "arty", 3.0, 0.8)
```
In `_impact(s)` sostituire
```gdscript
	if p.distance_to(battle.cam.global_position) < 200.0:
		battle._sfx("explosion", 0.2)
```
con
```gdscript
	if battle.audio != null:
		battle.audio.play_at("arty_impact" if s["land"] else "expl_small", p, "big" if s["land"] else "small")
```
(`play_at` scarta da sé i suoni inudibili, sceglie la variante lontana e applica il ritardo del suono.)

## API di BattleAudio
- `setup(battle_root: Node3D, sim, camera: Camera3D)` — dopo `add_child`.
- `on_fx(list: Array)` — eventi della sim: fire, impact, kill, bomb, smoke, airstrike, spotted, ambush.
- `update(dt)` — ogni frame.
- `play_at(name, pos: Vector3, cat := "misc", vol_db := 0.0, pitch := 1.0, delay := 0.0) -> bool` — qualunque banco
  di Sfx in un punto del mondo; categorie: rifle, mg, hmg, aa, flak, cannon, arty, expl, big, small, rocket, whistle, misc.
- `active_voices()`, `stats` (played/dropped/culled), `cost_us` — diagnostica.
