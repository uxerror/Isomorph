class_name MaterialSimulationServer
extends Node

# ====================== ОСНОВНЫЕ НАСТРОЙКИ ======================
#region Основные настройки
@export var material_cell_scene: PackedScene
@export var refresh_rate: float = 1.0

var _quadrant_size: int = 16
@export_range(1, 100) var quadrant_size: int = 16:
	set(value):
		if value >= 1: 
			_quadrant_size = value
	get:
		return _quadrant_size

# Карты столкновений
@export var collision_maps: Array[CollisionMap]
var main_map: TileMapLayer

# Контейнер для ячеек
@export var use_map_as_container: bool = true
@export var container: Node2D
@export var change_container_position: bool = true
#endregion

# ====================== НАСТРОЙКИ СИМУЛЯЦИИ ======================
#region Настройки симуляции
@export_group("Simulation Settings")
@export var gravity: Vector2 = Vector2(0, 9.8)
@export_range(0, 100, 1) var cleanup_min_iterations: int = 5
@export_range(0, 100, 1) var max_iterations: int = 10
@export_range(10, 1000, 1) var max_falls: int = 100
@export_range(0.0, 1.0, 0.001) var min_amount: float = 0.005
@export var enable_temperature: bool = false
@export var enable_pressure: bool = false

@export_range(0.001, 0.1, 0.001) var micro_flow_threshold: float = 0.01

# Расширенные физические свойства
@export var enable_phase_transitions: bool = true
@export var enable_chemical_reactions: bool = true
@export var enable_thermal_expansion: bool = true
@export var enable_electromagnetic: bool = false
@export var enable_biological: bool = false
@export var world_pressure: float = 1.0 # Атмосферное давление
@export var world_temperature: float = 20.0 # Базовая температура
#endregion

# ====================== МОНИТОРИНГ И ДАННЫЕ ======================
#region Мониторинг и данные
var monitor_started: bool = false:
	set(value):
		monitor_started = value
		if value: started.emit()
		else: stopped.emit()
var total_amount: float = 0
var time_passed: float = 0
var flow_counters: Dictionary = {}

# Хранилища данных симуляции
var cells: Array[MaterialCell] = []
var cells_positions: Dictionary = {}
var updated_cells: Array[MaterialCell] = []
#endregion

# ====================== СИГНАЛЫ ======================
#region Сигналы
signal started()
signal stopped()
signal updated()
signal material_added(x, y, amount, material)
signal material_removed(x, y, amount, material)
#endregion

# ====================== ИНИЦИАЛИЗАЦИЯ ======================
#region Инициализация
func _ready():
	# Проверка и инициализация карт столкновений
	assert(collision_maps.size() > 0, "Need at least one CollisionMap!")
	for i in collision_maps.size():
		var map_node = get_node(collision_maps[i].tile_map_path)
		assert(map_node is TileMapLayer, "CollisionMap %d must be a TileMapLayer!" % i)
		collision_maps[i].tile_map = map_node
		
		# Проверка совместимости размеров квадрантов
		var factor: int = map_node.rendering_quadrant_size / quadrant_size
		assert(factor >= 1, "CollisionMap %d quadrant size too small!" % i)
		assert(factor * quadrant_size == map_node.rendering_quadrant_size, 
			"CollisionMap %d quadrant size must be a multiple of simulation quadrant_size!" % i)
	
	main_map = collision_maps[0].tile_map
	
	# Настройка контейнера
	if use_map_as_container:
		container = main_map
	assert(container is Node2D, "Container must be a Node2D!")
	
	if change_container_position:
		container.position = main_map.position
	
	# Инициализация счетчиков потока
	flow_counters = {
		"fall": 0,
		"decompression": 0,
		"left": 0,
		"right": 0,
		"burn": 0,
		"state_change": 0
	}
	
	# Настройка мониторинга производительности
	_setup_performance_monitors()
	
	# Конвертация существующих ячеек
	_convert_existing_cells()
	
	start()
#endregion

