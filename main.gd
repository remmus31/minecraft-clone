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
	FLOWING_WATER = 6,
	WOOD = 7,
	LEAVES = 8,
	COBBLESTONE = 9
}

# Block colors
var block_colors := {
	BlockType.GRASS: Color(0.3, 0.8, 0.2),
	BlockType.DIRT: Color(0.55, 0.4, 0.25),
	BlockType.STONE: Color(0.5, 0.5, 0.5),
	BlockType.SAND: Color(0.9, 0.85, 0.6),
	BlockType.WATER: Color(0.2, 0.4, 0.8, 0.8),
	BlockType.FLOWING_WATER: Color(0.3, 0.5, 0.9, 0.6),
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
var jump_force := 9.0
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
var hotbar_slot_nodes: Array = []

# Block preview
var block_preview: MeshInstance3D
var current_target_block := Vector3i(-1, -1, -1)

# Water flow simulation
var water_flow_timer := 0.0
const WATER_FLOW_INTERVAL := 0.3
const MAX_FLOW_DISTANCE := 7
# Track water sources for flow distance calculation
var water_sources := {}  # Vector3i -> flow_distance (0 for source)

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
	raycast.target_position = Vector3(0, 0, -6)
	# Set collision mask to only collide with terrain (layer 1), not player
	raycast.collision_mask = 1
	# Exclude player from raycast
	raycast.add_exception(player)
	# Add raycast to camera so it points where player is looking
	camera.add_child(raycast)

	# Setup block preview
	setup_block_preview()

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

	# Wait for physics frame to ensure collisions are ready
	await get_tree().physics_frame
	# Force raycast update to ensure it can detect terrain
	raycast.force_raycast_update()

	# Capture mouse
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func setup_player() -> void:
	# Position player above ground (offset slightly to avoid being inside a block)
	var start_x := 8.5  # Start in middle of chunk, offset to avoid block center
	var start_z := 8.5
	var ground_height = get_height_at(int(start_x), int(start_z))
	var start_y = ground_height + 10.0  # Spawn high above to fall down
	player.global_position = Vector3(start_x, start_y, start_z)

func setup_block_preview() -> void:
	# Create a wireframe cube for block preview
	block_preview = MeshInstance3D.new()

	# Create box mesh
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(1.02, 1.02, 1.02)  # Slightly larger than block
	block_preview.mesh = box_mesh

	# Create outline material
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1, 1, 1, 0.3)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	block_preview.material_override = material

	# Add to world (not player, so it stays fixed in world space)
	$World.add_child(block_preview)
	block_preview.visible = false

func update_block_preview() -> void:
	raycast.force_raycast_update()

	if raycast.is_colliding():
		var hit_pos = raycast.get_collision_point()
		var normal = raycast.get_collision_normal()

		# Get the block position
		var block_pos = (hit_pos - normal * 0.5).floor()

		# Update preview position
		block_preview.global_position = Vector3(block_pos.x + 0.5, block_pos.y + 0.5, block_pos.z + 0.5)
		block_preview.visible = true
		current_target_block = Vector3i(block_pos.x, block_pos.y, block_pos.z)
	else:
		block_preview.visible = false
		current_target_block = Vector3i(-1, -1, -1)

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

		hotbar.add_child(slot)
		hotbar_slot_nodes.append(slot)

	update_hotbar_selection()

func update_hotbar_selection() -> void:
	for i in range(hotbar_slot_nodes.size()):
		var slot = hotbar_slot_nodes[i]
		if i == selected_slot:
			# Selected slot: larger size and white border
			slot.custom_minimum_size = Vector2(48, 48)
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0, 0, 0, 0.3)
			style.border_width_left = 3
			style.border_width_top = 3
			style.border_width_right = 3
			style.border_width_bottom = 3
			style.border_color = Color.WHITE
			slot.add_theme_stylebox_override("normal", style)
		else:
			# Non-selected slot: normal size, no border
			slot.custom_minimum_size = Vector2(40, 40)
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

	# Update block preview
	update_block_preview()

	# Process water flow
	_process_water_flow(delta)

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
				var world_y = block_y

				if block_y < height:
					if block_y == height:
						# Top layer
						if height < 25:
							blocks[Vector3i(world_x, world_y, world_z)] = BlockType.GRASS
						elif height < 35:
							blocks[Vector3i(world_x, world_y, world_z)] = BlockType.GRASS
						else:
							blocks[Vector3i(world_x, world_y, world_z)] = BlockType.STONE
					elif block_y > height - 4:
						blocks[Vector3i(world_x, world_y, world_z)] = BlockType.DIRT
					else:
						blocks[Vector3i(world_x, world_y, world_z)] = BlockType.STONE
				elif block_y < 20:
					# Water level
					blocks[Vector3i(world_x, world_y, world_z)] = BlockType.WATER

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

		if block_type == BlockType.WATER or block_type == BlockType.FLOWING_WATER:
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
			if neighbor == null or neighbor == BlockType.AIR or neighbor == BlockType.WATER or neighbor == BlockType.FLOWING_WATER:
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

		# Add collision using mesh.create_trimesh_shape()
		if verts.size() > 0:
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			chunk_node.add_child(body)

			var shape := CollisionShape3D.new()
			shape.shape = mesh.create_trimesh_shape()
			body.add_child(shape)

			# Debug output
			print("Created collision shape with ", mesh.create_trimesh_shape().get_faces().size(), " faces")

	# Create water mesh
	var water_verts: PackedVector3Array = PackedVector3Array()
	var water_colors: PackedColorArray = PackedColorArray()
	var water_normals: PackedVector3Array = PackedVector3Array()

	for pos in blocks.keys():
		var block_type = blocks[pos]
		if block_type == BlockType.WATER or block_type == BlockType.FLOWING_WATER:
			var water_color = block_colors.get(block_type, block_colors[BlockType.WATER])
			add_water_face(water_verts, water_colors, water_normals, pos, water_color, blocks)

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

