class_name AnalyticsSink
extends RefCounted

# Абстрактный sink для аналитики. Реализации знают, куда писать
# event Dictionary (JSONL-файл, in-memory buffer для тестов, network endpoint).
# Analytics autoload держит одну реализацию, gameplay-код с sink'ами
# напрямую не общается.

# Записать одно событие. Реализация может буферизовать до flush().
# Ошибки не должны выбрасывать — sink обязан либо тихо проглотить,
# либо переключить свой internal state в "broken" и вернуться,
# не роняя вызывающий gameplay-код.
func write_event(_event: Dictionary) -> void:
	pass

# Принудительный сброс буфера на диск / в конечный transport.
# Вызывается на floor_completed, run_finished, quit_to_menu.
func flush() -> void:
	pass

# Финализирует sink — закрывает файлы, отменяет таймеры.
# После close() sink считается непригодным и не должен принимать write_event.
func close() -> void:
	pass

# Broken sink — sink, у которого произошла невосстановимая IO/serialization
# ошибка. Analytics service читает этот флаг после каждой операции и,
# если sink сломан, безопасно переключает себя на NullAnalyticsSink.
func is_broken() -> bool:
	return false