# ====================== ПРОЦЕСС СИМУЛЯЦИИ ======================
#region Главный цикл симуляции
func _process(delta):
	if not monitor_started: return
	
	time_passed += delta
	if time_passed >= refresh_rate:
		_reset_flow_counters()
		var simulation_updated = _update_simulation(delta)
		
		# Обновляем только измененные ячейки
		for cell in updated_cells:
			refresh_cell(cell)
		updated_cells.clear()
		
		self.updated.emit()
		if not simulation_updated: stop()
		time_passed = 0

func _reset_flow_counters():
	# Сброс всех счетчиков потоков
	for key in flow_counters:
		flow_counters[key] = 0

func _update_simulation(delta: float) -> bool:
	updated_cells.clear()
	var new_cells: Array[MaterialCell] = []
	var simulation_updated = false
	
	# Обновление состояния всех ячеек
	for cell in cells:
		cell.update_state(delta, world_temperature, world_pressure)
	
	# Обновление информации о соседях
	for cell in cells:
		refresh_cell_neighbors(cell)
	
	# Сброс аккумуляторов перед расчетами
	for cell in cells:
		cell.flow_accumulator = Vector4.ZERO
		cell.gravity_accumulator = 0.0
	
	# Основной цикл обработки ячеек
	var i = cells.size() - 1
	while i >= 0:
		var cell = cells[i]
		
		# Проверка условий удаления ячейки
		if cell.falls > max_falls:
			_destroy_cell(cell)
			i -= 1
			continue
		
		if cell.amount <= min_amount and not _is_map_cell_empty(cell.get_x(), cell.get_y() + 1) and cell.floor_can_absorb:
			_destroy_cell(cell)
			i -= 1
			continue
		
		# Применение физических правил
		_apply_physics_rules(cell, new_cells, delta)
		
		if cell.new_amount <= 0:
			_destroy_cell(cell)
			i -= 1
			continue
		
		i -= 1
	
	# Применение накопленных потоков
	_apply_accumulated_flows(new_cells)
	
	# Добавление новых ячеек
	for cell in new_cells:
		cells.append(cell)
		cells_positions[MaterialCell.hash_position(cell.get_x(), cell.get_y())] = cell
		updated_cells.append(cell)
	
	# Финальное обновление значений ячеек
	total_amount = 0
	for cell in cells:
		if cell.amount != cell.new_amount:
			simulation_updated = true
			cell.amount = cell.new_amount
			cell.iteration = 0
			cell.changed.emit(self)
			updated_cells.append(cell)
		else:
			cell.iteration = min(cell.iteration + 1, max_iterations)
			if cell.iteration < max_iterations:
				simulation_updated = true
		
		total_amount += cell.amount
	
	return simulation_updated
#endregion

# ====================== ФИЗИЧЕСКИЕ ПРАВИЛА ======================
#region Физические правила
func _apply_physics_rules(cell: MaterialCell, new_cells: Array, delta: float):
	# 0. Обновление состояния
	cell.update_state(delta, world_temperature, world_pressure)
	
	# 1. Тепловое расширение (особенно для газов)
	if enable_thermal_expansion and cell.current_state == MaterialCell.State.GAS:
		_apply_thermal_expansion(cell, new_cells)
	
	# 2. Применение гравитации
	_apply_gravity(cell, new_cells, delta)
	
	# 3. Горизонтальное растекание
	_apply_horizontal_flow(cell, new_cells, delta)
	
	# 4. Декомпрессия/сжатие
	_apply_decompression(cell, new_cells, delta)
	
	# 5. Химические реакции с соседями
	if enable_chemical_reactions:
		_apply_chemical_reactions(cell)
	
	# 6. Электромагнитные взаимодействия
	if enable_electromagnetic:
		_apply_electromagnetic(cell)
	
	# 7. Специальные эффекты (горение и т.д.)
	_apply_special_effects(cell)

