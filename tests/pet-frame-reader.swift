let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let statePath = directory.appendingPathComponent("state.json")
let configPath = directory.appendingPathComponent("config.toml")
let reader = PetFrameReader(globalStatePath: statePath)
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    guard condition() else { fatalError("FAIL: \(label)") }
    checks += 1
}
func writeConfig(_ text: String) throws {
    try text.write(to: configPath, atomically: true, encoding: .utf8)
}
func writeState(_ bounds: [String: Any], open: Bool = true) throws {
    let state: [String: Any] = ["electron-avatar-overlay-open": open,
        "electron-avatar-overlay-bounds": bounds,
        "electron-persisted-atom-state": ["selected-avatar-id": "custom:legacy"]]
    try JSONSerialization.data(withJSONObject: state).write(to: statePath, options: .atomic)
}
var native: [String: Any] = ["x": 34, "y": 65, "placement": "bottom-start",
    "displayId": 3, "displayBounds": ["x": 0, "y": 0, "width": 1920, "height": 1080]]
try writeState(native)
check(reader.readPetFrameTopLeft() == CGRect(x: 34, y: 65, width: 113, height: 123), "native default")
check(reader.readSelectedAvatarID() == "custom:legacy", "legacy avatar fallback")
try writeConfig("[desktop]\nselected-avatar-id = 'custom:pet#1' # comment\navatar-overlay-mascot-width-px = 160\n")
check(reader.readPetFrameTopLeft() == CGRect(x: 34, y: 65, width: 160, height: 174), "custom size")
check(reader.readSelectedAvatarID() == "custom:pet#1", "literal string with hash")
try writeConfig("[\"desktop\"]\n\"selected-avatar-id\" = \"custom:日本語\"\navatar-overlay-mascot-width-px = 224\n[other]\navatar-overlay-mascot-width-px = 80\n")
check(reader.readPetFrameTopLeft()?.width == 224, "quoted desktop table and unrelated section")
check(reader.readSelectedAvatarID() == "custom:日本語", "unicode ID")
// Same-size atomic replacement must invalidate the cached settings.
try writeConfig("[desktop]\navatar-overlay-mascot-width-px = 160\n")
check(reader.readPetFrameTopLeft()?.width == 160, "first replacement")
try writeConfig("[desktop]\navatar-overlay-mascot-width-px = 180\n")
check(reader.readPetFrameTopLeft()?.width == 180, "same-size replacement")
try "[desktop]\navatar-overlay-mascot-width-px = 200\n".write(to: configPath, atomically: false, encoding: .utf8)
check(reader.readPetFrameTopLeft()?.width == 200, "same-size in-place edit")
try writeConfig("[desktop]\navatar-overlay-mascot-width-px = 180\navatar-overlay-pet-visible = false\n")
check(reader.readPetFrameTopLeft() == nil, "pet hidden in desktop settings")
try writeConfig("[desktop]\navatar-overlay-pet-visible = true\n")
try writeState(native, open: false)
check(reader.readPetFrameTopLeft() == nil, "overlay closed")
native["x"] = -1200; native["y"] = -150
try writeState(native)
check(reader.readPetFrameTopLeft()?.origin == CGPoint(x: -1200, y: -150), "movement and negative screen coordinates")
var legacy = native
legacy["mascot"] = ["left": 20, "top": 30, "width": 100, "height": 110]
try writeState(legacy)
check(reader.readPetFrameTopLeft() == CGRect(x: -1180, y: -120, width: 100, height: 110), "legacy explicit geometry")
var nested = native
nested["byDisplayId"] = ["3": legacy]
try writeState(nested)
check(reader.readPetFrameTopLeft() == CGRect(x: -1200, y: -150, width: 100, height: 110), "legacy nested size without stale offset")
nested.removeValue(forKey: "byDisplayId")
nested["byResolution"] = ["1920x1080": legacy]
try writeState(nested)
check(reader.readPetFrameTopLeft()?.size == CGSize(width: 100, height: 110), "legacy resolution fallback")
try writeState(["x": 10, "y": 20])
check(reader.readPetFrameTopLeft() == nil, "unknown record stays hidden")
var invalid = native; invalid["mascot"] = ["width": 0]
try writeState(invalid)
check(reader.readPetFrameTopLeft() == nil, "malformed explicit geometry stays hidden")
try writeState(native)
try writeConfig("[desktop]\navatar-overlay-mascot-width-px = 999\n")
check(reader.readPetFrameTopLeft()?.width == 113, "invalid setting uses default")
try FileManager.default.removeItem(at: configPath)
check(reader.readPetFrameTopLeft()?.width == 113, "deleted configuration invalidates cache")
try writeConfig(String(repeating: "#", count: 1_048_577))
check(reader.readPetFrameTopLeft()?.width == 113, "oversized configuration is not parsed")
print("Passed \(checks) pet frame checks")
