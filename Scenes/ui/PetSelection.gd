## PetSelection.gd
## Tela de seleção e catálogo de pets disponíveis para apadrinhamento (RF003, UC002).
## Integra com AdotaPetAPI e permite apadrinhamento virtual (RF004).
extends Control

# ──────────────────────────────────────────────
@onready var grid_pets: GridContainer       = $ScrollContainer/GridPets
@onready var filter_species: OptionButton   = $Filters/FilterSpecies
@onready var btn_filter_apply: Button       = $Filters/BtnApply
@onready var search_bar: LineEdit           = $Filters/SearchBar
@onready var lbl_no_results: Label          = $LblNoResults
@onready var loading_spinner: TextureRect   = $LoadingSpinner
@onready var panel_pet_detail: PanelContainer = $PanelPetDetail
@onready var detail_name: Label             = $PanelPetDetail/VBox/LblName
@onready var detail_species: Label          = $PanelPetDetail/VBox/LblSpecies
@onready var detail_description: RichTextLabel = $PanelPetDetail/VBox/RtlDescription
@onready var detail_story: RichTextLabel    = $PanelPetDetail/VBox/RtlStory
@onready var btn_sponsor: Button            = $PanelPetDetail/VBox/BtnSponsor
@onready var btn_detail_close: Button       = $PanelPetDetail/BtnClose
@onready var confirm_dialog: CanvasLayer    = $ConfirmDialog
@onready var toast_container: Control       = $ToastContainer

# Cena pré-fabricada de card de pet
const PetCard := preload("res://scenes/ui/components/PetCard.tscn")

var _all_pets: Array = []
var _selected_pet: Dictionary = {}

# ──────────────────────────────────────────────
func _ready() -> void:
	UIManager.register_toast_container(toast_container)
	UIManager.register_dialog_overlay(confirm_dialog)
	_setup_filters()
	_connect_signals()
	_load_pets()

func _setup_filters() -> void:
	filter_species.add_item("Todos", 0)
	filter_species.add_item("Cães", 1)
	filter_species.add_item("Gatos", 2)
	filter_species.add_item("Outros", 3)

func _connect_signals() -> void:
	AdotaPetAPI.pets_loaded.connect(_on_pets_loaded)
	AdotaPetAPI.sponsorship_confirmed.connect(_on_sponsorship_confirmed)
	AdotaPetAPI.api_error.connect(_on_api_error)
	btn_filter_apply.pressed.connect(_apply_filters)
	search_bar.text_changed.connect(_on_search_changed)
	btn_sponsor.pressed.connect(_on_sponsor_pressed)
	btn_detail_close.pressed.connect(_close_detail_panel)
	UIManager.dialog_confirmed.connect(_on_confirm_sponsorship)
	GameManager.back_button_pressed if GameManager.has_signal("back_button_pressed") else null

# ──────────────────────────────────────────────
# Carregamento de pets
# ──────────────────────────────────────────────
func _load_pets(species: String = "") -> void:
	loading_spinner.visible = true
	lbl_no_results.visible  = false
	AdotaPetAPI.fetch_available_pets(species)

func _on_pets_loaded(pets: Array) -> void:
	loading_spinner.visible = false
	_all_pets = pets
	_render_pet_cards(pets)

func _render_pet_cards(pets: Array) -> void:
	# Limpa grid
	for child in grid_pets.get_children():
		child.queue_free()

	if pets.is_empty():
		lbl_no_results.visible = true
		lbl_no_results.text = "Nenhum pet encontrado. Tente outros filtros."
		return

	lbl_no_results.visible = false
	for pet in pets:
		var card: Control = PetCard.instantiate()
		grid_pets.add_child(card)
		card.setup(pet)
		card.selected.connect(_on_pet_card_selected.bind(pet))

# ──────────────────────────────────────────────
# Filtros e busca (RF003)
# ──────────────────────────────────────────────
func _apply_filters() -> void:
	var species_idx := filter_species.selected
	var species_map := {0: "", 1: "dog", 2: "cat", 3: "other"}
	var species := species_map.get(species_idx, "")
	_load_pets(species)