func _apply_accumulated_flows(new_cells: Array):
	# Обработка накопленных потоков для всех ячеек
	for cell in cells:
		# Горизонтальные потоки
		if cell.flow_accumulator.x > micro_flow_threshold:
			_apply_flow_to_direction(cell, -1, 0, cell.flow_accumulator.x, new_cells)
			cell.flow_accumulator.x = 0
		
		if cell.flow_accumulator.y > micro_flow_threshold:
			_apply_flow_to_direction(cell, 1, 0, cell.flow_accumulator.y, new_cells)
			cell.flow_accumulator.y = 0
		
		# Вертикальные потоки (падение вниз)
		if cell.flow_accumulator.w > micro_flow_threshold:
			var bottom_cell = get_cell_by_position(cell.get_x(), cell.get_y() + 1)
			if not bottom_cell:
				bottom_cell = _create_cell(cell.get_x(), cell.get_y() + 1, 0, cell.material_type)
				new_cells.append(bottom_cell)
			
			var flow = min(cell.flow_accumulator.w, cell.new_amount, 1.0 - bottom_cell.new_amount)
			bottom_cell.new_amount += flow
			cell.new_amount -= flow
			cell.flow_accumulator.w -= flow
			flow_counters.fall += 1
		
		# Декомпрессия (движение вверх)
		if cell.flow_accumulator.z > micro_flow_threshold:
			var top_cell = get_cell_by_position(cell.get_x(), cell.get_y() - 1)
			if not top_cell:
				top_cell = _create_cell(cell.get_x(), cell.get_y() - 1, 0, cell.material_type)
				new_cells.append(top_cell)
			
			var flow = min(cell.flow_accumulator.z, cell.new_amount, 1.0 - top_cell.new_amount)
			top_cell.new_amount += flow
			cell.new_amount -= flow
			cell.flow_accumulator.z -= flow
			flow_counters.decompression += 1

func _apply_thermal_expansion(cell: MaterialCell, new_cells: Array):
	# Расчет коэффициента расширения
	var expansion_factor = 1.0 + cell.material_type.thermal_expansion * (cell.temperature - 20.0)
	var max_expansion = 2.0
	
	# Особый расчет для газов
	if cell.current_state == MaterialCell.State.GAS:
		var kelvin_temp = cell.temperature + 273.15
		var base_kelvin = 293.15
		expansion_factor = kelvin_temp / base_kelvin
		
	# Применение расширения
	if expansion_factor > 1.01:
		var extra_volume = cell.new_amount * (expansion_factor - 1.0)
		extra_volume = min(extra_volume, cell.new_amount * (max_expansion - 1.0))
		_expand_gas(cell, extra_volume, new_cells)

func _expand_gas(cell: MaterialCell, extra_volume: float, new_cells: Array):
	# Направления расширения
	var expansion_directions = [
		Vector2i(0, 1),   # Вниз
		Vector2i(-1, 0),  # Влево
		Vector2i(1, 0),   # Вправо
		Vector2i(0, -1)   # Вверх
	]
	
	var remaining_volume = extra_volume
	
	# Попытка распределить объем по направлениям
	for dir in expansion_directions:
		if remaining_volume <= 0:
			break
			
		var new_x = cell.get_x() + dir.x
		var new_y = cell.get_y() + dir.y
		
		# Проверка возможности расширения
		var target_cell = get_cell_by_position(new_x, new_y)
		if not _is_map_cell_empty(new_x, new_y) or target_cell != null:
			continue
		
		# Создание новой ячейки
		target_cell = _create_cell(new_x, new_y, 0, cell.material_type)
		new_cells.append(target_cell)
		
		# Расчет доступного пространства
		var available_space = 1.0 - target_cell.new_amount - world_pressure
		var volume_to_add = min(remaining_volume, available_space)
		
		# Добавление объема
		target_cell.new_amount += volume_to_add
		remaining_volume -= volume_to_add
		updated_cells.append(target_cell)
	
	# Обновление исходной ячейки
	cell.new_amount -= (extra_volume - remaining_volume)
	updated_cells.append(cell)
	
	# Обработка остаточного давления
	if remaining_volume > 0:
		cell.pressure += remaining_volume * 0.1
		if cell.pressure > 1.0:
			_handle_high_pressure(cell, remaining_volume)

