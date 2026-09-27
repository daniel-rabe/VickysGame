extends RayCast3D

# The prompt text currently on screen, "" when none is. Driving the bulletin from
# the wanted text rather than from which node is under the crosshair fixes two
# things a plain is_hitting flag got wrong - panning straight from one interactable
# to another never crossed an empty frame, so the first one's prompt stayed up, and
# a ray hitting something that was not an Interactable stranded it too - without
# walking into a third: a freed node compares equal to null in GDScript, so
# tracking the node itself would miss the moment it is picked up and freed.
var shown_prompt := ""

func check_interaction() -> void:
	var interactable: Interactable = null
	if is_colliding():
		interactable = get_collider() as Interactable

	var wanted := interactable.prompt if interactable != null else ""
	if wanted != shown_prompt:
		shown_prompt = wanted
		if wanted.is_empty():
			EventSystem.BUL_destroy_bulletin.emit(BulletinConfig.Keys.InteractionPrompt)
		else:
			EventSystem.BUL_create_bulletin.emit(
				BulletinConfig.Keys.InteractionPrompt,
				wanted
			)

	if interactable != null and Input.is_action_just_pressed("interact"):
		interactable.start_interaction()
