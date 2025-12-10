extends CharacterBody2D

# Basic horizontal movement values
const SPEED = 2000.0
const ACCELERATION = 6000.0
var facing := 1

# Rotational values
const MAX_UP_TILT = deg_to_rad(80.0)
const MAX_DOWN_TILT = deg_to_rad(20.0)
const STICK_ROTATE_LERP = 20.0   # max up/down tilt
const FREE_ROTATE_LERP = 0.3            # how fast he turns
const TILT_VSPEED_REF = 1800.0      # vertical speed at which we reach full tilt


# Dash values
const DASH_SPEED = 5000.0
const DASH_ACCELERATION = 80000.0
const DASH_RECOVERY_DECEL = 30000.0
const DASH_PAUSE_TIME = 0.07

# Jump / gravity tuning
const JUMP_VELOCITY = -1800.0
const GRAVITY_MULTIPLIER = 4
const FALL_MULTIPLIER = 2
const JUMP_DECEL = 30000.0

# Ground / air horizontal friction
const FLOOR_FRICTION = 12000.0
const AIR_RESISTANCE = 4000.0

# Jump input buffering
const JUMP_BUFFER_TIME = 0.15  # seconds
var jump_buffer_timer := 0.0

# Respawn and state tracking
var last_jumped_from
var was_on_floor = false

# Dash state
var dashing = false
var dash_duration = 0.1
var max_dashes = 2
var dashes_left = 0
var dash_recovering = false
var dash_direction: Vector2 = Vector2.ZERO
var dash_pause = false
var base_trail_offset := Vector2.ZERO

@onready var visual = $Visual
@onready var dash_trail: CPUParticles2D = $Visual/DashTrail
@onready var animated_sprite = $Visual/AnimatedSprite2D2

func _ready() -> void:
	# Remember starting position in case of death
	last_jumped_from = global_position
	base_trail_offset = dash_trail.position
	# Start with full dashes
	dashes_left = max_dashes


