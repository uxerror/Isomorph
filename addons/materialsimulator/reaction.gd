class_name Reaction
extends Resource

# ====================== ОСНОВНЫЕ СВОЙСТВА РЕАКЦИИ ======================
#region Основные свойства реакции
@export var reacts_with: String  # Название материала, с которым происходит реакция
@export var min_temperature: float = 20.0  # Минимальная температура для начала реакции
@export var min_amount: float = 0.1  # Минимальное количество материала для реакции
@export var reaction_rate: float = 1.0  # Скорость протекания реакции
#endregion

# ====================== ПРОДУКТЫ РЕАКЦИИ ======================
#region Продукты реакции
@export var products: Array[Product] = []  # Список продуктов, образующихся в результате реакции
#endregion
