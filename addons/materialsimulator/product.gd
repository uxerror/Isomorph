###product.gd
class_name Product
extends Resource

# ====================== ОСНОВНЫЕ СВОЙСТВА ПРОДУКТА ======================
#region Основные свойства продукта
@export var material: MaterialType  # Тип материала, образующийся в результате реакции
@export var amount_factor: float = 1.0  # Коэффициент количества получаемого продукта
@export var temperature_change: float = 0.0  # Изменение температуры при образовании продукта
#endregion
