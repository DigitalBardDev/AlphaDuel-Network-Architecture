extends Node

var telemetry: Node
var next_match_id := 1001

var peer_to_match: Dictionary = {} # peer_id -> Match node

func init(tel: Node) -> void:
	telemetry = tel

func create_match(peer_a:int, peer_b:int) -> void:
	var match_id := next_match_id
	next_match_id += 1

	var m := preload("res://scripts/match.gd").new()
	add_child(m)
	m.init(match_id, peer_a, peer_b, telemetry)

	peer_to_match[peer_a] = m
	peer_to_match[peer_b] = m

	Net.send_match_found(peer_a, peer_b, match_id)

func handle_disconnect(peer_id:int) -> void:
	if not peer_to_match.has(peer_id):
		return
	var m: Node = peer_to_match[peer_id]
	m.on_peer_disconnected(peer_id)

func clear_peer(peer_id:int) -> void:
	peer_to_match.erase(peer_id)

func route_claim(peer_id:int, payload:Dictionary) -> void:
	if not peer_to_match.has(peer_id):
		return
	peer_to_match[peer_id].handle_claim(peer_id, payload)

func route_word_submit(peer_id:int, payload:Dictionary) -> void:
	if not peer_to_match.has(peer_id):
		return
	peer_to_match[peer_id].handle_word_submit(peer_id, payload)
