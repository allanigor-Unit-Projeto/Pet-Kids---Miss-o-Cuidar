## AuthService.gd
## Singleton Autoload: Autenticação via email/senha, Google OAuth e Apple ID (RF001).
## JWT com expiração 24h/30d (RNF-S004). Conformidade LGPD para menores (RNF-S003).
extends Node

# ──────────────────────────────────────────────
const AUTH_URL := "https://api.petkids.app/api/v1/auth"
const TOKEN_EXPIRY_HOURS := 24
const REFRESH_EXPIRY_DAYS := 30
const MIN_AGE_GUARDIAN_REQUIRED := 13   # RN006

# ──────────────────────────────────────────────
signal login_success(user: Dictionary)
signal login_failed(reason: String)
signal logout_completed
signal registration_success(user: Dictionary)
signal registration_failed(reason: String)

# ──────────────────────────────────────────────
var _access_token: String = ""
var _refresh_token: String = ""
var _token_expiry: int = 0
var _http: HTTPRequest = null

# ──────────────────────────────────────────────
func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	add_child(_http)
	_restore_session()

# ──────────────────────────────────────────────
# Restaurar sessão salva
# ──────────────────────────────────────────────
func _restore_session() -> void:
	_access_token  = SaveSystem.load_value("access_token", "")
	_refresh_token = SaveSystem.load_value("refresh_token", "")
	_token_expiry  = SaveSystem.load_value("token_expiry", 0)

	if _access_token.is_empty():
		return

	if _is_token_expired():
		await _refresh_access_token()
	else:
		_restore_user_from_save()

func _restore_user_from_save() -> void:
	var user_id: String = SaveSystem.load_value("user_id", "")
	if user_id.is_empty():
		return
	GameManager.current_user = DatabaseManager.get_user(user_id)
	SaveSystem.load_player_progress()
	GameManager.claim_daily_login_reward()

# ──────────────────────────────────────────────
# Login via email/senha (RF001)
# ──────────────────────────────────────────────
func login_email(email: String, password: String) -> void:
	if email.is_empty() or password.is_empty():
		login_failed.emit("Preencha todos os campos.")
		return

	var body := JSON.stringify({"email": email, "password": password})
	var err := _http.request(
		AUTH_URL + "/login",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST, body
	)
	if err != OK:
		login_failed.emit("Sem conexão com o servidor.")
		return

	var result: Array = await _http.request_completed
	_process_auth_response(result)

# ──────────────────────────────────────────────
# Login via OAuth (Google / Apple) (RF001)
# ──────────────────────────────────────────────
func login_oauth(provider: String, oauth_token: String) -> void:
	var body := JSON.stringify({"provider": provider, "token": oauth_token})
	var err := _http.request(
		AUTH_URL + "/oauth",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST, body
	)
	if err != OK:
		login_failed.emit("Falha ao conectar com %s." % provider)
		return

	var result: Array = await _http.request_completed
	_process_auth_response(result)

# ──────────────────────────────────────────────
# Cadastro (RF002)
# ──────────────────────────────────────────────
func register(
		name: String,
		email: String,
		password: String,
		birth_date: String,
		user_type: String = "jogador"
) -> void:
	if name.is_empty() or email.is_empty() or password.is_empty():
		registration_failed.emit("Preencha todos os campos obrigatórios.")
		return

	# Verificação de menor de idade (RN006, RNF-S003)
	var age := _calculate_age(birth_date)
	var requires_guardian := age < MIN_AGE_GUARDIAN_REQUIRED

	var body := JSON.stringify({
		"name": name, "email": email, "password": password,
		"birth_date": birth_date, "user_type": user_type,
		"requires_guardian": requires_guardian,
		"parental_control": requires_guardian   # Controle parental ativo por padrão (RN006)
	})

	var err := _http.request(
		AUTH_URL + "/register",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST, body
	)
	if err != OK:
		registration_failed.emit("Sem conexão com o servidor.")
		return

	var result: Array = await _http.request_completed
	_process_registration_response(result, requires_guardian)

func _calculate_age(birth_date_str: String) -> int:
	# Formato esperado: YYYY-MM-DD
	if birth_date_str.length() < 4:
		return 99
	var year := int(birth_date_str.substr(0, 4))
	var current_year := Time.get_date_dict_from_system().get("year", 2026)
	return current_year - year

