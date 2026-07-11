extends GutTest

# Тесты JSONL sink'а: буферизация, flush, is_broken, формат.
# Каждый тест создаёт свой session_id, чтобы файлы не пересекались.
# after_each чистит созданный файл.

var _test_session_id: String = ""
var _test_file_path: String = ""

func before_each() -> void:
	# Не используем глобальный randi() чтобы не сдвигать RNG-стрим других
	# тестов — соседние тесты аналитики проверяют invariant «Analytics
	# не трогает global RNG».
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_test_session_id = "test_%d_%d" % [Time.get_ticks_msec(), rng.randi() % 1000000]
	_test_file_path = "user://analytics/session_%s.jsonl" % _test_session_id

func after_each() -> void:
	if FileAccess.file_exists(_test_file_path):
		DirAccess.remove_absolute(_test_file_path)

func _read_lines() -> PackedStringArray:
	if not FileAccess.file_exists(_test_file_path):
		return PackedStringArray()
	var file := FileAccess.open(_test_file_path, FileAccess.READ)
	var out := PackedStringArray()
	while not file.eof_reached():
		var line := file.get_line()
		if line != "":
			out.append(line)
	file.close()
	return out

func test_write_event_buffers_until_limit() -> void:
	var sink := JsonlAnalyticsSink.new(_test_session_id)
	sink.write_event({"event_name": "test", "n": 1})
	assert_eq(sink.buffered_count(), 1)
	assert_false(FileAccess.file_exists(_test_file_path), "file not written yet")

func test_explicit_flush_writes_to_file() -> void:
	var sink := JsonlAnalyticsSink.new(_test_session_id)
	sink.write_event({"event_name": "test", "n": 1})
	sink.flush()
	assert_eq(sink.buffered_count(), 0, "buffer cleared after flush")
	var lines := _read_lines()
	assert_eq(lines.size(), 1, "one line written")

func test_each_line_is_valid_json() -> void:
	var sink := JsonlAnalyticsSink.new(_test_session_id)
	sink.write_event({"event_name": "first", "value": 42})
	sink.write_event({"event_name": "second", "value": "hello"})
	sink.flush()
	var lines := _read_lines()
	assert_eq(lines.size(), 2)
	for line in lines:
		var parsed = JSON.parse_string(line)
		assert_typeof(parsed, TYPE_DICTIONARY, "line must be valid JSON dict: '%s'" % line)

func test_flush_appends_to_existing_file() -> void:
	var sink := JsonlAnalyticsSink.new(_test_session_id)
	sink.write_event({"event_name": "first"})
	sink.flush()
	sink.write_event({"event_name": "second"})
	sink.flush()
	var lines := _read_lines()
	assert_eq(lines.size(), 2, "second flush appended, not overwrote")

func test_buffer_auto_flushes_at_limit() -> void:
	var sink := JsonlAnalyticsSink.new(_test_session_id)
	for i in range(JsonlAnalyticsSink.BUFFER_EVENT_LIMIT):
		sink.write_event({"event_name": "n_%d" % i})
	assert_eq(sink.buffered_count(), 0, "buffer flushed at BUFFER_EVENT_LIMIT")
	var lines := _read_lines()
	assert_eq(lines.size(), JsonlAnalyticsSink.BUFFER_EVENT_LIMIT)

func test_close_flushes_remaining_events() -> void:
	var sink := JsonlAnalyticsSink.new(_test_session_id)
	sink.write_event({"event_name": "test"})
	sink.close()
	var lines := _read_lines()
	assert_eq(lines.size(), 1)

func test_write_after_close_is_ignored() -> void:
	var sink := JsonlAnalyticsSink.new(_test_session_id)
	sink.write_event({"event_name": "first"})
	sink.close()
	sink.write_event({"event_name": "after_close"})
	sink.flush()
	var lines := _read_lines()
	assert_eq(lines.size(), 1, "second event ignored after close")

func test_flush_on_empty_buffer_does_not_create_file() -> void:
	var sink := JsonlAnalyticsSink.new(_test_session_id)
	sink.flush()
	assert_false(FileAccess.file_exists(_test_file_path), "empty flush is no-op")

func test_is_broken_false_on_normal_operation() -> void:
	var sink := JsonlAnalyticsSink.new(_test_session_id)
	sink.write_event({"event_name": "test"})
	sink.flush()
	assert_false(sink.is_broken())

func test_file_path_uses_session_id() -> void:
	var sink := JsonlAnalyticsSink.new(_test_session_id)
	assert_true(sink.file_path().ends_with("session_%s.jsonl" % _test_session_id))
