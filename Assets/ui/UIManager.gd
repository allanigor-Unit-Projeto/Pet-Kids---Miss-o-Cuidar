## UIManager.gd
## Singleton Autoload: Gerencia overlays, toasts, loading e transições de UI.
## Garante feedback multimodal (visual + sonoro + tátil) em todas as ações (RNF-D009).
extends Node

# ──────────────────────────────────────────────
# Sinais
# ──────────────────────────────────────────────
signal dialog_confirmed(dialog_id: String)
signal dialog_cancelled(dialog_id: String)

# ──────────────────────────────────────────────
# Referências a nós de overlay (injetadas pela cena raiz)
# ──────────────────────────────────────────────
var _loading_overlay: CanvasLayer = null
var _toast_container: Control = null
var _dialog_overlay: CanvasLayer = null
var _level_up_overlay: CanvasLayer = null

# Duração padrão das animações (RNF-D005: 150-400ms)
const ANIM_DURATION := 0.25
const TOAST_DURATION := 2.5

# ──────────────────────────────────────────────
# Registro de overlays (chamado pela cena raiz)
# ──────────────────────────────────────────────
func register_loading_overlay(node: CanvasLayer) -> void:
	_loading_overlay = node

func register_toast_container(node: Control) -> void:
	_toast_container = node

func register_dialog_overlay(node: CanvasLayer) -> void:
	_dialog_overlay = node

func register_level_up_overlay(node: CanvasLayer) -> void:
	_level_up_overlay = node

# ──────────────────────────────────────────────
# Loading
# ──────────────────────────────────────────────
func show_loading(message: String = "Carregando...") -> void:
	if _loading_overlay == null:
		return
	_loading_overlay.visible = true
	var label := _loading_overlay.find_child("MessageLabel", true, false)
	if label:
		label.text = message

func hide_loading() -> void:
	if _loading_overlay == null:
		return
	var tween := create_tween()
	tween.tween_property(_loading_overlay, "modulate:a", 0.0, ANIM_DURATION)
	tween.tween_callback(func(): _loading_overlay.visible = false; _loading_overlay.modulate.a = 1.0)

# ──────────────────────────────────────────────
# Toast (mensagem não-bloqueante)
# ──────────────────────────────────────────────
func show_toast(message: String, duration: float = TOAST_DURATION) -> void:
	if _toast_container == null:
		print("[UIManager] Toast: %s" % message)
		return
	var toast := _create_toast_node(message)
	_toast_container.add_child(toast)
	# Entrada
	toast.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(toast, "modulate:a", 1.0, ANIM_DURATION)
	tween.tween_interval(duration)
	tween.tween_property(toast, "modulate:a", 0.0, ANIM_DURATION)
	tween.tween_callback(toast.queue_free)
	# Feedback tátil (mobile/VR) (RNF-D009)
	_haptic_feedback(0.1)

func _create_toast_node(message: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var label := Label.new()
	label.text = message
	label.add_theme_font_size_override("font_size", 16)
	panel.add_child(label)
	return panel

# ──────────────────────────────────────────────
# Diálogo de confirmação (RNF-U009 — ações destrutivas)
# ──────────────────────────────────────────────
func show_confirmation_dialog(
		dialog_id: String,
		title: String,
		message: String,
		confirm_text: String = "Confirmar",
		cancel_text: String = "Cancelar"
) -> void:
	if _dialog_overlay == null:
		push_warning("[UIManager] Dialog overlay não registrado.")
		return
	_dialog_overlay.visible = true
	_populate_dialog(dialog_id, title, message, confirm_text, cancel_text)
	_animate_in(_dialog_overlay)

func _populate_dialog(
		dialog_id: String, title: String, message: String,
		confirm_text: String, cancel_text: String
) -> void:
	var title_label := _dialog_overlay.find_child("TitleLabel", true, false) as Label
	var msg_label   := _dialog_overlay.find_child("MessageLabel", true, false) as Label
	var confirm_btn := _dialog_overlay.find_child("ConfirmButton", true, false) as Button
	var cancel_btn  := _dialog_overlay.find_child("CancelButton", true, false) as Button

	if title_label:  title_label.text = title
	if msg_label:    msg_label.text = message
	if confirm_btn:
		confirm_btn.text = confirm_text
		# Reconecta sinal evitando duplicatas
		if confirm_btn.pressed.is_connected(_on_dialog_confirmed):
			confirm_btn.pressed.disconnect(_on_dialog_confirmed)
		confirm_btn.pressed.connect(_on_dialog_confirmed.bind(dialog_id))
	if cancel_btn:
		cancel_btn.text = cancel_text
		if cancel_btn.pressed.is_connected(_on_dialog_cancelled):
			cancel_btn.pressed.disconnect(_on_dialog_cancelled)
		cancel_btn.pressed.connect(_on_dialog_cancelled.bind(dialog_id))

func _on_dialog_confirmed(dialog_id: String) -> void:
	_close_dialog()
	dialog_confirmed.emit(dialog_id)

func _on_dialog_cancelled(dialog_id: String) -> void:
	_close_dialog()
	dialog_cancelled.emit(dialog_id)

func _close_dialog() -> void:
	if _dialog_overlay == null:
		return
	_animate_out(_dialog_overlay, func(): _dialog_overlay.visible = false)

# ──────────────────────────────────────────────
# Level Up
# ──────────────────────────────────────────────
func show_level_up(level: int) -> void:
	if _level_up_overlay == null:
		show_toast("🎉 Nível %d alcançado!" % level)
		return
	_level_up_overlay.visible = true
	var label := _level_up_overlay.find_child("LevelLabel", true, false) as Label
	if label:
		label.text = "Nível %d!" % level
	_animate_in(_level_up_overlay)
	AudioManager.play_sfx("level_up")
	_haptic_feedback(0.3)
	await get_tree().create_timer(2.5).timeout
	_animate_out(_level_up_overlay, func(): _level_up_overlay.visible = false)

# ──────────────────────────────────────────────
# Animações de UI (RNF-D005)
# ──────────────────────────────────────────────
func _animate_in(node: CanvasLayer) -> void:
	node.modulate.a = 0.0
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(node, "modulate:a", 1.0, ANIM_DURATION)

func _animate_out(node: CanvasLayer, callback: Callable) -> void:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(node, "modulate:a", 0.0, ANIM_DURATION)
	tween.tween_callback(callback)

# ──────────────────────────────────────────────
# Feedback tátil (mobile + VR) (RNF-D009)
# ──────────────────────────────────────────────
func _haptic_feedback(duration: float = 0.1) -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(int(duration * 1000))

# ──────────────────────────────────────────────
# Acessibilidade — Reduzir Movimento (RNF-D005)
# ──────────────────────────────────────────────
func should_reduce_motion() -> bool:
	return SaveSystem.load_settings().get("reduce_motion", false)

func get_anim_duration() -> float:
	return 0.0 if should_reduce_motion() else ANIM_DURATION