func _handle_high_pressure(cell: MaterialCell, excess_volume: float):
	# Визуальные эффекты давления
	cell.sprite.scale *= 1.1
	cell.sprite.modulate = Color(1.0, 0.7, 0.7)
	
	# Волна давления при критическом значении
	if cell.pressure > 2.0:
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				if dx == 0 and dy == 0: continue
				
				var dist = Vector2(dx, dy).length()
				var force = (2.0 - dist) * cell.pressure * 0.5
				
				if force > 0:
					var target_x = cell.get_x() + dx
					var target_y = cell.get_y() + dy
					var target = get_cell_by_position(target_x, target_y)
					
					if target:
						var direction = Vector2(dx, dy).normalized()
						target.apply_force(direction * force)
		
		# Сброс давления
		cell.pressure = 0
		cell.sprite.scale = Vector2(1, 1)
		cell.sprite.modulate = cell.material_type.color

func _apply_chemical_reactions(cell: MaterialCell):
	# Проверка реакций со всеми соседями
	for neighbor in [cell.left, cell.right, cell.top, cell.bottom]:
		if neighbor and neighbor != cell:
			var reaction = cell.material_type.check_reactions(neighbor.material_type)
			if reaction:
				cell.apply_reaction(neighbor, reaction)
				updated_cells.append(cell)
				updated_cells.append(neighbor)

func _apply_electromagnetic(cell: MaterialCell):
	# Применение только к магнитным материалам
	if cell.material_type.magnetic_permeability > 0.1:
		var magnetic_force = Vector2.ZERO
		
		# Расчет силы от соседних магнитных материалов
		for neighbor in [cell.left, cell.right, cell.top, cell.bottom]:
			if neighbor and neighbor.material_type.magnetic_permeability > 0:
				var direction = (neighbor.position - cell.position).normalized()
				var strength = cell.material_type.magnetic_permeability * neighbor.material_type.magnetic_permeability
				magnetic_force += direction * strength * 0.1
		
		# Применение силы
		cell.apply_force(magnetic_force)
		updated_cells.append(cell)

func _apply_gravity(cell: MaterialCell, new_cells: Array, delta: float):
	# Проверка наличия препятствия снизу
	if not _is_map_bottom_cell_empty(cell.get_x(), cell.get_y()): 
		cell.falls = 0
		return
	
	var mat = cell.material_type
	var density = mat.get_density(cell.temperature)
	var flow_potential = mat.get_flow_factor(cell.new_amount, cell.current_state)
	var gravity_flow = flow_potential * density * delta * 60.0
	
	# Накопление микропотоков гравитации
	cell.gravity_accumulator += gravity_flow
	
	# Применение при достижении порога
	if cell.gravity_accumulator >= micro_flow_threshold:
		var bottom_cell = get_cell_by_position(cell.get_x(), cell.get_y() + 1)
		var bottom_amount = bottom_cell.new_amount if bottom_cell else 0.0
		var available_space = 1.0 - bottom_amount
		
		var flow = min(cell.gravity_accumulator, available_space, mat.max_flow)
		
		if flow > 0:
			if not bottom_cell:
				bottom_cell = _create_cell(cell.get_x(), cell.get_y() + 1, 0, mat)
				new_cells.append(bottom_cell)
				bottom_cell.falls = cell.falls + 1
			
			# Перенос материала
			bottom_cell.new_amount += flow
			cell.bottom_has_flow = true
			cell.new_amount -= flow
			cell.gravity_accumulator -= flow
			flow_counters.fall += 1
			updated_cells.append(cell)
			updated_cells.append(bottom_cell)

func _apply_horizontal_flow(cell: MaterialCell, new_cells: Array, delta: float):
	var mat = cell.material_type
	var current_state = cell.current_state
	var flow_potential = mat.get_flow_factor(cell.new_amount, current_state)
	var flow_factor = flow_potential * mat.lateral_flow_factor * delta * 60.0
	
	# Распределение потока между направлениями
	var left_flow = 0.0
	var right_flow = 0.0
	
	if _is_map_left_cell_empty(cell.get_x(), cell.get_y()):
		left_flow = flow_factor * 0.5
	
	if _is_map_right_cell_empty(cell.get_x(), cell.get_y()):
		right_flow = flow_factor * 0.5
	
	# Накопление в аккумуляторы
	if left_flow > 0:
		cell.flow_accumulator.x += left_flow
	
	if right_flow > 0:
		cell.flow_accumulator.y += right_flow

