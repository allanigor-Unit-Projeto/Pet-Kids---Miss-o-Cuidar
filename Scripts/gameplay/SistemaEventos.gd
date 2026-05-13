## SistemaEventos.gd
## Gera eventos aleatórios de emergência (RF007) e histórias narradas (RF015).
class_name SistemaEventos
extends Node

signal event_triggered(event: Dictionary)
signal story_ready(story: Dictionary)

# Pool de eventos de emergência (RF007)
const EMERGENCY_EVENTS := [
	{"id": "ev_sick",        "tipo": "doenca",
	 "titulo": "Pet Doente",
	 "descricao": "Seu pet está com sintomas de mal-estar. Consulte um veterinário!",
	 "needs_affected": {"happiness": -30.0, "energy": -20.0},
	 "resolution": "vet", "penalty_xp": 10,
	 "educational_tip": "Sintomas como vômito e apatia requerem atenção veterinária imediata."},
	{"id": "ev_accident",    "tipo": "acidente",
	 "titulo": "Acidente Doméstico",
	 "descricao": "Seu pet se machucou! Verifique e consulte um veterinário.",
	 "needs_affected": {"happiness": -20.0, "energy": -30.0},
	 "resolution": "vet", "penalty_xp": 10,
	 "educational_tip": "Mantenha produtos de limpeza e medicamentos fora do alcance dos pets."},
	{"id": "ev_flea",        "tipo": "parasita",
	 "titulo": "Pulgas Detectadas",
	 "descricao": "Seu pet está com pulgas! Use antipulgas indicado pelo vet.",
	 "needs_affected": {"hygiene": -40.0, "happiness": -15.0},
	 "resolution": "medicine", "penalty_xp": 5,
	 "educational_tip": "A prevenção mensal de parasitas é mais econômica que o tratamento."},
	{"id": "ev_heat",        "tipo": "calor",
	 "titulo": "Insolação",
	 "descricao": "Faz muito calor! Hidrate seu pet e coloque em local fresco.",
	 "needs_affected": {"hydration": -40.0, "energy": -25.0},
	 "resolution": "hydrate", "penalty_xp": 5,
	 "educational_tip": "Nunca deixe seu pet em ambientes quentes sem água e ventilação."}
]

# Histórias reais narradas dos animais (RF015)
const PET_STORIES := [
	{"id": "story_rex",
	 "pet_name": "Rex",
	 "species": "dog",
	 "narration": "Rex foi encontrado na rua em estado de desnutrição. Com amor e cuidados, ele recuperou a saúde e agora espera uma família.",
	 "audio_path": "res://assets/audio/stories/story_rex.ogg",
	 "cutscene": "res://scenes/gameplay/cutscenes/story_rex.tscn"},
	{"id": "story_mia",
	 "pet_name": "Mia",
	 "species": "cat",
	 "narration": "Mia foi resgatada de um incêndio. Sua pelagem cresceu de volta, e ela aprendeu a confiar nas pessoas novamente.",
	 "audio_path": "res://assets/audio/stories/story_mia.ogg",
	 "cutscene": "res://scenes/gameplay/cutscenes/story_mia.tscn"}
]

var _rng := RandomNumberGenerator.new()
var _event_cooldown: float = 0.0
const EVENT_COOLDOWN_SECONDS := 300.0   # 5 minutos entre eventos

func _ready() -> void:
	_rng.randomize()

func _process(delta: float) -> void:
	_event_cooldown -= delta

func try_trigger_random_event() -> void:
	if _event_cooldown > 0:
		return
	# 15% de chance por verificação
	if _rng.randf() > 0.15:
		return
	_trigger_random_emergency()
	_event_cooldown = EVENT_COOLDOWN_SECONDS

func _trigger_random_emergency() -> void:
	var idx := _rng.randi() % EMERGENCY_EVENTS.size()
	var event := EMERGENCY_EVENTS[idx].duplicate()
	event["timestamp"] = Time.get_unix_time_from_system()

	# Aplica efeitos negativos nas necessidades
	var needs := GameManager.get_pet_needs().duplicate()
	for attr in event.get("needs_affected", {}):
		needs[attr] = clampf(needs.get(attr, 100.0) + event["needs_affected"][attr], 0.0, 100.0)
	GameManager.current_pet_virtual["needs"] = needs

	event_triggered.emit(event)
	GameManager.emergency_event_triggered.emit(event)

func trigger_health_critical_event() -> void:
	# Chamado pelo GameManager (RN004)
	var event := {
		"id": "ev_critical_health",
		"tipo": "saude_critica",
		"titulo": "Saúde Crítica!",
		"descricao": "Seu pet está em estado crítico há mais de 24h. Leve-o imediatamente ao veterinário!",
		"resolution": "vet", "penalty_xp": 20,
		"educational_tip": "Um tutor responsável monitora diariamente as necessidades do pet."
	}
	event_triggered.emit(event)

func play_pet_story(pet_id: String) -> void:
	# Busca história pelo id do pet ou espécie
	var pet_data := AdotaPetAPI.get_cached_pet(pet_id)
	var species: String = pet_data.get("species", "dog")

	for story in PET_STORIES:
		if story.get("pet_name") == pet_data.get("name") or story.get("species") == species:
			story_ready.emit(story)
			return

	# Fallback: história genérica
	story_ready.emit({
		"id": "story_generic",
		"pet_name": pet_data.get("name", "Seu pet"),
		"narration": "Este pet chegou ao abrigo em busca de um lar amoroso. Com os seus cuidados, ele está se tornando mais feliz a cada dia.",
		"audio_path": "",
		"cutscene": ""
	})
