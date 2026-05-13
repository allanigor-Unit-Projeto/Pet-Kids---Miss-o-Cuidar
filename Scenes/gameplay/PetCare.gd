## PetCare.gd
## Tela principal de cuidados com o pet — versão mobile (RF-M001, RF-M006, RF-M007, UC003).
## Interpreta gestos touch e aciona SistemaCuidados.
extends Control


@onready var pet_3d_viewport: SubViewport      = $PetViewport
@onready var hud_needs: Control                = $HUD/NeedsPanel
@onready var bar_hunger: ProgressBar           = $HUD/NeedsPanel/BarHunger
@onready var bar_hydration: ProgressBar        = $HUD/NeedsPanel/BarHydration
@onready var bar_hygiene: ProgressBar          = $HUD/NeedsPanel/BarHygiene
@onready var bar_energy: ProgressBar           = $HUD/NeedsPanel/BarEnergy
@onready var bar_happiness: ProgressBar        = $HUD/NeedsPanel/BarHappiness
@onready var lbl_wellbeing: Label              = $HUD/LblWellbeing
@onready var lbl_pet_name: Label               = $HUD/LblPetName
@onready var lbl_level: Label                  = $HUD/LblLevel
@onready var bar_xp: ProgressBar               = $HUD/XPBar

@onready var action_bar: HBoxContainer         = $ActionBar
@onready var btn_feed: Button                  = $ActionBar/BtnFeed
@onready var btn_water: Button                 = $ActionBar/BtnWater
@onready var btn_bathe: Button                 = $ActionBar/BtnBathe
@onready var btn_play: Button                  = $ActionBar/BtnPlay
@onready var btn_sleep: Button                 = $ActionBar/BtnSleep
@onready var btn_vet: Button                   = $ActionBar/BtnVet

@onready var btn_inventory: Button             = $HUD/TopBar/BtnInventory
@onready var btn_missions: Button              = $HUD/TopBar/BtnMissions
@onready var btn_settings: Button              = $HUD/TopBar/BtnSettings

@onready var tip_panel: PanelContainer         = $TipPanel
@onready var tip_label: RichTextLabel          = $TipPanel/LblTip
@onready var emergency_overlay: CanvasLayer    = $EmergencyOverlay
@onready var toast_container: Control          = $ToastContainer
@onready var dialog_overlay: CanvasLayer       = $DialogOverlay
@onready var level_up_overlay: CanvasLayer     = $LevelUpOverlay


# Subsistemas de gameplay
var _sistema_cuidados: SistemaCuidados
var _sistema_progressao: SistemaProgressao
var _sistema_eventos: SistemaEventos

# Estado de gesture detection (RF-M007)
var _touch_start_pos: Vector2 = Vector2.ZERO
var _touch_start_time: float = 0.0
var _is_touching: bool = false
const SWIPE_MIN_DISTANCE := 80.0
const SWIPE_MAX_TIME := 0.5
const HOLD_MIN_TIME := 0.6
const CIRCLE_SEGMENTS := 6

var _circle_points: Array[Vector2] = []


func _ready() -> void:
	UIManager.register_toast_container(toast_container)
	UIManager.register_dialog_overlay(dialog_overlay)
	UIManager.register_level_up_overlay(level_up_overlay)
	UIManager.hide_loading()

	_create_subsystems()
	_connect_signals()
	_setup_buttons()
	_update_hud()
	_play_background_music()

func _create_subsystems() -> void:
	_sistema_cuidados = SistemaCuidados.new()
	_sistema_progressao = SistemaProgressao.new()
	_sistema_eventos = SistemaEventos.new()
	add_child(_sistema_cuidados)
	add_child(_sistema_progressao)
	add_child(_sistema_eventos)