# ──────────────────────────────────────────────
# Processamento de respostas
# ──────────────────────────────────────────────
func _process_auth_response(result: Array) -> void:
	var code: int = result[1]
	if code != 200:
		var err_msg := _parse_error(result[3])
		login_failed.emit(err_msg)
		return

	var json := JSON.new()
	json.parse(result[3].get_string_from_utf8())
	var data: Dictionary = json.data

	_save_tokens(data)
	var user := _extract_user(data)
	GameManager.current_user = user
	DatabaseManager.save_user(user)
	SaveSystem.load_player_progress()
	GameManager.claim_daily_login_reward()
	login_success.emit(user)

func _process_registration_response(result: Array, requires_guardian: bool) -> void:
	var code: int = result[1]
	if code not in [200, 201]:
		var err_msg := _parse_error(result[3])
		registration_failed.emit(err_msg)
		return

	var json := JSON.new()
	json.parse(result[3].get_string_from_utf8())
	var data: Dictionary = json.data
	_save_tokens(data)
	var user := _extract_user(data)
	GameManager.current_user = user
	DatabaseManager.save_user(user)

	if requires_guardian:
		UIManager.show_toast("Conta criada! Peça ao responsável para aprovar.")
	registration_success.emit(user)

func _extract_user(data: Dictionary) -> Dictionary:
	return {
		"id": str(data.get("user_id", data.get("id", ""))),
		"nome": data.get("name", data.get("nome", "")),
		"email": data.get("email", ""),
		"tipo_usuario": data.get("user_type", "jogador"),
		"nivel": data.get("level", 1),
		"xp": data.get("xp", 0),
		"pet_coins": data.get("pet_coins", 0)
	}

# ──────────────────────────────────────────────
# Tokens JWT (RNF-S004)
# ──────────────────────────────────────────────
func _save_tokens(data: Dictionary) -> void:
	_access_token  = data.get("access_token", "")
	_refresh_token = data.get("refresh_token", "")
	_token_expiry  = Time.get_unix_time_from_system() + (TOKEN_EXPIRY_HOURS * 3600)
	SaveSystem.save_value("access_token", _access_token)
	SaveSystem.save_value("refresh_token", _refresh_token)
	SaveSystem.save_value("token_expiry", _token_expiry)
	SaveSystem.save_value("user_id", data.get("user_id", data.get("id", "")))

func _is_token_expired() -> bool:
	return Time.get_unix_time_from_system() >= _token_expiry

func _refresh_access_token() -> void:
	if _refresh_token.is_empty():
		_force_logout()
		return
	var body := JSON.stringify({"refresh_token": _refresh_token})
	var err := _http.request(
		AUTH_URL + "/refresh",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST, body
	)
	if err != OK:
		return
	var result: Array = await _http.request_completed
	if result[1] == 200:
		var json := JSON.new()
		json.parse(result[3].get_string_from_utf8())
		_save_tokens(json.data)
		_restore_user_from_save()
	else:
		_force_logout()

func get_access_token() -> String:
	return _access_token

# ──────────────────────────────────────────────
# Logout (RNF-S004 — revogação imediata)
# ──────────────────────────────────────────────
func logout() -> void:
	UIManager.show_confirmation_dialog(
		"logout", "Sair", "Deseja realmente sair da conta?", "Sair", "Cancelar"
	)
	var result: String = await UIManager.dialog_confirmed
	if result == "logout":
		_force_logout()

func _force_logout() -> void:
	_access_token = ""
	_refresh_token = ""
	_token_expiry = 0
	GameManager.current_user.clear()
	GameManager.active_sponsorship.clear()
	GameManager.current_pet_virtual.clear()
	SaveSystem.save_value("access_token", "")
	SaveSystem.save_value("refresh_token", "")
	SaveSystem.save_value("token_expiry", 0)
	logout_completed.emit()
	GameManager.go_to_login()

# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────
func _parse_error(body: PackedByteArray) -> String:
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) == OK:
		return json.data.get("message", json.data.get("error", "Erro desconhecido"))
	return "Erro ao processar resposta do servidor"

func is_logged_in() -> bool:
	return not _access_token.is_empty() and not _is_token_expired()
