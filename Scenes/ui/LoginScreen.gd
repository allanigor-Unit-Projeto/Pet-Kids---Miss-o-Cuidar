## LoginScreen.gd
## Tela de login e cadastro (RF001, RF002). Suporta email/senha, Google e Apple ID.
## Controle parental para menores de 13 anos (RN006, RNF-S003).
extends Control


# Referências UI
@onready var tab_container: TabContainer     = $TabContainer
@onready var btn_login_email: Button         = $TabContainer/Login/VBox/BtnLoginEmail
@onready var btn_google: Button              = $TabContainer/Login/VBox/BtnGoogle
@onready var btn_apple: Button               = $TabContainer/Login/VBox/BtnApple
@onready var inp_email: LineEdit             = $TabContainer/Login/VBox/InpEmail
@onready var inp_password: LineEdit          = $TabContainer/Login/VBox/InpPassword
@onready var lbl_login_error: Label          = $TabContainer/Login/VBox/LblError

@onready var inp_reg_name: LineEdit          = $TabContainer/Cadastro/VBox/InpName
@onready var inp_reg_email: LineEdit         = $TabContainer/Cadastro/VBox/InpEmail
@onready var inp_reg_password: LineEdit      = $TabContainer/Cadastro/VBox/InpPassword
@onready var inp_reg_birth: LineEdit         = $TabContainer/Cadastro/VBox/InpBirth
@onready var btn_register: Button            = $TabContainer/Cadastro/VBox/BtnRegister
@onready var lbl_reg_error: Label            = $TabContainer/Cadastro/VBox/LblError
@onready var chk_terms: CheckBox             = $TabContainer/Cadastro/VBox/ChkTerms

@onready var loading_overlay: CanvasLayer    = $LoadingOverlay
@onready var toast_container: Control        = $ToastContainer


func _ready() -> void:
	UIManager.register_loading_overlay(loading_overlay)
	UIManager.register_toast_container(toast_container)
	UIManager.hide_loading()

	_connect_signals()
	_setup_accessibility()
	_check_existing_session()


# Conexão sinais de botões

func _connect_signals() -> void:
	# Login
	btn_login_email.pressed.connect(_on_login_email_pressed)
	btn_google.pressed.connect(_on_google_pressed)
	btn_apple.pressed.connect(_on_apple_pressed)
	inp_password.text_submitted.connect(func(_t): _on_login_email_pressed())

	# Cadastro
	btn_register.pressed.connect(_on_register_pressed)
	inp_reg_birth.text_changed.connect(_on_birth_date_changed)

	# AuthService
	AuthService.login_success.connect(_on_login_success)
	AuthService.login_failed.connect(_on_login_failed)
	AuthService.registration_success.connect(_on_registration_success)
	AuthService.registration_failed.connect(_on_registration_failed)


# Acessibilidade (RNF-U001, RNF-U004)

func _setup_accessibility() -> void:
	inp_email.placeholder_text    = "seu@email.com"
	inp_password.placeholder_text = "Senha"
	inp_password.secret           = true

	inp_reg_name.placeholder_text  = "Seu nome completo"
	inp_reg_email.placeholder_text = "seu@email.com"
	inp_reg_password.placeholder_text = "Mínimo 8 caracteres"
	inp_reg_password.secret        = true
	inp_reg_birth.placeholder_text = "AAAA-MM-DD"

	# Tooltips para leitores de tela (TalkBack/VoiceOver)
	btn_login_email.tooltip_text = "Entrar com email e senha"
	btn_google.tooltip_text      = "Entrar com conta Google"
	btn_apple.tooltip_text       = "Entrar com Apple ID"
	btn_register.tooltip_text    = "Criar nova conta"


# Verifica sessão salva

func _check_existing_session() -> void:
	if AuthService.is_logged_in():
		GameManager.go_to_main_menu()


# Handlers de botões — Login

