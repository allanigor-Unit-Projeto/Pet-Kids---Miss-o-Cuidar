## SaveSystem.gd
## Singleton Autoload: Persistência local e sincronização com nuvem (RF018).
## Salva automaticamente progresso e mantém compatibilidade retroativa (RNF-M005).
extends Node

const SAVE_FILE := "user://save_data.cfg"
const SAVE_VERSION := 1

var _config := ConfigFile.new()

# ──────────────────────────────────────────────
func _ready() -> void:
	_load_file()

func _load_file() -> void:
	var err := _config.load(SAVE_FILE)
	if err != OK:
		print("[SaveSystem] Nenhum save encontrado. Criando novo.")

# ──────────────────────────────────────────────
# Progresso do jogador
# ──────────────────────────────────────────────
func save_player_progress() -> void:
	_config.set_value("player", "level", GameManager.player_level)
	_config.set_value("player", "xp", GameManager.player_xp)
	_config.set_value("player", "pet_coins", GameManager.pet_coins)
	_config.set_value("meta", "save_version", SAVE_VERSION)
	_config.set_value("meta", "saved_at", Time.get_unix_time_from_system())
	_config.save(SAVE_FILE)
	DatabaseManager.save_user({
		"id": GameManager.current_user.get("id", "local"),
		"nome": GameManager.current_user.get("nome", ""),
		"email": GameManager.current_user.get("email", ""),
		"nivel": GameManager.player_level,
		"xp": GameManager.player_xp,
		"pet_coins": GameManager.pet_coins
	})

func load_player_progress() -> void:
	GameManager.player_level = _config.get_value("player", "level", 1)
	GameManager.player_xp   = _config.get_value("player", "xp", 0)
	GameManager.pet_coins   = _config.get_value("player", "pet_coins", 0)
	# Compatibilidade retroativa (RNF-M005)
	var save_version: int = _config.get_value("meta", "save_version", 0)
	if save_version < SAVE_VERSION:
		_migrate_save(save_version)

func _migrate_save(from_version: int) -> void:
	print("[SaveSystem] Migrando save v%d → v%d" % [from_version, SAVE_VERSION])
	# Adicionar migrações futuras aqui

# ──────────────────────────────────────────────
# Pet virtual / Apadrinhamento
# ──────────────────────────────────────────────
func save_sponsorship(sponsorship: Dictionary) -> void:
	for key in sponsorship:
		_config.set_value("sponsorship", key, sponsorship[key])
	_config.save(SAVE_FILE)

func load_sponsorship() -> Dictionary:
	if not _config.has_section("sponsorship"):
		return {}
	var data := {}
	for key in _config.get_section_keys("sponsorship"):
		data[key] = _config.get_value("sponsorship", key)
	return data

func clear_sponsorship() -> void:
	_config.erase_section("sponsorship")
	_config.save(SAVE_FILE)
	DatabaseManager.clear_pet_virtual()

func save_pet_virtual(pet: Dictionary) -> void:
	DatabaseManager.save_pet_virtual(pet)

func load_pet_virtual() -> Dictionary:
	return DatabaseManager.get_active_pet_virtual()

# ──────────────────────────────────────────────
# Configurações
# ──────────────────────────────────────────────
func save_settings(settings: Dictionary) -> void:
	for key in settings:
		_config.set_value("settings", key, settings[key])
	_config.save(SAVE_FILE)

func load_settings() -> Dictionary:
	if not _config.has_section("settings"):
		return _default_settings()
	var data := {}
	for key in _config.get_section_keys("settings"):
		data[key] = _config.get_value("settings", key)
	return data

func _default_settings() -> Dictionary:
	return {
		"audio_master": 1.0, "audio_sfx": 1.0, "audio_music": 0.8,
		"graphics_quality": "medium", "language": "pt_BR",
		"colorblind_mode": "none", "reduce_motion": false,
		"dark_theme": false, "parental_control": false,
		"vr_locomotion": "teleport", "vr_comfort": true
	}

# ──────────────────────────────────────────────
# Chave-valor genérico
# ──────────────────────────────────────────────
func save_value(key: String, value) -> void:
	_config.set_value("misc", key, value)
	_config.save(SAVE_FILE)

func load_value(key: String, default_value = null):
	return _config.get_value("misc", key, default_value)

# ──────────────────────────────────────────────
# Deleção de dados (RNF-U009 — ação destrutiva)
# ──────────────────────────────────────────────
func delete_all_data() -> void:
	DirAccess.remove_absolute(SAVE_FILE)
	DatabaseManager.clear_pet_virtual()
	_config = ConfigFile.new()
	print("[SaveSystem] Todos os dados locais removidos.")
