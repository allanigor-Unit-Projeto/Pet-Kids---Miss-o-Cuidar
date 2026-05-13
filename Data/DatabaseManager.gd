## DatabaseManager.gd
## Singleton Autoload: Gerencia o banco de dados SQLite local (RNF-I009).
## Armazena sessão, cache de progresso e suporte a modo offline (RNF-P009).
##
## Tabelas: usuario_local, pet_virtual_cache, missoes_pendentes,
##           inventario_local, eventos_offline, conquistas_local
extends Node

# ──────────────────────────────────────────────
# Constantes
# ──────────────────────────────────────────────
const DB_PATH := "user://pet_kids.db"
const DB_VERSION := 2.2

# ──────────────────────────────────────────────
# Estado interno
# ──────────────────────────────────────────────

## SQLite plugin godot-sqlite .
## Se o plugin não estiver presente, usa dicionário em memória como fallback.
var _db = null
var _use_memory_fallback: bool = false
var _memory_db: Dictionary = {
	"usuario_local": [],
	"pet_virtual_cache": [],
	"missoes_pendentes": [],
	"inventario_local": [],
	"eventos_offline": [],
	"conquistas_local": [],
	"configuracoes": []
}

# ──────────────────────────────────────────────
# Inicialização
# ──────────────────────────────────────────────
func _ready() -> void:
	_initialize_database()

func _initialize_database() -> void:
	# Tenta carregar plugin SQLite; caso ausente usa fallback em memória
	if ClassDB.class_exists("SQLite"):
		_db = ClassDB.instantiate("SQLite")
		_db.path = DB_PATH
		_db.verbosity_level = 0
		if _db.open_db():
			_create_tables()
			_run_migrations()
			print("[DatabaseManager] SQLite aberto: %s" % DB_PATH)
		else:
			push_error("[DatabaseManager] Falha ao abrir SQLite. Usando fallback.")
			_use_memory_fallback = true
	else:
		push_warning("[DatabaseManager] Plugin SQLite não encontrado. Usando fallback em memória.")
		_use_memory_fallback = true

# ──────────────────────────────────────────────
# DDL — Criação de tabelas (RNF-I009)
# ──────────────────────────────────────────────
func _create_tables() -> void:
	var ddl_statements := [
		"""CREATE TABLE IF NOT EXISTS usuario_local (
			id TEXT PRIMARY KEY,
			nome TEXT NOT NULL,
			email TEXT UNIQUE NOT NULL,
			tipo_usuario TEXT DEFAULT 'jogador',
			nivel INTEGER DEFAULT 1,
			xp INTEGER DEFAULT 0,
			pet_coins INTEGER DEFAULT 0,
			ultimo_login TEXT,
			criado_em TEXT DEFAULT CURRENT_TIMESTAMP
		)""",

		"""CREATE TABLE IF NOT EXISTS pet_virtual_cache (
			id TEXT PRIMARY KEY,
			pet_id TEXT NOT NULL,
			nome TEXT NOT NULL,
			especie TEXT NOT NULL,
			fome REAL DEFAULT 100.0,
			hidratacao REAL DEFAULT 100.0,
			higiene REAL DEFAULT 100.0,
			energia REAL DEFAULT 100.0,
			felicidade REAL DEFAULT 100.0,
			nivel INTEGER DEFAULT 1,
			ultimo_update INTEGER,
			decay_rate REAL DEFAULT 1.0,
			sincronizado INTEGER DEFAULT 0
		)""",

		"""CREATE TABLE IF NOT EXISTS missoes_pendentes (
			id TEXT PRIMARY KEY,
			titulo TEXT NOT NULL,
			descricao TEXT,
			tipo TEXT,
			status TEXT DEFAULT 'em_progresso',
			xp_recompensa INTEGER DEFAULT 0,
			coins_recompensa INTEGER DEFAULT 0,
			progresso REAL DEFAULT 0.0,
			meta REAL DEFAULT 1.0,
			criado_em TEXT DEFAULT CURRENT_TIMESTAMP,
			concluido_em TEXT
		)""",

		"""CREATE TABLE IF NOT EXISTS inventario_local (
			id TEXT PRIMARY KEY,
			item_id TEXT NOT NULL,
			nome TEXT NOT NULL,
			categoria TEXT NOT NULL,
			quantidade INTEGER DEFAULT 1,
			valor_unitario INTEGER DEFAULT 0,
			icone_path TEXT,
			sincronizado INTEGER DEFAULT 0
		)""",

		"""CREATE TABLE IF NOT EXISTS eventos_offline (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			tipo TEXT NOT NULL,
			payload TEXT NOT NULL,
			criado_em INTEGER DEFAULT (strftime('%s','now')),
			sincronizado INTEGER DEFAULT 0
		)""",

		"""CREATE TABLE IF NOT EXISTS conquistas_local (
			id TEXT PRIMARY KEY,
			titulo TEXT NOT NULL,
			descricao TEXT,
			badge_art TEXT,
			xp_recompensa INTEGER DEFAULT 0,
			desbloqueado INTEGER DEFAULT 0,
			desbloqueado_em TEXT,
			plataforma TEXT DEFAULT 'mobile'
		)""",

		"""CREATE TABLE IF NOT EXISTS configuracoes (
			chave TEXT PRIMARY KEY,
			valor TEXT NOT NULL
		)""",

		"""CREATE TABLE IF NOT EXISTS db_version (
			version INTEGER PRIMARY KEY
		)"""
	]
	for stmt in ddl_statements:
		_execute(stmt)

