extends RefCounted
class_name VoxelTextures
## Loads the baked PBR maps into three Texture2DArrays, one layer per material.
##
## The arrays are built once, on the main thread, and shared by every world
## material. VoxelMaterials then only has to hand a shader a layer index, which
## is what keeps this cheap: a chunk with six materials still costs six surfaces
## and no extra shader compiles.
##
## Falls back cleanly. If the texture directory is missing — a fresh clone that
## has not run the generator, or the web export, where the megabytes are not
## worth it — `ready` stays false, VoxelMaterials does not set the arrays, and
## the shader's USE_PBR_TEXTURES block falls back to flat base colour. Worse,
## but not broken.
##
## Godot's own constraint shapes most of this: ImageTextureLayered.
## create_from_images() takes the width, height, FORMAT and mipmap setting from
## the first image and requires every other layer to match. A texture array
## carries one sampler configuration for all its layers, so the albedo array
## (sRGB) and the ORM array (linear data) cannot be two different formats in
## one call — each is built in its own array, which is exactly why there are
## three of them and not one atlas.

## Two texture sets, same generator, different resolution.
##
## assets/tex/      1024px — desktop, and the reference the tuning tables
##                             in voxel_materials.gd were measured against
## assets/tex_web/   512px  — what the web export ships
##
## Why two: the 1024px set is 100 MB, and a Godot .pck must be fully downloaded
## and parsed before the first frame. Measured on the deployed site, that took
## the web pack from 20.6 MB to 88.6 MB and the cold load from about 25 s to
## about 53 s, and on a phone it is minutes — the tab wedges entirely, wedging
## on document.readyState, because the main thread is inside the pack parser.
##
## 512px is the compromise: a quarter of the pixels, a quarter of the bytes, and
## at the distance a browser player actually views a village the mip chain was
## throwing most of the 1024px away anyway. The desktop build keeps the full
## set because it loads from disk, where the size costs nothing.
##
## The directory is resolved at runtime rather than compiled in, so the same
## binary works with either set present. If both are missing the world falls
## back to flat colour and still runs.
const TEX_DIR_DESKTOP := "res://assets/tex/"
const TEX_DIR_WEB := "res://assets/tex_web/"

## The order here IS the layer order. Changing it silently repaints the world,
## because the shader only ever receives an index.
const ORDER := [
	"timber", "plank", "dark_oak", "bark",
	"brick", "sandstone", "granite", "cobble", "stone", "rock",
	"concrete", "rebar_concrete", "concrete_slab",
	"steel_frame", "corrugated_steel", "sheet_metal", "plastic_panel",
	"carbon_composite", "solar_panel",
	"thatch", "clay_tile", "asphalt_shingle",
	"dirt", "gravel", "farmland", "wet_farmland", "asphalt",
	"grass", "sand", "leaf",
	"clay", "iron_ore",
	"painted_white", "painted_red", "chrome", "matte_black", "neon_strip",
	"ember", "glass", "reinforced_glass", "water",
]

static var _layer_of: Dictionary = {}

static var _albedo: Texture2DArray = null
static var _normal: Texture2DArray = null
static var _orm: Texture2DArray = null
static var _loaded := false
static var _ok := false
## Which directory the arrays were built from, and how many texels it has per
## side. The shader's UVs are in metres, so a smaller source needs a
## proportionally smaller repeat count to cover the same wall — without this a
## 512px brick texture is stretched over twice the area it was authored for and
## every pattern looks twice as large.
static var _dir := ""
static var _res := 1024


## Picks the texture directory.
##
## The 512px set is only correct for a build that has to download them, and the
## engine knows that: OS.has_feature("web") is true for the web export and false
## everywhere else. Choosing on that rather than on "which directory exists" is
## what lets a single checkout ship 1024px on the desktop and 512px on the web
## without either build needing its own assets — and it fixes a real mistake,
## which was preferring the smaller set merely because it was on disk, so a
## desktop run that had both directories quietly used the 512px one.
static func _pick_dir() -> String:
	var web := OS.has_feature("web")
	if web and ResourceLoader.exists(TEX_DIR_WEB + "brick_a.png"):
		return TEX_DIR_WEB
	if ResourceLoader.exists(TEX_DIR_DESKTOP + "brick_a.png"):
		return TEX_DIR_DESKTOP
	if ResourceLoader.exists(TEX_DIR_WEB + "brick_a.png"):
		return TEX_DIR_WEB
	return TEX_DIR_DESKTOP


