import AppKit
import Carbon

final class Launcher: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let chat = Conversation()
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var binding: EventHotKeyRef?
    var handler: EventHandlerRef?
    let choices = [(0,"每次打开"), (5,"5 分钟"), (15,"15 分钟"), (30,"30 分钟"), (60,"1 小时"), (-1,"从不")]

    func applicationDidFinishLaunching(_ notification: Notification) {
        status.button?.image = Mark.image(size: 19, template: true)
        status.button?.toolTip = "chatgpt-quick-chat"
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            Unmanaged<Launcher>.fromOpaque(context).takeUnretainedValue().toggle()
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if installed == noErr {
            let id = EventHotKeyID(signature: 0x4351504C, id: 1)
            if RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), id, GetApplicationEventTarget(), 0, &binding) != noErr {
                binding = nil
            }
        }
        if binding == nil { status.button?.toolTip = "⌥ Space 不可用，可从菜单打开对话" }
        let main = NSMenu()
        let appMenu = NSMenu(title:"chatgpt-quick-chat")
        appMenu.addItem(quitItem())
        main.addItem(withTitle:"chatgpt-quick-chat",action:nil,keyEquivalent:"").submenu = appMenu
        let edit = NSMenu(title:"编辑")
        for (name,key,action) in [("复制","c","copy:"),("剪切","x","cut:"),("粘贴","v","paste:"),("全选","a","selectAll:"),("撤销","z","undo:")] {
            edit.addItem(withTitle:name,action:NSSelectorFromString(action),keyEquivalent:key)
        }
        let redo = edit.addItem(withTitle:"重做",action:NSSelectorFromString("redo:"),keyEquivalent:"z")
        redo.keyEquivalentModifierMask = [.command,.shift]
        main.addItem(withTitle:"编辑",action:nil,keyEquivalent:"").submenu = edit
        let file = NSMenu(title:"文件")
        file.addItem(withTitle:"关闭窗口", action:#selector(NSWindow.performClose(_:)), keyEquivalent:"w")
        main.insertItem(withTitle:"文件", action:nil, keyEquivalent:"", at:1).submenu = file
        let windows = NSMenu(title:"窗口")
        windows.addItem(withTitle:"前置全部窗口", action:#selector(NSApplication.arrangeInFront(_:)), keyEquivalent:"")
        main.addItem(withTitle:"窗口", action:nil, keyEquivalent:"").submenu = windows
        NSApp.windowsMenu = windows
        NSApp.mainMenu = main
        chat.warmUp()
    }

    private func quitItem() -> NSMenuItem {
        let item = NSMenuItem(title:"退出 chatgpt-quick-chat",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        return item
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !chat.window.isVisible { chat.show(activate:sender.isActive) }
        return true
    }

    func applyDockPreference() {
        let show = UserDefaults.standard.bool(forKey: "showsDockIcon")
        NSApp.setActivationPolicy(show ? .regular : .accessory)
    }

    @objc func toggleDockIcon() {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: "showsDockIcon"), forKey: "showsDockIcon")
        applyDockPreference()
    }

    @objc func toggle() { chat.toggle() }
    @objc func selectInterval(_ sender: NSMenuItem) { UserDefaults.standard.set(sender.tag, forKey: "minutes") }
    @objc func openSite() { chat.showPage() }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func item(_ title: String, _ action: Selector) -> NSMenuItem {
            let row = menu.addItem(withTitle:title, action:action, keyEquivalent:"")
            row.target = self
            return row
        }
        _ = item(chat.window.isVisible ? "收起对话" : "打开对话", #selector(toggle))
        if binding == nil {
            menu.addItem(withTitle:"⌥ Space 不可用",action:nil,keyEquivalent:"")
        }
        _ = item("显示完整页面", #selector(openSite))
        let intervals = NSMenu()
        for (value,label) in choices {
            let row = intervals.addItem(withTitle:label,action:#selector(selectInterval(_:)),keyEquivalent:"")
            row.tag = value
            row.target = self
            row.state = value == chat.minutes ? .on : .off
        }
        menu.addItem(withTitle:"会话重置时间",action:nil,keyEquivalent:"").submenu = intervals
        item("在程序坞中隐藏图标", #selector(toggleDockIcon)).state = NSApp.activationPolicy() == .accessory ? .on : .off
        menu.addItem(.separator())
        menu.addItem(quitItem())
    }
}
