import Foundation

/// A failed duplicate must exit, even when the owner is hung. Let a system helper
/// display the diagnostic rather than keeping a second Inkpost process in a modal loop.
@MainActor
enum LaunchFailurePresentation {
    static func show(_ message: String) {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        helper.arguments = ["-e", "on run argv\ndisplay alert \"无法启动墨驿\" message (item 1 of argv) as warning buttons {\"好\"} default button \"好\"\nend run", message]
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        do {
            try helper.run()
        } catch {
            FileHandle.standardError.write(Data("Inkpost: 无法显示启动错误：\(error.localizedDescription)\n".utf8))
        }
    }
}
