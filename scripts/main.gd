extends Node3D
## NEON BAY CITY — world boot. The entire world is generated from code.

const CityGenerator := preload("res://scripts/city_generator.gd")
const PlayerFPP := preload("res://scripts/player_fpp.gd")
const CarAgent := preload("res://scripts/car_agent.gd")
const Pedestrian := preload("res://scripts/pedestrian.gd")
const Hud := preload("res://scripts/hud.gd")
const AutoCapture := preload("res://scripts/auto_capture.gd")
const CommandUI := preload("res://scripts/command_ui.gd")

const CAR_COUNT := 16
const PED_COUNT := 26

var gen: Node3D
var player: CharacterBody3D


func _ready() -> void:
	randomize()
	_setup_environment()

	# --- city ---
	gen = CityGenerator.new()
	add_child(gen)
	gen.generate()

	# --- player (the king, first-person) ---
	player = PlayerFPP.new()
	add_child(player)
	player.set_state(gen.spawn_point, gen.spawn_yaw, 0.0)

	# --- HUD ---
	add_child(Hud.new())

	# --- AI command console (free internet LLM) ---
	var cmd := CommandUI.new()
	add_child(cmd)
	cmd.bind(gen, self)

	# --- life: cars + pedestrians ---
	for i in CAR_COUNT:
		var car := CarAgent.new()
		add_child(car)
		car.setup_from_graph(gen, i)

	for i in PED_COUNT:
		var ped := Pedestrian.new()
		add_child(ped)
		ped.setup_from_graph(gen, i)

	# --- verification mode: auto screenshots + quit ---
	if "--autocap" in OS.get_cmdline_user_args():
		var ac := AutoCapture.new()
		ac.player = player
		ac.gen = gen
		ac.main = self
		add_child(ac)


func _setup_environment() -> void:
	# Perpetual golden-hour sunset — the Vice City signature.
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY

	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#3b1f66")
	sky_mat.sky_horizon_color = Color("#ff9d76")
	sky_mat.ground_bottom_color = Color("#241536")
	sky_mat.ground_horizon_color = Color("#ff9d76")
	sky_mat.sun_angle_max = 20.0
	sky_mat.sun_curve = 0.12
	sky.sky_material = sky_mat
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.15

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05

	# neon glow
	env.glow_enabled = true
	env.glow_intensity = 0.95
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 1.0

	# warm evening haze
	env.fog_enabled = true
	env.fog_light_color = Color("#e8907c")
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.12

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# low warm sun (sunset over the ocean, east)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-13.0, 100.0, 0.0)
	sun.light_color = Color("#ffb070")
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	add_child(sun)
