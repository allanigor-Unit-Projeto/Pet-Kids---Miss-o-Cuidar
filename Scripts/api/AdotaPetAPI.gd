## AdotaPetAPI.gd
## Singleton Autoload: Integração com a API Adota Pet da Prefeitura do Recife (RF004, RN008).
## Sincroniza dados de animais a cada 24h e confirma disponibilidade de apadrinhamento.
extends Node

# ──────────────────────────────────────────────
# Configuração da API
# ──────────────────────────────────────────────
const BASE_URL := "https://adotapet.recife.pe.gov.br/api/v1"
const TIMEOUT_SECONDS := 10.0
const SYNC_INTERVAL_HOURS := 24      # RN008: sincronização mínima 24h
const MAX_LATENCY_MS := 3000         # RNF-P008: máx 3s em 4G/Wi-Fi

# ──────────────────────────────────────────────
# Sinais
# ──────────────────────────────────────────────
signal pets_loaded(pets: Array)
signal pet_sponsored(pet_data: Dictionary)
signal sponsorship_confirmed(success: bool, message: String)
signal api_error(code: int, message: String)

# ──────────────────────────────────────────────
# Estado interno
# ──────────────────────────────────────────────
var _api_key: String = ""
var _last_sync_timestamp: int = 0
var _cached_pets: Array = []
var _http_request: HTTPRequest = null

# ──────────────────────────────────────────────
func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = TIMEOUT_SECONDS
	add_child(_http_request)
	_api_key = _load_api_key()

func _load_api_key() -> String:
	# Em produção, carregar de variável de ambiente ou cofre seguro
	return OS.get_environment("ADOTA_PET_API_KEY")

# ──────────────────────────────────────────────
# Listagem de animais disponíveis
# ──────────────────────────────────────────────
func fetch_available_pets(
		species: String = "",
		page: int = 1,
		per_page: int = 20
) -> void:
	if GameManager.is_offline:
		# Retorna cache local (RNF-P009)
		pets_loaded.emit(_cached_pets)
		return

	# Verifica se cache ainda é válido (RN008)
	var now := Time.get_unix_time_from_system()
	var hours_since_sync := (now - _last_sync_timestamp) / 3600.0
	if hours_since_sync < SYNC_INTERVAL_HOURS and not _cached_pets.is_empty():
		pets_loaded.emit(_cached_pets)
		return

	var url := "%s/pets?page=%d&per_page=%d" % [BASE_URL, page, per_page]
	if species != "":
		url += "&species=%s" % species

	var headers := _build_headers()
	var req_start := Time.get_ticks_msec()

	var err := _http_request.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		_handle_offline_fallback("fetch_available_pets", {})
		return

	# Aguarda resposta assíncrona
	var result: Array = await _http_request.request_completed
	var latency := Time.get_ticks_msec() - req_start
	if latency > MAX_LATENCY_MS:
		push_warning("[AdotaPetAPI] Latência alta: %dms" % latency)

	_process_pets_response(result)

func _process_pets_response(result: Array) -> void:
	var response_code: int = result[1]
	var body: PackedByteArray = result[3]

	if response_code != 200:
		api_error.emit(response_code, "Erro ao buscar pets: %d" % response_code)
		pets_loaded.emit(_cached_pets)   # fallback para cache
		return

	var json := JSON.new()
	var parse_err := json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		api_error.emit(-1, "Erro ao parsear resposta da API")
		return

	var data = json.data
	var pets: Array = data.get("pets", data if data is Array else [])

	_cached_pets = pets.map(func(p): return _normalize_pet(p))
	_last_sync_timestamp = Time.get_unix_time_from_system()

	# Persiste no banco local (modo offline)
	for pet in _cached_pets:
		DatabaseManager.queue_offline_event("pet_cache", pet)

	pets_loaded.emit(_cached_pets)

func _normalize_pet(raw: Dictionary) -> Dictionary:
	return {
		"id": str(raw.get("id", raw.get("codigo", ""))),
		"name": raw.get("nome", raw.get("name", "Sem nome")),
		"species": raw.get("especie", raw.get("species", "dog")),
		"breed": raw.get("raca", raw.get("breed", "SRD")),
		"age_months": int(raw.get("idade_meses", raw.get("age_months", 0))),
		"gender": raw.get("sexo", raw.get("gender", "unknown")),
		"description": raw.get("descricao", raw.get("description", "")),
		"story": raw.get("historia", raw.get("story", "")),
		"shelter_id": str(raw.get("abrigo_id", raw.get("shelter_id", ""))),
		"photos": raw.get("fotos", raw.get("photos", [])),
		"available": bool(raw.get("disponivel", raw.get("available", true))),
		"health_status": raw.get("status_saude", "healthy"),
		"vaccinated": bool(raw.get("vacinado", false)),
		"castrated": bool(raw.get("castrado", false))
	}

