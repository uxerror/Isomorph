@tool
extends EditorPlugin

func _enter_tree() -> void:
	add_custom_type("MaterialCell", "Node2D", preload("material_cell.gd"), preload("res://addons/materialsimulator/icons/icon.png"));
	add_custom_type("MaterialSimulationServer", "Node", preload("material_simulation_server.gd"), preload("res://addons/materialsimulator/icons/LiquidServer.svg"));
	add_custom_type("CollisionMap", "Resource", preload("collision_map.gd"), preload("res://addons/materialsimulator/icons/LiquidMap.svg"));

func _exit_tree():
	remove_custom_type("MaterialCell");
	remove_custom_type("MaterialSimulationServer");
	remove_custom_type("CollisionMap");
