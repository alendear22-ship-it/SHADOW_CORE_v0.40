extends Panel
class_name RoomCard

func setup(card_data: Dictionary) -> void:
    tooltip_text = JSON.stringify(card_data)
