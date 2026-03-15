extends Node

const SAVE_FILE_PATH := "user://world_save.dat"

class WorldSaveData:
	var chunks: Dictionary = {}
	var player_position: Vector3 = Vector3(0, 64, 0)
	var seed: int = 0

	func save_to_file(path: String) -> bool:
		var file = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return false

		# Save seed
		file.store_64(seed)

		# Save player position
		file.store_float(player_position.x)
		file.store_float(player_position.y)
		file.store_float(player_position.z)

		# Save chunk count
		file.store_32(chunks.size())

		# Save each chunk
		for key in chunks.keys():
			var cx = key.x
			var cz = key.y
			file.store_32(cx)
			file.store_32(cz)

			var blocks = chunks[key]
			file.store_32(blocks.size())

			for block_pos in blocks.keys():
				var bx = block_pos.x
				var by = block_pos.y
				var bz = block_pos.z
				var block_type = blocks[block_pos]

				file.store_8(bx)
				file.store_16(by)
				file.store_8(bz)
				file.store_8(block_type)

		file.close()
		return true

	func load_from_file(path: String) -> bool:
		if not FileAccess.file_exists(path):
			return false

		var file = FileAccess.open(path, FileAccess.READ)
		if file == null:
			return false

		# Load seed
		seed = file.get_64()

		# Load player position
		player_position = Vector3(
			file.get_float(),
			file.get_float(),
			file.get_float()
		)

		# Load chunk count
		var chunk_count = file.get_32()

		# Load each chunk
		for i in range(chunk_count):
			var cx = file.get_32()
			var cz = file.get_32()
			var key = Vector2i(cx, cz)

			var block_count = file.get_32()
			var blocks = {}

			for j in range(block_count):
				var bx = file.get_8()
				var by = file.get_16()
				var bz = file.get_8()
				var block_type = file.get_8()

				blocks[Vector3i(bx, by, bz)] = block_type

			chunks[key] = blocks

		file.close()
		return true
