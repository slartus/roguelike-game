extends GutTest

# Тесты генерации ID и persistence installation_id.
# installation_id file — единственный persistence, снимок делаем в
# before_each, восстанавливаем в after_each чтобы соседние тесты
# не мешали друг другу.

const INSTALLATION_ID_PATH: String = "user://analytics/installation_id.txt"

var _saved_installation_id: String = ""
var _had_installation_id: bool = false

func before_each() -> void:
	_had_installation_id = FileAccess.file_exists(INSTALLATION_ID_PATH)
	if _had_installation_id:
		var file := FileAccess.open(INSTALLATION_ID_PATH, FileAccess.READ)
		_saved_installation_id = file.get_as_text().strip_edges()
		file.close()
	AnalyticsIds.clear_installation_id_file()

func after_each() -> void:
	AnalyticsIds.clear_installation_id_file()
	if _had_installation_id:
		if not DirAccess.dir_exists_absolute("user://analytics"):
			DirAccess.make_dir_recursive_absolute("user://analytics")
		var file := FileAccess.open(INSTALLATION_ID_PATH, FileAccess.WRITE)
		file.store_string(_saved_installation_id)
		file.close()

func test_new_uuid_has_correct_format() -> void:
	var uuid := AnalyticsIds.new_uuid()
	assert_eq(uuid.length(), 36, "UUID has 32 hex chars + 4 dashes")
	var parts := uuid.split("-")
	assert_eq(parts.size(), 4 + 1, "UUID has 5 dash-separated segments")
	assert_eq(parts[0].length(), 8)
	assert_eq(parts[1].length(), 4)
	assert_eq(parts[2].length(), 4)
	assert_eq(parts[3].length(), 4)
	assert_eq(parts[4].length(), 12)

func test_new_uuid_uses_only_hex_chars() -> void:
	var uuid := AnalyticsIds.new_uuid()
	for i in range(uuid.length()):
		var ch := uuid[i]
		var is_hex := (ch >= "0" and ch <= "9") or (ch >= "a" and ch <= "f") or ch == "-"
		assert_true(is_hex, "unexpected char '%s' at position %d in '%s'" % [ch, i, uuid])

func test_uuids_are_unique_across_calls() -> void:
	# 100 UUID должны быть все разные — коллизия при 122 битах энтропии
	# практически невозможна. Если коллизия случится — генератор сломан.
	var seen := {}
	for i in range(100):
		var uuid := AnalyticsIds.new_uuid()
		assert_false(seen.has(uuid), "UUID collision at iteration %d: %s" % [i, uuid])
		seen[uuid] = true

func test_new_uuid_does_not_consume_global_rng() -> void:
	# Критично: аналитика не должна сдвигать gameplay RNG.
	# global randi() использует свой стрим, отдельный от RandomNumberGenerator.
	seed(42)
	var expected := randi()
	seed(42)
	AnalyticsIds.new_uuid()
	AnalyticsIds.new_uuid()
	AnalyticsIds.new_uuid()
	var actual := randi()
	assert_eq(actual, expected, "global randi() stream shifted by UUID generation")

func test_load_or_create_installation_id_creates_new_when_missing() -> void:
	assert_false(FileAccess.file_exists(INSTALLATION_ID_PATH), "precondition: no file")
	var id := AnalyticsIds.load_or_create_installation_id()
	assert_ne(id, "", "installation_id must be non-empty")
	assert_true(FileAccess.file_exists(INSTALLATION_ID_PATH), "file was created")

func test_load_or_create_installation_id_reads_existing() -> void:
	var first := AnalyticsIds.load_or_create_installation_id()
	var second := AnalyticsIds.load_or_create_installation_id()
	assert_eq(first, second, "second call returns persisted ID")

func test_clear_installation_id_removes_file() -> void:
	AnalyticsIds.load_or_create_installation_id()
	assert_true(FileAccess.file_exists(INSTALLATION_ID_PATH))
	AnalyticsIds.clear_installation_id_file()
	assert_false(FileAccess.file_exists(INSTALLATION_ID_PATH))
