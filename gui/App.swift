import Cocoa
import UniformTypeIdentifiers

final class App: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate {
    var window: NSWindow!
    
    // Configuration Fields (No default values, no placeholder hints)
    let serverField = NSTextField()
    let portField = NSTextField()
    let loginPathField = NSTextField()
    
    // Status & Feedback
    let statusLabel = NSTextField(labelWithString: "未连接")
    let detailLabel = NSTextField(wrappingLabelWithString: "请在上方输入服务器地址和端口，或登录 VPN 网页后点击“连接”。")
    let pathLabel = NSTextField(labelWithString: "")
    let connectButton = NSButton(title: "连接 VPN", target: nil, action: nil)
    let logView = NSTextView()
    
    var pagePath: String = ""
    var activeLink: String?
    var process: Process?
    var controlDir: URL?
    var pollTimer: Timer?
    var isStopping = false
    var isQuitting = false
    var isConnected = false
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(receiveURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }
    
    func makeFieldRow(labelText: String, field: NSTextField) -> NSStackView {
        let label = NSTextField(labelWithString: labelText)
        label.alignment = .right
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 90).isActive = true
        
        field.font = .systemFont(ofSize: 12)
        field.bezelStyle = .roundedBezel
        field.isEditable = true
        field.isSelectable = true
        field.delegate = self
        field.placeholderString = ""
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 450).isActive = true
        
        let row = NSStackView(views: [label, field])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        
        // Setup Main Menu with standard Edit menu to enable ⌘V, ⌘C, ⌘X, ⌘A
        setupMainMenu()
        
        // Main Window setup
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "UTM SSLVPN 客户端"
        window.delegate = self
        window.isReleasedWhenClosed = false
        
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 12
        container.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(container)
        
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
            container.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
            container.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22),
            container.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -20)
        ])
        
        // Title
        let headerLabel = NSTextField(labelWithString: "轻松连接 · 内网办公")
        headerLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        container.addArrangedSubview(headerLabel)
        
        // Status & Detail
        statusLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        statusLabel.textColor = .secondaryLabelColor
        container.addArrangedSubview(statusLabel)
        
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.maximumNumberOfLines = 3
        container.addArrangedSubview(detailLabel)
        
        // Configuration Section (hints removed)
        let configSectionTitle = NSTextField(labelWithString: "连接参数配置：")
        configSectionTitle.font = .systemFont(ofSize: 13, weight: .bold)
        configSectionTitle.textColor = .labelColor
        container.addArrangedSubview(configSectionTitle)
        
        container.addArrangedSubview(makeFieldRow(labelText: "服务器地址:", field: serverField))
        container.addArrangedSubview(makeFieldRow(labelText: "隧道端口:", field: portField))
        container.addArrangedSubview(makeFieldRow(labelText: "登录页路径:", field: loginPathField))
        
        // Load config into fields
        loadInitialConfig()
        
        // Action Buttons
        let loginButton = NSButton(title: "① 打开 VPN 登录页", target: self, action: #selector(openLoginPage))
        loginButton.bezelStyle = .rounded
        container.addArrangedSubview(loginButton)
        
        connectButton.target = self
        connectButton.action = #selector(toggleConnection)
        connectButton.bezelStyle = .rounded
        connectButton.controlSize = .large
        container.addArrangedSubview(connectButton)
        
        // Fallback & Repair Row
        let repairButton = NSButton(title: "清理旧连接", target: self, action: #selector(repairOldConnections))
        repairButton.bezelStyle = .rounded
        
        let chooseFileButton = NSButton(title: "备用方式：选择已保存网页…", target: self, action: #selector(chooseSavedPage))
        chooseFileButton.bezelStyle = .rounded
        
        let subRow = NSStackView(views: [repairButton, chooseFileButton])
        subRow.orientation = .horizontal
        subRow.alignment = .centerY
        subRow.spacing = 12
        container.addArrangedSubview(subRow)
        
        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        container.addArrangedSubview(pathLabel)
        
        // Log view
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = logView
        logView.isEditable = false
        logView.isSelectable = true
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.autoresizingMask = [.width]
        logView.textContainer!.widthTracksTextView = true
        
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        container.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 90).isActive = true
        
        let footerTip = NSTextField(labelWithString: "保持应用打开。点击“断开”或退出应用即可结束连接。")
        footerTip.font = .systemFont(ofSize: 11)
        footerTip.textColor = .secondaryLabelColor
        container.addArrangedSubview(footerTip)
        
        refreshSourceInfo()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        if activeLink != nil {
            linkReady()
        }
    }
    
    // MARK: - Menu Setup with Edit/Clipboard support
    func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // App Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 UTM SSLVPN", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出 UTM SSLVPN", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        
        // Standard Edit Menu for Cut/Copy/Paste/SelectAll/Undo
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        
        NSApp.mainMenu = mainMenu
    }
    
    // MARK: - NSTextFieldDelegate (Real-time auto-saving)
    func controlTextDidChange(_ obj: Notification) {
        persistCurrentConfig()
    }
    
    // MARK: - Configuration Handling & Persistence
    func loadInitialConfig() {
        let defaults = UserDefaults.standard
        pagePath = defaults.string(forKey: "page") ?? (NSHomeDirectory() + "/Desktop/SSLVPN 客户端.html")
        
        var s = defaults.string(forKey: "server") ?? ""
        var p = defaults.string(forKey: "port") ?? ""
        var lp = defaults.string(forKey: "login_path") ?? ""
        
        // Fallback to ~/.utmssl_config.json if UserDefaults has not stored it yet
        let cfgUrl = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".utmssl_config.json")
        if (s.isEmpty || p.isEmpty), let data = try? Data(contentsOf: cfgUrl),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if s.isEmpty, let serverVal = json["server"] as? String { s = serverVal }
            if p.isEmpty, let portVal = json["port"] as? String { p = portVal }
            else if p.isEmpty, let portInt = json["port"] as? Int, portInt > 0 { p = String(portInt) }
            if lp.isEmpty, let pathVal = json["login_path"] as? String { lp = pathVal }
        }
        
        serverField.stringValue = s
        portField.stringValue = p
        loginPathField.stringValue = lp
    }
    
    func persistCurrentConfig() {
        let defaults = UserDefaults.standard
        let s = serverField.stringValue.trimmingCharacters(in: .whitespaces)
        let p = portField.stringValue.trimmingCharacters(in: .whitespaces)
        let lp = loginPathField.stringValue.trimmingCharacters(in: .whitespaces)
        
        defaults.set(s, forKey: "server")
        defaults.set(p, forKey: "port")
        defaults.set(lp, forKey: "login_path")
        defaults.set(pagePath, forKey: "page")
        defaults.synchronize()
        
        // Also persist to ~/.utmssl_config.json for stable cross-session persistence
        let cfgUrl = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".utmssl_config.json")
        let dict: [String: Any] = [
            "server": s,
            "port": p,
            "login_path": lp,
            "page": pagePath
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]) {
            try? data.write(to: cfgUrl, options: .atomic)
        }
    }
    
    func refreshSourceInfo() {
        if activeLink != nil {
            pathLabel.stringValue = "登录信息已就绪（仅供本次连接，不会明文保存凭据）"
        } else {
            pathLabel.stringValue = "备用网页路径: " + pagePath
        }
    }
    
    // MARK: - URL Scheme Handler (utmssl://...)
    @objc func receiveURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let components = URLComponents(string: urlString),
              components.scheme == "utmssl",
              components.path == "/conn",
              let host = components.host, !host.isEmpty,
              let port = components.port, port > 0,
              let query = components.percentEncodedQuery,
              let token = query.split(separator: "&").first,
              (1...32).contains(token.utf8.count),
              urlString.utf8.count < 1024 else { return }
        
        if process != nil { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.serverField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
                self.serverField.stringValue = host
            }
            if self.portField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
                self.portField.stringValue = String(port)
            }
            self.persistCurrentConfig()
            self.activeLink = urlString
            self.linkReady()
        }
    }
    
    func linkReady() {
        detailLabel.stringValue = "已收到网页“连接”指令。点击“连接 VPN”并在系统窗口验证密码即可建立隧道。"
        refreshSourceInfo()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Actions
    @objc func openLoginPage() {
        persistCurrentConfig()
        let server = serverField.stringValue.trimmingCharacters(in: .whitespaces)
        let portStr = portField.stringValue.trimmingCharacters(in: .whitespaces)
        var path = loginPathField.stringValue.trimmingCharacters(in: .whitespaces)
        if path.isEmpty { path = "/internal-server/pages/index.html" }
        if !path.hasPrefix("/") { path = "/" + path }
        
        guard !server.isEmpty, let port = Int(portStr), port > 0 else {
            detailLabel.stringValue = "请先填写服务器地址和端口（支持直接从剪贴板粘贴 ⌘+V）。"
            return
        }
        
        let urlStr = "https://\(server):\(port)\(path)"
        if let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
            detailLabel.stringValue = "已在浏览器中打开登录页面，登录后点击网页上的“连接”即可。"
        }
    }
    
    @objc func chooseSavedPage() {
        guard process == nil else { return }
        let panel = NSOpenPanel()
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [UTType.html]
        } else {
            panel.allowedFileTypes = ["html", "htm"]
        }
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "选择在浏览器中完整保存的 SSLVPN 客户端.html（需保留同名 _files 文件夹）"
        if panel.runModal() == .OK, let url = panel.url {
            pagePath = url.path
            activeLink = nil
            persistCurrentConfig()
            refreshSourceInfo()
            detailLabel.stringValue = "已选择保存的 VPN 页面，点击“连接 VPN”开始连接。"
        }
    }
    
    @objc func toggleConnection() {
        if process != nil {
            stopConnection()
        } else {
            startConnection()
        }
    }
    
    func parseSavedLink() throws -> String {
        let base = URL(fileURLWithPath: pagePath)
        let filesDir = base.deletingLastPathComponent().appendingPathComponent(base.deletingPathExtension().lastPathComponent + "_files")
        var candidates = [base]
        if let entries = try? FileManager.default.contentsOfDirectory(at: filesDir, includingPropertiesForKeys: nil) {
            candidates += entries.filter { $0.pathExtension.lowercased() == "html" }
        }
        
        let regex = try NSRegularExpression(pattern: "utmssl://[^\"'<>\\s]+")
        for candidate in candidates {
            guard let data = try? Data(contentsOf: candidate), data.count <= 2_000_000 else { continue }
            let text = String(decoding: data, as: UTF8.self)
            let ns = text as NSString
            if let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                let linkStr = ns.substring(with: match.range).replacingOccurrences(of: "&amp;", with: "&")
                if let u = URLComponents(string: linkStr), u.path == "/conn", u.host != nil, u.port != nil {
                    return linkStr
                }
            }
        }
        throw NSError(domain: "UTMSSLVPN", code: 1, userInfo: [NSLocalizedDescriptionKey: "未在指定的网页或其资源文件夹中找到有效连接链接。"])
    }
    
    func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    
    func appleQuote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    
    // MARK: - Start & Stop Connection
    func startConnection() {
        persistCurrentConfig()
        guard let resources = Bundle.main.resourceURL else { return }
        
        if activeLink == nil && !FileManager.default.fileExists(atPath: pagePath) {
            detailLabel.stringValue = "请先在网页登录并点击“连接”，或通过下方备用方式选择保存的完整 HTML 网页。"
            return
        }
        
        do {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("simplevpn-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            controlDir = tempDir
            
            let connLink = try (activeLink ?? parseSavedLink())
            let linkFile = tempDir.appendingPathComponent("link")
            try Data(connLink.utf8).write(to: linkFile, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: linkFile.path)
            
            // Create config.json in temp dir if server/port provided
            let server = serverField.stringValue.trimmingCharacters(in: .whitespaces)
            let port = Int(portField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0
            var configDict: [String: Any] = [:]
            if !server.isEmpty { configDict["server"] = server }
            if port > 0 { configDict["port"] = port }
            
            if !configDict.isEmpty {
                let configJsonData = try JSONSerialization.data(withJSONObject: configDict, options: .prettyPrinted)
                try configJsonData.write(to: tempDir.appendingPathComponent("config.json"))
            }
            
            for file in ["worker.py", "mac_vpn.py", "protocol.py"] {
                try FileManager.default.copyItem(at: resources.appendingPathComponent(file), to: tempDir.appendingPathComponent(file))
            }
            
            let logFile = tempDir.appendingPathComponent("log")
            FileManager.default.createFile(atPath: logFile.path, contents: Data(), attributes: [.posixPermissions: 0o600])
            
            let workerArgs = [
                "/usr/bin/python3", "-E", "-s", "-u", "-B",
                tempDir.appendingPathComponent("worker.py").path,
                tempDir.path,
                String(ProcessInfo.processInfo.processIdentifier),
                "--link-file",
                linkFile.path
            ]
            let command = workerArgs.map(quote).joined(separator: " ") + " > " + quote(logFile.path) + " 2>&1"
            let appleScript = "do shell script " + appleQuote(command) + " with administrator privileges"
            
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-"]
            
            let inPipe = Pipe()
            let errPipe = Pipe()
            proc.standardInput = inPipe
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = errPipe
            
            isStopping = false
            isConnected = false
            process = proc
            statusLabel.stringValue = "正在连接…"
            statusLabel.textColor = .systemOrange
            detailLabel.stringValue = "请在 macOS 弹出的授权窗口中输入管理员密码（用于创建 utun 网卡及添加路由）。"
            connectButton.title = "取消连接"
            logView.string = ""
            
            proc.terminationHandler = { [weak self] done in
                let errStr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    self?.handleTermination(done.terminationStatus, error: errStr)
                }
            }
            
            try proc.run()
            inPipe.fileHandleForWriting.write(Data(appleScript.utf8))
            try? inPipe.fileHandleForWriting.close()
            
            pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.pollLogs()
            }
        } catch {
            process = nil
            statusLabel.stringValue = "未能启动"
            detailLabel.stringValue = "准备连接失败：\(error.localizedDescription)"
            connectButton.title = "连接 VPN"
            cleanupTemp()
        }
    }
    
    func pollLogs() {
        guard let dir = controlDir else { return }
        let logText = (try? String(contentsOf: dir.appendingPathComponent("log"), encoding: .utf8)) ?? ""
        logView.string = String(logText.suffix(12000))
        logView.scrollToEndOfDocument(nil)
        
        if !isStopping && logText.contains("隧道已启动") && !isConnected {
            isConnected = true
            statusLabel.stringValue = "● 已连接"
            statusLabel.textColor = .systemGreen
            detailLabel.stringValue = "内网隧道已就绪，已成功接入私网路由。用完后点击“断开 VPN”。"
            connectButton.title = "断开 VPN"
        }
    }
    
    func stopConnection() {
        guard let dir = controlDir else { return }
        isStopping = true
        statusLabel.stringValue = "正在断开…"
        connectButton.isEnabled = false
        try? Data().write(to: dir.appendingPathComponent("stop"))
        detailLabel.stringValue = "正在关闭隧道并清理临时路由..."
    }
    
    func handleTermination(_ code: Int32, error: String) {
        pollLogs()
        pollTimer?.invalidate()
        pollTimer = nil
        process = nil
        isConnected = false
        connectButton.title = "连接 VPN"
        connectButton.isEnabled = true
        statusLabel.stringValue = "未连接"
        statusLabel.textColor = .secondaryLabelColor
        
        if isStopping || code == 0 {
            detailLabel.stringValue = "已安全断开并清理路由。若会话过期，请重新打开网页获取新会话。"
        } else if error.contains("-128") {
            detailLabel.stringValue = "已取消管理员授权，连接未建立。"
        } else {
            detailLabel.stringValue = "连接未完成或异常退出。请查看下方运行记录；若凭据过期请重新在网页登录。"
        }
        
        cleanupTemp()
        if isQuitting {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
    }
    
    func cleanupTemp() {
        if let dir = controlDir {
            try? FileManager.default.removeItem(at: dir)
        }
        controlDir = nil
    }
    
    @objc func repairOldConnections() {
        guard process == nil else { stopConnection(); return }
        guard let resources = Bundle.main.resourceURL else { return }
        
        let alert = NSAlert()
        alert.messageText = "断开残留的旧连接？"
        alert.informativeText = "将向旧的后台工作进程发送退出信号，清理残留路由并释放网卡锁定。"
        alert.addButton(withTitle: "立即清理")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        
        do {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("simplevpn-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            controlDir = tempDir
            
            let scriptFile = tempDir.appendingPathComponent("repair.py")
            try FileManager.default.copyItem(at: resources.appendingPathComponent("repair.py"), to: scriptFile)
            
            let logFile = tempDir.appendingPathComponent("log")
            FileManager.default.createFile(atPath: logFile.path, contents: Data(), attributes: [.posixPermissions: 0o600])
            
            let cmd = ["/usr/bin/python3", "-E", "-s", "-B", scriptFile.path].map(quote).joined(separator: " ") + " > " + quote(logFile.path) + " 2>&1"
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-"]
            let inPipe = Pipe()
            p.standardInput = inPipe
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            
            process = p
            isStopping = false
            statusLabel.stringValue = "正在清理旧连接…"
            connectButton.isEnabled = false
            
            p.terminationHandler = { [weak self] res in
                DispatchQueue.main.async { self?.handleTermination(res.terminationStatus, error: "") }
            }
            try p.run()
            inPipe.fileHandleForWriting.write(Data(("do shell script " + appleQuote(cmd) + " with administrator privileges").utf8))
            try? inPipe.fileHandleForWriting.close()
            
            pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.pollLogs() }
        } catch {
            process = nil
            cleanupTemp()
            connectButton.isEnabled = true
            detailLabel.stringValue = "启动清理失败：\(error.localizedDescription)"
        }
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        persistCurrentConfig()
        if process == nil { return .terminateNow }
        isQuitting = true
        stopConnection()
        return .terminateLater
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        persistCurrentConfig()
        NSApp.terminate(nil)
        return false
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.run()
