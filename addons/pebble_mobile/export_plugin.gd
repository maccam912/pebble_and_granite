@tool
extends EditorPlugin
var exporter: EditorExportPlugin
func _enter_tree() -> void:
	exporter = MobileExport.new()
	add_export_plugin(exporter)
func _exit_tree() -> void:
	remove_export_plugin(exporter)
	exporter = null
class MobileExport extends EditorExportPlugin:
	func _get_name() -> String: return "PebbleMobile"
	func _supports_platform(platform: EditorExportPlatform) -> bool: return platform is EditorExportPlatformAndroid
	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["pebble_mobile/bin/pebble-mobile.aar"])
