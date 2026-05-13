## SistemaCuidados.gd
## Lógica de negócio: simula cuidados diários com o pet (RF005, RF006, UC003).
## Usado por PetCare.gd (mobile) e VRPetCare.gd (VR).
class_name SistemaCuidados
extends Node


# Sinais

signal care_applied(care_type: String, effect: float, needs: Dictionary)
signal item_consumed(item_id: String)
signal feedback_requested(care_type: String)  # dispara visual + som + tátil
signal educational_tip_ready(tip: String)


# Enumeração de tipos de cuidado

enum CareType {
	FEED,        # alimentar
	HYDRATE,     # hidratar
	BATHE,       # banho
	PLAY,        # brincar
	SLEEP,       # dormir
	VET,         # veterinário
	MEDICINE,    # medicar
	GROOM        # escovar/cuidados estéticos
}

# Item necessário por tipo de cuidado
const REQUIRED_ITEMS := {
	CareType.FEED:     "feed_bowl",
	CareType.HYDRATE:  "water_bowl",
	CareType.BATHE:    "shampoo",
	CareType.PLAY:     "toy_ball",
	CareType.SLEEP:    "",           # sem item necessário
	CareType.VET:      "vet_ticket",
	CareType.MEDICINE: "medicine",
	CareType.GROOM:    "brush"
}

# Efeito base nos atributos por tipo de cuidado
const CARE_EFFECTS := {
	CareType.FEED:     {"hunger": 40.0, "happiness": 5.0},
	CareType.HYDRATE:  {"hydration": 35.0, "happiness": 5.0},
	CareType.BATHE:    {"hygiene": 50.0, "happiness": 10.0},
	CareType.PLAY:     {"happiness": 30.0, "energy": -15.0, "hunger": -5.0},
	CareType.SLEEP:    {"energy": 60.0, "happiness": 10.0},
	CareType.VET:      {"happiness": 5.0},   # saúde tratada separadamente
	CareType.MEDICINE: {"happiness": 5.0},
	CareType.GROOM:    {"hygiene": 30.0, "happiness": 15.0}
}

# XP concedido por cuidado
const CARE_XP := {
	CareType.FEED: 10, CareType.HYDRATE: 10, CareType.BATHE: 15,
	CareType.PLAY: 12, CareType.SLEEP: 8,    CareType.VET: 30,
	CareType.MEDICINE: 20, CareType.GROOM: 12
}

# Dicas educativas (RF020)
const EDUCATIONAL_TIPS := {
	CareType.FEED:    "Pets precisam de alimentação regular. Evite deixar comida exposta por muito tempo!",
	CareType.HYDRATE: "Água fresca é essencial. Troque diariamente o recipiente de água do seu pet.",
	CareType.BATHE:   "Cães devem ser banhados a cada 15-30 dias. Gatos geralmente se auto-limpam.",
	CareType.PLAY:    "Brincar reduz estresse e fortalece o vínculo. Reserve 30 min por dia!",
	CareType.SLEEP:   "Pets precisam de descanso. Crie um espaço confortável e seguro para dormir.",
	CareType.VET:     "Consultas preventivas anuais são essenciais para detectar doenças cedo.",
	CareType.MEDICINE:"Siga sempre a dosagem prescrita pelo veterinário. Nunca automedique.",
	CareType.GROOM:   "Escovação frequente previne nós e distribui os óleos naturais da pelagem."
}


# Aplicar cuidado (chamado por touch mobile ou motion VR)