func _apply_flow_to_direction(cell: MaterialCell, dx: int, dy: int, flow: float, new_cells: Array):
	# Перенос материала в указанном направлении
	var mat = cell.material_type
	var target_cell = get_cell_by_position(cell.get_x() + dx, cell.get_y() + dy)
	
	# Создание новой ячейки при необходимости
	if not target_cell:
		target_cell = _create_cell(cell.get_x() + dx, cell.get_y() + dy, 0, mat)
		new_cells.append(target_cell)
	
	# Расчет доступного пространства и реального потока
	var available_space = 1.0 - target_cell.new_amount
	var actual_flow = min(flow, mat.max_flow, cell.new_amount, available_space)
	
	# Обновление значений
	target_cell.new_amount += actual_flow
	cell.new_amount -= actual_flow
	
	# Обновление счетчиков
	if dx < 0: 
		flow_counters.left += 1
	else: 
		flow_counters.right += 1
	
	# Добавление в список обновленных
	updated_cells.append(cell)
	updated_cells.append(target_cell)

func _apply_decompression(cell: MaterialCell, new_cells: Array, delta: float):
	# Проверка наличия пространства сверху
	if not _is_map_top_cell_empty(cell.get_x(), cell.get_y()): 
		return
	
	var mat = cell.material_type
	# Расчет фактора давления
	var pressure_factor = mat.compressibility * cell.new_amount * delta * 60.0
	
	# Накопление в аккумулятор потока (z-компонента)
	if pressure_factor > 0:
		cell.flow_accumulator.z += pressure_factor

func _apply_special_effects(cell: MaterialCell):
	# Обработка горения материалов
	if cell.material_type.is_flammable and cell.temperature > cell.material_type.ignition_point:
		if not cell.is_burning:
			cell.is_burning = true
		
		# Уменьшение количества при горении
		cell.new_amount -= cell.material_type.burn_rate
		flow_counters.burn += 1
		updated_cells.append(cell)
#endregion

# ====================== УПРАВЛЕНИЕ ЯЧЕЙКАМИ ======================
#region Управление ячейками
func _create_cell(x: int, y: int, amount: float, material: MaterialType) -> MaterialCell:
	# Создание новой ячейки материала
	var instance = material_cell_scene.instantiate()
	instance.config(x, y, amount, material, self)
	container.add_child(instance)
	updated_cells.append(instance)
	material_added.emit(x, y, amount, material)
	return instance

func _destroy_cell(cell: MaterialCell):
	# Полное удаление ячейки
	var amount = cell.amount
	var material = cell.material_type
	var x = cell.get_x()
	var y = cell.get_y()
	
	cell.new_amount = 0
	cell.amount = 0
	cells.erase(cell)
	cells_positions.erase(MaterialCell.hash_position(x, y))
	cell.destroyed.emit(self)
	cell.queue_free()
	
	material_removed.emit(x, y, amount, material)
#endregion

# ====================== КОЛЛИЗИИ И КАРТЫ ======================
#region Коллизии и карты
func _is_map_top_cell_empty(x: int, y: int) -> bool:
	return _is_map_cell_empty(x, y - 1, Vector2i(0, -1))

func _is_map_bottom_cell_empty(x: int, y: int) -> bool:
	return _is_map_cell_empty(x, y + 1, Vector2i(0, 1), true)

func _is_map_left_cell_empty(x: int, y: int) -> bool:
	return _is_map_cell_empty(x - 1, y, Vector2i(-1, 0))

func _is_map_right_cell_empty(x: int, y: int) -> bool:
	return _is_map_cell_empty(x + 1, y, Vector2i(1, 0))

