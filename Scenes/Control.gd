extends Control # Ou CanvasLayer, dependendo de onde você anexou o script

@onready var prev_scene_button = $"BotaoVoltar" # Caminho para o botão "Cena Anterior"
@onready var next_scene_button = $"BotaoAvancar" # Caminho para o botão "Próxima Cena"

# Array com os caminhos das suas cenas.
# Certifique-se de que os caminhos estão corretos (ex: "res://cenas/cena_1.tscn")
@export var scene_paths: Array[String] = [
	"res://Scenes/PanoramaLogin.tscn",
	"res://Scenes/PetKids.tscn"
]

var current_scene_index = 0

func _ready():
	# Conecta os sinais "pressed" dos botões às funções correspondentes
	if prev_scene_button:
		prev_scene_button.pressed.connect(_on_prev_scene_button_pressed)
	if next_scene_button:
		next_scene_button.pressed.connect(_on_next_scene_button_pressed)
	
	# Encontra o índice da cena atual no array, se ela estiver lá
	var current_scene_path = get_tree().current_scene.scene_file_path
	for i in range(scene_paths.size()):
		if scene_paths[i] == current_scene_path:
			current_scene_index = i
			break
	
	_update_button_states() # Atualiza o estado dos botões (habilitado/desabilitado)

func _on_prev_scene_button_pressed():
	if current_scene_index > 0:
		current_scene_index -= 1
		change_scene()

func _on_next_scene_button_pressed():
	if current_scene_index < scene_paths.size() - 1:
		current_scene_index += 1
		change_scene()

func change_scene():
	var next_scene_path = scene_paths[current_scene_index]
	if ResourceLoader.exists(next_scene_path):
		get_tree().change_scene_to_file(next_scene_path)
	else:
		print("Erro: Cena não encontrada no caminho: ", next_scene_path)
	
	_update_button_states()

func _update_button_states():
	# Desabilita o botão "Anterior" se estiver na primeira cena
	if prev_scene_button:
		prev_scene_button.disabled = (current_scene_index == 0)
	
	# Desabilita o botão "Próxima" se estiver na última cena
	if next_scene_button:
		next_scene_button.disabled = (current_scene_index == scene_paths.size() - 1)
