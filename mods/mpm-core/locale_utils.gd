extends RefCounted

## Shared trilingual locale detection helpers for first-party mods.


func is_tw_locale(loc: String = "") -> bool:
	var low: String = (TranslationServer.get_locale() if loc.is_empty() else loc).to_lower()
	return low == "zht" or low.contains("tw") or low.contains("hk") or low.contains("hant") or low.contains("mo")


func is_cn_locale(loc: String = "") -> bool:
	var low: String = (TranslationServer.get_locale() if loc.is_empty() else loc).to_lower()
	return not is_tw_locale(low) and (low.begins_with("zh") or low == "zhs")


func pick(en: String, cn: String, tw: String) -> String:
	var locale: String = TranslationServer.get_locale()
	if is_tw_locale(locale):
		return tw
	if is_cn_locale(locale):
		return cn
	return en
