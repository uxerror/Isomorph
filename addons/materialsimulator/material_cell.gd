class_name MaterialCell
extends Node2D

# ====================== СОСТОЯНИЯ И СИГНАЛЫ ======================
#region Состояния и сигналы
enum State {SOLID, LIQUID, GAS, PLASMA}

# Сигналы жизненного цикла
signal created(server)
signal changed(server)
signal destroyed(server)
signal refreshed(server)
signal state_changed(old_state, new_state)
signal reaction_occurred(reactant1, reactant2, product_type, product_amount)
#endregion

# ====================== ОСНОВНЫЕ СВОЙСТВА ======================
#region Основные свойства
# Координаты ячейки в сетке симуляции
var cell_x: int
var cell_y: int

# Аккумуляторы потоков (x:left, y:right, z:top, w:bottom)
var flow_accumulator: Vector4 = Vector4.ZERO
var gravity_accumulator: float = 0.0

# Физические свойства
@export var material_type: MaterialType
var amount: float
var new_amount: float
var temperature: float = 20.0
var pressure: float = 1.0
var velocity: Vector2 = Vector2.ZERO
var current_state: int = State.SOLID
var lifetime: float = 0.0
var charge: float = 0.0

# Настройки отображения
var check_borders: bool = true
var snap_pixel: bool = true
var opacity_is_amount: bool = true
var max_opacity: float = 1.0
var min_opacity: float = 0.2

# Состояние ячейки
var iteration: int = 0
var falls: int = 0
var is_burning: bool = false
var last_update_time: float = 0.0
var bottom_has_flow: bool = false
var floor_can_absorb: bool = true
var decay_timer: float = 0.0
var growth_timer: float = 0.0
#endregion

# ====================== СОСЕДИ И ГРАНИЦЫ ======================
#region Соседи и границы
# Соседние ячейки
var left: MaterialCell = null
var right: MaterialCell = null
var top: MaterialCell = null
var bottom: MaterialCell = null

# Флаги границ
var border_top: bool = false
var border_bottom: bool = false
var border_left: bool = false
var border_right: bool = false
#endregion

# ====================== ВИЗУАЛЬНЫЕ ЭЛЕМЕНТЫ ======================
#region Визуальные элементы
@export var sprite: Sprite2D
@export var particles: GPUParticles2D
#endregion

# ====================== ИНИЦИАЛИЗАЦИЯ И НАСТРОЙКА ======================
#region Инициализация и настройка
func config(x: int, y: int, amount: int, _material: MaterialType, server: Node):
	"""Инициализация ячейки с заданными параметрами"""
	# Установка координат и базовых свойств
	self.cell_x = x
	self.cell_y = y
	position = Vector2i(x, y)
	self.amount = amount
	self.new_amount = amount
	self.material_type = _material
	last_update_time = Time.get_ticks_msec()
	
	# Настройка визуальных элементов
	if material_type.texture:
		sprite.texture = material_type.texture
	sprite.modulate = material_type.color
	
	# Настройка частиц
	if material_type.particle_effect:
		particles.emitting = false
	
	# Определение начального состояния
	current_state = material_type.get_state(temperature, pressure)
	
	# Настройка биологических свойств
	if material_type.is_biological:
		lifetime = material_type.life_span
	
	# Оповещение о создании
	created.emit(server)

func reset_neighbors():
	"""Сброс ссылок на соседние ячейки"""
	left = null
	right = null
	top = null
	bottom = null
#endregion

# ====================== СЛУЖЕБНЫЕ МЕТОДЫ ======================
#region Служебные методы
func get_x() -> int: 
	"""Получение координаты X в сетке симуляции"""
	return cell_x

func get_y() -> int: 
	"""Получение координаты Y в сетке симуляции"""
	return cell_y

static func hash_position(x: int, y: int) -> int:
	"""Генерация уникального хэша для позиции"""
	return (y << 16) | (x & 0xFFFF)
#endregion

# ====================== ОБНОВЛЕНИЕ СОСТОЯНИЯ ======================
#region Обновление состояния
func update_state(delta: float, world_temperature: float, world_pressure: float):
	"""Обновление физического состояния ячейки"""
	# Обновление таймеров
	decay_timer += delta
	growth_timer += delta
	
	# Расчет эффективного давления
	var effective_pressure = pressure + world_pressure
	
	# Стабилизация температуры к мировому значению
	temperature = lerp(temperature, world_temperature, 0.1 * delta)
	
	# Проверка изменения состояния
	var new_state = material_type.get_state(temperature, effective_pressure)
	if new_state != current_state:
		handle_state_change(new_state)
	
	# Обработка биологических свойств
	if material_type.is_biological:
		# Распад материала
		if decay_timer > 1.0:
			new_amount -= material_type.decay_rate * amount
			decay_timer = 0
			
		# Рост материала
		if growth_timer > 1.0:
			new_amount += material_type.growth_rate * amount
			growth_timer = 0
			
		# Обработка срока жизни
		if lifetime > 0:
			lifetime -= delta
			if lifetime <= 0:
				new_amount = 0
	
	# Проверка возгорания
	if material_type.is_flammable and temperature > material_type.autoignition_temp:
		is_burning = true
		
	# Обработка горения
	if is_burning:
		new_amount -= material_type.burn_rate * delta
		temperature += material_type.burn_rate * 50.0
	
	last_update_time = Time.get_ticks_msec()

func handle_state_change(new_state: int):
	"""Обработка изменения состояния материала"""
	var old_state = current_state
	current_state = new_state
	
	# Специальные действия при смене состояния
	match new_state:
		State.SOLID:
			# Сброс скорости для твердых материалов
			velocity = Vector2.ZERO
		State.LIQUID:
			# Дополнительные действия для жидкостей
			pass
		State.GAS:
			# Дополнительные действия для газов
			pass
	
	# Оповещение о смене состояния
	emit_signal("state_changed", old_state, new_state)
#endregion

# ====================== ФИЗИЧЕСКИЕ ВЗАИМОДЕЙСТВИЯ ======================
#region Физические взаимодействия
func apply_force(force: Vector2):
	"""Применение силы к ячейке с учетом трения"""
	velocity += force * (1.0 - material_type.friction)

func apply_reaction(other: MaterialCell, reaction: Reaction):
	"""Обработка химической реакции с другой ячейкой"""
	# Определение количества материала для реакции
	var reaction_amount = min(amount, other.amount, reaction.min_amount)
	
	# Уменьшение материала в обеих ячейках
	new_amount -= reaction_amount
	other.new_amount -= reaction_amount
	
	# Создание продуктов реакции
	for product in reaction.products:
		var product_amount = reaction_amount * product.amount_factor
		emit_signal("reaction_occurred", self, other, product.material, product_amount)
	
	# Нагрев ячеек от реакции
	temperature += reaction.reaction_rate * 10
	other.temperature += reaction.reaction_rate * 10
#endregion
