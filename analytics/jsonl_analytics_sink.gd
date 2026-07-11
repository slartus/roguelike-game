class_name JsonlAnalyticsSink
extends AnalyticsSink

# JSONL sink: одна строка = одно JSON-событие.
# Файл: user://analytics/session_<session_id>.jsonl.
#
# Буферизация: держим до BUFFER_EVENT_LIMIT событий в памяти,
# сбрасываем на диск batch'ем. Analytics service дополнительно
# вызывает flush() на важных lifecycle-точках (floor_completed,
# run_finished, session_finished, application close).
#
# Ошибки I/O не выбрасываются наружу — sink помечает себя broken=true,
# Analytics service читает is_broken() и переключается на NullAnalyticsSink.

const BUFFER_EVENT_LIMIT: int = 32
const ANALYTICS_DIR: String = "user://analytics"

var _file_path: String
var _buffer: PackedStringArray = PackedStringArray()
var _broken: bool = false
var _closed: bool = false

func _init(session_id: String) -> void:
	_file_path = "%s/session_%s.jsonl" % [ANALYTICS_DIR, session_id]
	if not _ensure_directory():
		_broken = true

func write_event(event: Dictionary) -> void:
	if _closed or _broken:
		return
	var line := JSON.stringify(event)
	# JSON.stringify вернёт "null" для несериализуемых значений — на этом
	# уровне доверяем, что Analytics.autoload шлёт валидный Dictionary
	# (там уже прошла защита от Object'ов).
	_buffer.append(line)
	if _buffer.size() >= BUFFER_EVENT_LIMIT:
		flush()

func flush() -> void:
	if _closed or _broken or _buffer.is_empty():
		return
	var file := FileAccess.open(_file_path, FileAccess.READ_WRITE)
	if file == null:
		# Файла ещё нет — создаём в WRITE mode.
		file = FileAccess.open(_file_path, FileAccess.WRITE)
	else:
		file.seek_end()
	if file == null:
		# Не удалось открыть даже на запись. Помечаем sink broken,
		# сбрасываем буфер, чтобы память не росла.
		push_warning("[analytics] failed to open sink file: %s" % _file_path)
		_broken = true
		_buffer.clear()
		return
	for line in _buffer:
		file.store_line(line)
	file.close()
	_buffer.clear()

func close() -> void:
	if _closed:
		return
	flush()
	_closed = true

func is_broken() -> bool:
	return _broken

func file_path() -> String:
	# Для тестов / диагностики.
	return _file_path

func buffered_count() -> int:
	# Для тестов — сколько событий сидит в буфере до flush.
	return _buffer.size()

func _ensure_directory() -> bool:
	if DirAccess.dir_exists_absolute(ANALYTICS_DIR):
		return true
	var err := DirAccess.make_dir_recursive_absolute(ANALYTICS_DIR)
	if err != OK:
		push_warning("[analytics] failed to create %s (err=%s)" % [ANALYTICS_DIR, err])
		return false
	return true
