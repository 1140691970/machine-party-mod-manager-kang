extends RefCounted

## Configurable balance & rule parameters for Roller Carnival (滾筒嘉年華).

# --- Match & Roster ---
var round_duration: float = 50.0
var max_players: int = 1

# --- Roller Speed & Acceleration Curve ---
var roller_initial_speed: float = 4.0
var roller_max_speed: float = 4.6
var roller_acceleration_exponent: float = 1.15
## Supported modes: "linear", "exponential", "stepped"
var speed_curve_mode: String = "linear"

# --- Spawn Intervals & Safety Floor ---
var pair_start_time := 10.0
var triple_start_time := 32.0
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
var crouch_duration := 0.75
var crouch_recovery := 0.10
var crouch_height: float = 0.72
var jump_height: float = 1.65
var jump_air_time: float = 0.58
var landing_recovery_time: float = 0.08

# --- Stage & Lava Boundaries ---
var stage_left_lava_x: float = -6.2
var player_spawn_x: float = 1.60
var roller_spawn_x: float = 13.0
var roller_despawn_x: float = -8.5

# --- Ranking & Bonus Points ---
## Supported rules: "shared_rank", "survival_time"
var tie_break_rule: String = "shared_rank"


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


func wave_size(elapsed: float) -> int:
	if elapsed < pair_start_time:
		return 1
	if elapsed < triple_start_time:
		return 2
	return 3


func spawn_interval(elapsed: float, within_wave: bool, rng: RandomNumberGenerator) -> float:
	if elapsed < pair_start_time:
		return rng.randf_range(3.15, 3.45)
	var progress := clampf((elapsed - pair_start_time) / (round_duration - pair_start_time), 0, 1)
	if within_wave:
		# A small margin covers the acceleration between the dispenser and the player.
		var shortest := safe_interval_floor() + 0.04
		return rng.randf_range(lerpf(1.2, shortest, progress), lerpf(1.32, shortest + 0.05, progress))
	return rng.randf_range(lerpf(2.1, 1.5, progress), lerpf(2.35, 1.7, progress))


func bonus_for_rank(rank_1_based: int, player_count: int) -> int:
	return maxi(0, player_count - rank_1_based + 1)
