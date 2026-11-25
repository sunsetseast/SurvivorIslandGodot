class_name IslandTheme
extends RefCounted

const IVORY := Color.WHITE
const GOLD := Color("#edc574")
const INK := Color("#291a10")
const SPACE := 6
const TOUCH := 48
const BODY := 21
const HEADING := 30

static func font() -> Font:
    if ResourceLoader.exists("res://private_brand/Survivant.ttf"):
        var original := load("res://private_brand/Survivant.ttf") as FontFile
        original.fallbacks = [preload("res://application/presentation/fonts/NotoSans-Regular.ttf")]
        return original
    return preload("res://application/presentation/fonts/NotoSans-Regular.ttf")

static func install() -> void:
    # All Controls, including separate CanvasLayers and future screens, inherit this.
    ThemeDB.get_default_theme().merge_with(create())
    ThemeDB.get_default_theme().default_font = font()
    ThemeDB.fallback_font = font()

static func surface(color: Color, border := Color("#795633"), padding := 16) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = color
    box.border_color = border
    box.set_border_width_all(1)
    box.set_corner_radius_all(3)
    box.content_margin_left = padding
    box.content_margin_right = padding
    box.content_margin_top = 8
    box.content_margin_bottom = 8
    return box

static func wood(tint := Color.WHITE) -> StyleBox:
    if not ResourceLoader.exists("res://private_brand/rect-button.png"):
        return surface(Color("#714321") * tint, Color("#bd8a4c"))
    var box := StyleBoxTexture.new()
    box.texture = load("res://private_brand/rect-button.png")
    box.modulate_color = tint
    for side in [SIDE_LEFT, SIDE_RIGHT]:
        box.set_texture_margin(side, 25)
        box.set_content_margin(side, 24)
    for side in [SIDE_TOP, SIDE_BOTTOM]:
        box.set_texture_margin(side, 20)
        box.set_content_margin(side, 5)
    return box

static func parchment() -> StyleBox:
    if not ResourceLoader.exists("res://private_brand/rect-button-1.png"):
        return surface(Color("#e7c790"), Color("#855c31"), 24)
    var box := StyleBoxTexture.new()
    box.texture = load("res://private_brand/rect-button-1.png")
    # Preserve the rope, rock and leaf corners; stretch only the quiet center.
    box.set_texture_margin(SIDE_LEFT, 105)
    box.set_texture_margin(SIDE_RIGHT, 105)
    box.set_texture_margin(SIDE_TOP, 70)
    box.set_texture_margin(SIDE_BOTTOM, 70)
    box.content_margin_left = 52
    box.content_margin_right = 52
    box.content_margin_top = 34
    box.content_margin_bottom = 34
    return box

static func create() -> Theme:
    var theme := Theme.new()
    theme.default_font = font()
    theme.default_font_size = BODY
    for type: String in ["Label", "Button", "LineEdit", "CheckButton", "OptionButton", "RichTextLabel", "TextEdit"]:
        theme.set_color("font_color", type, Color.WHITE)
        theme.set_color("font_focus_color", type, Color.WHITE)
        theme.set_color("font_outline_color", type, Color.BLACK)
        theme.set_constant("outline_size", type, 3)
    for type: String in ["Button", "OptionButton"]:
        theme.set_stylebox("normal", type, wood())
        theme.set_stylebox("hover", type, wood(Color("#fff0cb")))
        theme.set_stylebox("pressed", type, wood(Color("#b7a18c")))
        theme.set_stylebox("disabled", type, wood(Color("#81786d")))
        var focus := surface(Color.TRANSPARENT, GOLD, 0)
        focus.set_border_width_all(2)
        focus.shadow_color = Color("#edc57455")
        focus.shadow_size = 3
        theme.set_stylebox("focus", type, focus)
        theme.set_color("font_disabled_color", type, Color("#a6a29a"))
        theme.set_color("font_hover_color", type, Color.WHITE)
        theme.set_color("font_pressed_color", type, Color.WHITE)
        theme.set_color("font_hover_pressed_color", type, Color.WHITE)
    theme.set_type_variation("PrimaryButton", "Button")
    theme.set_type_variation("ParchmentHeading", "Label")
    theme.set_stylebox("normal", "ParchmentHeading", parchment())
    theme.set_color("font_color", "ParchmentHeading", INK)
    theme.set_constant("outline_size", "ParchmentHeading", 0)
    theme.set_font_size("font_size", "ParchmentHeading", HEADING)
    theme.set_stylebox("panel", "PanelContainer", surface(Color("#291c12e8"), Color("#8d673b"), 20))
    theme.set_stylebox("panel", "PopupPanel", parchment())
    theme.set_stylebox("normal", "LineEdit", surface(Color("#f0d7aa")))
    theme.set_stylebox("focus", "LineEdit", surface(Color("#ffe5b7"), GOLD))
    theme.set_color("font_color", "LineEdit", INK)
    theme.set_color("font_selected_color", "LineEdit", Color.WHITE)
    theme.set_constant("outline_size", "LineEdit", 0)
    theme.set_color("caret_color", "LineEdit", INK)
    theme.set_color("font_placeholder_color", "LineEdit", Color("#6d533a"))
    theme.set_stylebox("background", "ProgressBar", surface(INK, INK, 0))
    theme.set_stylebox("fill", "ProgressBar", surface(GOLD, GOLD, 0))
    var track := surface(INK, INK, 3)
    theme.set_stylebox("scroll", "VScrollBar", track)
    theme.set_stylebox("grabber", "VScrollBar", surface(Color("#ad8151"), GOLD, 3))
    theme.set_stylebox("grabber_highlight", "VScrollBar", surface(GOLD, GOLD, 3))
    for type: String in ["VBoxContainer", "HBoxContainer"]:
        theme.set_constant("separation", type, SPACE)
    theme.set_type_variation("SectionHeading", "Label")
    theme.set_font_size("font_size", "SectionHeading", HEADING)
    return theme
