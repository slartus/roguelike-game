class_name AnalyticsIds
extends RefCounted

# Генерация/чтение уникальных ID для аналитики.
# UUID4-подобный формат: 32 hex-символа, отформатированные 8-4-4-4-12.
#
# Внутренний RNG — отдельный RandomNumberGenerator с явным randomize().
# Он НЕ трогает глобальный `randi()` стрим Godot, поэтому запись событий
# аналитики никогда не сдвигает detrministic gameplay RNG (dungeon,
# spawn table, upgrade offer generator).

const INSTALLATION_ID_PATH: String = "user://analytics/installation_id.txt"

static func new_uuid() -> String:
	# 128-битный random, форматированный как UUID4 (8-4-4-4-12).
	# Не PRODUCTION-grade UUID (не выставляем version/variant nibbles),
	# но для аналитики достаточно: 122 bits энтропии, коллизии
	# практически невозможны в масштабе сотен тысяч сессий.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var parts := PackedStringArray()
	parts.append(_hex(rng, 8))
	parts.append(_hex(rng, 4))
	parts.append(_hex(rng, 4))
	parts.append(_hex(rng, 4))
	parts.append(_hex(rng, 12))
	return "-".join(parts)

static func _hex(rng: RandomNumberGenerator, length: int) -> String:
	var out := ""
	for i in range(length):
		out += "%x" % rng.randi_range(0, 15)
	return out

# installation_id — стабильный между запусками игры, обнуляется при
# удалении user:// данных. Первый вызов генерирует и сохраняет,
# последующие читают из файла.
static func load_or_create_installation_id() -> String:
	var existing := _read_installation_id_file()
	if existing != "":
		return existing
	var new_id := new_uuid()
	_write_installation_id_file(new_id)
	return new_id

static func _read_installation_id_file() -> String:
	if not FileAccess.file_exists(INSTALLATION_ID_PATH):
		return ""
	var file := FileAccess.open(INSTALLATION_ID_PATH, FileAccess.READ)
	if file == null:
		return ""
	var content := file.get_as_text().strip_edges()
	file.close()
	return content

static func _write_installation_id_file(id: String) -> void:
	# Директория та же, что у JsonlAnalyticsSink — создаём безопасно.
	if not DirAccess.dir_exists_absolute("user://analytics"):
		var err := DirAccess.make_dir_recursive_absolute("user://analytics")
		if err != OK:
			push_warning("[analytics] cannot create user://analytics for installation_id")
			return
	var file := FileAccess.open(INSTALLATION_ID_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("[analytics] cannot write installation_id to %s" % INSTALLATION_ID_PATH)
		return
	file.store_string(id)
	file.close()

# Экспонируется для тестов — очистка installation_id из user://.
static func clear_installation_id_file() -> void:
	if not FileAccess.file_exists(INSTALLATION_ID_PATH):
		return
	DirAccess.remove_absolute(INSTALLATION_ID_PATH)
