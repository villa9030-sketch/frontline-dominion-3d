# Polish battaglia 3D — proposta per l'agente vista (Agente F → vista battaglia)

Modelli, materiali e VFX sono già stati aggiornati in `scripts/models/*` (nessuna modifica necessaria nella battaglia per
vederli). Qui sotto le modifiche **pronte da applicare** ai file della vista (`battle3d.gd`, `battle_terrain.gd`), in ordine di
resa/costo. Tutte sono economiche (niente SDFGI/volumetrica/SSR: il PC è debole). Misurare prima/dopo con `--prof=1`.

## 1. Tonemap e grading (battle3d.gd `_build_env`, ~riga 660) — costo zero
Il Filmic attuale schiaccia le alte luci e lascia le ombre grigie. AgX (Godot ≥ 4.4) è più naturale sui verdi militari;
una LUT 1D dà ombre leggermente fredde e luci calde (look "cinematografico" sobrio).

```gdscript
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = expo * 1.08
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 1.12 if mood != "coperto" else 1.0   # AgX desatura un po': compensare
	# ombre fredde, mezzitoni neutri, luci calde (LUT 1D, 256 px)
	var cc := Gradient.new()
	cc.offsets = PackedFloat32Array([0.0, 0.18, 0.5, 0.82, 1.0])
	cc.colors = PackedColorArray([Color(0.0, 0.01, 0.03), Color(0.16, 0.18, 0.21), Color(0.5, 0.5, 0.49), Color(0.84, 0.82, 0.77), Color(1, 0.98, 0.94)])
	var lut := GradientTexture1D.new()
	lut.gradient = cc
	lut.width = 256
	env.adjustment_color_correction = lut
```
Se si preferisce restare su Filmic: almeno `adjustment_contrast = 1.1` + la LUT.

## 2. SSAO che "appoggia" i mezzi al suolo — costo trascurabile (già attivo su qualità alta)
Oggi l'AO si vede poco al sole perché `ssao_light_affect` = 0. Con un po' di effetto anche in luce diretta i carri e le
squadre smettono di "galleggiare".
```gdscript
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.2
	env.ssao_power = 1.5
	env.ssao_detail = 0.6
	env.ssao_horizon = 0.06
	env.ssao_sharpness = 0.98
	env.ssao_light_affect = 0.25      # chiave: AO visibile anche al sole sotto scafi e cingoli
	env.ssao_ao_channel_affect = 0.0
```

## 3. Ombre più nitide dove guarda la telecamera (battle3d.gd ~riga 694)
350 m di distanza d'ombra con la telecamera a ~90 m sprecano risoluzione: le ombre dei carri risultano sfocate.
```gdscript
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_split_1 = 0.08
	sun.directional_shadow_split_2 = 0.22
	sun.directional_shadow_split_3 = 0.5
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 0.9        # contatto cingolo/terreno meno "staccato"
	sun.shadow_blur = 1.2
```
Opzionale (project.godot, solo agente E): `rendering/lights_and_shadows/directional_shadow/size = 4096` su qualità alta
(già 4096? verificare) e `soft_shadow_filter_quality = 3` (medio) — +0.3 ms circa su GTX 1070.

## 4. Luce ambiente/cielo
- `env.ambient_light_sky_contribution = 0.85` e `env.ambient_light_color = fog` (riempie le ombre con il colore della foschia,
  meno grigio-blu piatto).
- Cielo: `sm.sky_energy_multiplier = 1.0`, `sm.ground_bottom_color = sky_hor.darkened(0.65)`, `sm.sun_curve = 0.08` (disco
  solare più morbido con il glow).
- Glow: `env.glow_intensity = 0.4`, `env.glow_strength = 0.9`, `env.glow_levels/2 = 0.6` per esplosioni e vampe con alone ampio
  ma senza velare tutto: 
```gdscript
	env.set_glow_level(1, 0.0); env.set_glow_level(2, 0.6); env.set_glow_level(3, 1.0); env.set_glow_level(4, 0.8); env.set_glow_level(5, 0.4)
```

## 5. Nebbia di profondità (aerial perspective)
```gdscript
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = fog_d * 0.7
	env.fog_aerial_perspective = 0.55 if mood != "coperto" else 0.3   # il fondo prende il colore del cielo: scala e profondità
	env.fog_sky_affect = 0.35
	env.fog_height = -2.0
	env.fog_height_density = 0.0015     # leggera foschia radente in tutte le mappe (non solo foresta)
```

