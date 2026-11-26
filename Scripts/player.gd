extends CharacterBody3D


@export_category("Components")
@export var cam: Camera3D
@export var head: Node3D


@export_category("Camera")
@export var sensitivity: float = 0.003
@export_range(60, 120, 1) var Base_FOV : int = 75
@export var bob_freq : float = 1.4
@export var bob_amp : float = 0.14
@export var fov_multiplier : int = 30

@export_category("Movement")
@export_range(1.0, 10, 0.5) var max_speed : float = 30.0
@export_range(1.0, 3.0, 0.1) var sprint_multiplier : float = 1.5
@export var acceleration : float = 15.0
@export var deceleration : float = 30.0


@export_category("Jumping")
@export var JUMP_VELOCITY = 6.0
@export var GRAVITY: float = 9.8
@export_range(0.1, 0.5, 0.02) var COYOTE_TIME = 0.2
@export_range(1.0, 3.0, 0.1) var FALL_MULTIPLIER = 1.5
@export_range(1.0, 3.0, 0.1) var LOW_JUMP_MULTIPLIER = 2.0


var base_speed : float
var base_gravity : float
var Jump_buffer = 0.2
var coyote_timer = 0.0
var jump_buffer_timer = 0.0
var FOV_multiplier = 30
var current_speed
var t_bob = 0.0

var camera_headbob_offset := Vector3.ZERO
var shake_offset := Vector3.ZERO
var target_velocity = Vector3.ZERO


var pitch : float = 0.0
var mouse_captured: bool = false

func _ready() -> void:
	mouse_captured = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	base_gravity = GRAVITY
	base_speed = max_speed


func _physics_process(delta: float) -> void:
	if is_on_wall_only():
		cam.rotation = Vector3(0,0,0)
		
	# Apply gravity
	if not is_on_floor():
		if velocity.y < 0:
			velocity.y -= GRAVITY * FALL_MULTIPLIER * delta
		elif not Input.is_action_pressed("jump"):
			velocity.y -= GRAVITY * LOW_JUMP_MULTIPLIER * delta
		else:
			velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0  # Reset Y velocity on floor
	
	# Coyote time
	if is_on_floor():
		coyote_timer = COYOTE_TIME
	else:
		coyote_timer = max(coyote_timer - delta, 0)
	
	# Jump buffer for instant jumps
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = Jump_buffer
	else:
		jump_buffer_timer = max(jump_buffer_timer - delta, 0)
		
	if jump_buffer_timer > 0 and coyote_timer > 0:
		velocity.y = JUMP_VELOCITY
		jump_buffer_timer = 0.0
		coyote_timer = 0.0
		
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var horizontal_velocity = Vector3(velocity.x, 0, velocity.z)
	
	if is_on_floor():
		current_speed = horizontal_velocity.length()
		var is_sprinting := Input.is_action_pressed("sprint")
		
		if direction != Vector3.ZERO:
			var accel := acceleration
			var speed_cap := max_speed
			
			if is_sprinting:
				accel *= sprint_multiplier
				speed_cap *= sprint_multiplier

			# Extra punch at low speed so you don't start slow
			if current_speed < 10.0:
				accel *= 1.6

			var new_speed := minf(current_speed + accel * delta, speed_cap)
			horizontal_velocity = direction * new_speed
		else:
			horizontal_velocity = Vector3.ZERO
		
		# Handle FOV changes
		handle_fov(delta)
		
	else:
		# Air control
		if direction != Vector3.ZERO:
			var speed = horizontal_velocity.length()
			if speed < 0.1:
				speed = max_speed * 0.5
				
			horizontal_velocity = direction * speed
	
	# Apply back to velocity
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	
	# Move the character
	move_and_slide()
	
	# Apply headbob and gun positioning
	handle_headbob(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_captured:
		# Rotate head (yaw)
		head.rotate_y(-event.relative.x * sensitivity)
		# Clamp camera rotation (pitch)
		pitch = clamp(pitch - event.relative.y * sensitivity, deg_to_rad(-90), deg_to_rad(90))
		cam.rotation.x = pitch
		
	if event is InputEventKey and event.pressed:
		if event.keycode == Key.KEY_ESCAPE:
			if not mouse_captured:
				mouse_captured = true
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			else:
				mouse_captured = false
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				
func _input(event: InputEvent) -> void:
	if not mouse_captured and event is InputEventMouseButton and event.pressed:
		mouse_captured = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func handle_headbob(delta: float) -> void:
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	
	# Only update headbob time when moving and on floor
	if horizontal_speed > 0.1 and is_on_floor():
		# Normalize the speed for headbob calculation - this prevents crazy fast bobbing
		var normalized_speed = sqrt(horizontal_speed) * 2.0  # Square root dampening + scaling
		t_bob += delta * normalized_speed * float(is_on_floor())
	else:
		# Gradually reduce headbob when stopping
		t_bob = lerp(t_bob, 0.0, delta * 3.0)
	
	# Calculate separate headbob offsets
	camera_headbob_offset = camera_headbob(t_bob, horizontal_speed)
	
	# Apply to camera and gun
	cam.transform.origin = camera_headbob_offset + shake_offset

# --------- Camera Headbob Function ---------
func camera_headbob(time: float, speed: float) -> Vector3:
	var pos = Vector3.ZERO
	
	if speed > 0.1:
		# Normalize speed for amplitude calculation to prevent extreme bobbing
		var speed_factor = sqrt(speed) / sqrt(max_speed)  # Square root normalization
		speed_factor = clamp(speed_factor, 0.3, 1.5)  # Keep reasonable range
		
		pos.y = sin(time * bob_freq) * bob_amp * speed_factor
		pos.x = cos(time * bob_freq / 2) * bob_amp * speed_factor
	
	return pos

# --------- FOV Handling ---------
func handle_fov(delta: float) -> void:
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	# Use logarithmic scaling for FOV as well to prevent extreme FOV changes
	var speed_factor = log(horizontal_speed + 1) / log(max_speed + 1)
	speed_factor = clamp(speed_factor, 0.0, 2.0)  # Cap the FOV multiplier
	
	# Increase FOV for sprinting
	var sprint_factor = 1.5 if Input.is_action_pressed("sprint") else 1.0
	var target_fov = Base_FOV + FOV_multiplier * speed_factor * sprint_factor
	
	cam.fov = lerp(cam.fov, target_fov, delta * 10.0)
