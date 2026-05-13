## VRPetCare.gd
## Tela de cuidados em modo VR (RF-V001 a RF-V010, OpenXR).
## Equivalente ao PetCare.gd mas com motion controllers e UI espacial 3D.
extends Node3D

# ──────────────────────────────────────────────
@onready var xr_origin: XROrigin3D            = $XROrigin3D
@onready var xr_camera: XRCamera3D            = $XROrigin3D/XRCamera3D
@onready var xr_left_hand: XRController3D     = $XROrigin3D/LeftHand
@onready var xr_right_hand: XRController3D    = $XROrigin3D/RightHand
@onready var left_hand_mesh: MeshInstance3D   = $XROrigin3D/LeftHand/HandMesh
@onready var right_hand_mesh: MeshInstance3D  = $XROrigin3D/RightHand/HandMesh

@onready var pet_node: Node3D                 = $PetAnchor/PetModel
@onready var pet_anim: AnimationPlayer        = $PetAnchor/PetModel/AnimationPlayer

# UI espacial 3D (RF-V009)
@onready var hud_spatial: Node3D             = $SpatialHUD
@onready var needs_panel_3d: Node3D          = $SpatialHUD/NeedsPanel3D
@onready var action_wheel_3d: Node3D         = $SpatialHUD/ActionWheel3D

# Ambiente 360° (RF-V004)
@onready var environment_360: WorldEnvironment = $WorldEnvironment
@onready var shelter_area: Node3D              = $ShelterEnvironment

# Vignette (anti-enjoo RF-V008)
@onready var vignette_overlay: MeshInstance3D = $XROrigin3D/XRCamera3D/VignetteOverlay

# ──────────────────────────────────────────────
var _sistema_cuidados: SistemaCuidados
var _sistema_progressao: SistemaProgressao
var _sistema_eventos: SistemaEventos

# Estado VR
var _left_grip_pressed: bool  = false
var _right_grip_pressed: bool = false
var _locomotion_mode: String  = "teleport"   # "teleport" ou "free" (RF-V007)
var _vignette_active: bool    = false
var _pet_interaction_zone: Area3D = null
var _gaze_target: Node3D = null

# Constantes VR
const MIN_FRAME_RATE := 72          # Google Cardboard (RNF-P002)
const TARGET_FRAME_RATE := 90       # Meta Quest 3 (RNF-P002)
const HUD_DISTANCE := 1.2           # metros à frente da câmera (RNF-U006)
const HAPTIC_INTENSITY := 0.5
const HAPTIC_DURATION := 0.1

# ──────────────────────────────────────────────
func _ready() -> void:
	_initialize_xr()
	_create_subsystems()
	_connect_signals()
	_setup_spatial_hud()
	_apply_vr_settings()
	AudioManager.play_music("vr_ambient")

# ──────────────────────────────────────────────
# Inicialização OpenXR (RNF-I011)
# ──────────────────────────────────────────────
func _initialize_xr() -> void:
	var xr_interface := XRServer.find_interface("OpenXR")
	if xr_interface == null:
		push_error("[VRPetCare] Interface OpenXR não encontrada.")
		GameManager.go_to_pet_care()   # Fallback para mobile
		return

	if xr_interface.initialize():
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = TARGET_FRAME_RATE
		print("[VRPetCare] OpenXR inicializado. Alvo: %d Hz" % TARGET_FRAME_RATE)
	else:
		push_error("[VRPetCare] Falha ao inicializar OpenXR.")
		GameManager.go_to_pet_care()

func _create_subsystems() -> void:
	_sistema_cuidados   = SistemaCuidados.new()
	_sistema_progressao = SistemaProgressao.new()
	_sistema_eventos    = SistemaEventos.new()
	add_child(_sistema_cuidados)
	add_child(_sistema_progressao)
	add_child(_sistema_eventos)

func _connect_signals() -> void:
	# Controles dos motion controllers (RF-V001)
	xr_left_hand.button_pressed.connect(_on_left_button_pressed)
	xr_left_hand.button_released.connect(_on_left_button_released)
	xr_right_hand.button_pressed.connect(_on_right_button_pressed)
	xr_right_hand.button_released.connect(_on_right_button_released)

	# Área de interação por proximidade do pet (RF-V005)
	_pet_interaction_zone = pet_node.find_child("InteractionZone", true, false) as Area3D
	if _pet_interaction_zone:
		_pet_interaction_zone.body_entered.connect(_on_hand_entered_pet_zone)
		_pet_interaction_zone.body_exited.connect(_on_hand_exited_pet_zone)

	# GameManager
	GameManager.pet_needs_updated.connect(_on_needs_updated)
	GameManager.emergency_event_triggered.connect(_on_emergency_triggered)
	_sistema_cuidados.educational_tip_ready.connect(_show_spatial_tip)
	_sistema_cuidados.care_applied.connect(_on_care_applied_vr)

