import AppKit
import WebKit

final class Conversation: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    static let home = URL(string:"https://chatgpt.com/")!
    var minutes: Int { defaults.object(forKey:"minutes") as? Int ?? 30 }
    static func expired(minutes: Int, elapsed: TimeInterval) -> Bool {
        minutes == 0 || (minutes > 0 && elapsed > Double(minutes) * 60)
    }

    let window = ChatWindow(contentRect:.zero,styleMask:[.nonactivatingPanel],backing:.buffered,defer:false)
    private let clip = NSView()
    private var positioning = false
    private let world = WKContentWorld.world(name:"ChatPanelLayout")
    private var page: WKWebView!
    private var spare: WKWebView?
    private var spareReady = false
    private var inactiveSince: Date?
    private let readingSize = NSSize(width:462,height:652)
    private var compact = true
    private var prefersCompact = true
    private var landingPageUsed = false
    private var hasTextDraft = false
    private var routeObservation: NSKeyValueObservation?
    private var ready = false
    private var menuHeight: CGFloat = 108
    private var composerHeight: CGFloat = 108
    private var revision = 0
    private var anchor: CGPoint = .zero
    private var area = NSRect.zero
    private let errorLabel = NSTextField(labelWithString:"")
    private let defaults = UserDefaults.standard
    var isPinned: Bool { defaults.bool(forKey: "keepWindowInFront") }

    func setPinned(_ enabled: Bool) {
        guard enabled != isPinned else { return }
        defaults.set(enabled, forKey: "keepWindowInFront")
        applyPin()
    }

    private func applyPin() {
        window.pin.image = NSImage(systemSymbolName:isPinned ? "pin.fill" : "pin", accessibilityDescription:nil)
        window.pin.toolTip = isPinned ? "取消置顶" : "窗口置顶"
        window.pin.setAccessibilityLabel(window.pin.toolTip)
        window.pin.setAccessibilityValue(isPinned ? 1 : 0)
        window.collectionBehavior = isPinned
            ? [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary]
            : [.moveToActiveSpace, .canJoinAllApplications, .fullScreenAuxiliary]
        window.level = isPinned || window.isKeyWindow ? .floating : .normal
        if isPinned && window.isVisible { window.orderFrontRegardless() }
    }

    private func loadHome(_ web: WKWebView) {
        web.load(URLRequest(url: Self.home))
    }

    override init() {
        super.init()
        applyPin()
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.animationBehavior = .none
        window.contentView = clip
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        window.delegate = self
        window.togglePin = { [weak self] in
            guard let self else { return }
            self.setPinned(!self.isPinned)
        }
        window.dismiss = { [weak self] in self?.hide() }
    }

    func windowDidResignKey(_ notification: Notification) {
        if !isPinned { window.level = .normal }
    }

    func windowDidBecomeKey(_ notification: Notification) { window.level = .floating }

    private func makePage() -> WKWebView {
        let config = WKWebViewConfiguration()
        let scripts = config.userContentController
        do {
            let folder = Bundle.module.resourceURL!.appendingPathComponent("Web")
            let js = try String(contentsOf:folder.appendingPathComponent("adapter.js"),encoding:.utf8)
            let css = try String(contentsOf:folder.appendingPathComponent("compact.css"),encoding:.utf8)
            let literal = String(decoding:try JSONEncoder().encode(css),as:UTF8.self)
            let style = "if(location.origin==='https://chatgpt.com'){const s=document.createElement('style');s.textContent=" + literal + ";document.head.append(s)}"
            scripts.addUserScript(WKUserScript(source:style+";"+js,injectionTime:.atDocumentEnd,forMainFrameOnly:true,in:world))
        } catch { fatalError("加载输入栏资源失败：\(error)") }
        scripts.add(self,contentWorld:world,name:"floating")
        let web = WKWebView(frame:NSRect(x:0,y:0,width:520,height:470),configuration:config)
        web.setValue(false,forKey:"drawsBackground")
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
        web.navigationDelegate = self
        web.uiDelegate = self
        return web
    }

    private func prepareNextIfNeeded() {
        guard minutes == 0, spare == nil else { return }
        let next = makePage()
        spare = next
        loadHome(next)
    }

    private func prepare() {
        routeObservation?.invalidate()
        if let previous = page {
            previous.navigationDelegate = nil
            previous.uiDelegate = nil
            previous.configuration.userContentController.removeScriptMessageHandler(forName:"floating", contentWorld:world)
            previous.stopLoading()
            previous.removeFromSuperview()
        }
        let next = spare ?? makePage()
        let needsLoad = spare == nil
        page = next
        ready = spareReady
        spare = nil
        spareReady = false
        page.alphaValue = 0
        routeObservation = page.observe(\.url, options:[.old,.new]) { [weak self] web, change in
            guard let self, web === self.page, let old = change.oldValue ?? nil,
                  let new = change.newValue ?? nil, old.host == Self.home.host,
                  new.host == Self.home.host, old.pathComponents.contains("c") || old.pathComponents.contains("uc"),
                  new.path == "/" || new.path.isEmpty else { return }
            self.startCompactConversation()
        }
        clip.addSubview(page)
        errorLabel.alignment = .center
        errorLabel.isHidden = true
        clip.addSubview(errorLabel)
        if needsLoad { loadHome(page) }
    }

    func warmUp() {
        guard page == nil else { return }
        prepare()
    }

    func toggle() {
        if window.isVisible && window.isOnActiveSpace { hide() } else { show() }
    }
    func show(activate: Bool = true) {
        let expired = inactiveSince.map { Self.expired(minutes:minutes,elapsed:Date().timeIntervalSince($0)) } == true
        let reusableComposer = prefersCompact && !landingPageUsed && errorLabel.isHidden &&
            (page?.url == nil || page.url == Self.home)
        let fresh = page == nil || (expired && !reusableComposer)
        inactiveSince = nil
        let pointer = NSEvent.mouseLocation
        area = (NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main)?.visibleFrame ?? .zero
        anchor = CGPoint(x:area.midX,y:area.minY+32)
        let resetDraft = expired && reusableComposer && hasTextDraft
        if fresh || resetDraft { hasTextDraft = false }
        if fresh {
            prepare()
            landingPageUsed = false
            prefersCompact = true
            errorLabel.isHidden = true
        } else if !errorLabel.isHidden {
            errorLabel.isHidden = true
            if page.url == nil { loadHome(page) } else { page.reload() }
        }
        if fresh { composerHeight = 108; menuHeight = 108 }
        let nextCompact = prefersCompact
        if !fresh && nextCompact != compact { page.alphaValue = 0 }
        if resetDraft { page.alphaValue = 0 }
        compact = nextCompact
        resize()
        if activate {
            window.level = .floating
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
        window.makeFirstResponder(page)
        sync(focus:activate,resetDraft:resetDraft)
    }
    private func startCompactConversation() {
        prefersCompact = true
        menuHeight = 108
        composerHeight = 108
        apply(compact:true,focus:window.isKeyWindow)
    }

    func showPage() {
        if !window.isVisible { show() }
        prefersCompact = false
        prepareNextIfNeeded()
        apply(compact:false,focus:false)
    }
    func hide() {
        guard window.isVisible else { return }
        window.orderOut(nil)
        inactiveSince = Date()
        sync(focus:false)
    }

    private func recordReplyUpdate() {
        if inactiveSince != nil { inactiveSince = Date() }
    }

    private func resize() {
        guard !area.isEmpty else { return }
        positioning = true
        defer { positioning = false }
        let width = min(compact ? 520 : readingSize.width,area.width)
        let height = min(compact ? max(composerHeight, menuHeight) : readingSize.height, area.height)
        let y = max(area.minY, min(anchor.y, area.maxY-height))
        let x = max(area.minX, min(round(anchor.x-width/2), area.maxX-width))
        let frame = NSRect(x:x,y:y,width:width,height:height)
        let modeChanged = window.styleMask.contains(.titled) != !compact
        guard modeChanged || window.frame != frame else { return }
        if modeChanged {
            window.hasShadow = !compact
            window.isOpaque = !compact
            window.backgroundColor = compact ? .clear : .windowBackgroundColor
            window.setExpanded(!compact)
        }
        if window.frame != frame { window.setFrame(frame,display:false,animate:false) }
        window.updateTitlebarTracking()
        layoutPage()
    }

    private func layoutPage() {
        let width = clip.bounds.width
        let height = clip.bounds.height
        page.frame = NSRect(x:0,y:0,width:width,height:compact ? max(height,470) : window.contentLayoutRect.height)
        errorLabel.frame = NSRect(x:0,y:max(0,height/2-12),width:width,height:24)
    }

    func windowDidResize(_ notification: Notification) {
        guard !positioning, !compact, page != nil else { return }
        anchor = CGPoint(x:window.frame.midX,y:window.frame.minY)
        window.updateTitlebarTracking()
        layoutPage()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
    func windowDidMove(_ notification: Notification) {
        guard !positioning, !compact, window.isVisible else { return }
        area = window.screen?.visibleFrame ?? area
        anchor = CGPoint(x:window.frame.midX,y:window.frame.minY)
    }
    private func apply(compact next: Bool,focus: Bool) {
        let changed = compact != next
        compact = next
        if changed {
            page.alphaValue = 0
            resize()
        }
        sync(focus:focus)
    }
    private func sync(focus: Bool,resetDraft: Bool = false) {
        revision += 1
        let ticket = revision
        let visible = window.isVisible
        page.callAsyncJavaScript("window.qcLayout?.(small, visible, focus, trackChanges, resetDraft)",
            arguments:["small":compact,"visible":visible,"focus":focus,
                       "trackChanges":prefersCompact,"resetDraft":resetDraft],in:nil,in:world) { [weak self] _ in
                guard let self, ticket == self.revision, self.ready else { return }
                self.page.alphaValue = 1
            }
    }
    func userContentController(_ controller: WKUserContentController,didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.host == "chatgpt.com" else { return }
        if let spare, message.webView === spare {
            if let state = message.body as? String, ["ready","full"].contains(state) {
                spareReady = true
                spare.callAsyncJavaScript("window.qcLayout?.(true,false,false,true)", arguments:[:], in:nil, in:world)
            }
            return
        }
        guard message.webView === page else { return }
        if let info = message.body as? [String:CGFloat], let measured = info["composerHeight"] {
            let height = min(470, max(108, ceil(measured) + 16))
            if compact && height != composerHeight { composerHeight = height; resize() }
            return
        }
        if let height = message.body as? NSNumber {
            menuHeight = min(470,max(108,CGFloat(height.doubleValue)))
            resize()
            return
        }
        switch message.body as? String {
        case "ready","full":
            let first = !ready
            ready = true
            let wasMenuOpen = compact && menuHeight != 108
            menuHeight = 108
            if wasMenuOpen { resize() }
            apply(compact:prefersCompact,focus:first && window.isKeyWindow)
        case "newChat": startCompactConversation()
        case "textDraft": hasTextDraft = true
        case "landingUsed":
            landingPageUsed = true
            prepareNextIfNeeded()
        case "sent":
            prepareNextIfNeeded()
            prefersCompact = false
            if compact && window.isVisible { apply(compact:false,focus:false) }
        case "replyUpdated": recordReplyUpdate()
        case "hide": hide()
        default: break
        }
    }
    func webView(_ webView: WKWebView,didFinish navigation: WKNavigation!) {
        if webView === page, webView.url?.host != "chatgpt.com" { ready = true; prefersCompact = false; apply(compact:false,focus:false) }
    }
    func webView(_ webView: WKWebView,didFailProvisionalNavigation navigation: WKNavigation!,withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        if webView === spare { spare = nil; spareReady = false; return }
        guard webView === page else { return }
        errorLabel.stringValue = "页面加载失败，收起后重新打开可重试"
        errorLabel.isHidden = false
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === spare { spareReady = false } else { ready = false }
        webView.reload()
    }
    func webView(_ webView: WKWebView,decidePolicyFor action: WKNavigationAction,decisionHandler: @escaping (WKNavigationActionPolicy)->Void) {
        guard action.targetFrame?.isMainFrame != false, let url = action.request.url else { decisionHandler(.allow); return }
        let host = url.host?.lowercased() ?? ""
        let official = ["chatgpt.com","openai.com","auth0.com","accounts.google.com","appleid.apple.com","login.live.com","login.microsoftonline.com"].contains { host == $0 || host.hasSuffix("."+$0) }
        if url.scheme == "https", official {
            if action.targetFrame == nil { decisionHandler(.cancel); webView.load(action.request) } else { decisionHandler(.allow) }
        } else {
            decisionHandler(.cancel)
            if action.navigationType == .linkActivated, ["https","http"].contains(url.scheme) { NSWorkspace.shared.open(url) }
        }
    }
    func webView(_ webView: WKWebView,runOpenPanelWith parameters: WKOpenPanelParameters,initiatedByFrame frame: WKFrameInfo,completionHandler: @escaping ([URL]?)->Void) {
        let chooser = NSOpenPanel()
        chooser.allowsMultipleSelection = parameters.allowsMultipleSelection
        chooser.begin { result in completionHandler(result == .OK ? chooser.urls : nil) }
    }
}
