## Settings.gd
## Tela de configurações: gráficos, áudio, acessibilidade, idioma (RF019, RNF-U003).
## Suporte a modo daltônico (RNF-U005), reduzir movimento (RNF-D005), tema escuro (RNF-D008).
extends Control

@onready var slider_master: HSlider    = $Scroll/VBox/AudioSection/SliderMaster
@onready var slider_sfx: HSlider       = $Scroll/VBox/AudioSection/SliderSFX
@onready var slider_music: HSlider     = $Scroll/VBox/AudioSection/SliderMusic
@onready var opt_graphics: OptionButton = $Scroll/VBox/GraphicsSection/OptGraphics
@onready var opt_language: OptionButton = $Scroll/VBox/GeneralSection/OptLanguage
@onready var opt_colorblind: OptionButton = $Scroll/VBox/AccessSection/OptColorblind
@onready var chk_dark_theme: CheckBox  = $Scroll/VBox/GeneralSection/ChkDark
@onready var chk_reduce_motion: CheckBox = $Scroll/VBox/AccessSection/ChkReduceMotion
@onready var chk_parental: CheckBox    = $Scroll/VBox/GeneralSection/ChkParental
@onready var opt_vr_locomotion: OptionButton = $Scroll/VBox/VRSection/OptLocomotion
@onready var chk_vr_comfort: CheckBox  = $Scroll/VBox/VRSection/ChkVRComfort
@onready var vr_section: VBoxContainer = $Scroll/VBox/VRSection
@onready var btn_save: Button          = $BtnSave
@onready var btn_back: Button          = $BtnBack
@onready var btn_delete_data: Button   = $Scroll/VBox/DangerSection/BtnDeleteData
@onready var dialog_overlay: CanvasLayer = $DialogOverlay
@onready var toast_container: Control  = $ToastContainer
@onready var lbl_version: Label        = $LblVersion

var _settings: Dictionary = {}


func _ready() -> void:
	UIManager.register_dialog_overlay(dialog_overlay)
	UIManager.register_toast_container(toast_container)
	lbl_version.text = "v%s" % GameManager.VERSION
	_load_settings()
	_setup_options()
	_connect_signals()
	_show_vr_section_if_needed()

func _load_settings() -> void:
	_settings = SaveSystem.load_settings()

func _setup_options() -> void:
	# Áudio
	slider_master.value = _settings.get("audio_master", 1.0) * 100
	slider_sfx.value    = _settings.get("audio_sfx", 1.0) * 100
	slider_music.value  = _settings.get("audio_music", 0.8) * 100

	# Gráficos
	opt_graphics.clear()
	opt_graphics.add_item("Baixo", 0)
	opt_graphics.add_item("Médio", 1)
	opt_graphics.add_item("Alto", 2)
	var q_map := {"low": 0, "medium": 1, "high": 2}
	opt_graphics.selected = q_map.get(_settings.get("graphics_quality", "medium"), 1)

	# Idioma (RNF-U003)
	opt_language.clear()
	opt_language.add_item("Português (BR)", 0)
	opt_language.add_item("English (US)", 1)
	opt_language.selected = 0 if _settings.get("language", "pt_BR") == "pt_BR" else 1

	# Acessibilidade — modo daltônico (RNF-U005)
	opt_colorblind.clear()
	opt_colorblind.add_item("Nenhum", 0)
	opt_colorblind.add_item("Deuteranopia (vermelho-verde)", 1)
	opt_colorblind.add_item("Protanopia (vermelho-verde)", 2)
	opt_colorblind.add_item("Tritanopia (azul-amarelo)", 3)
	var cb_map := {"none": 0, "deuteranopia": 1, "protanopia": 2, "tritanopia": 3}
	opt_colorblind.selected = cb_map.get(_settings.get("colorblind_mode", "none"), 0)

	# Outros
	chk_dark_theme.button_pressed    = _settings.get("dark_theme", false)
	chk_reduce_motion.button_pressed = _settings.get("reduce_motion", false)
	chk_parental.button_pressed      = _settings.get("parental_control", false)

	# VR (RF-V007)
	opt_vr_locomotion.clear()
	opt_vr_locomotion.add_item("Teleporte (recomendado)", 0)
	opt_vr_locomotion.add_item("Movimento livre", 1)
	opt_vr_locomotion.selected = 0 if _settings.get("vr_locomotion", "teleport") == "teleport" else 1
	chk_vr_comfort.button_pressed = _settings.get("vr_comfort", true)