func _connect_signals() -> void:
	# GameManager
	GameManager.pet_needs_updated.connect(_on_needs_updated)
	GameManager.player_xp_changed.connect(_on_xp_changed)
	GameManager.emergency_event_triggered.connect(_on_emergency_triggered)

	# SistemaCuidados
	_sistema_cuidados.care_applied.connect(_on_care_applied)
	_sistema_cuidados.educational_tip_ready.connect(_show_tip)

	# Botões de ação
	btn_feed.pressed.connect(func(): _apply_care(SistemaCuidados.CareType.FEED))
	btn_water.pressed.connect(func(): _apply_care(SistemaCuidados.CareType.HYDRATE))
	btn_bathe.pressed.connect(func(): _apply_care(SistemaCuidados.CareType.BATHE))
	btn_play.pressed.connect(func(): _apply_care(SistemaCuidados.CareType.PLAY))
	btn_sleep.pressed.connect(func(): _apply_care(SistemaCuidados.CareType.SLEEP))
	btn_vet.pressed.connect(func(): _apply_care(SistemaCuidados.CareType.VET))

	# Navegação
	btn_inventory.pressed.connect(GameManager.go_to_inventory)
	btn_missions.pressed.connect(GameManager.go_to_missions)
	btn_settings.pressed.connect(GameManager.go_to_settings)


# Setup de botões com ícones e tooltips (RF-M001, RNF-U004)

func _setup_buttons() -> void:
	var care_buttons := {
		btn_feed:  {"label": "Alimentar 🍖",  "tooltip": "Dê comida ao seu pet"},
		btn_water: {"label": "Água 💧",        "tooltip": "Ofereça água fresca"},
		btn_bathe: {"label": "Banho 🛁",       "tooltip": "Dê banho no seu pet"},
		btn_play:  {"label": "Brincar 🎾",    "tooltip": "Brinque com seu pet"},
		btn_sleep: {"label": "Descanso 💤",   "tooltip": "Deixe seu pet descansar"},
		btn_vet:   {"label": "Veterinário 🩺","tooltip": "Leve ao veterinário"}
	}
	for btn in care_buttons:
		btn.text         = care_buttons[btn]["label"]
		btn.tooltip_text = care_buttons[btn]["tooltip"]
		btn.custom_minimum_size = Vector2(80, 80)   # área de toque 48dp+ (RNF-U001)


# Aplicar cuidado via botão

func _apply_care(care_type: int) -> void:
	var success := _sistema_cuidados.apply_care(care_type)
	if success:
		_sistema_progressao.check_first_care_achievements(
			SistemaCuidados.CareType.keys()[care_type]
		)
		_sistema_progressao.check_full_needs_achievement()
		_sistema_eventos.try_trigger_random_event()
		_animate_pet_reaction()


# Gestos touch (RF-M001, RF-M006, RF-M007)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag and _is_touching:
		_handle_drag(event)

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touch_start_pos  = event.position
		_touch_start_time = Time.get_ticks_msec() / 1000.0
		_is_touching      = true
		_circle_points.clear()
	else:
		_is_touching = false
		var elapsed := Time.get_ticks_msec() / 1000.0 - _touch_start_time
		var distance := event.position.distance_to(_touch_start_pos)

		if elapsed >= HOLD_MIN_TIME and distance < 20.0:
			_on_hold_gesture()
		elif distance < 20.0 and elapsed < 0.3:
			_on_tap_gesture(event.position)
		elif _circle_points.size() >= CIRCLE_SEGMENTS:
			_on_circle_gesture()

func _handle_drag(event: InputEventScreenDrag) -> void:
	_circle_points.append(event.position)
	var distance := event.position.distance_to(_touch_start_pos)
	var elapsed  := Time.get_ticks_msec() / 1000.0 - _touch_start_time

	if distance >= SWIPE_MIN_DISTANCE and elapsed <= SWIPE_MAX_TIME:
		_on_swipe_gesture(event.relative)

func _on_tap_gesture(_pos: Vector2) -> void:
	# Tap: chamar atenção (RF-M007)
	UIManager.show_toast("%s te olhou! 👀" % GameManager.current_pet_virtual.get("name", ""))
	AudioManager.play_sfx("pet_attention")

func _on_swipe_gesture(relative: Vector2) -> void:
	# Swipe: acariciar (RF-M007)
	var direction := relative.normalized()
	if abs(direction.x) > abs(direction.y):
		_apply_care(SistemaCuidados.CareType.GROOM)
		UIManager.show_toast("Você acariciou %s! 💕" % GameManager.current_pet_virtual.get("name", ""))

