## SistemaProgressao.gd
## Lógica de progressão: missões diárias, conquistas e recompensas (RF011, RF012, RN009).
class_name SistemaProgressao
extends Node


signal mission_unlocked(mission: Dictionary)
signal achievement_unlocked(achievement: Dictionary)
signal daily_missions_refreshed(missions: Array)


# Dados estáticos de missões diárias (RF011)

const DAILY_MISSION_POOL := [
	{"id": "dm_feed_3",    "titulo": "Alimentação Responsável",
	 "descricao": "Alimente seu pet 3 vezes hoje.",
	 "tipo": "cuidado_feed", "meta": 3.0,
	 "xp_recompensa": 50, "coins_recompensa": 5},
	{"id": "dm_play_2",    "titulo": "Hora do Brinquedo",
	 "descricao": "Brinque com seu pet 2 vezes.",
	 "tipo": "cuidado_play", "meta": 2.0,
	 "xp_recompensa": 40, "coins_recompensa": 5},
	{"id": "dm_hydrate_3", "titulo": "Hidratação em Dia",
	 "descricao": "Garanta água fresca 3 vezes.",
	 "tipo": "cuidado_hydrate", "meta": 3.0,
	 "xp_recompensa": 30, "coins_recompensa": 3},
	{"id": "dm_bathe_1",   "titulo": "Pet Cheiroso",
	 "descricao": "Dê um banho no seu pet.",
	 "tipo": "cuidado_bathe", "meta": 1.0,
	 "xp_recompensa": 60, "coins_recompensa": 8},
	{"id": "dm_groom_1",   "titulo": "Beleza e Saúde",
	 "descricao": "Escove seu pet hoje.",
	 "tipo": "cuidado_groom", "meta": 1.0,
	 "xp_recompensa": 35, "coins_recompensa": 4}
]

# Conquistas (RF012)
const ACHIEVEMENTS := [
	{"id": "ach_first_feed",   "titulo": "Primeiro Jantar",
	 "descricao": "Alimente seu pet pela primeira vez.",
	 "badge_art": "badge_first_feed", "xp_recompensa": 20},
	{"id": "ach_week_streak",  "titulo": "Comprometido",
	 "descricao": "Cuide do pet por 7 dias seguidos.",
	 "badge_art": "badge_streak_7", "xp_recompensa": 100},
	{"id": "ach_first_vet",    "titulo": "Saúde em Primeiro",
	 "descricao": "Leve seu pet ao veterinário.",
	 "badge_art": "badge_vet", "xp_recompensa": 50},
	{"id": "ach_level_5",      "titulo": "Tutor Experiente",
	 "descricao": "Alcance o nível 5.",
	 "badge_art": "badge_level5", "xp_recompensa": 80},
	{"id": "ach_full_needs",   "titulo": "Cuidados Completos",
	 "descricao": "Mantenha todos os indicadores acima de 80% em um dia.",
	 "badge_art": "badge_full_care", "xp_recompensa": 60},
	{"id": "ach_adopted_info", "titulo": "Pronto para Adotar",
	 "descricao": "Complete a enciclopédia de cuidados da espécie do seu pet.",
	 "badge_art": "badge_encyclopedia", "xp_recompensa": 120}
]


func _ready() -> void:
	GameManager.player_xp_changed.connect(_check_level_achievements)
	GameManager.emergency_event_triggered.connect(_on_emergency)
	_refresh_daily_missions()


# Missões diárias (RF011)

func _refresh_daily_missions() -> void:
	var today := Time.get_date_string_from_system()
	var last_refresh: String = SaveSystem.load_value("last_mission_refresh", "")
	if today == last_refresh:
		return   # Já atualizadas hoje

	# Escolhe 3 missões aleatórias do pool
	var pool := DAILY_MISSION_POOL.duplicate()
	pool.shuffle()
	var selected := pool.slice(0, 3)

	for mission in selected:
		var m := mission.duplicate()
		m["status"] = "em_progresso"
		m["progresso"] = 0.0
		DatabaseManager.save_mission(m)
		mission_unlocked.emit(m)

	SaveSystem.save_value("last_mission_refresh", today)
	daily_missions_refreshed.emit(selected)

func get_active_missions() -> Array:
	return DatabaseManager.get_active_missions()

func get_completed_missions_today() -> Array:
	return DatabaseManager.get_active_missions().filter(
		func(m): return m.get("status") == "concluida"
	)


# Conquistas (RF012)

func check_achievement(achievement_id: String) -> void:
	var unlocked := DatabaseManager.get_unlocked_achievements()
	for a in unlocked:
		if a.get("id") == achievement_id:
			return  # Já desbloqueada

	# Busca definição
	for ach in ACHIEVEMENTS:
		if ach.get("id") == achievement_id:
			DatabaseManager.unlock_achievement(ach)
			GameManager.add_xp(ach.get("xp_recompensa", 0))
			UIManager.show_toast("🏅 Conquista: %s!" % ach.get("titulo", ""))
			AudioManager.play_sfx("achievement_unlock")
			UIManager._haptic_feedback(0.25)
			achievement_unlocked.emit(ach)
			return

func _check_level_achievements(_xp: int, level: int) -> void:
	if level >= 5:
		check_achievement("ach_level_5")

func _on_emergency(_event: Dictionary) -> void:
	# Emergência resolvida pelo cuidado de veterinário
	check_achievement("ach_first_vet")

func check_first_care_achievements(care_type: String) -> void:
	match care_type:
		"FEED": check_achievement("ach_first_feed")
		"VET":  check_achievement("ach_first_vet")

func check_full_needs_achievement() -> void:
	var needs := GameManager.get_pet_needs()
	var all_high := needs.values().all(func(v): return float(v) >= 80.0)
	if all_high:
		check_achievement("ach_full_needs")

func get_all_achievements() -> Array:
	return ACHIEVEMENTS

func get_unlocked_achievements() -> Array:
	return DatabaseManager.get_unlocked_achievements()