# ──────────────────────────────────────────────
# HUD espacial 3D (RF-V009) — máx 10% do FOV (RNF-D006)
# ──────────────────────────────────────────────
func _setup_spatial_hud() -> void:
	if hud_spatial == null:
		return
	# HUD segue a câmera com suavização
	hud_spatial.set_as_top_level(true)

func _update_spatial_hud() -> void:
	if hud_spatial == null:
		return
	var cam_forward := -xr_camera.global_transform.basis.z
	var target_pos := xr_camera.global_position + cam_forward * HUD_DISTANCE
	# Suaviza o movimento do HUD (sem elementos fixos na periferia RNF-U006)
	hud_spatial.global_position = hud_spatial.global_position.lerp(target_pos, 0.05)
	hud_spatial.look_at(xr_camera.global_position)

# ──────────────────────────────────────────────
# Motion Controllers — botões (RF-V001)
# ──────────────────────────────────────────────
func _on_right_button_pressed(button_name: String) -> void:
	match button_name:
		"trigger_click":
			_try_interact_with_pet()
		"grip_click":
			_right_grip_pressed = true
			_show_action_wheel()
		"ax_button":
			_apply_care_vr(SistemaCuidados.CareType.FEED)
		"by_button":
			_apply_care_vr(SistemaCuidados.CareType.PLAY)

func _on_right_button_released(button_name: String) -> void:
	if button_name == "grip_click":
		_right_grip_pressed = false
		_hide_action_wheel()

func _on_left_button_pressed(button_name: String) -> void:
	match button_name:
		"trigger_click":
			_teleport_to_gaze_target()
		"grip_click":
			_left_grip_pressed = true
			_toggle_locomotion_mode()
		"ax_button":
			_apply_care_vr(SistemaCuidados.CareType.BATHE)
		"by_button":
			_apply_care_vr(SistemaCuidados.CareType.VET)

func _on_left_button_released(button_name: String) -> void:
	if button_name == "grip_click":
		_left_grip_pressed = false

# ──────────────────────────────────────────────
# Interação por proximidade (RF-V005)
# ──────────────────────────────────────────────
func _on_hand_entered_pet_zone(body: Node3D) -> void:
	if body == xr_right_hand or body == xr_left_hand:
		_haptic_both_hands(0.3, 0.15)
		UIManager.show_toast("Toque o pet para interagir!")
		pet_anim.play("idle_curious")

func _on_hand_exited_pet_zone(_body: Node3D) -> void:
	pet_anim.play("idle")

func _try_interact_with_pet() -> void:
	# Verifica se mão direita está na zona de interação
	if _pet_interaction_zone == null:
		return
	var overlapping := _pet_interaction_zone.get_overlapping_bodies()
	if xr_right_hand in overlapping:
		_apply_care_vr(SistemaCuidados.CareType.GROOM)
		UIManager.show_toast("Você acariciou %s! 💕" % GameManager.current_pet_virtual.get("name", ""))

# ──────────────────────────────────────────────
# Aplicar cuidado em VR
# ──────────────────────────────────────────────
func _apply_care_vr(care_type: int) -> void:
	var success := _sistema_cuidados.apply_care(care_type)
	if success:
		_haptic_right_hand(HAPTIC_INTENSITY, HAPTIC_DURATION)
		var anim := _care_animation(care_type)
		if pet_anim.has_animation(anim):
			pet_anim.play(anim)
		_sistema_progressao.check_first_care_achievements(
			SistemaCuidados.CareType.keys()[care_type]
		)
		_sistema_eventos.try_trigger_random_event()

func _care_animation(care_type: int) -> String:
	match care_type:
		SistemaCuidados.CareType.FEED:    return "eat"
		SistemaCuidados.CareType.HYDRATE: return "drink"
		SistemaCuidados.CareType.BATHE:   return "bath"
		SistemaCuidados.CareType.PLAY:    return "play"
		SistemaCuidados.CareType.SLEEP:   return "sleep"
		SistemaCuidados.CareType.GROOM:   return "groom"
		_: return "happy"

func _on_care_applied_vr(_type: String, _effect: float, _needs: Dictionary) -> void:
	SaveSystem.save_pet_virtual(GameManager.current_pet_virtual)

