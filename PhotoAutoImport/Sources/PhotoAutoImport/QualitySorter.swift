import Foundation

struct QualitySortResult {
    var kept = 0
    var moved = 0
}

/// 分析新匯入的檔案，把模糊／曝光不良的搬到目的地根目錄下的 `_LowQuality/<日期>/`，
/// 讓留下來的（畫質好的）素材保持乾淨——之後送進達芬奇也只會匯入留下的。
enum QualitySorter {

    /// 在背景執行緒呼叫。`files` 是新複製到目的地的檔案路徑。
    static func sort(_ files: [URL], destinationRoot: URL) -> QualitySortResult {
        var result = QualitySortResult()
        let fm = FileManager.default
        let lowRoot = destinationRoot.appendingPathComponent("_LowQuality", isDirectory: true)

        for file in files {
            guard fm.fileExists(atPath: file.path) else { continue }
            guard let score = QualityAnalyzer.analyze(file) else {
                result.kept += 1   // 無法分析就保守保留
                continue
            }
            if score.keep {
                result.kept += 1
                continue
            }

            // 模糊/曝光差 → 搬到 _LowQuality/<原本的日期資料夾名>/
            let dayName = file.deletingLastPathComponent().lastPathComponent
            let lowDir = lowRoot.appendingPathComponent(dayName, isDirectory: true)
            do {
                try fm.createDirectory(at: lowDir, withIntermediateDirectories: true)
                let dest = uniqueDestination(in: lowDir, name: file.lastPathComponent)
                try fm.moveItem(at: file, to: dest)
                result.moved += 1
            } catch {
                result.kept += 1   // 搬移失敗就當保留，不影響原檔
            }
        }
        return result
    }

    private static func uniqueDestination(in dir: URL, name: String) -> URL {
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent(name)
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var i = 1
        while fm.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(base)-\(i)" : "\(base)-\(i).\(ext)"
            candidate = dir.appendingPathComponent(newName)
            i += 1
        }
        return candidate
    }
}
