import Foundation

/// 使用者偏好設定，存在 UserDefaults。
enum Prefs {
    private static let d = UserDefaults.standard

    /// 是否啟用「插卡自動匯入」。預設開啟。
    static var enabled: Bool {
        get { d.object(forKey: "enabled") == nil ? true : d.bool(forKey: "enabled") }
        set { d.set(newValue, forKey: "enabled") }
    }

    /// 匯入成功後是否詢問清空卡片。預設關閉（較安全）。
    static var eraseAfterImport: Bool {
        get { d.bool(forKey: "eraseAfterImport") }
        set { d.set(newValue, forKey: "eraseAfterImport") }
    }

    /// 匯入後是否做本機畫質分析、把模糊/曝光差的挑到 _LowQuality。預設關閉。
    static var analyzeQuality: Bool {
        get { d.bool(forKey: "analyzeQuality") }
        set { d.set(newValue, forKey: "analyzeQuality") }
    }

    /// 匯入後是否詢問「送進 DaVinci Resolve」。預設關閉。
    static var sendToDavinci: Bool {
        get { d.bool(forKey: "sendToDavinci") }
        set { d.set(newValue, forKey: "sendToDavinci") }
    }

    /// 匯入目的地根資料夾。預設 ~/Pictures/AutoImport。
    static var destination: URL {
        get {
            if let path = d.string(forKey: "destination"), !path.isEmpty {
                return URL(fileURLWithPath: path)
            }
            let pics = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            return pics.appendingPathComponent("AutoImport", isDirectory: true)
        }
        set { d.set(newValue.path, forKey: "destination") }
    }
}
