import AppKit

final class ChatWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    var dismiss: (() -> Void)?
    var togglePin: (() -> Void)?
    let pin = NSButton()
    private var accessory: NSTitlebarAccessoryViewController?
    private var hover: NSTrackingArea?
    private var expanded = false

    func setExpanded(_ value: Bool) {
        if value != expanded {
            expanded = value
            if value {
                styleMask.insert([.titled, .closable, .fullSizeContentView])
                titleVisibility = .hidden
                titlebarAppearsTransparent = true
                titlebarSeparatorStyle = .none
                let control = NSTitlebarAccessoryViewController()
                control.layoutAttribute = .right
                pin.frame = NSRect(x:0,y:0,width:38,height:24)
                pin.setButtonType(.momentaryPushIn)
                pin.isBordered = false
                pin.focusRingType = .none
                pin.imageScaling = .scaleProportionallyDown
                pin.imagePosition = .imageOnly
                pin.target = self
                pin.action = #selector(pinPressed)
                control.view = pin
                addTitlebarAccessoryViewController(control)
                accessory = control
                standardWindowButton(.miniaturizeButton)?.isHidden = true
                standardWindowButton(.zoomButton)?.isHidden = true
            } else {
                if accessory != nil { removeTitlebarAccessoryViewController(at:0); accessory = nil }
                styleMask.remove([.titled, .closable, .fullSizeContentView])
            }
        }
    }

    func updateTitlebarTracking() {
        guard let view = contentView else { return }
        if !expanded {
            if let hover { view.removeTrackingArea(hover); self.hover = nil }
            return
        }
        let region = NSRect(x:0,y:contentLayoutRect.maxY,width:view.bounds.width,
                            height:max(1,view.bounds.height-contentLayoutRect.maxY))
        if hover?.rect == region { return }
        if let hover { view.removeTrackingArea(hover) }
        let tracking = NSTrackingArea(rect:region,options:[.activeAlways,.mouseEnteredAndExited],owner:self,userInfo:nil)
        view.addTrackingArea(tracking)
        hover = tracking
        reveal(region.contains(view.convert(mouseLocationOutsideOfEventStream,from:nil)))
    }

    func reveal(_ visible: Bool) {
        standardWindowButton(.closeButton)?.isHidden = !visible
        pin.isHidden = !visible
    }
    override func mouseEntered(with event: NSEvent) { reveal(true) }
    override func mouseExited(with event: NSEvent) { reveal(false) }
    @objc private func pinPressed() { togglePin?() }
    override func performClose(_ sender: Any?) { dismiss?() }

    override func cancelOperation(_ sender: Any?) { dismiss?() }
    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(performClose(_:)) { return isVisible }
        return super.validateMenuItem(item)
    }
}
