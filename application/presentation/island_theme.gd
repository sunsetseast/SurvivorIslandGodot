class_name IslandTheme
extends RefCounted

# Shared production tokens, in CSS-equivalent pixels at menu scale.
const IVORY := Color("#f4edda")
const GOLD := Color("#c6a46a")
const GREEN := Color("#163d34")
const INK := Color("#101e1b")
const SPACE := 8
const TOUCH := 48
const BODY := 18
const HEADING := 30
const SERIF := preload("res://application/presentation/fonts/NotoSerifDisplay-Regular.ttf")

static func surface(color: Color, border := Color("#587266"), padding := 16) -> StyleBoxFlat:
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

static func create() -> Theme:
    var theme := Theme.new()
    theme.default_font = preload("res://application/presentation/fonts/NotoSans-Regular.ttf")
    theme.default_font_size = BODY
    for type: String in ["Label", "Button", "LineEdit", "CheckButton", "OptionButton", "RichTextLabel"]:
        theme.set_color("font_color", type, IVORY)
        theme.set_color("font_focus_color", type, IVORY)
    for type: String in ["Button", "OptionButton"]:
        theme.set_stylebox("normal", type, surface(GREEN))
        theme.set_stylebox("hover", type, surface(Color("#285447"), GOLD))
        theme.set_stylebox("pressed", type, surface(Color("#84653a"), GOLD))
        theme.set_stylebox("disabled", type, surface(Color("#1e2925"), Color("#39453d")))
        var focus := surface(Color.TRANSPARENT, GOLD)
        focus.set_border_width_all(2)
        theme.set_stylebox("focus", type, focus)
        theme.set_color("font_disabled_color", type, Color("#879087"))
        theme.set_color("font_hover_color", type, IVORY)
        theme.set_color("font_pressed_color", type, IVORY)
    theme.set_type_variation("PrimaryButton", "Button")
    theme.set_stylebox("normal", "PrimaryButton", surface(Color("#87683e"), GOLD))
    theme.set_stylebox("panel", "PanelContainer", surface(Color("#101e1bf5"), Color("#697051"), 20))
    theme.set_stylebox("panel", "PopupPanel", surface(INK, GOLD))
    theme.set_stylebox("normal", "LineEdit", surface(INK))
    theme.set_stylebox("focus", "LineEdit", surface(INK, GOLD))
    theme.set_color("caret_color", "LineEdit", GOLD)
    theme.set_color("font_placeholder_color", "LineEdit", Color("#b5b9a8"))
    theme.set_stylebox("background", "ProgressBar", surface(INK, INK, 0))
    theme.set_stylebox("fill", "ProgressBar", surface(GOLD, GOLD, 0))
    theme.set_stylebox("scroll", "VScrollBar", surface(INK, INK, 0))
    theme.set_stylebox("grabber", "VScrollBar", surface(Color("#697051"), GOLD, 0))
    theme.set_stylebox("grabber_highlight", "VScrollBar", surface(GOLD, GOLD, 0))
    for type: String in ["VBoxContainer", "HBoxContainer"]:
        theme.set_constant("separation", type, SPACE)
    theme.set_type_variation("SectionHeading", "Label")
    theme.set_font("font", "SectionHeading", SERIF)
    theme.set_font_size("font_size", "SectionHeading", HEADING)
    theme.set_color("font_color", "SectionHeading", IVORY)
    return theme
