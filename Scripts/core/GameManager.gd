## GameManager.gd
## Singleton Autoload: Gerenciador central do estado do jogo.
## Controla fluxo de cenas, estado do jogador e eventos globais.
extends Node

# ──────────────────────────────────────────────
# Sinais globais
# ──────────────────────────────────────────────
signal scene_changed(scene_name: String)
signal player_xp_changed(new_xp: int, new_level: int)
signal pet_needs_updated(pet_id: String, needs: Dictionary)
signal emergency_event_triggered(event_data: Dictionary)
signal sponsorship_ended(reason: String)

# ──────────────────────────────────────────────
# Constantes
# ──────────────────────────────────────────────
const VERSION := "1.0.0"
const XP_BASE := 100
const XP_MULTIPLIER := 2.0          # dobra a cada 5 níveis (RN009)
const HEALTH_CRITICAL_THRESHOLD := 10  # < 10% gera emergência (RN004)
const EMERGENCY_HOURS_LIMIT := 24   # horas em estado crítico (RN004)
const NEED_DECAY_INTERVAL := 60.0   # segundos entre decaimento de necessidades
const PET_COINS_DAILY_LOGIN := 10   # PetCoins por login diário (RN005)

# ──────────────────────────────────────────────
# Estado global do jogo
# ──────────────────────────────────────────────
var current_user: Dictionary = {}
var current_pet_virtual: Dictionary = {}
var active_sponsorship: Dictionary = {}
var player_level: int = 1
var player_xp: int = 0
var pet_coins: int = 0
var is_vr_mode: bool = false
var is_offline: bool = false
var platform: String = ""          # "mobile", "vr", "desktop"

# Controle interno
var _need_decay_timer: float = 0.0
var _emergency_start_time: int = 0
var _in_critical_state: bool = false

# ──────────────────────────────────────────────
# Ciclo de vida
# ──────────────────────────────────────────────
func _ready() -> void:
	_detect_platform()
	_check_vr_support()
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	if current_pet_virtual.is_empty():
		return
	_update_pet_needs(delta)
	_check_emergency_state()

# ──────────────────────────────────────────────
# Detecção de plataforma (RNF-PT003)
# ──────────────────────────────────────────────
func _detect_platform() -> void:
	if OS.has_feature("mobile"):
		platform = "mobile"
	elif OS.has_feature("web"):
		platform = "web"
	else:
		platform = "desktop"
	print("[GameManager] Plataforma detectada: %s" % platform)

func _check_vr_support() -> void:
	# Verifica suporte OpenXR (RNF-I011)
	if OS.has_feature("xr"):
		is_vr_mode = true
		platform = "vr"
		print("[GameManager] Modo VR ativado via OpenXR")

# ──────────────────────────────────────────────
# Gerenciamento de cenas
# ──────────────────────────────────────────────
func change_scene(scene_path: String, data: Dictionary = {}) -> void:
	UIManager.show_loading()
	# Passa dados opcionais para a próxima cena via metadata
	if not data.is_empty():
		Engine.get_main_loop().set_meta("scene_data", data)
	get_tree().change_scene_to_file(scene_path)
	scene_changed.emit(scene_path.get_file().get_basename())

func go_to_main_menu() -> void:
	change_scene("res://scenes/ui/MainMenu.tscn")

func go_to_login() -> void:
	change_scene("res://scenes/ui/LoginScreen.tscn")

func go_to_pet_selection() -> void:
	change_scene("res://scenes/ui/PetSelection.tscn")

func go_to_pet_care() -> void:
	if is_vr_mode:
		change_scene("res://scenes/vr/VRPetCare.tscn")
	else:
		change_scene("res://scenes/gameplay/PetCare.tscn")

func go_to_inventory() -> void:
	change_scene("res://scenes/ui/Inventory.tscn")

func go_to_missions() -> void:
	change_scene("res://scenes/ui/Missions.tscn")

func go_to_achievements() -> void:
	change_scene("res://scenes/ui/Achievements.tscn")

func go_to_settings() -> void:
	change_scene("res://scenes/ui/Settings.tscn")

# ──────────────────────────────────────────────
# Sistema de XP e Nível (RN009)
# ──────────────────────────────────────────────
func add_xp(amount: int) -> void:
	player_xp += amount
	var xp_needed := _xp_for_next_level()
	while player_xp >= xp_needed:
		player_xp -= xp_needed
		player_level += 1
		xp_needed = _xp_for_next_level()
		UIManager.show_level_up(player_level)
	player_xp_changed.emit(player_xp, player_level)
	SaveSystem.save_player_progress()

func _xp_for_next_level() -> int:
	# XP dobra a cada 5 níveis
	var tier := (player_level - 1) / 5
	return int(XP_BASE * pow(XP_MULTIPLIER, tier))

func get_xp_progress_percent() -> float:
	return float(player_xp) / float(_xp_for_next_level())

# ──────────────────────────────────────────────
# PetCoins — apenas por conquistas/missões (RN005)
# ──────────────────────────────────────────────
func add_pet_coins(amount: int) -> void:
	pet_coins += amount
	SaveSystem.save_player_progress()

