extends RefCounted

## Configurable balance & rule parameters for Roller Carnival (滾筒嘉年華).

# --- Match & Roster ---
var round_duration: float = 50.0
var max_players: int = 8

# --- Roller Speed & Acceleration Curve ---
var roller_initial_speed: float = 6.2
var roller_max_speed: float = 13.8
var roller_acceleration_exponent: float = 1.15
## Supported modes: "linear", "exponential", "stepped"
var speed_curve_mode: String = "linear"

# --- Spawn Intervals & Safety Floor ---
var spawn_interval_max: float = 1.90
var spawn_interval_min: float = 0.92
var min_safe_reaction_time: float = 0.26

# --- Gold (High / Crouch) & Silver (Low / Jump) Rollers ---
var gold_roller_probability: float = 0.50
var max_same_type_streak: int = 3
var gold_roller_center_y: float = 1.32
var gold_roller_radius: float = 0.42
var silver_roller_center_y: float = 0.40
var silver_roller_radius: float = 0.36

# --- Pure Knockback (No HP Loss) ---
var knockback_distance: float = 1.35
var knockback_duration: float = 0.16
var knockback_cooldown: float = 0.40

# --- Player Heights, Jump & Crouch ---
var standing_height: float = 1.50
var crouch_height: float = 0.72
var jump_height: float = 1.65
var jump_air_time: float = 0.58
var landing_recovery_time: float = 0.08

# --- Configurable Input Key Codes ---
var crouch_key_codes: Array[int] = [KEY_S, KEY_DOWN]
var jump_key_codes: Array[int] = [KEY_SPACE]

# --- Stage & Lava Boundaries ---
var stage_left_lava_x: float = -6.2
var player_spawn_x: float = 1.60
var roller_spawn_x: float = 9.8
var roller_despawn_x: float = -8.5

# --- Pummel Party-Style Preset Selectors ---
var preset_pace: String = "standard"
var preset_duration: String = "standard"
var preset_spawn: String = "standard"
var preset_knockback: String = "standard"

# --- Ranking & Bonus Points ---
## Ranks 1..8 bonus points: 1st=+100, 2nd=+80, 3rd=+60, 4th-6th=+40, 7th-8th=+20
var rank_bonus_points: Array[int] = [100, 80, 60, 40, 40, 40, 20, 20]
## Supported rules: "shared_rank", "survival_time"
var tie_break_rule: String = "shared_rank"
var linear_points_per_dodge: int = 0


func speed_at_progress(progress: float) -> float:
	var t: float = clampf(progress, 0.0, 1.0)
	var factor: float = t
	if speed_curve_mode == "exponential":
		factor = pow(t, maxf(0.1, roller_acceleration_exponent))
	elif speed_curve_mode == "stepped":
		if t < 0.25:
			factor = 0.0
		elif t < 0.50:
			factor = 0.33
		elif t < 0.75:
			factor = 0.68
		else:
			factor = 1.0
	else:
		factor = pow(t, 1.0)
	return lerpf(roller_initial_speed, maxf(roller_initial_speed, roller_max_speed), factor)


func safe_interval_floor() -> float:
	return jump_air_time + landing_recovery_time + min_safe_reaction_time


func interval_range_at_progress(progress: float) -> Vector2:
	var t: float = clampf(progress, 0.0, 1.0)
	var safe_floor: float = safe_interval_floor()
	var low: float = maxf(safe_floor + 0.0001, lerpf(spawn_interval_min + 0.30, spawn_interval_min, t))
	var high: float = maxf(low + 0.20, lerpf(spawn_interval_max, maxf(low + 0.25, spawn_interval_max * 0.72), t))
	return Vector2(low, high)


func bonus_for_rank(rank_1_based: int, dodges: int) -> int:
	var idx: int = clampi(rank_1_based - 1, 0, rank_bonus_points.size() - 1)
	var base_bonus: int = rank_bonus_points[idx] if not rank_bonus_points.is_empty() else 0
	return base_bonus + maxi(0, dodges) * maxi(0, linear_points_per_dodge)


func apply_pummel_presets(pace: String, duration_mode: String, spawn_mode: String, knockback_mode: String) -> void:
	preset_pace = pace if pace in ["casual", "standard", "frantic"] else "standard"
	preset_duration = duration_mode if duration_mode in ["short", "standard", "long"] else "standard"
	preset_spawn = spawn_mode if spawn_mode in ["safe", "standard", "extreme"] else "standard"
	preset_knockback = knockback_mode if knockback_mode in ["light", "standard", "heavy"] else "standard"

	if preset_pace == "casual":
		roller_initial_speed = 4.8
		roller_max_speed = 10.2
		spawn_interval_min = 1.15
		spawn_interval_max = 2.25
		speed_curve_mode = "linear"
		max_same_type_streak = 2
	elif preset_pace == "frantic":
		roller_initial_speed = 7.6
		roller_max_speed = 16.8
		spawn_interval_min = 0.86
		spawn_interval_max = 1.55
		speed_curve_mode = "exponential"
		roller_acceleration_exponent = 1.05
		max_same_type_streak = 4
	else:
		roller_initial_speed = 6.2
		roller_max_speed = 13.8
		spawn_interval_min = 0.92
		spawn_interval_max = 1.90
		speed_curve_mode = "linear"
		max_same_type_streak = 3

	if preset_duration == "short":
		round_duration = 30.0
	elif preset_duration == "long":
		round_duration = 80.0
	else:
		round_duration = 50.0

	if preset_spawn == "safe":
		player_spawn_x = 3.00
	elif preset_spawn == "extreme":
		player_spawn_x = -1.60
	else:
		player_spawn_x = 1.60

	if preset_knockback == "light":
		knockback_distance = 0.85
		knockback_cooldown = 0.45
	elif preset_knockback == "heavy":
		knockback_distance = 2.10
		knockback_cooldown = 0.35
	else:
		knockback_distance = 1.35
		knockback_cooldown = 0.40


