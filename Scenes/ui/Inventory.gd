## Inventory.gd
## Tela de inventário: gerencia itens de cuidado com o pet (RF013, RF014).
## Loja virtual com PetCoins — sem microtransações reais (RN005).
extends Control

@onready var grid_inventory: GridContainer = $ScrollContainer/GridInventory
@onready var lbl_coins: Label              = $TopBar/LblCoins
@onready var filter_bar: HBoxContainer     = $FilterBar
@onready var panel_shop: PanelContainer    = $PanelShop
@onready var grid_shop: GridContainer      = $PanelShop/ScrollContainer/GridShop
@onready var btn_open_shop: Button         = $TopBar/BtnShop
@onready var btn_close_shop: Button        = $PanelShop/BtnClose
@onready var btn_back: Button              = $TopBar/BtnBack
@onready var toast_container: Control      = $ToastContainer
@onready var lbl_empty: Label              = $LblEmpty

const ItemCard := preload("res://scenes/ui/components/ItemCard.tscn")
const ShopItemCard := preload("res://scenes/ui/components/ShopItemCard.tscn")

# Catálogo da loja virtual (RF014, RN005)
const SHOP_CATALOG := [
	{"item_id": "feed_bowl",  "nome": "Ração Premium",    "categoria": "comida",
	 "preco": 10, "icone": "🍖", "descricao": "Aumenta fome em 40 pontos."},
	{"item_id": "water_bowl", "nome": "Tigela de Água",   "categoria": "bebida",
	 "preco": 8,  "icone": "💧", "descricao": "Aumenta hidratação em 35 pontos."},
	{"item_id": "shampoo",    "nome": "Shampoo Pet",      "categoria": "higiene",
	 "preco": 15, "icone": "🛁", "descricao": "Aumenta higiene em 50 pontos."},
	{"item_id": "toy_ball",   "nome": "Bola de Brincar",  "categoria": "brinquedo",
	 "preco": 12, "icone": "🎾", "descricao": "Necessário para sessão de brincadeira."},
	{"item_id": "brush",      "nome": "Escova de Pelagem","categoria": "higiene",
	 "preco": 10, "icone": "🪮", "descricao": "Aumenta higiene e felicidade."},
	{"item_id": "vet_ticket", "nome": "Consulta Vet",     "categoria": "saude",
	 "preco": 50, "icone": "🩺", "descricao": "Necessário para consulta veterinária."},
	{"item_id": "medicine",   "nome": "Medicamento",      "categoria": "saude",
	 "preco": 30, "icone": "💊", "descricao": "Trata doenças leves do pet."}
]

var _active_filter: String = "todos"

func _ready() -> void:
	UIManager.register_toast_container(toast_container)
	GameManager.player_xp_changed.connect(func(_x,_l): _update_coins_label())
	btn_open_shop.pressed.connect(_open_shop)
	btn_close_shop.pressed.connect(_close_shop)
	btn_back.pressed.connect(GameManager.go_to_pet_care)
	_setup_filters()
	_update_coins_label()
	_load_inventory()

func _setup_filters() -> void:
	var categories := ["todos", "comida", "bebida", "higiene", "brinquedo", "saude"]
	for cat in categories:
		var btn := Button.new()
		btn.text = cat.capitalize()
		btn.toggle_mode = true
		btn.button_pressed = cat == "todos"
		btn.pressed.connect(func(): _filter_by(cat))
		filter_bar.add_child(btn)

func _filter_by(category: String) -> void:
	_active_filter = category
	_load_inventory()

func _update_coins_label() -> void:
	lbl_coins.text = "🪙 %d PetCoins" % GameManager.pet_coins

func _load_inventory() -> void:
	for child in grid_inventory.get_children():
		child.queue_free()

	var items := DatabaseManager.get_inventory()
	var filtered := items if _active_filter == "todos" else items.filter(
		func(i): return i.get("categoria") == _active_filter
	)

	lbl_empty.visible = filtered.is_empty()

	for item in filtered:
		var card: Control = ItemCard.instantiate()
		grid_inventory.add_child(card)
		if card.has_method("setup"):
			card.setup(item)

func _open_shop() -> void:
	panel_shop.visible = true
	_load_shop()

func _close_shop() -> void:
	panel_shop.visible = false

func _load_shop() -> void:
	for child in grid_shop.get_children():
		child.queue_free()
	for item in SHOP_CATALOG:
		var card: Control = ShopItemCard.instantiate()
		grid_shop.add_child(card)
		if card.has_method("setup"):
			card.setup(item)
		if card.has_signal("buy_requested"):
			card.buy_requested.connect(_buy_item.bind(item))

func _buy_item(item: Dictionary) -> void:
	var price: int = item.get("preco", 0)
	if not GameManager.spend_pet_coins(price):
		return  # UIManager já exibiu toast de PetCoins insuficientes

	# Adiciona ao inventário local
	var inv_item := {
		"id": "inv_%s_%d" % [item.get("item_id", ""), Time.get_unix_time_from_system()],
		"item_id": item.get("item_id", ""),
		"nome": item.get("nome", ""),
		"categoria": item.get("categoria", ""),
		"quantidade": 1,
		"valor_unitario": price,
		"icone_path": item.get("icone", "")
	}
	DatabaseManager.save_inventory_item(inv_item)
	UIManager.show_toast("✅ %s comprado(a)!" % item.get("nome", ""))
	AudioManager.play_sfx("purchase_success")
	_update_coins_label()
	_load_inventory()
