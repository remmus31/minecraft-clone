extends Node3D

# World settings
const CHUNK_SIZE := 16
const CHUNK_HEIGHT := 64
const VIEW_DISTANCE := 4
const NOISE_SCALE := 0.02

# Block types
enum BlockType {
	AIR = 0,
	GRASS = 1,
	DIRT = 2,
	STONE = 3,
	SAND = 4,
	WATER = 5,
	WOOD = 6,
	LEAVES = 7,
	COBBLESTONE = 8
}

# Block colors
var block_colors := {
	BlockType.GRASS: Color(0.3, 0.8, 0.2),
	BlockType.DIRT: Color(0.55, 0.4, 0.25),
	BlockType.STONE: Color(0.5, 0.5, 0.5),
	BlockType.SAND: Color(0.9, 0.85, 0.6),
	BlockType.WATER: Color(0.2, 0.4, 0.8, 0.7),
	BlockType.WOOD: Color(0.4, 0.25, 0.1),
	BlockType.LEAVES: Color(0.2, 0.5, 0.2),
	BlockType.COBBLESTONE: Color(0.4, 0.4, 0.4)
}

# Player settings
var player: CharacterBody3D
var camera: Camera3D
var player_velocity := Vector3.ZERO
var move_speed := 5.0
var sprint_speed := 8.0
var jump_force := 5.0
var mouse_sensitivity := 0.002
var gravity := 15.0
var is_grounded := false

# World data
var noise: FastNoiseLite
var chunks := {}
var mesh_instances := {}

# Current selected block
var selected_block := BlockType.GRASS

# Raycast
var raycast: RayCast3D

# Hotbar
var hotbar_slots: Array = []
var selected_slot := 0

# UI elements
var hotbar: HBoxContainer

# Vertices data for mesh generation
var vertices: Array = []
var colors: Array = []
var normals: Array = []

func _ready() -> void:
	# Initialize noise
	noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = NOISE_SCALE

	# Get references
	player = $World/Player
	camera = $World/Player/Camera3D
	raycast = RayCast3D.new()
	raycast.enabled = true
	raycast.target_position = Vector3(0, 0, -5)
	player.add_child(raycast)

	# Setup collision shape
	var collision = player.get_node("CollisionShape3D")
	var shape = CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	collision.shape = shape

	# Setup UI
	setup_ui()

	# Set player position first so chunks generate around it
	setup_player()

	# Generate chunks around player position
	update_chunks()

	# Capture mouse
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func setup_player() -> void:
	# Position player above ground (offset slightly to avoid being inside a block)
	var start_x := 8.5  # Start in middle of chunk, offset to avoid block center
	var start_z := 8.5
	var ground_height = get_height_at(int(start_x), int(start_z))
	var start_y = ground_height + 10.0  # Spawn high above to fall down
	player.global_position = Vector3(start_x, start_y, start_z)

func setup_ui() -> void:
	hotbar = $CanvasLayer/Hotbar

	# Create hotbar slots
	var block_types := [
		BlockType.GRASS,
		BlockType.DIRT,
		BlockType.STONE,
		BlockType.SAND,
		BlockType.COBBLESTONE,
		BlockType.WOOD,
		BlockType.LEAVES,
		BlockType.WATER
	]

	for i in range(8):
		var slot = ColorRect.new()
		slot.custom_minimum_size = Vector2(40, 40)

		if i < block_types.size():
			var block_type = block_types[i]
			slot.color = block_colors.get(block_type, Color.GRAY)
			hotbar_slots.append(block_type)
		else:
			slot.color = Color(0.3, 0.3, 0.3)
			hotbar_slots.append(BlockType.AIR)

		# Add selection border using StyleBox
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.border_width_left = 0
		style.border_width_top = 0
		style.border_width_right = 0
		style.border_width_bottom = 0
		style.set_content_margin_all(0)
		slot.add_theme_stylebox_override("normal", style)

		var style_hover = StyleBoxFlat.new()
		style_hover.bg_color = Color(0, 0, 0, 0)
		style_hover.border_width_left = 3
		style_hover.border_width_top = 3
		style_hover.border_width_right = 3
		style_hover.border_width_bottom = 3
		style_hover.border_color = Color.WHITE
		slot.add_theme_stylebox_override("hover", style_hover)

		hotbar.add_child(slot)

	update_hotbar_selection()

