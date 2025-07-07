###collision_map.gd
class_name CollisionMap
extends Resource

@export_node_path("TileMapLayer") var tile_map_path: NodePath
@export var one_way_collision: bool = false

var tile_map: TileMapLayer