func _run_migrations() -> void:
	var rows := _query("SELECT version FROM db_version ORDER BY version DESC LIMIT 1")
	var current_version := 0
	if rows.size() > 0:
		current_version = int(rows[0].get("version", 0))
	if current_version < DB_VERSION:
		_execute("INSERT OR REPLACE INTO db_version (version) VALUES (%d)" % DB_VERSION)
		print("[DatabaseManager] Migração concluída para v%d" % DB_VERSION)

# ──────────────────────────────────────────────
# Helpers de execução SQL
# ──────────────────────────────────────────────
func _execute(sql: String, params: Array = []) -> bool:
	if _use_memory_fallback:
		return true  # Fallback não executa SQL real
	return _db.query_with_bindings(sql, params)

func _query(sql: String, params: Array = []) -> Array:
	if _use_memory_fallback:
		return []
	if _db.query_with_bindings(sql, params):
		return _db.query_result
	return []

# ──────────────────────────────────────────────
# CRUD — Usuario Local
# ──────────────────────────────────────────────
func save_user(user: Dictionary) -> bool:
	if _use_memory_fallback:
		_upsert_memory("usuario_local", user, "id")
		return true
	return _execute("""
		INSERT OR REPLACE INTO usuario_local
		(id, nome, email, tipo_usuario, nivel, xp, pet_coins, ultimo_login)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		user.get("id", ""), user.get("nome", ""), user.get("email", ""),
		user.get("tipo_usuario", "jogador"), user.get("nivel", 1),
		user.get("xp", 0), user.get("pet_coins", 0),
		Time.get_datetime_string_from_system()
	])

func get_user(user_id: String) -> Dictionary:
	if _use_memory_fallback:
		return _find_memory("usuario_local", "id", user_id)
	var rows := _query("SELECT * FROM usuario_local WHERE id = ?", [user_id])
	return rows[0] if rows.size() > 0 else {}

# ──────────────────────────────────────────────
# CRUD — Pet Virtual Cache
# ──────────────────────────────────────────────
func save_pet_virtual(pet: Dictionary) -> bool:
	if _use_memory_fallback:
		_upsert_memory("pet_virtual_cache", pet, "id")
		return true
	var needs: Dictionary = pet.get("needs", {})
	return _execute("""
		INSERT OR REPLACE INTO pet_virtual_cache
		(id, pet_id, nome, especie, fome, hidratacao, higiene, energia,
		 felicidade, nivel, ultimo_update, decay_rate, sincronizado)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
	""", [
		pet.get("id", ""), pet.get("pet_id", ""), pet.get("name", ""),
		pet.get("species", ""), needs.get("hunger", 100.0),
		needs.get("hydration", 100.0), needs.get("hygiene", 100.0),
		needs.get("energy", 100.0), needs.get("happiness", 100.0),
		pet.get("level", 1), pet.get("last_update_timestamp", 0),
		pet.get("decay_rate", 1.0)
	])

func get_active_pet_virtual() -> Dictionary:
	if _use_memory_fallback:
		var list: Array = _memory_db.get("pet_virtual_cache", [])
		return list[0] if list.size() > 0 else {}
	var rows := _query("SELECT * FROM pet_virtual_cache LIMIT 1")
	if rows.is_empty():
		return {}
	var row: Dictionary = rows[0]
	return {
		"id": row.get("id", ""), "pet_id": row.get("pet_id", ""),
		"name": row.get("nome", ""), "species": row.get("especie", ""),
		"needs": {
			"hunger": float(row.get("fome", 100)),
			"hydration": float(row.get("hidratacao", 100)),
			"hygiene": float(row.get("higiene", 100)),
			"energy": float(row.get("energia", 100)),
			"happiness": float(row.get("felicidade", 100))
		},
		"level": int(row.get("nivel", 1)),
		"last_update_timestamp": int(row.get("ultimo_update", 0)),
		"decay_rate": float(row.get("decay_rate", 1.0))
	}

func clear_pet_virtual() -> void:
	if _use_memory_fallback:
		_memory_db["pet_virtual_cache"] = []
		return
	_execute("DELETE FROM pet_virtual_cache")

# ──────────────────────────────────────────────
# CRUD — Missões
# ──────────────────────────────────────────────
func save_mission(mission: Dictionary) -> bool:
	if _use_memory_fallback:
		_upsert_memory("missoes_pendentes", mission, "id")
		return true
	return _execute("""
		INSERT OR REPLACE INTO missoes_pendentes
		(id, titulo, descricao, tipo, status, xp_recompensa, coins_recompensa,
		 progresso, meta)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		mission.get("id", ""), mission.get("titulo", ""),
		mission.get("descricao", ""), mission.get("tipo", "diaria"),
		mission.get("status", "em_progresso"),
		mission.get("xp_recompensa", 0), mission.get("coins_recompensa", 0),
		mission.get("progresso", 0.0), mission.get("meta", 1.0)
	])

