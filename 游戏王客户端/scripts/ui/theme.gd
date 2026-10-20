class_name UITheme
extends RefCounted

## 统一的深色主题（三个项目共用）

const BG := Color("14141f")
const BG_PANEL := Color("1c1c2e")
const BG_PANEL_LIGHT := Color("252544")
const BG_CARD := Color("2a2a4a")
const BORDER := Color("34345a")
const TEXT := Color("e8e8f2")
const TEXT_DIM := Color("9a9ab8")
const ACCENT := Color("8f88e8")
const ACCENT_DEEP := Color("534AB7")
const GOLD := Color("ef9f27")
const GREEN := Color("5dcaa5")
const RED := Color("e24b4a")
const YELLOW := Color("fac775")
const BLUE := Color("85b7eb")


## 生成一个圆角样式盒
static func sb(bg: Color, border: Color, radius := 8, border_w := 1, pad := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	return s


## 给按钮套用主题样式；accent=true 时为主按钮
static func style_button(btn: Button, accent := false, small := false) -> void:
	var font := 13 if small else 14
	btn.add_theme_font_size_override("font_size", font)
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_color_override("font_disabled_color", TEXT_DIM)
	var pad := 6 if small else 9
	var base := ACCENT_DEEP if accent else BG_PANEL_LIGHT
	var hover := ACCENT if accent else Color("32325c")
	var pressed := Color("3d3489") if accent else Color("3a3a68")
	var n := sb(base, BORDER if not accent else ACCENT_DEEP, 7, 1, pad)
	var h := sb(hover, hover.lightened(0.15), 7, 1, pad)
	var p := sb(pressed, pressed, 7, 1, pad)
	var d := sb(Color("232338"), BORDER, 7, 1, pad)
	btn.add_theme_stylebox_override("normal", n)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", p)
	btn.add_theme_stylebox_override("disabled", d)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## 危险操作按钮（红）
static func style_button_danger(btn: Button, small := true) -> void:
	style_button(btn, false, small)
	btn.add_theme_color_override("font_color", RED)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	var h := sb(RED.darkened(0.35), RED, 7, 1, 6 if small else 9)
	btn.add_theme_stylebox_override("hover", h)
	var p := sb(RED.darkened(0.5), RED, 7, 1, 6 if small else 9)
	btn.add_theme_stylebox_override("pressed", p)


## 主面板样式
static func panel_box() -> StyleBoxFlat:
	return sb(BG_PANEL, BORDER, 12, 1, 14)


## 小圆点标签（状态指示）
static func dot_label(color: Color) -> Label:
	var l := Label.new()
	l.text = "●"
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 12)
	return l


## 普通文字标签
static func text_label(text: String, color := TEXT, size := 13, dim := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", TEXT_DIM if dim else color)
	l.add_theme_font_size_override("font_size", size)
	return l


## 输入框样式
static func style_line_edit(edit: LineEdit) -> void:
	edit.add_theme_stylebox_override("normal", sb(Color("111122"), BORDER, 7, 1, 8))
	edit.add_theme_stylebox_override("focus", sb(Color("111122"), ACCENT, 7, 1, 8))
	edit.add_theme_color_override("font_color", TEXT)
	edit.add_theme_color_override("font_placeholder_color", TEXT_DIM)
	edit.add_theme_color_override("caret_color", ACCENT)
	edit.add_theme_font_size_override("font_size", 14)