# ──────────────────────────────────────────────
# Detalhes de um pet específico
# ──────────────────────────────────────────────
func fetch_pet_details(pet_id: String) -> void:
	if GameManager.is_offline:
		var cached := _cached_pets.filter(func(p): return p.get("id") == pet_id)
		if not cached.is_empty():
			pets_loaded.emit([cached[0]])
		return

	var url := "%s/pets/%s" % [BASE_URL, pet_id]
	var err := _http_request.request(url, _build_headers(), HTTPClient.METHOD_GET)
	if err != OK:
		_handle_offline_fallback("fetch_pet_details", {"pet_id": pet_id})
		return

	var result: Array = await _http_request.request_completed
	if result[1] == 200:
		var json := JSON.new()
		json.parse(result[3].get_string_from_utf8())
		pets_loaded.emit([_normalize_pet(json.data)])
	else:
		api_error.emit(result[1], "Pet não encontrado")

# ──────────────────────────────────────────────
# Confirmar disponibilidade para apadrinhamento (UC002)
# ──────────────────────────────────────────────
func confirm_sponsorship_availability(pet_id: String, user_id: String) -> void:
	if GameManager.is_offline:
		# Adia operação para quando houver conexão (RNF-P009)
		DatabaseManager.queue_offline_event("confirm_sponsorship", {
			"pet_id": pet_id, "user_id": user_id
		})
		sponsorship_confirmed.emit(true, "Solicitação enfileirada (offline)")
		return

	var url := "%s/sponsorship/confirm" % BASE_URL
	var body := JSON.stringify({"pet_id": pet_id, "user_id": user_id})
	var headers := _build_headers()
	headers.append("Content-Type: application/json")

	var err := _http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_handle_offline_fallback("confirm_sponsorship", {"pet_id": pet_id, "user_id": user_id})
		return

	var result: Array = await _http_request.request_completed
	if result[1] == 200:
		var json := JSON.new()
		json.parse(result[3].get_string_from_utf8())
		var data: Dictionary = json.data
		sponsorship_confirmed.emit(
			data.get("available", false),
			data.get("message", "")
		)
	elif result[1] == 409:
		# Animal já foi adotado (RN002)
		sponsorship_confirmed.emit(false, "Este animal já foi adotado. 🎉")
	else:
		api_error.emit(result[1], "Erro ao confirmar apadrinhamento")

# ──────────────────────────────────────────────
# Encerrar apadrinhamento no servidor
# ──────────────────────────────────────────────
func end_sponsorship_remote(pet_id: String, user_id: String, reason: String) -> void:
	if GameManager.is_offline:
		DatabaseManager.queue_offline_event("end_sponsorship", {
			"pet_id": pet_id, "user_id": user_id, "reason": reason
		})
		return

	var url := "%s/sponsorship/end" % BASE_URL
	var body := JSON.stringify({"pet_id": pet_id, "user_id": user_id, "reason": reason})
	var headers := _build_headers()
	headers.append("Content-Type: application/json")
	_http_request.request(url, headers, HTTPClient.METHOD_POST, body)

# ──────────────────────────────────────────────
# Fallback offline
# ──────────────────────────────────────────────
func _handle_offline_fallback(operation: String, payload: Dictionary) -> void:
	GameManager.is_offline = true
	DatabaseManager.queue_offline_event(operation, payload)
	push_warning("[AdotaPetAPI] Offline. Operação '%s' enfileirada." % operation)

# ──────────────────────────────────────────────
# Headers padrão (Bearer Token — RNF-S001)
# ──────────────────────────────────────────────
func _build_headers() -> PackedStringArray:
	return PackedStringArray([
		"Authorization: Bearer %s" % _api_key,
		"Accept: application/json",
		"X-App-Version: %s" % GameManager.VERSION,
		"X-Platform: %s" % GameManager.platform
	])

# ──────────────────────────────────────────────
# Getters de cache
# ──────────────────────────────────────────────
func get_cached_pets() -> Array:
	return _cached_pets

func get_cached_pet(pet_id: String) -> Dictionary:
	for p in _cached_pets:
		if p.get("id") == pet_id:
			return p
	return {}
