extends Panel
class_name BossCard

func setup(card: Dictionary) -> void:
    tooltip_text = card.get("name", "") + " — " + card.get("threat", "")
