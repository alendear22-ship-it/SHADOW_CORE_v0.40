extends Node
class_name TargetingHelper

static func nearest_node(origin: Vector2, nodes: Array, max_distance: float) -> Node2D:
    var best: Node2D = null
    var best_dist_sq: float = max_distance * max_distance
    for node in nodes:
        var node2d: Node2D = node as Node2D
        if node2d == null:
            continue
        var dist_sq: float = origin.distance_squared_to(node2d.global_position)
        if dist_sq < best_dist_sq:
            best = node2d
            best_dist_sq = dist_sq
    return best
