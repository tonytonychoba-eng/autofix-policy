import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let monitor = VolumeMonitor()
    private let ledger = ImportLedger()
    private lazy var importer = Importer(ledger: ledger)

    // 匯入工作放在序列佇列，避免同時插多張卡時互相干擾。
    private let workQueue = DispatchQueue(label: "PhotoAutoImport.work")

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.requestAuthorization()
        setupStatusItem()

        monitor.onRemovableMounted = { [weak self] volume in
            guard Prefs.enabled else { return }
            self?.startImport(volume: volume, manual: false)
        }
        monitor.start()
    }

    // MARK: - 選單列

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "photo.on.rectangle.angled",
                accessibilityDescription: "PhotoAutoImport"
            )
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let statusLine = NSMenuItem(
            title: Prefs.enabled ? "● 監看中" : "○ 已暫停",
            action: nil, keyEquivalent: ""
        )
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        let enableItem = NSMenuItem(
            title: "插卡自動匯入",
            action: #selector(toggleEnabled), keyEquivalent: ""
        )
        enableItem.target = self
        enableItem.state = Prefs.enabled ? .on : .off
        menu.addItem(enableItem)

        let eraseItem = NSMenuItem(
            title: "匯入後詢問清空卡",
            action: #selector(toggleErase), keyEquivalent: ""
        )
        eraseItem.target = self
        eraseItem.state = Prefs.eraseAfterImport ? .on : .off
        menu.addItem(eraseItem)

        let davinciItem = NSMenuItem(
            title: "匯入後詢問送進達芬奇",
            action: #selector(toggleDavinci), keyEquivalent: ""
        )
        davinciItem.target = self
        davinciItem.state = Prefs.sendToDavinci ? .on : .off
        menu.addItem(davinciItem)

        menu.addItem(.separator())

        let destItem = NSMenuItem(
            title: "匯入到：\(Prefs.destination.path)",
            action: nil, keyEquivalent: ""
        )
        destItem.isEnabled = false
        menu.addItem(destItem)

        let chooseItem = NSMenuItem(
            title: "選擇匯入資料夾…",
            action: #selector(chooseDestination), keyEquivalent: ""
        )
        chooseItem.target = self
        menu.addItem(chooseItem)

        let openItem = NSMenuItem(
            title: "開啟匯入資料夾",
            action: #selector(openDestination), keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let importNow = NSMenuItem(
            title: "立即匯入已連接的卡",
            action: #selector(importNow), keyEquivalent: ""
        )
        importNow.target = self
        menu.addItem(importNow)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "結束", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - 動作

    @objc private func toggleEnabled() {
        Prefs.enabled.toggle()
        rebuildMenu()
    }

    @objc private func toggleErase() {
        Prefs.eraseAfterImport.toggle()
        rebuildMenu()
    }

    @objc private func toggleDavinci() {
        Prefs.sendToDavinci.toggle()
        rebuildMenu()
    }

    @objc private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "選擇"
        panel.directoryURL = Prefs.destination
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            Prefs.destination = url
            rebuildMenu()
        }
    }

    @objc private func openDestination() {
        let dest = Prefs.destination
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dest)
    }

    @objc private func importNow() {
        let volumes = VolumeMonitor.mountedRemovableVolumes()
        if volumes.isEmpty {
            Notifier.notify(title: "沒有偵測到卡片", body: "請先插上 SD 卡或隨身碟。")
            return
        }
        for volume in volumes {
            startImport(volume: volume, manual: true)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - 匯入流程

    private func startImport(volume: URL, manual: Bool) {
        let destination = Prefs.destination
        workQueue.async { [weak self] in
            guard let self else { return }
            try? FileManager.default.createDirectory(
                at: destination, withIntermediateDirectories: true)

            let result = self.importer.importVolume(volume, destinationRoot: destination)

            DispatchQueue.main.async {
                self.handleResult(result, volume: volume, manual: manual)
            }
        }
    }

    private func handleResult(_ result: ImportResult, volume: URL, manual: Bool) {
        let volumeName = volume.lastPathComponent

        if result.copied == 0 && result.skipped == 0 && result.failed == 0 {
            if manual {
                Notifier.notify(title: "「\(volumeName)」沒有可匯入的照片或影片", body: "")
            }
            return
        }

        var parts: [String] = []
        if result.copied > 0 { parts.append("新匯入 \(result.copied)") }
        if result.skipped > 0 { parts.append("略過重複 \(result.skipped)") }
        if result.failed > 0 { parts.append("失敗 \(result.failed)") }
        Notifier.notify(title: "匯入完成：\(volumeName)", body: parts.joined(separator: "、"))

        // 先問達芬奇，再問清空卡（兩者都是選用、且都會先確認）。
        promptDavinciThenErase(result: result, volumeName: volumeName)
    }

    private func promptDavinciThenErase(result: ImportResult, volumeName: String) {
        let folders = result.touchedDayFolders
        if Prefs.sendToDavinci && !folders.isEmpty {
            let alert = NSAlert()
            alert.messageText = "要把這次的素材送進達芬奇嗎？"
            alert.informativeText = "會在媒體池的 AutoImport bin 底下，依日期建立 \(folders.count) 個 bin 並匯入素材。" +
                "需要 DaVinci Resolve Studio 正在執行、且已開啟專案。"
            alert.addButton(withTitle: "送進達芬奇")
            alert.addButton(withTitle: "略過")
            NSApp.activate(ignoringOtherApps: true)

            if alert.runModal() == .alertFirstButtonReturn {
                workQueue.async { [weak self] in
                    DavinciBridge.sendFolders(folders)
                    DispatchQueue.main.async {
                        self?.maybePromptErase(result: result, volumeName: volumeName)
                    }
                }
                return
            }
        }
        maybePromptErase(result: result, volumeName: volumeName)
    }

    private func maybePromptErase(result: ImportResult, volumeName: String) {
        // 只有真的有新檔複製成功，且使用者開了「清空卡」才詢問。
        if Prefs.eraseAfterImport && result.copied > 0 && result.failed == 0 {
            promptErase(sources: result.importedSources, volumeName: volumeName)
        }
    }

    private func promptErase(sources: [URL], volumeName: String) {
        let alert = NSAlert()
        alert.messageText = "要清空「\(volumeName)」嗎？"
        alert.informativeText = "已成功匯入 \(sources.count) 個檔案。" +
            "刪除後將無法復原（不會進垃圾桶），請確認匯入無誤。"
        alert.addButton(withTitle: "刪除卡上的照片影片")
        alert.addButton(withTitle: "保留")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn {
            workQueue.async { [weak self] in
                let deleted = self?.importer.eraseSources(sources) ?? 0
                DispatchQueue.main.async {
                    Notifier.notify(title: "已清空：\(volumeName)",
                                    body: "刪除了 \(deleted) 個檔案。")
                }
            }
        }
    }
}
