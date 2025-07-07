extends Node2D

@export var material_server: MaterialSimulationCore
@export var selected_material: MaterialType  # Назначаем в инспекторе
@export var material_amount: int = 1

func _ready():
	# Инициализация сервера
	material_server.started.connect(_on_simulation_started)
	material_server.stopped.connect(_on_simulation_stopped)
	material_server.updated.connect(_on_simulation_updated)
	#material_server.material_added.connect(_on_material_added)

func _input(event):
	if event is InputEventMouseButton && event.pressed:
		# Получаем позицию мыши относительно контейнера симуляции
		var mouse_pos = get_global_mouse_position()
		var container_pos = material_server.container.get_global_transform()
		var local_pos = container_pos.affine_inverse() * mouse_pos
		
		# Рассчитываем координаты ячейки
		var quadrant_size = material_server.quadrant_size
		var x = int(local_pos.x / quadrant_size)
		var y = int(local_pos.y / quadrant_size)
		
		# Для отладки
		#print("Adding at grid position: ", x, ", ", y)
		#print("Raw mouse pos: ", get_global_mouse_position())
		#print("Container pos: ", material_server.container.position)
		#print("Local pos: ", local_pos)
		#print("Calculated grid: ", x, ", ", y)
		
		if event.button_index == MOUSE_BUTTON_LEFT:
			material_server.add_material(x, y, material_amount, selected_material)
		
		# ... остальной код ...
			
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			material_server.remove_material(x, y, material_amount)
			
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			material_amount = min(material_amount + 1, 10)
			
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			material_amount = max(material_amount - 1, 1)

func _on_simulation_started():
	print("Simulation started")

func _on_simulation_stopped():
	print("Simulation stopped")

func _on_simulation_updated():
	# Можно обновлять UI или другие элементы
	pass

#func _on_material_added(x: int, y: int, amount: float, _material: MaterialType):
	#print("Added ", amount, " of ", _material.name, " at (", x, ", ", y, ")")