func apply_care(care_type: int) -> bool:
	var required_item: String = REQUIRED_ITEMS.get(care_type, "")

	# Verifica item no inventário (RF013)
	if required_item != "" and not _has_item(required_item):
		UIManager.show_toast("Item necessário: %s não encontrado no inventário." % required_item)
		GameManager.go_to_inventory()
		return false

	# Verifica se o pet não está com energia nula (bloqueio de brincadeira)
	if care_type == CareType.PLAY:
		var energy: float = GameManager.get_pet_needs().get("energy", 100.0)
		if energy < 10.0:
			UIManager.show_toast("Seu pet está muito cansado para brincar agora.")
			return false

	# Aplica efeitos nas necessidades
	var effects: Dictionary = CARE_EFFECTS.get(care_type, {})
	var current_needs: Dictionary = GameManager.get_pet_needs().duplicate()

	for attr in effects:
		current_needs[attr] = clampf(
			current_needs.get(attr, 100.0) + effects[attr],
			0.0, 100.0
		)

	# Atualiza estado global
	GameManager.current_pet_virtual["needs"] = current_needs
	GameManager.current_pet_virtual["last_update_timestamp"] = Time.get_unix_time_from_system()
	SaveSystem.save_pet_virtual(GameManager.current_pet_virtual)

	# Consome item do inventário
	if required_item != "":
		DatabaseManager.consume_item(required_item)
		item_consumed.emit(required_item)

	# XP + PetCoins
	GameManager.add_xp(CARE_XP.get(care_type, 5))

	# Missões: verifica progresso
	_update_mission_progress(care_type)

	# Feedback multimodal (RNF-D009)
	feedback_requested.emit(CareType.keys()[care_type])
	AudioManager.play_sfx("care_%s" % CareType.keys()[care_type].to_lower())
	UIManager._haptic_feedback(0.15)

	# Dica educativa (RF020)
	var tip: String = EDUCATIONAL_TIPS.get(care_type, "")
	if tip != "":
		educational_tip_ready.emit(tip)

	# Emite sinal com novo estado
	care_applied.emit(CareType.keys()[care_type], effects.values().reduce(func(a,b): return a+b, 0.0), current_needs)
	GameManager.pet_needs_updated.emit(
		GameManager.current_pet_virtual.get("id", ""), current_needs
	)

	return true


# Verificação de inventário

func _has_item(item_id: String) -> bool:
	var inventory := DatabaseManager.get_inventory()
	for item in inventory:
		if item.get("item_id") == item_id and int(item.get("quantidade", 0)) > 0:
			return true
	return false


# Cálculo de bem-estar (RF009)

func calculate_wellbeing() -> float:
	var needs := GameManager.get_pet_needs()
	if needs.is_empty():
		return 100.0
	var weights := {"hunger": 0.25, "hydration": 0.25, "hygiene": 0.2, "energy": 0.15, "happiness": 0.15}
	var total := 0.0
	for attr in weights:
		total += needs.get(attr, 100.0) * weights[attr]
	return total

func get_wellbeing_label() -> String:
	var score := calculate_wellbeing()
	if score >= 80.0: return "Ótimo 😄"
	elif score >= 60.0: return "Bom 🙂"
	elif score >= 40.0: return "Regular 😐"
	elif score >= 20.0: return "Ruim 😟"
	else: return "Crítico 😰"


# Evento de emergência manual (veterinário) (RF007)

func handle_emergency(emergency_data: Dictionary) -> void:
	# Aplica penalidade educativa no bem-estar
	var needs := GameManager.get_pet_needs().duplicate()
	needs["happiness"] = maxf(needs.get("happiness", 100.0) - 20.0, 0.0)
	GameManager.current_pet_virtual["needs"] = needs

	UIManager.show_toast("🚨 Emergência: %s! Leve seu pet ao veterinário." %
		emergency_data.get("type", "desconhecida"))
	AudioManager.play_sfx("emergency_alert")
	UIManager._haptic_feedback(0.5)


# Progresso de missões

func _update_mission_progress(care_type: int) -> void:
	var missions := DatabaseManager.get_active_missions()
	for mission in missions:
		if mission.get("tipo") == "cuidado_%s" % CareType.keys()[care_type].to_lower():
			var current: float = float(mission.get("progresso", 0.0))
			var meta: float    = float(mission.get("meta", 1.0))
			current += 1.0
			if current >= meta:
				DatabaseManager.complete_mission(mission.get("id", ""))
				GameManager.add_xp(int(mission.get("xp_recompensa", 0)))
				GameManager.add_pet_coins(int(mission.get("coins_recompensa", 0)))
				UIManager.show_toast("🎯 Missão concluída: %s!" % mission.get("titulo", ""))
				AudioManager.play_sfx("mission_complete")
			else:
				mission["progresso"] = current
				DatabaseManager.save_mission(mission)
