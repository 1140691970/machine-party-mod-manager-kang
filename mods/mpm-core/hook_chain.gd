extends RefCounted

## MPM Core Method-Level Hook Chain (SDK-4).
## Allows multiple mods to wrap the same logical method/hook target in priority order.


class HookContext extends RefCounted:
	var _hooks: Array = []
	var _index: int = 0
	var _base_fn: Callable = Callable()
	var _args: Array = []

	func _init(hooks: Array, base_fn: Callable, args: Array) -> void:
		_hooks = hooks
		_base_fn = base_fn
		_args = args

	func next(override_args = null):
		var call_args: Array = override_args if override_args is Array else _args
		while _index < _hooks.size():
			var cb = _hooks[_index]
			_index += 1
			if cb is Callable and (cb as Callable).is_valid():
				return (cb as Callable).call(self, call_args)
		if _base_fn.is_valid():
			return _base_fn.callv(call_args)
		return null


var _hooks_by_target: Dictionary = {}
var _next_seq: int = 1


func add_hook(target: String, callback: Callable, priority: int = 0) -> String:
	if target.is_empty() or not callback.is_valid():
		return ""
	if not _hooks_by_target.has(target):
		_hooks_by_target[target] = []
	var hook_id := "hook_%d" % _next_seq
	_next_seq += 1
	var list: Array = _hooks_by_target[target] as Array
	list.append({
		"id": hook_id,
		"priority": priority,
		"seq": _next_seq,
		"cb": callback,
	})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: int = int(a.get("priority", 0))
		var pb: int = int(b.get("priority", 0))
		if pa != pb:
			return pa < pb
		return int(a.get("seq", 0)) < int(b.get("seq", 0))
	)
	return hook_id


func remove_hook(target: String, hook_id: String) -> bool:
	if not _hooks_by_target.has(target):
		return false
	var list: Array = _hooks_by_target[target] as Array
	for idx in range(list.size() - 1, -1, -1):
		var item: Dictionary = list[idx] as Dictionary
		if str(item.get("id", "")) == hook_id:
			list.remove_at(idx)
			if list.is_empty():
				_hooks_by_target.erase(target)
			return true
	return false


func hook_count(target: String) -> int:
	if not _hooks_by_target.has(target):
		return 0
	var list: Array = _hooks_by_target[target] as Array
	var active: Array = []
	for item in list:
		var d: Dictionary = item as Dictionary
		var cb = d.get("cb", Callable())
		if cb is Callable and (cb as Callable).is_valid():
			active.append(d)
	_hooks_by_target[target] = active
	return active.size()


func invoke(target: String, base_fn: Callable, args: Array = []):
	var callables: Array = []
	if _hooks_by_target.has(target):
		var list: Array = _hooks_by_target[target] as Array
		var active: Array = []
		for item in list:
			var d: Dictionary = item as Dictionary
			var cb = d.get("cb", Callable())
			if cb is Callable and (cb as Callable).is_valid():
				active.append(d)
				callables.append(cb)
		_hooks_by_target[target] = active
	var ctx := HookContext.new(callables, base_fn, args)
	return ctx.next()


func clear_target(target: String) -> void:
	_hooks_by_target.erase(target)


func clear() -> void:
	_hooks_by_target.clear()
