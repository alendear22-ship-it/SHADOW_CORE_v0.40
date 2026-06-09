extends Area2D
class_name HurtboxComponent

signal hurtbox_hit(payload: DamagePayload)

func receive_hit(payload: DamagePayload) -> void:
    hurtbox_hit.emit(payload)
