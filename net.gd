extends Node
# Autoload singleton named 'Net' on both client and server at /root/Net.

var peer: ENetMultiplayerPeer

# peer_id -> { uuid, user_no, offset_ms, rtt_ms, connected }
var peers: Dictionary = {}

var server_root: Node
var user_registry: UserRegistry
var queue_manager: Node
var match_manager: Node

func configure(_server_root:Node, _user_registry:UserRegistry, _queue_manager:Node, _match_manager:Node) -> void:
	server_root = _server_root
	user_registry = _user_registry
	queue_manager = _queue_manager
	match_manager = _match_manager

func start_server(port:int, max_clients:int) -> void:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_clients)
	if err != OK:
		push_error("Failed to create server: %s" % err)
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("AlphaDuel server listening on UDP %d" % port)

func _on_peer_connected(id:int) -> void:
	peers[id] = {"uuid":"", "user_no":0, "offset_ms":0.0, "rtt_ms":0.0, "connected":true}
	print("Peer connected: %d" % id)

func _on_peer_disconnected(id:int) -> void:
	print("Peer disconnected: %d" % id)
	if peers.has(id):
		peers[id]["connected"] = false
	if queue_manager:
		queue_manager.remove_if_queued(id)
	if match_manager:
		match_manager.handle_disconnect(id)

# ---- getters used by server match logic ----
func get_user_no(peer_id:int) -> int:
	if peers.has(peer_id):
		return int(peers[peer_id].get("user_no", 0))
	return 0

func get_offset_ms(peer_id:int) -> float:
	if peers.has(peer_id):
		return float(peers[peer_id].get("offset_ms", 0.0))
	return 0.0

func get_rtt_ms(peer_id:int) -> float:
	if peers.has(peer_id):
		return float(peers[peer_id].get("rtt_ms", 0.0))
	return 0.0

func now_ms() -> int:
	return int(Time.get_ticks_msec())

# ---- server -> client send helpers (RPC) ----
func send_queue_status(peer_id:int, in_queue:bool, queue_len:int) -> void:
	rpc_id(peer_id, "rpc_queue_status", in_queue, queue_len)

func send_match_found(peer_a:int, peer_b:int, match_id:int) -> void:
	var a_user := get_user_no(peer_a)
	var b_user := get_user_no(peer_b)
	rpc_id(peer_a, "rpc_match_found", match_id, a_user, b_user, now_ms())
	rpc_id(peer_b, "rpc_match_found", match_id, b_user, a_user, now_ms())

func send_phase_start(peer_id:int, match_id:int, phase:int, dur_ms:int, start_server_ms:int) -> void:
	rpc_id(peer_id, "rpc_phase_start", match_id, phase, dur_ms, start_server_ms)

func send_letter_spawn(peer_id:int, payload:Dictionary) -> void:
	rpc_id(peer_id, "rpc_letter_spawn", payload)

func send_claim_result(peer_id:int, payload:Dictionary) -> void:
	rpc_id(peer_id, "rpc_claim_result", payload)

func send_match_result(peer_id:int, payload:Dictionary) -> void:
	rpc_id(peer_id, "rpc_match_result", payload)

# ---- RPC endpoints called by clients ----

@rpc("any_peer", "reliable")
func rpc_hello(install_uuid:String, client_version:String) -> void:
	var pid := multiplayer.get_remote_sender_id()
	var user_no := user_registry.get_or_assign_user_no(install_uuid)
	if not peers.has(pid):
		peers[pid] = {"uuid":"", "user_no":0, "offset_ms":0.0, "rtt_ms":0.0, "connected":true}
	peers[pid]["uuid"] = install_uuid
	peers[pid]["user_no"] = user_no
	rpc_id(pid, "rpc_hello_ok", user_no, now_ms())
	if server_root and server_root.has_method("log_event"):
		server_root.log_event({"type":"hello","peer_id":pid,"user_no":user_no,"uuid":install_uuid,"client_version":client_version,"server_ms":now_ms()})

@rpc("any_peer", "unreliable")
func rpc_ping(t0_client_ms:int) -> void:
	var pid := multiplayer.get_remote_sender_id()
	rpc_id(pid, "rpc_pong", t0_client_ms, now_ms())

@rpc("any_peer", "unreliable")
func rpc_time_sync_report(offset_ms:float, rtt_ms:float) -> void:
	var pid := multiplayer.get_remote_sender_id()
	if not peers.has(pid):
		return
	peers[pid]["offset_ms"] = offset_ms
	peers[pid]["rtt_ms"] = rtt_ms

@rpc("any_peer", "reliable")
func rpc_join_queue() -> void:
	var pid := multiplayer.get_remote_sender_id()
	queue_manager.join_queue(pid)

@rpc("any_peer", "reliable")
func rpc_leave_queue() -> void:
	var pid := multiplayer.get_remote_sender_id()
	queue_manager.leave_queue(pid)

@rpc("any_peer", "reliable")
func rpc_claim_request(payload:Dictionary) -> void:
	var pid := multiplayer.get_remote_sender_id()
	match_manager.route_claim(pid, payload)

@rpc("any_peer", "reliable")
func rpc_word_submit(payload:Dictionary) -> void:
	var pid := multiplayer.get_remote_sender_id()
	match_manager.route_word_submit(pid, payload)