func update_hotbar_selection() -> void:
	for i in range(hotbar.get_child_count()):
		var slot = hotbar.get_child(i)
		if i == selected_slot:
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0, 0, 0, 0)
			style.border_width_left = 3
			style.border_width_top = 3
			style.border_width_right = 3
			style.border_width_bottom = 3
			style.border_color = Color.WHITE
			slot.add_theme_stylebox_override("normal", style)
		else:
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0, 0, 0, 0)
			style.border_width_left = 0
			style.border_width_top = 0
			style.border_width_right = 0
			style.border_width_bottom = 0
			slot.add_theme_stylebox_override("normal", style)

func _input(event: InputEvent) -> void:
	# Mouse look
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		player.rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, -PI/2, PI/2)

	# Toggle mouse capture
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Block selection with number keys
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1:
			selected_slot = 0
		elif event.keycode == KEY_2:
			selected_slot = 1
		elif event.keycode == KEY_3:
			selected_slot = 2
		elif event.keycode == KEY_4:
			selected_slot = 3
		elif event.keycode == KEY_5:
			selected_slot = 4
		elif event.keycode == KEY_6:
			selected_slot = 5
		elif event.keycode == KEY_7:
			selected_slot = 6
		elif event.keycode == KEY_8:
			selected_slot = 7

		if selected_slot < hotbar_slots.size():
			selected_block = hotbar_slots[selected_slot]
			update_hotbar_selection()

	# Left click - break block
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			break_block()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			place_block()

func _physics_process(delta: float) -> void:
	# Movement
	var input_dir := Vector3.ZERO

	if Input.is_action_pressed("move_forward"):
		input_dir -= player.global_transform.basis.z
	if Input.is_action_pressed("move_backward"):
		input_dir += player.global_transform.basis.z
	if Input.is_action_pressed("move_left"):
		input_dir -= player.global_transform.basis.x
	if Input.is_action_pressed("move_right"):
		input_dir += player.global_transform.basis.x

	input_dir = input_dir.normalized()

	# Apply gravity
	if not is_grounded:
		player_velocity.y -= gravity * delta
	else:
		player_velocity.y = max(player_velocity.y, -1.0)

	# Jump
	if Input.is_action_pressed("jump") and is_grounded:
		player_velocity.y = jump_force

	# Sprint
	var current_speed = move_speed
	if Input.is_action_pressed("sprint"):
		current_speed = sprint_speed

	# Apply movement
	if input_dir.length() > 0:
		player_velocity.x = input_dir.x * current_speed
		player_velocity.z = input_dir.z * current_speed
	else:
		player_velocity.x = move_toward(player_velocity.x, 0, current_speed * delta * 10)
		player_velocity.z = move_toward(player_velocity.z, 0, current_speed * delta * 10)

	player.velocity = player_velocity
	player.move_and_slide()

	# Check if grounded
	is_grounded = player.is_on_floor()

	# Update chunks around player
	update_chunks()

func get_height_at(x: int, z: int) -> float:
	var height = noise.get_noise_2d(x, z) * 20 + 20
	return floor(height)

func get_chunk_key(cx: int, cz: int) -> Vector2i:
	return Vector2i(cx, cz)

func update_chunks() -> void:
	var player_chunk_x = int(floor(player.global_position.x / CHUNK_SIZE))
	var player_chunk_z = int(floor(player.global_position.z / CHUNK_SIZE))

	# Generate chunks in view distance
	for cz in range(player_chunk_z - VIEW_DISTANCE, player_chunk_z + VIEW_DISTANCE + 1):
		for cx in range(player_chunk_x - VIEW_DISTANCE, player_chunk_x + VIEW_DISTANCE + 1):
			var key = get_chunk_key(cx, cz)
			if not chunks.has(key):
				generate_chunk(cx, cz)

func generate_chunk(cx: int, cz: int) -> void:
	var key = get_chunk_key(cx, cz)
	var chunk_node = Node3D.new()
	chunk_node.name = "Chunk_%d_%d" % [cx, cz]
	$World.add_child(chunk_node)

	var blocks = {}

	# Generate terrain
	for x in range(CHUNK_SIZE):
		for z in range(CHUNK_SIZE):
			var world_x = cx * CHUNK_SIZE + x
			var world_z = cz * CHUNK_SIZE + z
			var height = get_height_at(world_x, world_z)

			for y in range(CHUNK_HEIGHT):
				var block_y = y
				var local_y = block_y

				if block_y < height:
					if block_y == height:
						# Top layer
						if height < 25:
							blocks[Vector3i(x, local_y, z)] = BlockType.GRASS
						elif height < 35:
							blocks[Vector3i(x, local_y, z)] = BlockType.GRASS
						else:
							blocks[Vector3i(x, local_y, z)] = BlockType.STONE
					elif block_y > height - 4:
						blocks[Vector3i(x, local_y, z)] = BlockType.DIRT
					else:
						blocks[Vector3i(x, local_y, z)] = BlockType.STONE
				elif block_y < 20:
					# Water level
					blocks[Vector3i(x, local_y, z)] = BlockType.WATER

	chunks[key] = blocks
	create_chunk_mesh(chunk_node, blocks, cx, cz)

