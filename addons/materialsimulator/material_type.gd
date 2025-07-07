###material_type.gd
class_name MaterialType
extends Resource

# ====================== СОСТОЯНИЯ И БАЗОВЫЕ СВОЙСТВА ======================
#region Состояния и базовые свойства
enum State {SOLID, LIQUID, GAS, PLASMA}

@export var name: String = "Material"
@export var base_density: float = 1.0
@export var viscosity: float = 0.1
@export var friction: float = 0.1
@export var elasticity: float = 0.0
@export var compressibility: float = 0.0
@export_range(0, 1) var stability: float = 0.9
#endregion

# ====================== ФИЗИЧЕСКИЕ СВОЙСТВА ======================
#region Физические свойства
@export var max_flow: float = 1.0
@export var min_flow: float = 0.001
@export var flow_threshold: float = 0.01
@export var lateral_flow_factor: float = 0.5
#endregion

# ====================== ТЕРМИЧЕСКИЕ СВОЙСТВА ======================
#region Термические свойства
@export var melting_point: float = 0.0
@export var boiling_point: float = 100.0
@export var freezing_point: float = 0.0
@export var condensation_point: float = 100.0
@export var pressure_sensitivity: float = 0.0
@export var ignition_point: float = 600.0

@export var thermal_conductivity: float = 0.0
@export var thermal_expansion: float = 0.0
@export var specific_heat: float = 1.0
#endregion

# ====================== ХИМИЧЕСКИЕ СВОЙСТВА ======================
#region Химические свойства
@export var reactivity: Array[Reaction] = []
@export var is_flammable: bool = false
@export var autoignition_temp: float = 1000.0
@export var burn_rate: float = 0.0
#endregion

# ====================== ЭЛЕКТРОМАГНИТНЫЕ СВОЙСТВА ======================
#region Электромагнитные свойства
@export var electrical_resistance: float = 1.0
@export var magnetic_permeability: float = 0.0
@export var is_conductor: bool = false
#endregion

# ====================== БИОЛОГИЧЕСКИЕ СВОЙСТВА ======================
#region Биологические свойства
@export var is_biological: bool = false
@export var decay_rate: float = 0.0
@export var growth_rate: float = 0.0
@export var life_span: float = 0.0
#endregion

# ====================== ВИЗУАЛЬНЫЕ И ЗВУКОВЫЕ СВОЙСТВА ======================
#region Визуальные и звуковые свойства
@export var color: Color = Color.WHITE
@export var texture: Texture2D
@export var particle_effect: PackedScene
@export var sound_effects: Dictionary = {
	"flow": "",
	"impact": "",
	"destroy": ""
}
#endregion

# ====================== МЕТОДЫ РАСЧЕТА ======================
#region Методы расчета
func get_state(temperature: float, pressure: float) -> State:
	"""Определение состояния материала на основе температуры и давления"""
	# Корректировка точек перехода с учетом давления
	var adjusted_melting = melting_point + (pressure * pressure_sensitivity)
	var adjusted_boiling = boiling_point + (pressure * pressure_sensitivity)
	
	# Определение состояния
	if temperature < adjusted_melting:
		return State.SOLID
	elif temperature < adjusted_boiling:
		return State.LIQUID
	else:
		return State.GAS

func get_density(temperature: float) -> float:
	"""Расчет плотности с учетом теплового расширения"""
	return base_density / (1.0 + thermal_expansion * (temperature - 20.0))

func get_flow_factor(amount: float, state: State) -> float:
	"""Расчет фактора текучести материала"""
	var factor = 1.0
	match state:
		State.SOLID: factor = 0.01
		State.LIQUID: factor = 1.0 - viscosity
		State.GAS: factor = 2.0 - viscosity
	
	# Ограничение значения в допустимых пределах
	return clamp((amount - flow_threshold) * factor, 0.0, max_flow)

func check_reactions(other_material: MaterialType) -> Reaction:
	"""Проверка возможных реакций с другим материалом"""
	for reaction in reactivity:
		if reaction.reacts_with == other_material.name:
			return reaction
	return null
#endregion