# ──────────────────────────────────────────────
# Locomoção VR (RF-V007) — teleporte + livre
# ──────────────────────────────────────────────
func _teleport_to_gaze_target() -> void:
	if _locomotion_mode != "teleport":
		return
	# Raycast da câmera para o chão
	var space := get_world_3d().direct_space_state
	var ray_from := xr_camera.global_position
	var ray_to   := ray_from + (-xr_camera.global_transform.basis.z * 10.0)
	var query    := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	var hit      := space.intersect_ray(query)
	if not hit.is_empty():
		_activate_vignette(true)
		xr_origin.global_position = hit.get("position", xr_origin.global_position)
		await get_tree().create_timer(0.2).timeout
		_activate_vignette(false)

func _toggle_locomotion_mode() -> void:
	_locomotion_mode = "free" if _locomotion_mode == "teleport" else "teleport"
	UIManager.show_toast("Locomoção: %s" % _locomotion_mode)

func _process_free_locomotion(delta: float) -> void:
	if _locomotion_mode != "free":
		return
	var joystick_val := xr_left_hand.get_vector2("primary")
	if joystick_val.length() > 0.1:
		_activate_vignette(true)
		var forward := -xr_camera.global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := xr_camera.global_transform.basis.x
		right.y = 0.0
		var move := (forward * joystick_val.y + right * joystick_val.x) * 3.0 * delta
		xr_origin.global_position += move
	else:
		_activate_vignette(false)

# ──────────────────────────────────────────────
# Vignette anti-enjoo (RF-V008)
# ──────────────────────────────────────────────
func _activate_vignette(active: bool) -> void:
	if vignette_overlay == null:
		return
	var settings := SaveSystem.load_settings()
	if not settings.get("vr_comfort", true):
		return
	vignette_overlay.visible = active
	_vignette_active = active

# ──────────────────────────────────────────────
# Áudio espacial 3D (RF-V006)
# ──────────────────────────────────────────────
func _play_spatial_sfx(sfx_name: String, position: Vector3) -> void:
	AudioManager.create_spatial_audio(sfx_name, position)

# ──────────────────────────────────────────────
# UI Dica espacial
# ──────────────────────────────────────────────
func _show_spatial_tip(tip: String) -> void:
	# Posiciona label 3D à frente do jogador em VR
	var tip_node := hud_spatial.find_child("TipLabel3D", true, false) as Label3D
	if tip_node:
		tip_node.text    = "💡 " + tip
		tip_node.visible = true
		await get_tree().create_timer(5.0).timeout
		tip_node.visible = false

# ──────────────────────────────────────────────
# Roda de ações VR
# ──────────────────────────────────────────────
func _show_action_wheel() -> void:
	if action_wheel_3d:
		action_wheel_3d.visible = true

func _hide_action_wheel() -> void:
	if action_wheel_3d:
		action_wheel_3d.visible = false

# ──────────────────────────────────────────────
# Emergência em VR
# ──────────────────────────────────────────────
func _on_emergency_triggered(event: Dictionary) -> void:
	_haptic_both_hands(1.0, 0.5)
	_play_spatial_sfx("emergency_alert", pet_node.global_position)
	_show_spatial_tip(event.get("descricao", "Emergência!"))

# ──────────────────────────────────────────────
# HUD necessidades (atualização via sinal)
# ──────────────────────────────────────────────
func _on_needs_updated(_pet_id: String, _needs: Dictionary) -> void:
	# Atualiza painéis 3D do HUD espacial
	pass  # Implementado via Material shaders no needs_panel_3d

# ──────────────────────────────────────────────
# Haptic feedback (RF-V010)
# ──────────────────────────────────────────────
func _haptic_right_hand(intensity: float, duration: float) -> void:
	xr_right_hand.trigger_haptic_pulse("haptic", 0.0, intensity, duration, 0.0)

func _haptic_left_hand(intensity: float, duration: float) -> void:
	xr_left_hand.trigger_haptic_pulse("haptic", 0.0, intensity, duration, 0.0)

func _haptic_both_hands(intensity: float, duration: float) -> void:
	_haptic_right_hand(intensity, duration)
	_haptic_left_hand(intensity, duration)

# ──────────────────────────────────────────────
func _process(delta: float) -> void:
	_update_spatial_hud()
	_process_free_locomotion(delta)

func _apply_vr_settings() -> void:
	var settings := SaveSystem.load_settings()
	_locomotion_mode = settings.get("vr_locomotion", "teleport")
