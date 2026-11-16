import AppKit

let app = NSApplication.shared
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--render-icon" {
    try Mark.writePNG(to: URL(fileURLWithPath: CommandLine.arguments[2]))
} else {
    let launcher = Launcher()
    launcher.applyDockPreference()
    app.delegate = launcher
    app.run()
}