func get_active_missions() -> Array:
	if _use_memory_fallback:
		return _memory_db.get("missoes_pendentes", [])
	return _query("SELECT * FROM missoes_pendentes WHERE status = 'em_progresso'")

func complete_mission(mission_id: String) -> void:
	if _use_memory_fallback:
		for m in _memory_db["missoes_pendentes"]:
			if m.get("id") == mission_id:
				m["status"] = "concluida"
		return
	_execute("""
		UPDATE missoes_pendentes SET status = 'concluida',
		concluido_em = CURRENT_TIMESTAMP WHERE id = ?
	""", [mission_id])

# ──────────────────────────────────────────────
# CRUD — Inventário
# ──────────────────────────────────────────────
func save_inventory_item(item: Dictionary) -> bool:
	if _use_memory_fallback:
		_upsert_memory("inventario_local", item, "id")
		return true
	return _execute("""
		INSERT OR REPLACE INTO inventario_local
		(id, item_id, nome, categoria, quantidade, valor_unitario, icone_path, sincronizado)
		VALUES (?, ?, ?, ?, ?, ?, ?, 0)
	""", [
		item.get("id", ""), item.get("item_id", ""), item.get("nome", ""),
		item.get("categoria", ""), item.get("quantidade", 1),
		item.get("valor_unitario", 0), item.get("icone_path", "")
	])

func get_inventory() -> Array:
	if _use_memory_fallback:
		return _memory_db.get("inventario_local", [])
	return _query("SELECT * FROM inventario_local WHERE quantidade > 0")