func _on_search_changed(query: String) -> void:
	if query.strip_edges().is_empty():
		_render_pet_cards(_all_pets)
		return
	var filtered := _all_pets.filter(func(p):
		return p.get("name", "").to_lower().contains(query.to_lower()) or
		       p.get("breed", "").to_lower().contains(query.to_lower())
	)
	_render_pet_cards(filtered)

# ──────────────────────────────────────────────
# Seleção de pet — exibe painel de detalhes
# ──────────────────────────────────────────────
func _on_pet_card_selected(pet: Dictionary) -> void:
	_selected_pet = pet
	detail_name.text    = pet.get("name", "Sem nome")
	detail_species.text = _species_label(pet.get("species", ""))

	var age_months: int = pet.get("age_months", 0)
	var age_str := "%d meses" % age_months if age_months < 12 else "%d ano(s)" % (age_months / 12)

	detail_description.text = "[b]Raça:[/b] %s\n[b]Idade:[/b] %s\n[b]Gênero:[/b] %s\n\n%s" % [
		pet.get("breed", "SRD"), age_str,
		_gender_label(pet.get("gender", "")),
		pet.get("description", "")
	]
	detail_story.text = "[i]%s[/i]" % pet.get("story", "Sem história cadastrada.")

	btn_sponsor.disabled = not pet.get("available", true)
	btn_sponsor.text     = "Apadrinhar" if pet.get("available", true) else "Indisponível"

	panel_pet_detail.visible = true
	_animate_panel_in()

func _close_detail_panel() -> void:
	var tween := create_tween()
	tween.tween_property(panel_pet_detail, "position:y",
		get_viewport().get_visible_rect().size.y, 0.25)
	tween.tween_callback(func(): panel_pet_detail.visible = false)

func _animate_panel_in() -> void:
	panel_pet_detail.position.y = get_viewport().get_visible_rect().size.y
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(panel_pet_detail, "position:y", 0.0, 0.35)

# ──────────────────────────────────────────────
# Apadrinhamento (UC002, RN001)
# ──────────────────────────────────────────────
func _on_sponsor_pressed() -> void:
	if not GameManager.active_sponsorship.is_empty():
		UIManager.show_toast("Encerre o apadrinhamento atual antes de iniciar outro.")
		return

	# Diálogo de confirmação (RNF-U009)
	UIManager.show_confirmation_dialog(
		"sponsor_%s" % _selected_pet.get("id", ""),
		"Apadrinhar %s?" % _selected_pet.get("name", ""),
		"Você cuidará de %s virtualmente. Isso exige atenção diária!\nDeseja continuar?" %
			_selected_pet.get("name", ""),
		"Sim, quero apadrinhar!",
		"Ainda não"
	)

func _on_confirm_sponsorship(dialog_id: String) -> void:
	if not dialog_id.begins_with("sponsor_"):
		return
	UIManager.show_loading("Confirmando disponibilidade...")
	var user_id: String = GameManager.current_user.get("id", "guest")
	AdotaPetAPI.confirm_sponsorship_availability(_selected_pet.get("id", ""), user_id)

func _on_sponsorship_confirmed(success: bool, message: String) -> void:
	UIManager.hide_loading()
	if success:
		var started := GameManager.start_sponsorship(_selected_pet)
		if started:
			UIManager.show_toast("🐾 Bem-vindo(a), %s!" % _selected_pet.get("name", ""))
			await get_tree().create_timer(1.5).timeout
			GameManager.go_to_pet_care()
	else:
		# Animal pode ter sido adotado (RN002)
		UIManager.show_toast(message)
		_selected_pet["available"] = false
		btn_sponsor.disabled = true
		btn_sponsor.text = "Indisponível"
		_load_pets()   # Recarrega lista atualizada

func _on_api_error(code: int, message: String) -> void:
	UIManager.hide_loading()
	UIManager.show_toast("Erro %d: %s" % [code, message])
	loading_spinner.visible = false

# ──────────────────────────────────────────────
# Helpers de label
# ──────────────────────────────────────────────
func _species_label(species: String) -> String:
	match species:
		"dog": return "🐶 Cão"
		"cat": return "🐱 Gato"
		"rabbit": return "🐰 Coelho"
		_: return "🐾 Animal"

func _gender_label(gender: String) -> String:
	match gender:
		"male": return "Macho"
		"female": return "Fêmea"
		_: return "Não informado"