func add_water_face(verts: PackedVector3Array, cols: PackedColorArray, norms: PackedVector3Array, pos: Vector3i, color: Color, blocks: Dictionary) -> void:
	var x = pos.x
	var y = pos.y
	var z = pos.z

	# Check adjacent blocks - only render face if adjacent block is not water
	var above = blocks.get(pos + Vector3i(0, 1, 0))
	var below = blocks.get(pos + Vector3i(0, -1, 0))
	var front = blocks.get(pos + Vector3i(0, 0, 1))
	var back = blocks.get(pos + Vector3i(0, 0, -1))
	var left = blocks.get(pos + Vector3i(-1, 0, 0))
	var right = blocks.get(pos + Vector3i(1, 0, 0))

	var water_types = [BlockType.WATER, BlockType.FLOWING_WATER]

	# Top face - always render (water surface)
	if above == null or not above in water_types:
		var top_verts = [
			Vector3(x, y + 1, z), Vector3(x + 1, y + 1, z),
			Vector3(x + 1, y + 1, z + 1), Vector3(x, y + 1, z + 1)
		]
		add_face(verts, cols, norms, top_verts, Vector3.UP, color)

	# Bottom face
	if below == null or not below in water_types:
		var bottom_verts = [
			Vector3(x, y, z + 1), Vector3(x + 1, y, z + 1),
			Vector3(x + 1, y, z), Vector3(x, y, z)
		]
		add_face(verts, cols, norms, bottom_verts, Vector3.DOWN, color)

	# Front face
	if front == null or not front in water_types:
		var front_verts = [
			Vector3(x, y, z + 1), Vector3(x, y + 1, z + 1),
			Vector3(x + 1, y + 1, z + 1), Vector3(x + 1, y, z + 1)
		]
		add_face(verts, cols, norms, front_verts, Vector3.BACK, color)

	# Back face
	if back == null or not back in water_types:
		var back_verts = [
			Vector3(x + 1, y, z), Vector3(x + 1, y + 1, z),
			Vector3(x, y + 1, z), Vector3(x, y, z)
		]
		add_face(verts, cols, norms, back_verts, Vector3.FORWARD, color)

	# Left face
	if left == null or not left in water_types:
		var left_verts = [
			Vector3(x, y, z), Vector3(x, y + 1, z),
			Vector3(x, y + 1, z + 1), Vector3(x, y, z + 1)
		]
		add_face(verts, cols, norms, left_verts, Vector3.LEFT, color)

	# Right face
	if right == null or not right in water_types:
		var right_verts = [
			Vector3(x + 1, y, z + 1), Vector3(x + 1, y + 1, z + 1),
			Vector3(x + 1, y + 1, z), Vector3(x + 1, y, z)
		]
		add_face(verts, cols, norms, right_verts, Vector3.RIGHT, color)

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
	print("Raycast colliding: ", raycast.is_colliding())
	if raycast.is_colliding():
		var hit_pos = raycast.get_collision_point()
		var normal = raycast.get_collision_normal()

		# Calculate block position (the block being hit)
		var block_pos = Vector3i(
			int(floor(hit_pos.x - normal.x * 0.5)),
			int(floor(hit_pos.y - normal.y * 0.5)),
			int(floor(hit_pos.z - normal.z * 0.5))
		)
		var chunk_x = int(floor(float(block_pos.x) / CHUNK_SIZE))
		var chunk_z = int(floor(float(block_pos.z) / CHUNK_SIZE))
		var key = get_chunk_key(chunk_x, chunk_z)

		print("block_pos: ", block_pos, " chunk_x: ", chunk_x, " chunk_z: ", chunk_z, " key: ", key)
		if chunks.has(key):
			# Use world coordinates directly (blocks are stored in world coords)
			var block_key = block_pos

			# Debug: show what blocks exist near this position
			var y_range = range(max(0, block_pos.y - 3), min(CHUNK_HEIGHT, block_pos.y + 4))
			var nearby_blocks = []
			for test_y in y_range:
				var test_key = Vector3i(block_pos.x, test_y, block_pos.z)
				if chunks[key].has(test_key):
					nearby_blocks.append(test_key)
			print("Nearby blocks at x=", block_pos.x, " z=", block_pos.z, ": ", nearby_blocks)

			print("block_key: ", block_key, " exists: ", chunks[key].has(block_key))
			if chunks[key].has(block_key):
				chunks[key].erase(block_key)
				# Regenerate chunk mesh
				regenerate_chunk(chunk_x, chunk_z)
				print("Block removed and chunk regenerated")
			else:
				print("Block not found at block_key!")
		else:
			print("Chunk not found for key: ", key)