func _is_map_cell_empty(x: int, y: int, increments = Vector2i.ZERO, one_way: bool = false) -> bool:
	# Проверка всех карт столкновений
	for map in collision_maps:
		var map_cell = _get_map_cell_by_position(x, y, map.tile_map)
		
		# Пропуск односторонних коллизий
		if map.one_way_collision and _get_map_cell_by_position(x - increments.x, y - increments.y, map.tile_map) != -1:
			continue
		
		# Проверка наличия коллизии
		if map_cell != -1 and (not map.one_way_collision or one_way):
			return false
	
	return true

func _get_map_cell_by_position(x: int, y: int, map: TileMapLayer) -> int:
	# Конвертация координат симуляции в координаты карты
	var qx = x * quadrant_size
	var qy = y * quadrant_size
	var xx = floor(qx / float(map.rendering_quadrant_size))
	var yy = floor(qy / float(map.rendering_quadrant_size))
	return map.get_cell_source_id(Vector2i(xx, yy))
#endregion

# ====================== ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ======================
#region Вспомогательные методы
func _setup_performance_monitors():
	# Настройка пользовательских мониторов производительности
	Performance.add_custom_monitor("material/instances", func(): return cells.size())
	Performance.add_custom_monitor("material/total_amount", get_total_amount)
	Performance.add_custom_monitor("material/is_running", func(): return int(is_running()))
	for flow_type in flow_counters:
		Performance.add_custom_monitor("material/flow/" + flow_type, 
			func(): return flow_counters[flow_type])

func _convert_existing_cells():
	# Конвертация существующих ячеек из карты
	main_map.update_internals()
	var coords: Array[Vector3] = []
	
	# Сбор существующих ячеек
	for map_child in main_map.get_children():
		if map_child is MaterialCell:
			var coord = main_map.local_to_map(map_child.position)
			coords.append(Vector3(coord.x, coord.y, map_child.amount))
			main_map.erase_cell(coord)
	
	# Создание новых ячеек с учетом размера квадрантов
	var factor: int = int(main_map.rendering_quadrant_size / quadrant_size)
	for coord in coords:
		for x in factor:
			for y in factor:
				add_material(
					(coord.x * factor) + x, 
					(coord.y * factor) + y, 
					coord.z, 
					null  # Используйте материал по умолчанию
				)

func refresh_cell(cell: MaterialCell):
	# Полное обновление состояния ячейки
	refresh_cell_neighbors(cell)
	refresh_cell_borders(cell)
	refresh_cell_visuals(cell)
	cell.refreshed.emit(self)

func refresh_cell_neighbors(cell: MaterialCell):
	# Обновление информации о соседних ячейках
	var x = cell.get_x()
	var y = cell.get_y()
	
	cell.left = cells_positions.get(MaterialCell.hash_position(x - 1, y))
	cell.right = cells_positions.get(MaterialCell.hash_position(x + 1, y))
	cell.top = cells_positions.get(MaterialCell.hash_position(x, y - 1))
	cell.bottom = cells_positions.get(MaterialCell.hash_position(x, y + 1))
	
	# Проверка валидности ссылок
	if cell.left and !is_instance_valid(cell.left): cell.left = null
	if cell.right and !is_instance_valid(cell.right): cell.right = null
	if cell.top and !is_instance_valid(cell.top): cell.top = null
	if cell.bottom and !is_instance_valid(cell.bottom): cell.bottom = null

func refresh_cell_borders(cell: MaterialCell):
	# Обновление информации о границах
	if not cell.check_borders: return
	
	cell.border_top = not cell.top and _is_map_cell_empty(cell.get_x(), cell.get_y() - 1)
	cell.border_bottom = not cell.bottom and _is_map_cell_empty(cell.get_x(), cell.get_y() + 1)
	cell.border_left = not cell.left and _is_map_cell_empty(cell.get_x() - 1, cell.get_y())
	cell.border_right = not cell.right and _is_map_cell_empty(cell.get_x() + 1, cell.get_y())

