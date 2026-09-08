guard CommandLine.arguments.count == 4,
      let iterations = Int(CommandLine.arguments[2]), iterations > 0,
      ["cached", "changed"].contains(CommandLine.arguments[3]) else {
    fputs("Usage: benchmark STATE_PATH ITERATIONS cached|changed\n", stderr)
    exit(2)
}
let path = URL(fileURLWithPath: CommandLine.arguments[1])
let reader = PetFrameReader(globalStatePath: path)
let changed = CommandLine.arguments[3] == "changed"
let start = ProcessInfo.processInfo.systemUptime
var frames = 0
for _ in 0..<iterations {
    autoreleasepool {
        if changed { reader.invalidateState() }
        if reader.readPetFrameTopLeft() != nil { frames += 1 }
        _ = reader.readSelectedAvatarID()
    }
}
print("reads=\(iterations) mode=\(CommandLine.arguments[3]) frames=\(frames) seconds=\(ProcessInfo.processInfo.systemUptime - start)")
