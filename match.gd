extends Node

const CLAIM_MS := 60_000
const BUILD_MS := 30_000

# fairness controls
const CLAIM_EPSILON_MS := 35.0
const CLAIM_FINALIZE_WINDOW_MS := 85

var match_id: int
var peer_a: int
var peer_b: int

var telemetry: Node
var log_file: FileAccess

var wordlist := Wordlist.new() # optional; OFF by default

var phase := Protocol.Phase.LOBBY
var phase_ends_server_ms := 0

var next_letter_id := 1
var active_letters: Dictionary = {}  # letter_id -> {ch, spawn_server_ms, ttl_ms}
var claim_buffers: Dictionary = {}   # letter_id -> Array[attempt]
var resolved_claims: Dictionary = {} # letter_id -> winner_peer_id

var racks: Dictionary = {}           # peer_id -> Array[String]
var submitted: Dictionary = {}       # peer_id -> {word, score}

var letter_spawner: Node
var phase_timer: Timer

func init(mid:int, a:int, b:int, tel:Node) -> void:
	match_id = mid
	peer_a = a
	peer_b = b
	telemetry = tel

	racks[peer_a] = []
	racks[peer_b] = []
	submitted[peer_a] = {"word":"", "score":0}
	submitted[peer_b] = {"word":"", "score":0}

	log_file = telemetry.open_match_log(match_id)
	_log({"type":"match_created","server_ms":Net.now_ms(),"peers":[peer_a, peer_b]})

	letter_spawner = preload("res://scripts/letter_spawner.gd").new()
	add_child(letter_spawner)
	letter_spawner.spawned.connect(_on_spawner_event)

	phase_timer = Timer.new()
	phase_timer.one_shot = true
	add_child(phase_timer)
	phase_timer.timeout.connect(_on_phase_timeout)

	# Optional dictionary validation later:
	# wordlist.enabled = true
	# wordlist.load_from_file("res://data/wordlist.txt")

	_start_claim_phase()

func _exit_tree() -> void:
	if log_file:
		log_file.close()

func _log(obj:Dictionary) -> void:
	obj["match_id"] = match_id
	telemetry.write_line(log_file, obj)

func _broadcast_phase(phase_id:int, duration_ms:int, start_server_ms:int) -> void:
	Net.send_phase_start(peer_a, match_id, phase_id, duration_ms, start_server_ms)
	Net.send_phase_start(peer_b, match_id, phase_id, duration_ms, start_server_ms)

func _start_claim_phase() -> void:
	phase = Protocol.Phase.CLAIM
	var start_ms := Net.now_ms()
	phase_ends_server_ms = start_ms + CLAIM_MS
	_broadcast_phase(phase, CLAIM_MS, start_ms)
	_log({"type":"phase_start","phase":"claim","server_ms":start_ms,"duration_ms":CLAIM_MS})

	letter_spawner.start(match_id * 1337 + 17)

	phase_timer.wait_time = float(CLAIM_MS)/1000.0
	phase_timer.start()

func _start_build_phase() -> void:
	phase = Protocol.Phase.BUILD
	var start_ms := Net.now_ms()
	phase_ends_server_ms = start_ms + BUILD_MS
	_broadcast_phase(phase, BUILD_MS, start_ms)
	_log({"type":"phase_start","phase":"build","server_ms":start_ms,"duration_ms":BUILD_MS})

	letter_spawner.stop()
	active_letters.clear()
	claim_buffers.clear()

	phase_timer.wait_time = float(BUILD_MS)/1000.0
	phase_timer.start()

func _start_result_phase_and_end(reason:String) -> void:
	phase = Protocol.Phase.RESULT
	_log({"type":"phase_start","phase":"result","server_ms":Net.now_ms(),"reason":reason})

	var a_sub := submitted[peer_a]
	var b_sub := submitted[peer_b]

	var winner_peer := 0
	if reason == "disconnect":
		# winner is remaining connected peer if any
		var a_conn := bool(Net.peers.get(peer_a, {}).get("connected", false))
		var b_conn := bool(Net.peers.get(peer_b, {}).get("connected", false))
		if a_conn and not b_conn:
			winner_peer = peer_a
		elif b_conn and not a_conn:
			winner_peer = peer_b
	else:
		var a_score := int(a_sub["score"])
		var b_score := int(b_sub["score"])
		if a_score > b_score:
			winner_peer = peer_a
		elif b_score > a_score:
			winner_peer = peer_b
		else:
			winner_peer = 0

	var result := {
		"match_id": match_id,
		"reason": reason,
		"winner_peer_id": winner_peer,
		"p1": {"peer_id":peer_a, "user_no":Net.get_user_no(peer_a), "word":String(a_sub["word"]), "score":int(a_sub["score"])},
		"p2": {"peer_id":peer_b, "user_no":Net.get_user_no(peer_b), "word":String(b_sub["word"]), "score":int(b_sub["score"])}
	}

	Net.send_match_result(peer_a, result)
	Net.send_match_result(peer_b, result)

	_log({"type":"match_result","server_ms":Net.now_ms(),"result":result})
	_end()

func _end() -> void:
	# clear match manager mappings
	var mm := get_parent()
	while mm and not mm.has_method("clear_peer"):
		mm = mm.get_parent()
	if mm:
		mm.clear_peer(peer_a)
		mm.clear_peer(peer_b)
	queue_free()