func refresh_cell_visuals(cell: MaterialCell):
	# Обновление визуального представления
	var qx = cell.cell_x * quadrant_size
	var qy = cell.cell_y * quadrant_size
	var rx = qx % main_map.rendering_quadrant_size
	var ry = qy % main_map.rendering_quadrant_size
	var xx = floor(qx / float(main_map.rendering_quadrant_size))
	var yy = floor(qy / float(main_map.rendering_quadrant_size))
	var diff = main_map.rendering_quadrant_size - quadrant_size
	cell.position = main_map.map_to_local(Vector2(xx, yy)) - Vector2((diff/2.0) - rx, (diff/2.0) - ry)
	
	# Масштабирование по количеству материала
	var scale = min(cell.amount, 1.0)
	cell.sprite.scale.y = scale
	cell.sprite.position.y = (1.0 - scale) * quadrant_size / 2.0
	
	# Обновление частиц
	if cell.particles:
		cell.particles.emitting = (cell.amount > cell.material_type.flow_threshold) and (cell.current_state == MaterialCell.State.LIQUID or cell.current_state == MaterialCell.State.GAS)

func refresh_all():
	# Полное обновление всех ячеек
	for cell in cells:
		refresh_cell(cell)
#endregion

# ====================== ПУБЛИЧНОЕ API ======================
#region Публичное API
func start():
	# Запуск симуляции
	monitor_started = true

func stop():
	# Остановка симуляции
	monitor_started = false

func clear(stop_after: bool = true):
	# Очистка всех ячеек
	for i in range(cells.size() - 1, -1, -1):
		_destroy_cell(cells[i])
	if stop_after: stop()

func add_material(x: int, y: int, amount: int, material: MaterialType):
	# Добавление материала в указанную позицию
	if x < -10000 || x > 10000 || y < -10000 || y > 10000:
		push_error("Invalid coordinates: ", x, ", ", y)
		return
	if not _is_map_cell_empty(x, y) or amount <= 0: 
		return
	
	var cell = get_cell_by_position(x, y)
	if not cell:
		cell = _create_cell(x, y, amount, material)
		cells.append(cell)
		cells_positions[MaterialCell.hash_position(x, y)] = cell
	else:
		cell.new_amount += amount
		updated_cells.append(cell)
	
	start()

func remove_material(x: int, y: int, amount: float):
	# Удаление материала из указанной позиции
	var cell = get_cell_by_position(x, y)
	if cell:
		cell.new_amount = max(cell.new_amount - amount, 0)
		updated_cells.append(cell)
		start()

func set_material(x: int, y: int, amount: float, material: MaterialType):
	# Установка материала в указанную позицию
	if not _is_map_cell_empty(x, y) or amount < 0: 
		return
	
	var cell = get_cell_by_position(x, y)
	if not cell:
		add_material(x, y, amount, material)
	else:
		cell.material_type = material
		cell.new_amount = amount
		updated_cells.append(cell)
		start()

func get_material(x: int, y: int) -> float:
	# Получение количества материала в позиции
	var cell = get_cell_by_position(x, y)
	return cell.amount if cell else 0.0

func get_material_type(x: int, y: int) -> MaterialType:
	# Получение типа материала в позиции
	var cell = get_cell_by_position(x, y)
	return cell.material_type if cell else null

func apply_force(area: Rect2, force: Vector2):
	# Применение силы к области
	for cell in cells:
		if area.has_point(Vector2(cell.get_x(), cell.get_y())):
			cell.apply_force(force)
			updated_cells.append(cell)

func set_temperature(area: Rect2, temperature: float):
	# Установка температуры в области
	for cell in cells:
		if area.has_point(Vector2(cell.get_x(), cell.get_y())):
			cell.temperature = temperature
			updated_cells.append(cell)

func get_cell_by_position(x: int, y: int) -> MaterialCell:
	# Получение ячейки по координатам
	var uid = MaterialCell.hash_position(x, y)
	if cells_positions.has(uid):
		var cell = cells_positions[uid]
		# Проверка валидности объекта
		if is_instance_valid(cell):
			return cell
		else:
			# Удаление невалидной ссылки
			cells_positions.erase(uid)
	return null

func is_running() -> bool:
	# Проверка активности симуляции
	return monitor_started

func get_total_amount() -> float:
	# Получение общего количества материала
	return total_amount
#endregion
