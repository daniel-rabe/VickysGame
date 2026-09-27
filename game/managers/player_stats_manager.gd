extends Node

const MAX_ENERGY = 100.0
const MAX_HEALTH = 100.0

var current_energy: float = MAX_ENERGY
var current_health: float = MAX_HEALTH

func change_energy(delta: float) -> void:
	current_energy += delta
	# Clamp the stored value, not just the broadcast one. Leaving it unclamped
	# made the whole accumulated deficit bleed into health every single frame,
	# and let energy bank above MAX_ENERGY while the bar showed it full.
	var deficit := 0.0
	if current_energy < 0.0:
		deficit = current_energy
		current_energy = 0.0
	elif current_energy > MAX_ENERGY:
		current_energy = MAX_ENERGY

	EventSystem.PLA_energy_updated.emit(MAX_ENERGY, current_energy)

	# Route starvation damage through change_health so PLA_health_updated fires
	# and the health bar actually moves.
	if deficit < 0.0:
		change_health(deficit)

func change_health(delta: float) -> void:
	current_health = clamp(current_health + delta, 0, MAX_HEALTH)
	EventSystem.PLA_health_updated.emit(
		MAX_HEALTH, current_health
	)

func _enter_tree() -> void:
	EventSystem.PLA_change_energy.connect(change_energy)
	EventSystem.PLA_change_health.connect(change_health)