func _connect_signals() -> void:
	slider_master.value_changed.connect(func(v): AudioManager.set_master_volume(v / 100.0))
	slider_sfx.value_changed.connect(func(v): AudioManager.set_sfx_volume(v / 100.0))
	slider_music.value_changed.connect(func(v): AudioManager.set_music_volume(v / 100.0))
	btn_save.pressed.connect(_on_save_pressed)
	btn_back.pressed.connect(func(): get_tree().pop_current_scene() if false else GameManager.go_to_pet_care())
	btn_delete_data.pressed.connect(_on_delete_data_pressed)
	UIManager.dialog_confirmed.connect(_on_dialog_confirmed)

func _show_vr_section_if_needed() -> void:
	vr_section.visible = GameManager.is_vr_mode


# Salvar configurações

func _on_save_pressed() -> void:
	var q_keys := {0: "low", 1: "medium", 2: "high"}
	var lang_keys := {0: "pt_BR", 1: "en_US"}
	var cb_keys := {0: "none", 1: "deuteranopia", 2: "protanopia", 3: "tritanopia"}
	var loco_keys := {0: "teleport", 1: "free"}

	_settings = {
		"audio_master":      slider_master.value / 100.0,
		"audio_sfx":         slider_sfx.value / 100.0,
		"audio_music":       slider_music.value / 100.0,
		"graphics_quality":  q_keys.get(opt_graphics.selected, "medium"),
		"language":          lang_keys.get(opt_language.selected, "pt_BR"),
		"colorblind_mode":   cb_keys.get(opt_colorblind.selected, "none"),
		"dark_theme":        chk_dark_theme.button_pressed,
		"reduce_motion":     chk_reduce_motion.button_pressed,
		"parental_control":  chk_parental.button_pressed,
		"vr_locomotion":     loco_keys.get(opt_vr_locomotion.selected, "teleport"),
		"vr_comfort":        chk_vr_comfort.button_pressed
	}

	SaveSystem.save_settings(_settings)
	_apply_realtime_settings()
	UIManager.show_toast("Configurações salvas!")
	AudioManager.play_sfx("button_confirm")

func _apply_realtime_settings() -> void:
	# Idioma em tempo real (RNF-U003)
	TranslationServer.set_locale(_settings.get("language", "pt_BR"))

	# Tema escuro (RNF-D008)
	if _settings.get("dark_theme", false):
		_apply_dark_theme()
	else:
		_apply_light_theme()

	# Modo daltônico (RNF-U005)
	_apply_colorblind_mode(_settings.get("colorblind_mode", "none"))

func _apply_dark_theme() -> void:
	# Altera Environment conforme tema
	RenderingServer.set_default_clear_color(Color("#1a1a1a"))

func _apply_light_theme() -> void:
	RenderingServer.set_default_clear_color(Color("#F1EFE8"))

func _apply_colorblind_mode(mode: String) -> void:
	match mode:
		"deuteranopia":
			# Ajusta paleta via Environment shader
			print("[Settings] Modo daltônico: Deuteranopia")
		"protanopia":
			print("[Settings] Modo daltônico: Protanopia")
		"tritanopia":
			print("[Settings] Modo daltônico: Tritanopia")
		_:
			print("[Settings] Sem filtro de daltonismo")


# Excluir dados (RNF-U009 — ação destrutiva)

func _on_delete_data_pressed() -> void:
	UIManager.show_confirmation_dialog(
		"delete_all_data",
		"Excluir todos os dados?",
		"Esta ação é IRREVERSÍVEL. Todo progresso, apadrinhamentos e configurações serão apagados.\n\nDeseja continuar?",
		"Excluir permanentemente",
		"Cancelar"
	)

func _on_dialog_confirmed(dialog_id: String) -> void:
	if dialog_id == "delete_all_data":
		SaveSystem.delete_all_data()
		AuthService._force_logout()
		UIManager.show_toast("Dados excluídos. Até mais!")
		await get_tree().create_timer(2.0).timeout
		GameManager.go_to_login()