func spend_pet_coins(amount: int) -> bool:
	if pet_coins < amount:
		UIManager.show_toast("PetCoins insuficientes!")
		return false
	pet_coins -= amount
	SaveSystem.save_player_progress()
	return true

func claim_daily_login_reward() -> void:
	var today := Time.get_date_string_from_system()
	var last_claim: String = SaveSystem.load_value("last_daily_claim", "")
	if today != last_claim:
		add_pet_coins(PET_COINS_DAILY_LOGIN)
		add_xp(20)
		SaveSystem.save_value("last_daily_claim", today)
		UIManager.show_toast("Login diário: +%d PetCoins!" % PET_COINS_DAILY_LOGIN)

# ──────────────────────────────────────────────
# Atualização de necessidades do pet em tempo real (RN003)
# ──────────────────────────────────────────────
func _update_pet_needs(delta: float) -> void:
	_need_decay_timer += delta
	if _need_decay_timer < NEED_DECAY_INTERVAL:
		return
	_need_decay_timer = 0.0

	# Calcula decaimento por tempo offline
	var now := Time.get_unix_time_from_system()
	var last_update: int = current_pet_virtual.get("last_update_timestamp", now)
	var elapsed_minutes := (now - last_update) / 60.0

	var decay_rate := _get_decay_rate()
	var total_decay := elapsed_minutes * decay_rate

	var needs := current_pet_virtual.get("needs", {
		"hunger": 100.0, "hydration": 100.0,
		"hygiene": 100.0, "energy": 100.0, "happiness": 100.0
	})

	for key in needs:
		needs[key] = clampf(needs[key] - total_decay, 0.0, 100.0)

	current_pet_virtual["needs"] = needs
	current_pet_virtual["last_update_timestamp"] = now
	pet_needs_updated.emit(current_pet_virtual.get("id", ""), needs)

func _get_decay_rate() -> float:
	# Taxa base: 1 ponto por minuto (ajustável por espécie)
	return current_pet_virtual.get("decay_rate", 1.0)

# ──────────────────────────────────────────────
# Verificação de emergência (RN004)
# ──────────────────────────────────────────────
func _check_emergency_state() -> void:
	var needs: Dictionary = current_pet_virtual.get("needs", {})
	var health: float = _calculate_health(needs)

	if health < HEALTH_CRITICAL_THRESHOLD:
		if not _in_critical_state:
			_in_critical_state = true
			_emergency_start_time = Time.get_unix_time_from_system()
		else:
			var hours_critical := (Time.get_unix_time_from_system() - _emergency_start_time) / 3600.0
			if hours_critical >= EMERGENCY_HOURS_LIMIT:
				_trigger_emergency_event()
	else:
		_in_critical_state = false
		_emergency_start_time = 0

func _calculate_health(needs: Dictionary) -> float:
	if needs.is_empty():
		return 100.0
	var total := 0.0
	for v in needs.values():
		total += v
	return total / needs.size()

func _trigger_emergency_event() -> void:
	var event := {
		"type": "health_critical",
		"pet_id": current_pet_virtual.get("id", ""),
		"timestamp": Time.get_unix_time_from_system(),
		"penalty": "pedagogical"
	}
	emergency_event_triggered.emit(event)
	_emergency_start_time = Time.get_unix_time_from_system()  # reset timer

# ──────────────────────────────────────────────
# Apadrinhamento (RN001, RN002)
# ──────────────────────────────────────────────
func start_sponsorship(pet_data: Dictionary) -> bool:
	if not active_sponsorship.is_empty():
		UIManager.show_toast("Você já possui um apadrinhamento ativo.")
		return false
	active_sponsorship = pet_data
	current_pet_virtual = _create_pet_virtual(pet_data)
	SaveSystem.save_sponsorship(active_sponsorship)
	SaveSystem.save_pet_virtual(current_pet_virtual)
	return true

func end_sponsorship(reason: String) -> void:
	active_sponsorship.clear()
	current_pet_virtual.clear()
	_in_critical_state = false
	SaveSystem.clear_sponsorship()
	sponsorship_ended.emit(reason)
	UIManager.show_toast("Apadrinhamento encerrado: %s" % reason)

func _create_pet_virtual(pet_data: Dictionary) -> Dictionary:
	return {
		"id": "pv_%s_%d" % [pet_data.get("id", ""), Time.get_unix_time_from_system()],
		"pet_id": pet_data.get("id", ""),
		"name": pet_data.get("name", ""),
		"species": pet_data.get("species", "dog"),
		"needs": {
			"hunger": 100.0, "hydration": 100.0,
			"hygiene": 100.0, "energy": 100.0, "happiness": 100.0
		},
		"level": 1,
		"last_update_timestamp": Time.get_unix_time_from_system(),
		"decay_rate": _species_decay_rate(pet_data.get("species", "dog"))
	}

func _species_decay_rate(species: String) -> float:
	match species:
		"dog": return 1.2
		"cat": return 0.8
		"rabbit": return 1.5
		_: return 1.0

# ──────────────────────────────────────────────
# Helpers públicos
# ──────────────────────────────────────────────
func is_authenticated() -> bool:
	return not current_user.is_empty()

func get_pet_needs() -> Dictionary:
	return current_pet_virtual.get("needs", {})

func get_platform() -> String:
	return platform
