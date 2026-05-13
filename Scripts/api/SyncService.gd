## SyncService.gd
## Singleton Autoload: Sincronização de eventos offline com o servidor (RNF-P009).
## Enfileira operações sem conexão e sincroniza em background quando online.
extends Node

signal sync_completed(synced_count: int)
signal sync_failed(reason: String)

const SYNC_URL := "https://api.petkids.app/api/v1/sync"
const SYNC_INTERVAL := 30.0   # segundos entre tentativas automáticas

var _sync_timer: float = 0.0
var _is_syncing: bool = false
var _http: HTTPRequest = null

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	add_child(_http)
	# Monitora mudança de conectividade
	get_tree().connect("node_added", _on_node_added)

func _process(delta: float) -> void:
	if _is_syncing or GameManager.is_offline:
		return
	_sync_timer += delta
	if _sync_timer >= SYNC_INTERVAL:
		_sync_timer = 0.0
		sync_pending_events()

func _on_node_added(_node: Node) -> void:
	pass  # Placeholder para detecção de reconexão


# Sincronização principal

func sync_pending_events() -> void:
	var events := DatabaseManager.get_pending_offline_events()
	if events.is_empty():
		return
	if _is_syncing:
		return
	_is_syncing = true

	var payload := JSON.stringify({"events": events})
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % AuthService.get_access_token()
	])

	var err := _http.request(SYNC_URL, headers, HTTPClient.METHOD_POST, payload)
	if err != OK:
		_is_syncing = false
		GameManager.is_offline = true
		return

	var result: Array = await _http.request_completed
	_is_syncing = false

	if result[1] in [200, 207]:
		var ids := events.map(func(e): return e.get("id", -1))
		DatabaseManager.mark_events_synced(ids)
		GameManager.is_offline = false
		sync_completed.emit(events.size())
	else:
		sync_failed.emit("Falha na sincronização: HTTP %d" % result[1])


# Sincronização de progresso do jogador (RNF-PT004)

func sync_player_progress() -> void:
	if GameManager.is_offline or not AuthService.is_logged_in():
		return
	var payload := JSON.stringify({
		"user_id": GameManager.current_user.get("id", ""),
		"level": GameManager.player_level,
		"xp": GameManager.player_xp,
		"pet_coins": GameManager.pet_coins,
		"platform": GameManager.platform
	})
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % AuthService.get_access_token()
	])
	_http.request(
		"https://api.petkids.app/api/v1/player/sync",
		headers, HTTPClient.METHOD_PUT, payload
	)
	# Fire-and-forget; resultado não é crítico aqui
