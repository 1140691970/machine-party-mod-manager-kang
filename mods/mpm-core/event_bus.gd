extends RefCounted

## Lightweight cross-mod event bus with automatic dead-callable pruning.

var _listeners: Dictionary = {} # String -> Array[Dictionary]


func on(topic: String, cb: Callable) -> void:
	if topic.is_empty() or not cb.is_valid():
		return
	if not _listeners.has(topic):
		_listeners[topic] = []
	var bucket: Array = _listeners[topic] as Array
	for entry in bucket:
		if (entry as Dictionary).get("cb") == cb:
			return
	bucket.append({"cb": cb, "once": false})


func once(topic: String, cb: Callable) -> void:
	if topic.is_empty() or not cb.is_valid():
		return
	if not _listeners.has(topic):
		_listeners[topic] = []
	var bucket: Array = _listeners[topic] as Array
	bucket.append({"cb": cb, "once": true})


func off(topic: String, cb: Callable) -> void:
	if not _listeners.has(topic):
		return
	var bucket: Array = _listeners[topic] as Array
	for i in range(bucket.size() - 1, -1, -1):
		if (bucket[i] as Dictionary).get("cb") == cb:
			bucket.remove_at(i)
	if bucket.is_empty():
		_listeners.erase(topic)


func emit_event(topic: String, payload: Dictionary = {}) -> void:
	if not _listeners.has(topic):
		return
	var bucket: Array = (_listeners[topic] as Array).duplicate()
	var live: Array = []
	var to_call: Array[Callable] = []
	for raw in bucket:
		var entry: Dictionary = raw as Dictionary
		var cb: Callable = entry.get("cb", Callable())
		if not cb.is_valid():
			continue
		to_call.append(cb)
		if not bool(entry.get("once", false)):
			live.append(entry)
	if live.is_empty():
		_listeners.erase(topic)
	else:
		_listeners[topic] = live
	for cb in to_call:
		if cb.is_valid():
			cb.call(payload)


func clear() -> void:
	_listeners.clear()
