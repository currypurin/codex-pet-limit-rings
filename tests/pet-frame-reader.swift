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

try writeConfig("[desktop]\n")
var alternate = legacy
alternate["mascot"] = ["left": 0, "top": 0, "width": 200, "height": 210]
nested = native
nested["byDisplayId"] = ["1": alternate, "3": legacy]
try writeState(nested)
check(reader.readPetFrameTopLeft()?.width == 100, "numeric display ID preserves exact nested match")
// Cache must observe movement, including same-length edits and atomic replacement.
try writeState(native)
_ = reader.readPetFrameTopLeft()
native["x"] = -1100
try writeState(native)
check(reader.readPetFrameTopLeft()?.minX == -1100, "cached state invalidates on replacement")
let before = try Data(contentsOf: statePath)
let after = Data(String(decoding: before, as: UTF8.self).replacingOccurrences(of: "-1100", with: "-1000").utf8)
try after.write(to: statePath)
check(reader.readPetFrameTopLeft()?.minX == -1000, "cached state invalidates on direct edit")
// A real write event must refresh even if a writer preserves file metadata.
let attributes = try FileManager.default.attributesOfItem(atPath: statePath.path)
try Data(String(decoding: after, as: UTF8.self).replacingOccurrences(of: "-1000", with: "-1200").utf8).write(to: statePath)
try FileManager.default.setAttributes([.modificationDate: attributes[.modificationDate]!], ofItemAtPath: statePath.path)
reader.invalidateState()
check(reader.readPetFrameTopLeft()?.minX == -1200, "event invalidation overrides unchanged metadata")
try Data("{".utf8).write(to: statePath)
check(reader.readPetFrameTopLeft() == nil, "partial JSON hides stale geometry")
try writeState(native)
check(reader.readPetFrameTopLeft() != nil, "partial write recovery")
try FileManager.default.removeItem(at: statePath)
check(reader.readPetFrameTopLeft() == nil, "state deletion clears cached geometry")
let noisy: [String: Any] = ["electron-avatar-overlay-open": true, "electron-avatar-overlay-bounds": native,
    "unrelated": ["electron-avatar-overlay-open": false, "text": String(repeating: "unrelated", count: 200_000)],
    "electron-persisted-atom-state": ["selected-avatar-id": "custom:legacy", "unrelated": ["selected-avatar-id": "wrong"]]]
try JSONSerialization.data(withJSONObject: noisy).write(to: statePath, options: .atomic)
check(reader.readPetFrameTopLeft()?.minX == -1100, "large unrelated state does not affect geometry")
check(reader.readSelectedAvatarID() == "custom:legacy", "selected ID comes from the correct level")
print("Passed \(checks) pet frame checks")
