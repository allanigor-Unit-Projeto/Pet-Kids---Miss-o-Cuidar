extends CharacterBody3D

@onready var animation_player = $AnimationPlayer # Certifique-se de que este é o caminho correto
@export var speed = 1.0 # Velocidade de movimento do personagem
@export var rotation_speed = 3.0 # Velocidade de rotação para virar no próprio eixo (ajuste este valor!)
var animations_list = ["Agree_Gesture", "Casual_Walk", "Running", "Walking"]
var current_animation_index = 0 # Começa com a primeira animação da lista

func _ready():
	if animation_player:
		play_current_animation()
	else:
		print("Nó AnimationPlayer não encontrado!")

func _input(event):
	# Ação para o botão de animação (BotaoAnima).
	# Isso permite que tanto o botão da UI quanto uma tecla mapeada para "perform_animation" acionem a animação.
	if event.is_action_pressed("perform_animation"): # Nova ação mapeada para o BotaoAnima
		next_animation()

	# Se você ainda quiser usar a tecla "espaço" para alternar animações (ui_accept):
	if event.is_action_pressed("ui_accept"): # 'ui_accept' é a tecla espaço por padrão
		next_animation()

func _physics_process(delta):
	# Obtém o vetor de entrada do joystick analógico.
	# Os argumentos são: ação_esquerda, ação_direita, ação_para_frente, ação_para_trás.
	# Certifique-se que essas ações estão mapeadas corretamente para os eixos do seu joystick virtual/físico no Input Map.
	var analog_vector = Input.get_vector("rotate_left", "rotate_right", "move_backward", "move_forward")
	# Nota: get_vector() considera "up" como negativo no eixo Y, e "right" como positivo no eixo X.
	# Seu script original tinha -transform.basis.z para frente, então ajustamos o Y do analog_vector.

	var input_direction = Vector3.ZERO
	var current_rotation_y = rotation.y # Armazena a rotação Y atual

	# --- Lógica de Rotação (usando ações mapeadas para Joypad Analógico ou botões) ---
	# Se o analógico horizontal for usado para girar o personagem:
	if analog_vector.x != 0: # Se o analógico estiver para esquerda ou direita
		current_rotation_y -= analog_vector.x * rotation_speed * delta # x negativo para direita, x positivo para esquerda
		
	# Ou, se você ainda quiser que botões específicos (ou teclado) girem o personagem:
	elif Input.is_action_pressed("rotate_left"): # Ação mapeada para BotaoEsquerda
		current_rotation_y += rotation_speed * delta # Gira para a esquerda
	elif Input.is_action_pressed("rotate_right"): # Ação mapeada para BotaoDireita
		current_rotation_y -= rotation_speed * delta # Gira para a direita (subtrai para girar no sentido horário)
	
	# Aplica a rotação calculada
	rotation.y = current_rotation_y

	# --- Lógica de Movimento (usando ações mapeadas para Joypad Analógico ou botões) ---
	# Se o analógico vertical for usado para mover para frente/trás:
	if analog_vector.y != 0: # Se o analógico estiver para cima ou para baixo
		# Mapeia a entrada Y do analógico para o eixo Z (frente/trás) do mundo 3D
		# Note que analog_vector.y negativo é para frente, e positivo é para trás.
		input_direction = Vector3(0, 0, analog_vector.y)
		
		# Aplica a rotação do personagem à direção de movimento do analógico.
		# Isso faz com que "para frente" no analógico signifique "para frente do personagem".
		input_direction = input_direction.rotated(Vector3.UP, rotation.y)
	
	# Ou, se você ainda quiser que botões específicos (ou teclado) movam o personagem:
	elif Input.is_action_pressed("move_forward"): # Ação mapeada para BotaoFrente
		input_direction += -transform.basis.z # Mover para frente (na direção atual do personagem)
	elif Input.is_action_pressed("move_backward"): # Ação mapeada para BotaoTras
		input_direction += transform.basis.z # Mover para trás (na direção atual do personagem)
	
	# Se houver alguma entrada de movimento (do analógico ou de botões)
	if input_direction.length() > 0:
		input_direction = input_direction.normalized() # Normaliza para evitar movimento mais rápido na diagonal
		
		velocity = input_direction * speed
		
		# Lógica para alternar entre Walking e Running
		# Você pode adicionar uma ação para "correr" também (ex: "run_action") e mapear um botão para ela.
		if Input.is_action_pressed("ui_shift"): # Exemplo: Segurar Shift para correr (ainda pode usar teclado)
			play_animation_if_different("Running")
			velocity *= 1.5 # Aumenta a velocidade ao correr
		else:
			play_animation_if_different("Walking")
	else:
		# Se não há entrada de movimento, para o movimento
		velocity = Vector3.ZERO
		if animation_player.current_animation != "Agree_Gesture": # Assume que Agree_Gesture não é uma animação de loop
			animation_player.stop() # Ou play_animation_if_different("Idle") se tiver uma animação de inatividade

	# Move o personagem usando o método move_and_slide do CharacterBody3D
	move_and_slide()

func play_current_animation():
	var animation_name = animations_list[current_animation_index]
	play_animation_if_different(animation_name) # Usa a nova função para evitar repetições

func play_animation_if_different(animation_name: String):
	if animation_player.current_animation != animation_name:
		if animation_player.has_animation(animation_name):
			var animation = animation_player.get_animation(animation_name)
			
			if animation_name == "Agree_Gesture":
				animation.loop_mode = Animation.LOOP_NONE
			else:
				animation.loop_mode = Animation.LOOP_LINEAR

			animation_player.play(animation_name)
			print("Reproduzindo animação: ", animation_name)
		else:
			print("Animação '" + animation_name + "' não encontrada no AnimationPlayer!")

func next_animation():
	current_animation_index += 1
	if current_animation_index >= animations_list.size():
		current_animation_index = 0
	
	play_current_animation()
