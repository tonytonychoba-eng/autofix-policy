import AppKit

/// 監聽磁碟掛載事件。SD 卡、隨身碟插上時會收到通知。
final class VolumeMonitor {
    /// 有可移除卷宗掛載時呼叫，參數為該卷宗的根目錄 URL。
    var onRemovableMounted: ((URL) -> Void)?

    private let center = NSWorkspace.shared.notificationCenter

    func start() {
        center.addObserver(
            self,
            selector: #selector(didMount(_:)),
            name: NSWorkspace.didMountNotification,
            object: nil
        )
    }

    func stop() {
        center.removeObserver(self)
    }

    @objc private func didMount(_ note: Notification) {
        guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
        guard VolumeMonitor.isRemovable(url) else { return }
        onRemovableMounted?(url)
    }

    /// 判斷是否為可移除 / 可退出的外接卷宗（排除內接磁碟）。
    static func isRemovable(_ url: URL) -> Bool {
        let keys: Set<URLResourceKey> = [
            .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsInternalKey
        ]
        guard let v = try? url.resourceValues(forKeys: keys) else { return false }
        if v.volumeIsInternal == true { return false }
        return (v.volumeIsRemovable ?? false) || (v.volumeIsEjectable ?? false)
    }

    /// 目前已掛載的可移除卷宗清單（給「立即匯入」用）。
    static func mountedRemovableVolumes() -> [URL] {
        let fm = FileManager.default
        let urls = fm.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) ?? []
        return urls.filter { isRemovable($0) }
    }
}