## Builds the arrays. Must run before any material is created: VoxelMaterials
## prewarm() calls it, and prewarm() happens before the first chunk is meshed,
## so no worker thread ever races a lazy build.
static func load_all() -> bool:
	if _loaded:
		return _ok
	_loaded = true

	_dir = _pick_dir()
	if not ResourceLoader.exists(_dir + "brick_a.png"):
		print("[tex] no baked maps in %s — using flat colour" % _dir)
		_ok = false
		return false

	var albedo_layers: Array[Image] = []
	var normal_layers: Array[Image] = []
	var orm_layers: Array[Image] = []

	for name: String in ORDER:
		var a := _read(name + "_a.png")
		var n := _read(name + "_n.png")
		var o := _read(name + "_o.png")
		if a == null or n == null or o == null:
			print("[tex] missing maps for %s in %s — using flat colour" % [name, _dir])
			_ok = false
			return false
		albedo_layers.append(a)
		normal_layers.append(n)
		orm_layers.append(o)

	_albedo = _make_array(albedo_layers, "albedo")
	_normal = _make_array(normal_layers, "normal")
	_orm = _make_array(orm_layers, "ORM")
	_ok = _albedo != null and _normal != null and _orm != null
	if not _ok:
		return false

	_res = _albedo.get_width()
	for i in ORDER.size():
		_layer_of[ORDER[i]] = i
	print("[tex] %d materials -> 3 texture arrays @ %dx%d (%s)" % [
		ORDER.size(), _albedo.get_width(), _albedo.get_height(),
		"web 512" if _res <= 512 else "desktop 1024"])
	return true


## The multiplier that keeps a material's pattern the same physical size across
## both texture sets. A 512px source is half the linear resolution of 1024px, so
## at an unchanged repeat count a brick would be drawn twice as large on the
## web as on the desktop. Scaling the repeat by 0.5 puts the same number of
## bricks on the same wall.
static func res_scale() -> float:
	return float(_res) / 1024.0


## Reads one baked map, normalising it to the exact format and mipmap setting
## that create_from_images() requires every layer of an array to share.
static func _read(fname: String) -> Image:
	var path := _dir + fname
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		# A compressed normal map cannot be resampled correctly without
		# re-encoding it, and the normal pass depends on the filter being right.
		if img.decompress() != OK:
			return null
	# convert() also drops the mipmap chain, so generate() below is the single
	# source of mipmaps and every layer ends up identical in that respect.
	# convert() returns void in Godot 4.x, not an Error, so it cannot be
	# checked the way decompress() can.
	img.convert(Image.FORMAT_RGBA8)
	if not img.has_mipmaps():
		if img.generate_mipmaps() != OK:
			return null
	return img


static func _make_array(layers: Array[Image], label: String) -> Texture2DArray:
	if layers.is_empty():
		return null
	var w := layers[0].get_width()
	var h := layers[0].get_height()
	for img: Image in layers:
		if img.get_width() != w or img.get_height() != h:
			push_error("[tex] %s layer size mismatch: %dx%d vs %dx%d" % [
				label, img.get_width(), img.get_height(), w, h])
			return null

	var arr := Texture2DArray.new()
	# The first image fixes the format and the mipmap setting for the whole
	# array; _read() has already made every layer agree on both.
	if arr.create_from_images(layers) != OK:
		push_error("[tex] could not build the %s array" % label)
		return null
	return arr


static func ready() -> bool:
	return _ok


static func albedo_array() -> Texture2DArray:
	return _albedo


static func normal_array() -> Texture2DArray:
	return _normal


static func orm_array() -> Texture2DArray:
	return _orm


## Layer index for a material name, or -1 if it has no texture.
static func layer_of(mat_name: String) -> int:
	if _layer_of.is_empty() and _ok:
		for i in ORDER.size():
			_layer_of[ORDER[i]] = i
	return int(_layer_of.get(mat_name, -1))