func place_block() -> void:
	raycast.force_raycast_update()
	if raycast.is_colliding():
		var hit_pos = raycast.get_collision_point()
		var normal = raycast.get_collision_normal()

		# Calculate block position (opposite direction of hit)
		# For top face (normal = UP), this gives position above the block
		var block_pos = Vector3i(
			int(floor(hit_pos.x + normal.x * 0.6)),
			int(floor(hit_pos.y + normal.y * 0.6)),
			int(floor(hit_pos.z + normal.z * 0.6))
		)

		var chunk_x = int(floor(float(block_pos.x) / CHUNK_SIZE))
		var chunk_z = int(floor(float(block_pos.z) / CHUNK_SIZE))
		var key = get_chunk_key(chunk_x, chunk_z)

		# Ensure chunk exists
		if not chunks.has(key):
			generate_chunk(chunk_x, chunk_z)

		if chunks.has(key):
			# Use world coordinates directly (blocks are stored in world coords)
			var block_key = block_pos

			# Don't place if block already exists
			if not chunks[key].has(block_key):
				chunks[key][block_key] = selected_block
				# Track water source
				if selected_block == BlockType.WATER:
					water_sources[block_key] = 0
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

func _process_water_flow(delta: float) -> void:
	water_flow_timer += delta
	if water_flow_timer < WATER_FLOW_INTERVAL:
		return

	water_flow_timer = 0.0

	# Track changes to apply after iteration
	var blocks_to_add := []
	var blocks_to_remove := []
	var new_water_sources := {}

	# Process each water source
	for source_pos in water_sources.keys():
		var flow_distance = water_sources[source_pos]

		# Try to flow downward
		var below_pos = source_pos + Vector3i(0, -1, 0)
		if _can_flow_to(below_pos):
			# Only flow down if we haven't reached max distance
			if flow_distance < MAX_FLOW_DISTANCE:
				blocks_to_add.append({"pos": below_pos, "is_source": false, "source": source_pos})
				new_water_sources[below_pos] = flow_distance + 1

		# Try to flow horizontally (only if can't flow down or at max distance)
		if flow_distance >= MAX_FLOW_DISTANCE:
			continue

		var directions := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
		for dir in directions:
			var side_pos = source_pos + dir
			var below_side = side_pos + Vector3i(0, -1, 0)

			# First check if we can flow into the side position
			if _can_flow_to(side_pos):
				# Then check if we can flow down from the side position
				if _can_flow_to(below_side):
					# Only add if not already water and within distance limit
					if flow_distance + 1 < MAX_FLOW_DISTANCE:
						blocks_to_add.append({"pos": side_pos, "is_source": false, "source": source_pos})
						new_water_sources[side_pos] = flow_distance + 1

	# Apply changes
	for block_data in blocks_to_add:
		var pos = block_data["pos"]
		var cx = int(floor(float(pos.x) / CHUNK_SIZE))
		var cz = int(floor(float(pos.z) / CHUNK_SIZE))
		var key = get_chunk_key(cx, cz)

		if chunks.has(key) and not chunks[key].has(pos):
			if block_data["is_source"]:
				chunks[key][pos] = BlockType.WATER
				water_sources[pos] = 0
			else:
				chunks[key][pos] = BlockType.FLOWING_WATER
				# Track the original source's flow distance
				var source_pos = block_data["source"]
				if water_sources.has(source_pos):
					new_water_sources[pos] = water_sources[source_pos] + 1
			regenerate_chunk(cx, cz)

	# Update water_sources with new flowing water positions
	for pos in new_water_sources.keys():
		if not water_sources.has(pos):
			water_sources[pos] = new_water_sources[pos]

func _can_flow_to(pos: Vector3i) -> bool:
	var cx = int(floor(float(pos.x) / CHUNK_SIZE))
	var cz = int(floor(float(pos.z) / CHUNK_SIZE))
	var key = get_chunk_key(cx, cz)

	if not chunks.has(key):
		return false

	var current_block = chunks[key].get(pos, BlockType.AIR)
	# Can flow into air or existing water/flowing_water
	return current_block == BlockType.AIR or current_block == BlockType.WATER or current_block == BlockType.FLOWING_WATER
