class_name NullAnalyticsSink
extends AnalyticsSink

# No-op sink. Используется когда analytics_enabled=false либо когда
# основной sink сломался и Analytics переключилась в safe mode.
# Не создаёт файлов, не бросает ошибок, не аллоцирует.

func write_event(_event: Dictionary) -> void:
	pass

func flush() -> void:
	pass

func close() -> void:
	pass

func is_broken() -> bool:
	return false