func _physics_process(delta: float) -> void:
	# Base gravity and horizontal tuning for this frame
	var gravity = get_gravity() * GRAVITY_MULTIPLIER
	var top_speed = SPEED
	var top_acceleration = ACCELERATION

	# --- Landing detection & dash reset ---
	var on_floor := is_on_floor()
	if on_floor and not was_on_floor:
		# Just landed this frame: restore dash charges
		dashes_left = max_dashes
	was_on_floor = on_floor
	# --------------------------------------

	# Handle jump buffering: record jump press and count down
	if Input.is_action_just_pressed("player_jump"):
		jump_buffer_timer = JUMP_BUFFER_TIME

	if jump_buffer_timer > 0.0:
		jump_buffer_timer -= delta

	# Get horizontal input and flip sprite
	var direction := Input.get_axis("player_left", "player_right")
	if direction > 0:
		facing = 1
	elif direction < 0:
		facing = -1
	
	visual.scale.x = facing
	
	if dash_pause:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	
	# ---- DASH OVERRIDE ----
	# While dashing, ignore normal movement and force dash velocity
	if dashing:
		velocity = dash_direction * DASH_SPEED
		move_and_slide()
		return
	# -----------------------

	# Dash recovery phase: strong decel toward a target horizontal speed
	if dash_recovering:
		# Strong decel toward 0 (or basic run speed if there's input)
		var target_velocity := Vector2.ZERO
		if direction != 0:
			target_velocity = Vector2(direction, 0.0).normalized() * SPEED

		velocity = velocity.move_toward(target_velocity, DASH_RECOVERY_DECEL * delta)

		# When we're basically at target, snap and end recovery
		if abs(velocity.length() - target_velocity.length()) < 2.0:
			velocity = target_velocity
			dash_recovering = false
	else:
		# Normal horizontal movement (no dash recovery)
		if not is_on_floor():
			# In air: accelerate toward input, or slowly drift to a stop
			if direction:
				velocity.x = move_toward(velocity.x, direction * top_speed, top_acceleration * delta)
			else:
				velocity.x = move_toward(velocity.x, 0, AIR_RESISTANCE * delta)
		else:
			# On ground: strong friction toward 0
			velocity.x = move_toward(velocity.x, 0, FLOOR_FRICTION * delta)

	# Add gravity
	if not is_on_floor():
		velocity += gravity * delta
		var input_dir = Input.get_vector("player_left", "player_right", "player_up", "player_down")
		var target_angle = visual.rotation
		var rotate_lerp := STICK_ROTATE_LERP
		
		# If the stick is held, use that angle
		if input_dir != Vector2.ZERO:
			var tilt_input: float = clampf(input_dir.y, -1.0, 1.0)
			if tilt_input < 0.0:
				target_angle = tilt_input * MAX_UP_TILT * facing
				target_angle += (facing * deg_to_rad(20))
			else:
				target_angle = tilt_input * MAX_DOWN_TILT * facing
				target_angle += (facing * deg_to_rad(20))
			rotate_lerp = STICK_ROTATE_LERP
		# If no direction is held, dash in facing direction
		else:
			var v_norm: float = clampf(velocity.y / TILT_VSPEED_REF, -1.0, 1.0)
			if v_norm < 0.0:
				target_angle = v_norm * MAX_UP_TILT * facing
				target_angle += (facing * deg_to_rad(20))
			else:
				target_angle = v_norm * MAX_DOWN_TILT * facing
				target_angle += (facing * deg_to_rad(20))
			rotate_lerp = FREE_ROTATE_LERP
		# If no direction is held, dash in facing direction
		visual.rotation = lerp_angle(visual.rotation, target_angle, rotate_lerp * delta)


		# Extra gravity when falling for snappier fall
		if velocity.y > 0.0:
			velocity += gravity * (FALL_MULTIPLIER - 1) * delta
			

	else:
		# Idle animation while standing
		animated_sprite.play("idle")
		visual.rotation = 0
		

	# --- Jump handling ---
	var can_jump_now := is_on_floor() and jump_buffer_timer > 0.0

	if can_jump_now:
		# Consume buffered jump
		animated_sprite.play("jump")
		last_jumped_from = self.global_position
		jump_buffer_timer = 0.0

		# Small delay so jump happens after slide resolution
		await get_tree().create_timer(0).timeout
		velocity.y = JUMP_VELOCITY

		# Give a little horizontal boost if there's input
		if Input.is_action_pressed("player_right") or Input.is_action_pressed("player_left"):
			velocity.x = SPEED * direction

	# Short-hop: if jump is released while still rising, cut upward velocity
	if Input.is_action_just_released("player_jump") and not is_on_floor() and velocity.y < 0:
		velocity.y = move_toward(velocity.y, 0, JUMP_DECEL * delta)

	# Move the character and handle collisions
	move_and_slide()


func player_died():
	# Reset position and state to last jump point
	global_position = last_jumped_from
	velocity = Vector2.ZERO
	dashing = false
	dash_recovering = false


func _input(event):
	# Start dash if button pressed, we have charges, and we're in the air
	if event.is_action_pressed("player_dash") and dashes_left > 0 and not is_on_floor():
		dash_pause = true
		dash_trail.emitting = true
		# Get dash direction from input (4-way)
		var raw_dir = Input.get_vector("player_left", "player_right", "player_up", "player_down")

		# If no direction is held, dash in facing direction
		if raw_dir == Vector2.ZERO:
			raw_dir = Vector2(facing, 0.0)

		dash_direction = raw_dir.normalized()
		dashes_left -= 1
		$DashPauseTimer.start(DASH_PAUSE_TIME)


func _on_dash_timer_timeout() -> void:
	# End active dash phase and enter recovery
	dashing = false
	dash_recovering = true
	dash_trail.emitting = false
	
func _on_dash_pause_timer_timeout() -> void:
	# End dash pause phase and start active dashing phase
	dash_pause = false
	dashing = true
	print("dash_pause_ended")
	$DashTimer.start(dash_duration)