func create_chunk_mesh(chunk_node: Node3D, blocks: Dictionary, cx: int, cz: int) -> void:
	# Build vertex arrays
	var verts: PackedVector3Array = PackedVector3Array()
	var cols: PackedColorArray = PackedColorArray()
	var norms: PackedVector3Array = PackedVector3Array()

	# Generate faces for each block
	for pos in blocks.keys():
		var block_type = blocks[pos]

		if block_type == BlockType.WATER:
			continue  # Handle water separately

		# Check if any face is exposed
		var neighbors = [
			blocks.get(pos + Vector3i(1, 0, 0)),
			blocks.get(pos + Vector3i(-1, 0, 0)),
			blocks.get(pos + Vector3i(0, 1, 0)),
			blocks.get(pos + Vector3i(0, -1, 0)),
			blocks.get(pos + Vector3i(0, 0, 1)),
			blocks.get(pos + Vector3i(0, 0, -1))
		]

		var has_exposed_face = false
		for neighbor in neighbors:
			if neighbor == null or neighbor == BlockType.AIR or neighbor == BlockType.WATER:
				has_exposed_face = true
				break

		if has_exposed_face:
			var color = block_colors.get(block_type, Color.GRAY)
			add_block_to_mesh(verts, cols, norms, pos, color)

	# Create solid mesh
	if verts.size() > 0:
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_COLOR] = cols

		var mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

		var material = StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.surface_set_material(0, material)

		var instance = MeshInstance3D.new()
		instance.mesh = mesh
		chunk_node.add_child(instance)
		mesh_instances[get_chunk_key(cx, cz)] = instance

		# Add collision using ConcavePolygonShape3D from the mesh
		if verts.size() > 0:
			var static_body = StaticBody3D.new()
			instance.add_child(static_body)

			var collision_shape = CollisionShape3D.new()
			var concave_shape = ConcavePolygonShape3D.new()
			concave_shape.set_faces(verts)
			collision_shape.shape = concave_shape
			static_body.add_child(collision_shape)

	# Create water mesh
	var water_verts: PackedVector3Array = PackedVector3Array()
	var water_colors: PackedColorArray = PackedColorArray()
	var water_normals: PackedVector3Array = PackedVector3Array()

	for pos in blocks.keys():
		if blocks[pos] == BlockType.WATER:
			# Only show top water face
			var above = blocks.get(pos + Vector3i(0, 1, 0))
			if above == null or above == BlockType.AIR:
				add_water_face(water_verts, water_colors, water_normals, pos)

	if water_verts.size() > 0:
		var water_arrays = []
		water_arrays.resize(Mesh.ARRAY_MAX)
		water_arrays[Mesh.ARRAY_VERTEX] = water_verts
		water_arrays[Mesh.ARRAY_NORMAL] = water_normals
		water_arrays[Mesh.ARRAY_COLOR] = water_colors

		var water_mesh = ArrayMesh.new()
		water_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, water_arrays)

		var water_material = StandardMaterial3D.new()
		water_material.vertex_color_use_as_albedo = true
		water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		water_material.albedo_color = Color(0.2, 0.4, 0.8, 0.7)
		water_mesh.surface_set_material(0, water_material)

		var water_instance = MeshInstance3D.new()
		water_instance.mesh = water_mesh
		chunk_node.add_child(water_instance)