func _on_phase_timeout() -> void:
	if phase == Protocol.Phase.CLAIM:
		_start_build_phase()
	elif phase == Protocol.Phase.BUILD:
		_start_result_phase_and_end("normal")

func _on_spawner_event(e:Dictionary) -> void:
	if phase != Protocol.Phase.CLAIM:
		return
	var letter_id := next_letter_id
	next_letter_id += 1

	var spawn_ms := Net.now_ms()
	var ttl_ms := int(e["ttl_ms"])
	var ch := String(e["ch"])
	active_letters[letter_id] = {"ch": ch, "spawn_server_ms": spawn_ms, "ttl_ms": ttl_ms}

	var payload := Protocol.letter_spawn_event(match_id, letter_id, ch, int(e["lane"]), spawn_ms, float(e["fall_speed"]), ttl_ms)

	Net.send_letter_spawn(peer_a, payload)
	Net.send_letter_spawn(peer_b, payload)

	_log({"type":"letter_spawn","server_ms":spawn_ms,"letter_id":letter_id,"ch":ch,"lane":int(e["lane"])})

# ---- disconnect handling ----
func on_peer_disconnected(peer_id:int) -> void:
	_log({"type":"disconnect","server_ms":Net.now_ms(),"peer_id":peer_id})
	_start_result_phase_and_end("disconnect")

# ---- routing from MatchManager ----
func handle_claim(peer_id:int, payload:Dictionary) -> void:
	if int(payload.get("match_id",-1)) != match_id:
		return
	if phase != Protocol.Phase.CLAIM:
		return
	var letter_id := int(payload.get("letter_id",-1))
	if not active_letters.has(letter_id):
		return
	if resolved_claims.has(letter_id):
		return

	var now_ms := Net.now_ms()
	var info := active_letters[letter_id]
	var spawn_ms := int(info["spawn_server_ms"])
	var ttl_ms := int(info["ttl_ms"])
	if now_ms > spawn_ms + ttl_ms:
		return

	var tap_client_ms := int(payload.get("tap_client_ms", 0))
	var tap_server_est := float(tap_client_ms) + Net.get_offset_ms(peer_id)

	var attempt := {
		"peer_id": peer_id,
		"tap_server_est": tap_server_est,
		"recv_server_ms": now_ms
	}

	if not claim_buffers.has(letter_id):
		claim_buffers[letter_id] = []
		# schedule finalize window
		var t := Timer.new()
		t.one_shot = true
		t.wait_time = float(CLAIM_FINALIZE_WINDOW_MS)/1000.0
		add_child(t)
		t.timeout.connect(func():
			_finalize_claim(letter_id)
			t.queue_free()
		)
		t.start()

	claim_buffers[letter_id].append(attempt)
	_log({"type":"claim_attempt","server_ms":now_ms,"letter_id":letter_id,"peer_id":peer_id,"tap_server_est":tap_server_est,"rtt_ms":Net.get_rtt_ms(peer_id)})

func _finalize_claim(letter_id:int) -> void:
	if resolved_claims.has(letter_id):
		return
	if not active_letters.has(letter_id):
		return
	if not claim_buffers.has(letter_id):
		return

	var attempts: Array = claim_buffers[letter_id]
	if attempts.is_empty():
		return

	attempts.sort_custom(func(a,b):
		var ta := float(a["tap_server_est"])
		var tb := float(b["tap_server_est"])
		if abs(ta - tb) <= CLAIM_EPSILON_MS:
			return int(a["recv_server_ms"]) < int(b["recv_server_ms"])
		return ta < tb
	)

	var winner_peer := int(attempts[0]["peer_id"])
	resolved_claims[letter_id] = winner_peer

	var ch := String(active_letters[letter_id]["ch"])
	racks[winner_peer].append(ch)

	var payload := Protocol.claim_result(match_id, letter_id, winner_peer, Net.get_user_no(winner_peer), ch, Net.now_ms())
	Net.send_claim_result(peer_a, payload)
	Net.send_claim_result(peer_b, payload)

	_log({"type":"claim_resolved","server_ms":Net.now_ms(),"letter_id":letter_id,"winner_peer_id":winner_peer,"ch":ch})

	active_letters.erase(letter_id)
	claim_buffers.erase(letter_id)

func handle_word_submit(peer_id:int, payload:Dictionary) -> void:
	if int(payload.get("match_id",-1)) != match_id:
		return
	if phase != Protocol.Phase.BUILD:
		return

	var raw_word := String(payload.get("word",""))
	var word := Scoring.sanitize_word(raw_word)

	var rack: Array[String] = racks.get(peer_id, [])
	if not Validation.can_form_from_rack(word, rack):
		submitted[peer_id] = {"word":"", "score":0}
		_log({"type":"word_rejected","server_ms":Net.now_ms(),"peer_id":peer_id,"word":word,"reason":"rack_mismatch"})
		return

	if not wordlist.is_valid(word):
		submitted[peer_id] = {"word":"", "score":0}
		_log({"type":"word_rejected","server_ms":Net.now_ms(),"peer_id":peer_id,"word":word,"reason":"not_in_dictionary"})
		return

	var score := Scoring.score_word(word)
	submitted[peer_id] = {"word":word, "score":score}
	_log({"type":"word_submit","server_ms":Net.now_ms(),"peer_id":peer_id,"word":word,"score":score,"rack":"".join(rack)})

	# end early if both submitted
	if String(submitted[peer_a]["word"]) != "" and String(submitted[peer_b]["word"]) != "":
		_start_result_phase_and_end("normal")
