extends Bulletin

var prompt_text := ""

func initialize(prompt) -> void:
	prompt_text = prompt if prompt is String else ""
	# initialize() is called before the bulletin is added to the tree on creation,
	# and again on every refresh once it is already in it. Only the second case can
	# touch the Label.
	if is_node_ready():
		$Label.text = prompt_text

func _ready() -> void:
	$Label.text = prompt_text
