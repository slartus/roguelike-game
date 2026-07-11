extends GutTest

# Проверяем чистые графовые примитивы RoomGraph — smart entrance/exit
# selection и floor metrics полагаются на них.

func test_add_edge_is_bidirectional() -> void:
	var g := RoomGraph.new(3)
	g.add_edge(0, 1)
	assert_true(g.adjacency[0].has(1))
	assert_true(g.adjacency[1].has(0))
	# Двойной add_edge не дублирует.
	g.add_edge(0, 1)
	assert_eq(g.adjacency[0].size(), 1)

func test_bfs_distance_on_chain() -> void:
	var g := RoomGraph.new(4)
	g.add_edge(0, 1)
	g.add_edge(1, 2)
	g.add_edge(2, 3)
	var dist := g.bfs_distances(0)
	assert_eq(int(dist[0]), 0)
	assert_eq(int(dist[1]), 1)
	assert_eq(int(dist[2]), 2)
	assert_eq(int(dist[3]), 3)

func test_shortest_path_length_disconnected_returns_minus_one() -> void:
	var g := RoomGraph.new(3)
	g.add_edge(0, 1)  # node 2 изолирован
	assert_eq(g.shortest_path_length(0, 2), -1)

func test_is_graph_connected_true_when_all_reachable() -> void:
	var g := RoomGraph.new(3)
	g.add_edge(0, 1)
	g.add_edge(1, 2)
	assert_true(g.is_graph_connected())

func test_is_graph_connected_false_when_isolated_node() -> void:
	var g := RoomGraph.new(3)
	g.add_edge(0, 1)
	assert_false(g.is_graph_connected())

func test_dead_end_indices_return_degree_one_nodes() -> void:
	# 0 — 1 — 2  → dead ends {0, 2}
	var g := RoomGraph.new(3)
	g.add_edge(0, 1)
	g.add_edge(1, 2)
	var deads := g.dead_end_indices()
	assert_true(deads.has(0))
	assert_true(deads.has(2))
	assert_false(deads.has(1))

func test_branch_count_counts_degree_ge_3() -> void:
	# Star: 0 в центре, 1/2/3 висят. Только 0 имеет degree 3.
	var g := RoomGraph.new(4)
	g.add_edge(0, 1)
	g.add_edge(0, 2)
	g.add_edge(0, 3)
	assert_eq(g.branch_count(), 1)

func test_farthest_pair_on_chain_returns_endpoints() -> void:
	var g := RoomGraph.new(5)
	for i in range(4):
		g.add_edge(i, i + 1)
	var pair := g.farthest_pair()
	# Ожидаем пару 0-4 (концы цепочки).
	var lo: int = mini(pair.x, pair.y)
	var hi: int = maxi(pair.x, pair.y)
	assert_eq(lo, 0)
	assert_eq(hi, 4)

func test_shortest_path_returns_full_route() -> void:
	# 0 — 1 — 2 — 3
	var g := RoomGraph.new(4)
	g.add_edge(0, 1)
	g.add_edge(1, 2)
	g.add_edge(2, 3)
	var path := g.shortest_path(0, 3)
	assert_eq(path, [0, 1, 2, 3])

func test_cycle_count_zero_for_tree() -> void:
	var g := RoomGraph.new(4)
	g.add_edge(0, 1)
	g.add_edge(1, 2)
	g.add_edge(1, 3)  # ветка, но не цикл
	assert_eq(g.cycle_count(), 0)

func test_cycle_count_positive_for_triangle() -> void:
	var g := RoomGraph.new(3)
	g.add_edge(0, 1)
	g.add_edge(1, 2)
	g.add_edge(2, 0)
	assert_eq(g.cycle_count(), 1)

func test_build_from_doorways_detects_bsp_rooms() -> void:
	# Две смежные rooms + corridor в общей стене → edge должен появиться.
	var rooms: Array[Rect2i] = [
		Rect2i(Vector2i(0, 0), Vector2i(100, 100)),
		Rect2i(Vector2i(120, 0), Vector2i(100, 100)),
	]
	# Общая стена — вертикальная линия x=100..120, wall_thickness = 20.
	# Corridor должен быть внутри этой стены.
	var corridors: Array[Rect2i] = [
		Rect2i(Vector2i(100, 30), Vector2i(20, 40)),
	]
	var graph := RoomGraph.build_from_doorways(rooms, corridors)
	assert_true(graph.is_graph_connected())
	assert_eq(graph.shortest_path_length(0, 1), 1)
