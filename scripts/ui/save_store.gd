extends RefCounted
## Archivio dei salvataggi in user://saves: per ogni slot un file dati compresso (<slot>.sav, store_var: i tipi
## restano esatti), un file di intestazione leggero (<slot>.meta) e una miniatura (<slot>.png).
## Slot speciali: "quick" (F5/F9) e "auto" (salvataggio automatico). Uso statico: SaveStore.list(), save(), load_data()...

static var DIR := "user://saves"
const VERSION := 1
const THUMB := Vector2i(320, 180)

static func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)

static func path(slot: String, ext: String) -> String:
	return DIR.path_join(slot + "." + ext)

static func new_slot_id() -> String:
	return "s%d_%03d" % [int(Time.get_unix_time_from_system()), randi() % 1000]

## Elenco degli slot, il più recente per primo. Ogni voce: meta + {slot, thumb_path}.
static func list() -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(DIR):
		return out
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(".meta"):
			continue
		var slot := f.get_basename()
		if not FileAccess.file_exists(path(slot, "sav")):
			continue
		var m = _read_meta(slot)
		if m == null:
			continue
		m["slot"] = slot
		m["thumb_path"] = path(slot, "png") if FileAccess.file_exists(path(slot, "png")) else ""
		out.append(m)
	out.sort_custom(func(a, b): return float(a.get("date", 0)) > float(b.get("date", 0)))
	return out

static func latest():
	var l := list()
	return l[0] if l.size() else null

static func _read_meta(slot: String):
	var fa := FileAccess.open(path(slot, "meta"), FileAccess.READ)
	if fa == null:
		return null
	var m = fa.get_var()
	fa.close()
	return m if m is Dictionary else null

## Salva: data = game.serialize() (+ dati dell'interfaccia), meta = intestazione, img = miniatura (facoltativa).
static func save(slot: String, data: Dictionary, meta: Dictionary, img: Image = null) -> bool:
	_ensure_dir()
	var fa := FileAccess.open_compressed(path(slot, "sav"), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if fa == null:
		return false
	fa.store_var({"version": VERSION, "data": data})
	fa.close()
	var m := meta.duplicate(true)
	m["version"] = VERSION
	m["date"] = Time.get_unix_time_from_system()
	var fm := FileAccess.open(path(slot, "meta"), FileAccess.WRITE)
	if fm == null:
		return false
	fm.store_var(m)
	fm.close()
	if img != null and not img.is_empty():
		var t := img.duplicate() as Image
		if t.is_compressed():
			t.decompress()
		t.convert(Image.FORMAT_RGB8)
		var s := Vector2(t.get_size())
		var k := maxf(THUMB.x / s.x, THUMB.y / s.y)
		t.resize(maxi(1, int(s.x * k)), maxi(1, int(s.y * k)), Image.INTERPOLATE_LANCZOS)
		var ox := (t.get_width() - THUMB.x) / 2
		var oy := (t.get_height() - THUMB.y) / 2
		t = t.get_region(Rect2i(maxi(0, ox), maxi(0, oy), mini(THUMB.x, t.get_width()), mini(THUMB.y, t.get_height())))
		t.save_png(path(slot, "png"))
	return true

static func load_data(slot: String):
	if not FileAccess.file_exists(path(slot, "sav")):
		return null
	var fa := FileAccess.open_compressed(path(slot, "sav"), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if fa == null:
		return null
	var d = fa.get_var()
	fa.close()
	if not (d is Dictionary) or not d.has("data"):
		return null
	return d["data"]

static func remove(slot: String) -> void:
	for ext in ["sav", "meta", "png"]:
		if FileAccess.file_exists(path(slot, ext)):
			DirAccess.remove_absolute(path(slot, ext))

static func thumb_texture(p: String) -> Texture2D:
	if p == "" or not FileAccess.file_exists(p):
		return null
	var img := Image.load_from_file(p)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)

static func fmt_date(unix: float) -> String:
	var off := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(int(unix) + off)
	return "%02d/%02d/%04d %02d:%02d" % [d["day"], d["month"], d["year"], d["hour"], d["minute"]]