func consume_item(item_id: String, quantity: int = 1) -> bool:
	if _use_memory_fallback:
		for item in _memory_db["inventario_local"]:
			if item.get("item_id") == item_id:
				if item.get("quantidade", 0) >= quantity:
					item["quantidade"] -= quantity
					return true
		return false
	var rows := _query("SELECT quantidade FROM inventario_local WHERE item_id = ?", [item_id])
	if rows.is_empty() or int(rows[0].get("quantidade", 0)) < quantity:
		return false
	_execute("UPDATE inventario_local SET quantidade = quantidade - ? WHERE item_id = ?",
		[quantity, item_id])
	return true

# ──────────────────────────────────────────────
# Eventos offline (RNF-P009)
# ──────────────────────────────────────────────
func queue_offline_event(tipo: String, payload: Dictionary) -> void:
	var json_payload := JSON.stringify(payload)
	if _use_memory_fallback:
		_memory_db["eventos_offline"].append({
			"tipo": tipo, "payload": json_payload, "sincronizado": 0
		})
		return
	_execute("INSERT INTO eventos_offline (tipo, payload) VALUES (?, ?)",
		[tipo, json_payload])

func get_pending_offline_events() -> Array:
	if _use_memory_fallback:
		var pending := []
		for ev in _memory_db.get("eventos_offline", []):
			if ev.get("sincronizado", 0) == 0:
				pending.append(ev)
		return pending
	return _query("SELECT * FROM eventos_offline WHERE sincronizado = 0 ORDER BY criado_em")

func mark_events_synced(ids: Array) -> void:
	if _use_memory_fallback:
		return
	for id in ids:
		_execute("UPDATE eventos_offline SET sincronizado = 1 WHERE id = ?", [id])

# ──────────────────────────────────────────────
# Configurações (chave-valor)
# ──────────────────────────────────────────────
func set_config(key: String, value: String) -> void:
	if _use_memory_fallback:
		_upsert_memory("configuracoes", {"chave": key, "valor": value}, "chave")
		return
	_execute("INSERT OR REPLACE INTO configuracoes (chave, valor) VALUES (?, ?)", [key, value])

func get_config(key: String, default_value: String = "") -> String:
	if _use_memory_fallback:
		var row := _find_memory("configuracoes", "chave", key)
		return row.get("valor", default_value)
	var rows := _query("SELECT valor FROM configuracoes WHERE chave = ?", [key])
	return rows[0].get("valor", default_value) if rows.size() > 0 else default_value

# ──────────────────────────────────────────────
# Conquistas
# ──────────────────────────────────────────────
func unlock_achievement(achievement: Dictionary) -> void:
	if _use_memory_fallback:
		_upsert_memory("conquistas_local", achievement, "id")
		return
	_execute("""
		INSERT OR REPLACE INTO conquistas_local
		(id, titulo, descricao, badge_art, xp_recompensa, desbloqueado, desbloqueado_em)
		VALUES (?, ?, ?, ?, ?, 1, CURRENT_TIMESTAMP)
	""", [
		achievement.get("id", ""), achievement.get("titulo", ""),
		achievement.get("descricao", ""), achievement.get("badge_art", ""),
		achievement.get("xp_recompensa", 0)
	])

func get_unlocked_achievements() -> Array:
	if _use_memory_fallback:
		return _memory_db.get("conquistas_local", []).filter(
			func(a): return a.get("desbloqueado", 0) == 1
		)
	return _query("SELECT * FROM conquistas_local WHERE desbloqueado = 1")

# ──────────────────────────────────────────────
# Helpers de fallback em memória
# ──────────────────────────────────────────────
func _upsert_memory(table: String, record: Dictionary, pk: String) -> void:
	var list: Array = _memory_db.get(table, [])
	for i in list.size():
		if list[i].get(pk) == record.get(pk):
			list[i] = record
			return
	list.append(record)
	_memory_db[table] = list

func _find_memory(table: String, key: String, value) -> Dictionary:
	for row in _memory_db.get(table, []):
		if row.get(key) == value:
			return row
	return {}

# ──────────────────────────────────────────────
# Encerramento
# ──────────────────────────────────────────────
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _db != null and not _use_memory_fallback:
		_db.close_db()
		print("[DatabaseManager] Banco de dados fechado.")
