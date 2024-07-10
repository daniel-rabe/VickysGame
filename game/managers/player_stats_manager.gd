extends Node

const MAX_ENERGY = 100.0
const MAX_HEALTH = 100.0

var current_energy = MAX_ENERGY
var current_health = MAX_HEALTH

func change_energy(delta: float) -> void:
	current_energy += delta
	if current_energy < 0:
		current_health += current_energy
	EventSystem.PLA_energy_updated.emit(
		MAX_ENERGY,
		clamp(current_energy, 0, MAX_ENERGY)
	)

func change_health(delta: float) -> void:
	current_health = clamp(current_health + delta, 0, MAX_HEALTH)
	EventSystem.PLA_health_updated.emit(
		MAX_HEALTH, current_health
	)

func _enter_tree() -> void:
	EventSystem.PLA_change_energy.connect(change_energy)
	EventSystem.PLA_change_health.connect(change_health)
