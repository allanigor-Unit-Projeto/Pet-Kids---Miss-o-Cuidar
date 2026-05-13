## AudioManager.gd
## Singleton Autoload: Gerencia trilha sonora, efeitos e áudio espacial 3D (RF-V006).
extends Node

const SFX_PATH := "res://assets/audio/sfx/"
const MUSIC_PATH := "res://assets/audio/music/"

var _music_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_pool_size := 8

var _master_volume := 1.0
var _sfx_volume := 1.0
var _music_volume := 0.8

func _ready() -> void:
	_setup_music_player()
	_setup_sfx_pool()
	_load_volume_settings()

func _setup_music_player() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)

func _setup_sfx_pool() -> void:
	for i in _sfx_pool_size:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_players.append(p)

func _load_volume_settings() -> void:
	var settings := SaveSystem.load_settings()
	_master_volume = settings.get("audio_master", 1.0)
	_sfx_volume    = settings.get("audio_sfx", 1.0)
	_music_volume  = settings.get("audio_music", 0.8)
	_apply_volumes()

func _apply_volumes() -> void:
	AudioServer.set_bus_volume_db(
		AudioServer.get_bus_index("Master"),
		linear_to_db(_master_volume)
	)
	AudioServer.set_bus_volume_db(
		AudioServer.get_bus_index("Music"),
		linear_to_db(_music_volume)
	)
	AudioServer.set_bus_volume_db(
		AudioServer.get_bus_index("SFX"),
		linear_to_db(_sfx_volume)
	)

# ──────────────────────────────────────────────
# Música
# ──────────────────────────────────────────────
func play_music(track_name: String, loop: bool = true) -> void:
	var path := MUSIC_PATH + track_name + ".ogg"
	if not ResourceLoader.exists(path):
		push_warning("[AudioManager] Música não encontrada: %s" % path)
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	_music_player.stream = stream
	_music_player.play()

func stop_music(fade_time: float = 1.0) -> void:
	var tween := create_tween()
	tween.tween_property(_music_player, "volume_db", -80.0, fade_time)
	tween.tween_callback(func():
		_music_player.stop()
		_music_player.volume_db = 0.0
	)

# ──────────────────────────────────────────────
# Efeitos sonoros
# ──────────────────────────────────────────────
func play_sfx(sfx_name: String) -> void:
	var path := SFX_PATH + sfx_name + ".ogg"
	if not ResourceLoader.exists(path):
		return
	var player := _get_free_sfx_player()
	if player == null:
		return
	player.stream = load(path)
	player.play()

func _get_free_sfx_player() -> AudioStreamPlayer:
	for p in _sfx_players:
		if not p.playing:
			return p
	return _sfx_players[0]  # recicla o mais antigo

# ──────────────────────────────────────────────
# Áudio espacial 3D para VR (RF-V006)
# ──────────────────────────────────────────────
func create_spatial_audio(sfx_name: String, position: Vector3) -> AudioStreamPlayer3D:
	var path := SFX_PATH + sfx_name + ".ogg"
	if not ResourceLoader.exists(path):
		return null
	var player := AudioStreamPlayer3D.new()
	player.stream = load(path)
	player.position = position
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.max_distance = 20.0
	get_tree().current_scene.add_child(player)
	player.play()
	# Auto-remove após reprodução
	player.finished.connect(player.queue_free)
	return player

# ──────────────────────────────────────────────
# Volume (chamado por Settings)
# ──────────────────────────────────────────────
func set_master_volume(value: float) -> void:
	_master_volume = clampf(value, 0.0, 1.0)
	_apply_volumes()

func set_sfx_volume(value: float) -> void:
	_sfx_volume = clampf(value, 0.0, 1.0)
	_apply_volumes()

func set_music_volume(value: float) -> void:
	_music_volume = clampf(value, 0.0, 1.0)
	_apply_volumes()
