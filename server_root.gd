extends Node

@export var listen_port := 9000
@export var max_clients := 64

var user_registry: UserRegistry

@onready var queue_manager := $QueueManager
@onready var match_manager := $MatchManager
@onready var telemetry := $TelemetryLogger

func _ready() -> void:
	user_registry = UserRegistry.new()
	user_registry.load_from_disk("user://user_registry.json")

	# allow CLI override: --port=9000
	for a in OS.get_cmdline_args():
		if a.begins_with("--port="):
			listen_port = int(a.substr("--port=".length()))

	queue_manager.init(match_manager)
	match_manager.init(telemetry)

	Net.configure(self, user_registry, queue_manager, match_manager)
	Net.start_server(listen_port, max_clients)

func _exit_tree() -> void:
	user_registry.save_to_disk("user://user_registry.json")

func log_event(obj:Dictionary) -> void:
	# simple server-wide log hook if needed; telemetry is per match
	print(JSON.stringify(obj))
