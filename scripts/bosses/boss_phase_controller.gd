extends Node
class_name BossPhaseController

var current_phase: int = 1

func evaluate_phase(health_ratio: float) -> int:
    if health_ratio <= 0.30:
        current_phase = 3
    elif health_ratio <= 0.65:
        current_phase = 2
    else:
        current_phase = 1
    return current_phase
