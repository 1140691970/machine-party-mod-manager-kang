extends RefCounted

## MpmFxPool — reusable persistent node pool with warmup and timed auto-release.

var _pools: Dictionary = {}
var _active: Dictionary = {}


func _set_node_visible(node: Node, visible_flag: bool) -> void:
	if node == null:
		return
	if node is Node3D or node is CanvasItem:
		node.set("visible", visible_flag)


func register_pool(kind: String, parent: Node, factory: Callable, capacity: int) -> int:
	if kind.is_empty() or parent == null or not factory.is_valid() or capacity <= 0:
		return 0
	if not _pools.has(kind):
		_pools[kind] = []
	if not _active.has(kind):
		_active[kind] = []
	var pool: Array = _pools[kind] as Array
	var created: int = 0
	for _i in capacity:
		var node = factory.call()
		if node is Node:
			var n: Node = node as Node
			if n.get_parent() == null:
				parent.add_child(n)
			_set_node_visible(n, false)
			pool.append(n)
			created += 1
	return created


func warmup(kind: String = "") -> int:
	var warmed: int = 0
	var kinds: Array = [kind] if not kind.is_empty() else _pools.keys()
	for k in kinds:
		if not _pools.has(k):
			continue
		var pool: Array = _pools[k] as Array
		for raw in pool:
			if raw is Node and is_instance_valid(raw):
				var n: Node = raw as Node
				_set_node_visible(n, true)
				_set_node_visible(n, false)
				warmed += 1
	return warmed


func acquire(kind: String, duration: float = 0.0, on_release: Callable = Callable()) -> Node:
	if not _pools.has(kind):
		return null
	var pool: Array = _pools[kind] as Array
	while pool.size() > 0:
		var raw = pool.pop_back()
		if raw is Node and is_instance_valid(raw):
			var n: Node = raw as Node
			_set_node_visible(n, true)
			if not _active.has(kind):
				_active[kind] = []
			var active_list: Array = _active[kind] as Array
			active_list.append({
				"node": n,
				"remaining": duration,
				"timed": duration > 0.0,
				"on_release": on_release,
			})
			return n
	return null


func release(kind: String, node: Node) -> void:
	if node == null or not _pools.has(kind):
		return
	var cb := Callable()
	if _active.has(kind):
		var active_list: Array = _active[kind] as Array
		for idx in range(active_list.size() - 1, -1, -1):
			var item: Dictionary = active_list[idx] as Dictionary
			if item.get("node", null) == node:
				var raw_cb = item.get("on_release", Callable())
				if raw_cb is Callable:
					cb = raw_cb as Callable
				active_list.remove_at(idx)
				break
	if is_instance_valid(node):
		_set_node_visible(node, false)
	if cb.is_valid():
		cb.call(node)
	var pool: Array = _pools[kind] as Array
	if is_instance_valid(node) and not pool.has(node):
		pool.append(node)


func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	for kind in _active.keys():
		var active_list: Array = _active[kind] as Array
		var expired: Array = []
		for item in active_list:
			var d: Dictionary = item as Dictionary
			if not bool(d.get("timed", false)):
				continue
			var next_rem: float = float(d.get("remaining", 0.0)) - delta
			d["remaining"] = next_rem
			if next_rem <= 0.0:
				expired.append(d.get("node", null))
		for node in expired:
			if node is Node:
				release(str(kind), node as Node)


func available_count(kind: String) -> int:
	if not _pools.has(kind):
		return 0
	return (_pools[kind] as Array).size()


func active_count(kind: String) -> int:
	if not _active.has(kind):
		return 0
	return (_active[kind] as Array).size()


func clear() -> void:
	for kind in _pools.keys():
		for raw in (_pools[kind] as Array):
			if raw is Node and is_instance_valid(raw):
				(raw as Node).queue_free()
	for kind in _active.keys():
		for raw in (_active[kind] as Array):
			var d: Dictionary = raw as Dictionary
			var n = d.get("node", null)
			if n is Node and is_instance_valid(n):
				(n as Node).queue_free()
	_pools.clear()
	_active.clear()
