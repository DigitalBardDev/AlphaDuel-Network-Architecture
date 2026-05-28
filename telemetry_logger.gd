extends Node

var base_dir := "user://logs"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(base_dir)

func open_match_log(match_id:int) -> FileAccess:
	var ts := Time.get_unix_time_from_system()
	var path := "%s/match_%d_%d.jsonl" % [base_dir, match_id, ts]
	return FileAccess.open(path, FileAccess.WRITE)

func write_line(f: FileAccess, obj: Dictionary) -> void:
	f.store_string(JSON.stringify(obj) + "\n")
	f.flush()