func _on_hold_gesture() -> void:
	# Hold: interação especial com o pet
	UIManager.show_toast("Você abraçou %s! 🤗" % GameManager.current_pet_virtual.get("name", ""))
	var needs := GameManager.get_pet_needs().duplicate()
	needs["happiness"] = minf(needs.get("happiness", 100.0) + 5.0, 100.0)
	GameManager.current_pet_virtual["needs"] = needs
	AudioManager.play_sfx("pet_happy")
	UIManager._haptic_feedback(0.2)

func _on_circle_gesture() -> void:
	# Círculo: brincar (RF-M007)
	_apply_care(SistemaCuidados.CareType.PLAY)
	UIManager.show_toast("Você jogou com %s! 🎾" % GameManager.current_pet_virtual.get("name", ""))


# Atualização do HUD

func _update_hud() -> void:
	var pet := GameManager.current_pet_virtual
	if pet.is_empty():
		return
	lbl_pet_name.text = pet.get("name", "Meu Pet")
	lbl_level.text    = "Nv. %d" % GameManager.player_level
	bar_xp.value      = GameManager.get_xp_progress_percent() * 100.0
	lbl_wellbeing.text = _sistema_cuidados.get_wellbeing_label()
	_on_needs_updated("", pet.get("needs", {}))

func _on_needs_updated(_pet_id: String, needs: Dictionary) -> void:
	bar_hunger.value    = needs.get("hunger", 0.0)
	bar_hydration.value = needs.get("hydration", 0.0)
	bar_hygiene.value   = needs.get("hygiene", 0.0)
	bar_energy.value    = needs.get("energy", 0.0)
	bar_happiness.value = needs.get("happiness", 0.0)
	lbl_wellbeing.text  = _sistema_cuidados.get_wellbeing_label()
	_update_bar_colors()

func _update_bar_colors() -> void:
	# Muda cor das barras conforme estado (contraste RNF-U001, modo daltônico RNF-U005)
	for bar in [bar_hunger, bar_hydration, bar_hygiene, bar_energy, bar_happiness]:
		var val: float = bar.value
		if val >= 60.0:
			bar.modulate = Color("#639922")    # Verde-Lima (sucesso)
		elif val >= 30.0:
			bar.modulate = Color("#EF9F27")    # Laranja-Mel (atenção)
		else:
			bar.modulate = Color("#D85A30")    # Coral (alerta)

func _on_xp_changed(xp: int, level: int) -> void:
	lbl_level.text = "Nv. %d" % level
	bar_xp.value   = GameManager.get_xp_progress_percent() * 100.0


# Emergência (RF007, RN004)

func _on_emergency_triggered(event: Dictionary) -> void:
	emergency_overlay.visible = true
	var lbl_title := emergency_overlay.find_child("LblTitle", true, false) as Label
	var lbl_desc  := emergency_overlay.find_child("LblDesc", true, false) as Label
	var btn_resolve := emergency_overlay.find_child("BtnResolve", true, false) as Button
	if lbl_title: lbl_title.text = event.get("titulo", "Emergência!")
	if lbl_desc:  lbl_desc.text  = event.get("descricao", "")
	if btn_resolve:
		btn_resolve.pressed.connect(func():
			_sistema_cuidados.handle_emergency(event)
			emergency_overlay.visible = false
			_apply_care(SistemaCuidados.CareType.VET)
		, CONNECT_ONE_SHOT)
	AudioManager.play_sfx("emergency_alert")
	UIManager._haptic_feedback(0.5)


# Dica educativa (RF020)

func _show_tip(tip: String) -> void:
	tip_label.text   = "[i]💡 %s[/i]" % tip
	tip_panel.visible = true
	var tween := create_tween()
	tween.tween_interval(4.0)
	tween.tween_callback(func(): tip_panel.visible = false)


# Animação de reação do pet (placeholder — animar via AnimationPlayer 3D)

func _animate_pet_reaction() -> void:
	var ap := pet_3d_viewport.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap and ap.has_animation("happy"):
		ap.play("happy")


func _on_care_applied(_care_type: String, _effect: float, _needs: Dictionary) -> void:
	SaveSystem.save_pet_virtual(GameManager.current_pet_virtual)

func _play_background_music() -> void:
	AudioManager.play_music("pet_care_bg")

func _process(_delta: float) -> void:
	pass  # HUD atualizado via sinais; processo leve