## 6. Terreno (battle_terrain.gd, shader alle righe ~543-628)
a) **Macro-variazione di tono e "chiazze" di erba secca/fango** (rompe la ripetizione a grande scala):
```glsl
	// dopo il calcolo di `col` (riga ~553)
	float macro = texture(noise_tex, p / 520.0 + 0.17).r;
	col *= mix(vec3(0.92, 0.95, 0.88), vec3(1.06, 1.02, 0.94), macro);
	float dry = smoothstep(0.55, 0.75, texture(noise_tex, p / 90.0 + 0.41).r) * (1.0 - rk);
	col = mix(col, col * vec3(1.18, 1.08, 0.82), dry * 0.35 * float(ttype != 2));
```
b) **Rugosità variabile** (le zone umide/scure leggermente più lucide, polvere più opaca):
```glsl
	ROUGHNESS = clamp(0.93 - sn * 0.35 - wet * 0.6 - (1.0 - n3) * 0.06 - (ttype == 2 ? m.r * 0.08 : 0.0), 0.05, 1.0);
```
c) **Micro-normale in due scale** (oggi una sola a p/3.1, che da vicino si vede ripetuta):
```glsl
	vec3 nA = texture(noise_nrm, p / 3.1).rgb;
	vec3 nB = texture(noise_nrm, p / 0.9 + 0.5).rgb;
	NORMAL_MAP = normalize(mix(nA, nB, 0.35 * fine));
	NORMAL_MAP_DEPTH = 0.65 * fine + rk * 0.8;
```
d) **Solchi dei cingoli**: se il terreno ha già `scorch_tex` (field_rect), si può usare un secondo canale (G) dello stesso
`ImageTexture` per le tracce: la vista disegna ogni ~0,5 s un segmento scuro largo 0.6 m sotto ciascun cingolo dei mezzi
in movimento (stessa routine che scrive le bruciature). Nello shader:
```glsl
	float trk = texture(scorch_tex, suv).g * ins;
	col = mix(col, c_dirt * 0.62, trk * 0.55);
```

## 7. Erba e alberi
- Gli alberi (`Props.tree_mesh`) usano ora `foliage.gdshader`: luce avvolgente, controluce, variazione di colore e un leggero
  ondeggiare al vento (fase per istanza, funziona con MultiMesh). Nessuna modifica necessaria; se il vento disturba
  impostare `mat.set_shader_parameter("wind", 0.0)` sul materiale della superficie 1 della mesh.
- **Erba** (BattleProps.grass_mesh): colorare la base più scura e la punta più chiara (colore di vertice per altezza) e
  aggiungere nello shader dell'erba `diffuse_lambert_wrap` + `BACKLIGHT = ALBEDO * 0.4`; far sfumare la densità con la
  distanza (`visibility_range_end = 120`, `visibility_range_end_margin = 20`, fade `VISIBILITY_RANGE_FADE_SELF`).
- Ombre: l'erba non deve proiettare ombre (`cast_shadow = OFF`), gli alberi sì ma solo entro 150 m
  (`visibility_range_end` sul MultiMeshInstance dell'ombra, o `GeometryInstance3D.SHADOW_CASTING_SETTING_ON` solo LOD vicino).

## 8. Effetti
- `Vfx.explosion` ora lascia una colonna di fumo che persiste ~8 s e una bruciatura (Decal, max 24 vive, sbiadisce in 20 s).
  La battaglia ha già le bruciature nel terreno: se si vuole evitare il doppio, chiamare `Vfx.explosion` in un nodo e poi
  rimuovere i figli `Scorch` del genitore, oppure lasciarle (si sommano bene: la decal è un alone, la texture il cratere).
- Polvere al tiro dei carri: in `_on_fire` per i tipi `tank`/`art` aggiungere `Vfx.dust(self, p_suolo_davanti_alla_canna)`
  (già esistente, 6–8 particelle) — dà molto "peso" al colpo.

## Costi attesi (GTX 1070, 960×540 → 1080p)
1, 4, 5: ~0 ms · 2: +0.2–0.4 ms (solo qualità alta) · 3: −0.1/+0.2 ms · 6: +0.1 ms (2 letture texture) · 7: ~0.