func add_block_to_mesh(verts: PackedVector3Array, cols: PackedColorArray, norms: PackedVector3Array, pos: Vector3i, color: Color) -> void:
	var x = pos.x
	var y = pos.y
	var z = pos.z

	# Top face
	var top_verts = [
		Vector3(x, y + 1, z), Vector3(x + 1, y + 1, z),
		Vector3(x + 1, y + 1, z + 1), Vector3(x, y + 1, z + 1)
	]
	add_face(verts, cols, norms, top_verts, Vector3.UP, color)

	# Bottom face
	var bottom_verts = [
		Vector3(x, y, z + 1), Vector3(x + 1, y, z + 1),
		Vector3(x + 1, y, z), Vector3(x, y, z)
	]
	add_face(verts, cols, norms, bottom_verts, Vector3.DOWN, color)

	# Front face
	var front_verts = [
		Vector3(x, y, z + 1), Vector3(x, y + 1, z + 1),
		Vector3(x + 1, y + 1, z + 1), Vector3(x + 1, y, z + 1)
	]
	add_face(verts, cols, norms, front_verts, Vector3.BACK, color)

	# Back face
	var back_verts = [
		Vector3(x + 1, y, z), Vector3(x + 1, y + 1, z),
		Vector3(x, y + 1, z), Vector3(x, y, z)
	]
	add_face(verts, cols, norms, back_verts, Vector3.FORWARD, color)

	# Left face
	var left_verts = [
		Vector3(x, y, z), Vector3(x, y + 1, z),
		Vector3(x, y + 1, z + 1), Vector3(x, y, z + 1)
	]
	add_face(verts, cols, norms, left_verts, Vector3.LEFT, color)

	# Right face
	var right_verts = [
		Vector3(x + 1, y, z + 1), Vector3(x + 1, y + 1, z + 1),
		Vector3(x + 1, y + 1, z), Vector3(x + 1, y, z)
	]
	add_face(verts, cols, norms, right_verts, Vector3.RIGHT, color)

func add_water_face(verts: PackedVector3Array, cols: PackedColorArray, norms: PackedVector3Array, pos: Vector3i) -> void:
	var x = pos.x
	var y = pos.y
	var z = pos.z

	var water_verts = [
		Vector3(x, y + 1, z), Vector3(x + 1, y + 1, z),
		Vector3(x + 1, y + 1, z + 1), Vector3(x, y + 1, z + 1)
	]
	add_face(verts, cols, norms, water_verts, Vector3.UP, block_colors[BlockType.WATER])

func add_face(verts: PackedVector3Array, cols: PackedColorArray, norms: PackedVector3Array, face_verts: Array, normal: Vector3, color: Color) -> void:
	# Triangle 1
	verts.append(face_verts[0])
	verts.append(face_verts[1])
	verts.append(face_verts[2])

	# Triangle 2
	verts.append(face_verts[0])
	verts.append(face_verts[2])
	verts.append(face_verts[3])

	for i in range(6):
		cols.append(color)
		norms.append(normal)

func break_block() -> void:
	raycast.force_raycast_update()
	if raycast.is_colliding():
		var hit_pos = raycast.get_collision_point()
		var normal = raycast.get_collision_normal()

		# Calculate block position
		var block_pos = (hit_pos - normal * 0.5).floor()
		var chunk_x = int(floor(block_pos.x / CHUNK_SIZE))
		var chunk_z = int(floor(block_pos.z / CHUNK_SIZE))
		var key = get_chunk_key(chunk_x, chunk_z)

		if chunks.has(key):
			var local_x = int(block_pos.x) - chunk_x * CHUNK_SIZE
			var local_y = int(block_pos.y)
			var local_z = int(block_pos.z) - chunk_z * CHUNK_SIZE
			var block_key = Vector3i(local_x, local_y, local_z)

			if chunks[key].has(block_key):
				chunks[key].erase(block_key)
				# Regenerate chunk mesh
				regenerate_chunk(chunk_x, chunk_z)

func place_block() -> void:
	raycast.force_raycast_update()
	if raycast.is_colliding():
		var hit_pos = raycast.get_collision_point()
		var normal = raycast.get_collision_normal()

		# Calculate block position (opposite direction of hit)
		var block_pos = (hit_pos + normal * 0.5).floor()
		var chunk_x = int(floor(block_pos.x / CHUNK_SIZE))
		var chunk_z = int(floor(block_pos.z / CHUNK_SIZE))
		var key = get_chunk_key(chunk_x, chunk_z)

		if chunks.has(key):
			var local_x = int(block_pos.x) - chunk_x * CHUNK_SIZE
			var local_y = int(block_pos.y)
			var local_z = int(block_pos.z) - chunk_z * CHUNK_SIZE
			var block_key = Vector3i(local_x, local_y, local_z)

			# Don't place if block already exists
			if not chunks[key].has(block_key):
				chunks[key][block_key] = selected_block
				regenerate_chunk(chunk_x, chunk_z)

func regenerate_chunk(cx: int, cz: int) -> void:
	var key = get_chunk_key(cx, cz)
	var chunk_node = $World.get_node("Chunk_%d_%d" % [cx, cz])

	if chunk_node:
		# Remove old mesh instances
		for child in chunk_node.get_children():
			child.queue_free()

		# Create new mesh
		if chunks.has(key):
			create_chunk_mesh(chunk_node, chunks[key], cx, cz)