func _on_login_email_pressed() -> void:
	lbl_login_error.visible = false
	var email    := inp_email.text.strip_edges()
	var password := inp_password.text

	if not _is_valid_email(email):
		_show_login_error("E-mail inválido.")
		return
	if password.length() < 6:
		_show_login_error("A senha deve ter pelo menos 6 caracteres.")
		return

	UIManager.show_loading("Autenticando...")
	btn_login_email.disabled = true
	AuthService.login_email(email, password)

func _on_google_pressed() -> void:
	UIManager.show_loading("Conectando ao Google...")
	# Em produção: integração com Google Sign-In SDK
	# Simulação:
	await get_tree().create_timer(1.0).timeout
	AuthService.login_oauth("google", "simulated_google_token")

func _on_apple_pressed() -> void:
	UIManager.show_loading("Conectando à Apple...")
	await get_tree().create_timer(1.0).timeout
	AuthService.login_oauth("apple", "simulated_apple_token")


# Handlers de botões — Cadastro

func _on_register_pressed() -> void:
	lbl_reg_error.visible = false

	if not chk_terms.button_pressed:
		_show_reg_error("Aceite os Termos de Uso para continuar.")
		return

	var name_val  := inp_reg_name.text.strip_edges()
	var email_val := inp_reg_email.text.strip_edges()
	var pass_val  := inp_reg_password.text
	var birth_val := inp_reg_birth.text.strip_edges()

	if name_val.length() < 2:
		_show_reg_error("Digite seu nome completo.")
		return
	if not _is_valid_email(email_val):
		_show_reg_error("E-mail inválido.")
		return
	if pass_val.length() < 8:
		_show_reg_error("A senha deve ter no mínimo 8 caracteres.")
		return
	if not _is_valid_date(birth_val):
		_show_reg_error("Data inválida. Use o formato AAAA-MM-DD.")
		return

	UIManager.show_loading("Criando conta...")
	btn_register.disabled = true
	AuthService.register(name_val, email_val, pass_val, birth_val)

func _on_birth_date_changed(text: String) -> void:
	# Mostra aviso de controle parental para menores (RN006)
	if text.length() >= 4:
		var year := int(text.substr(0, 4))
		var age  := Time.get_date_dict_from_system().get("year", 2026) - year
		if age < 13:
			UIManager.show_toast("Conta para menor: será necessário aprovação de responsável.")


# Callbacks de AuthService

func _on_login_success(_user: Dictionary) -> void:
	UIManager.hide_loading()
	btn_login_email.disabled = false
	if GameManager.active_sponsorship.is_empty():
		GameManager.go_to_pet_selection()
	else:
		GameManager.go_to_pet_care()

func _on_login_failed(reason: String) -> void:
	UIManager.hide_loading()
	btn_login_email.disabled = false
	_show_login_error(reason)

func _on_registration_success(_user: Dictionary) -> void:
	UIManager.hide_loading()
	btn_register.disabled = false
	UIManager.show_toast("Conta criada com sucesso! Bem-vindo(a)!")
	tab_container.current_tab = 0   # Volta para aba de login

func _on_registration_failed(reason: String) -> void:
	UIManager.hide_loading()
	btn_register.disabled = false
	_show_reg_error(reason)


# Exibição de erros (RNF-U007 — linguagem não técnica)

func _show_login_error(msg: String) -> void:
	lbl_login_error.text    = msg
	lbl_login_error.visible = true

func _show_reg_error(msg: String) -> void:
	lbl_reg_error.text    = msg
	lbl_reg_error.visible = true


# Validações

func _is_valid_email(email: String) -> bool:
	return email.contains("@") and email.contains(".") and email.length() > 5

func _is_valid_date(date: String) -> bool:
	if date.length() != 10:
		return false
	var parts := date.split("-")
	if parts.size() != 3:
		return false
	return parts[0].is_valid_int() and parts[1].is_valid_int() and parts[2].is_valid_int()