func to_dict() -> Dictionary:
	return {
		"round_duration": round_duration,
		"max_players": max_players,
		"roller_initial_speed": roller_initial_speed,
		"roller_max_speed": roller_max_speed,
		"roller_acceleration_exponent": roller_acceleration_exponent,
		"speed_curve_mode": speed_curve_mode,
		"spawn_interval_max": spawn_interval_max,
		"spawn_interval_min": spawn_interval_min,
		"min_safe_reaction_time": min_safe_reaction_time,
		"gold_roller_probability": gold_roller_probability,
		"max_same_type_streak": max_same_type_streak,
		"gold_roller_center_y": gold_roller_center_y,
		"gold_roller_radius": gold_roller_radius,
		"silver_roller_center_y": silver_roller_center_y,
		"silver_roller_radius": silver_roller_radius,
		"knockback_distance": knockback_distance,
		"knockback_duration": knockback_duration,
		"knockback_cooldown": knockback_cooldown,
		"standing_height": standing_height,
		"crouch_height": crouch_height,
		"jump_height": jump_height,
		"jump_air_time": jump_air_time,
		"landing_recovery_time": landing_recovery_time,
		"stage_left_lava_x": stage_left_lava_x,
		"player_spawn_x": player_spawn_x,
		"roller_spawn_x": roller_spawn_x,
		"roller_despawn_x": roller_despawn_x,
		"preset_pace": preset_pace,
		"preset_duration": preset_duration,
		"preset_spawn": preset_spawn,
		"preset_knockback": preset_knockback,
		"rank_bonus_points": rank_bonus_points.duplicate(),
		"tie_break_rule": tie_break_rule,
		"linear_points_per_dodge": linear_points_per_dodge,
	}


func apply_dict(d: Dictionary) -> void:
	round_duration = clampf(float(d.get("round_duration", round_duration)), 10.0, 300.0)
	max_players = clampi(int(d.get("max_players", max_players)), 1, 16)
	roller_initial_speed = clampf(float(d.get("roller_initial_speed", roller_initial_speed)), 2.0, 20.0)
	roller_max_speed = clampf(float(d.get("roller_max_speed", roller_max_speed)), roller_initial_speed, 28.0)
	roller_acceleration_exponent = clampf(float(d.get("roller_acceleration_exponent", roller_acceleration_exponent)), 0.3, 3.0)
	speed_curve_mode = str(d.get("speed_curve_mode", speed_curve_mode))
	spawn_interval_min = clampf(float(d.get("spawn_interval_min", spawn_interval_min)), 0.5, 5.0)
	spawn_interval_max = clampf(float(d.get("spawn_interval_max", spawn_interval_max)), spawn_interval_min, 6.0)
	min_safe_reaction_time = clampf(float(d.get("min_safe_reaction_time", min_safe_reaction_time)), 0.25, 2.5)
	gold_roller_probability = clampf(float(d.get("gold_roller_probability", gold_roller_probability)), 0.0, 1.0)
	max_same_type_streak = clampi(int(d.get("max_same_type_streak", max_same_type_streak)), 1, 10)
	gold_roller_center_y = clampf(float(d.get("gold_roller_center_y", gold_roller_center_y)), 0.8, 2.5)
	gold_roller_radius = clampf(float(d.get("gold_roller_radius", gold_roller_radius)), 0.2, 0.8)
	silver_roller_center_y = clampf(float(d.get("silver_roller_center_y", silver_roller_center_y)), 0.2, 1.0)
	silver_roller_radius = clampf(float(d.get("silver_roller_radius", silver_roller_radius)), 0.2, 0.7)
	knockback_distance = clampf(float(d.get("knockback_distance", knockback_distance)), 0.4, 3.5)
	knockback_duration = clampf(float(d.get("knockback_duration", knockback_duration)), 0.05, 0.5)
	knockback_cooldown = clampf(float(d.get("knockback_cooldown", knockback_cooldown)), 0.1, 2.0)
	standing_height = clampf(float(d.get("standing_height", standing_height)), 1.0, 2.2)
	crouch_height = clampf(float(d.get("crouch_height", crouch_height)), 0.4, 1.1)
	jump_height = clampf(float(d.get("jump_height", jump_height)), 0.8, 3.0)
	jump_air_time = clampf(float(d.get("jump_air_time", jump_air_time)), 0.3, 1.2)
	landing_recovery_time = clampf(float(d.get("landing_recovery_time", landing_recovery_time)), 0.0, 0.4)
	player_spawn_x = clampf(float(d.get("player_spawn_x", player_spawn_x)), stage_left_lava_x + 2.0, roller_spawn_x - 2.0)
	preset_pace = str(d.get("preset_pace", preset_pace))
	preset_duration = str(d.get("preset_duration", preset_duration))
	preset_spawn = str(d.get("preset_spawn", preset_spawn))
	preset_knockback = str(d.get("preset_knockback", preset_knockback))
	tie_break_rule = str(d.get("tie_break_rule", tie_break_rule))
	linear_points_per_dodge = clampi(int(d.get("linear_points_per_dodge", linear_points_per_dodge)), 0, 100)
	if d.has("rank_bonus_points"):
		var raw_pts = d["rank_bonus_points"]
		var parsed: Array[int] = []
		if raw_pts is Array:
			for v in raw_pts:
				parsed.append(int(v))
		elif raw_pts is String:
			for part in str(raw_pts).split(",", false):
				parsed.append(int(part.strip_edges()))
		if not parsed.is_empty():
			rank_bonus_points = parsed
