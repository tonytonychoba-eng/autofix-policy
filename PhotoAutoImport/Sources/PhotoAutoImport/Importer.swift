import Foundation

struct ImportResult {
    var copied = 0
    var skipped = 0
    var failed = 0
    /// 已成功匯入的來源檔（供「清空卡」使用）。
    var importedSources: [URL] = []
    /// 這次有新檔複製進去的日期資料夾（供「送進達芬奇」使用）。
    var touchedDayFolders: [URL] = []
    /// 這次新複製到目的地的檔案路徑（供「畫質分析」使用）。
    var newlyCopied: [URL] = []
}

/// 負責掃描卷宗、複製照片影片、去重、依拍攝日期分資料夾。
final class Importer {
    /// 認得的照片 / 影片副檔名（小寫）。
    private static let mediaExtensions: Set<String> = [
        // 照片
        "jpg", "jpeg", "heic", "heif", "png", "tif", "tiff", "gif", "bmp", "webp",
        // RAW
        "dng", "raw", "cr2", "cr3", "nef", "nrw", "arw", "sr2", "srf",
        "raf", "orf", "rw2", "pef", "x3f", "3fr", "erf",
        // 影片
        "mov", "mp4", "m4v", "avi", "mpg", "mpeg", "3gp", "3g2",
        "mts", "m2ts", "mxf", "wmv", "mkv", "webm",
    ]

    private let ledger: ImportLedger
    private let fm = FileManager.default
    private let dateFormatter: DateFormatter

    init(ledger: ImportLedger) {
        self.ledger = ledger
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        self.dateFormatter = f
    }

    /// 掃描單一卷宗並匯入。會在背景執行緒呼叫；不碰 UI。
    func importVolume(_ volume: URL, destinationRoot: URL) -> ImportResult {
        var result = ImportResult()
        var touched = Set<URL>()

        let mediaFiles = scanMedia(in: volume)
        guard !mediaFiles.isEmpty else { return result }

        for source in mediaFiles {
            let info = fileInfo(source)
            let key = ImportLedger.key(name: source.lastPathComponent,
                                       size: info.size, mtime: info.mtime)
            if ledger.contains(key) {
                result.skipped += 1
                result.importedSources.append(source) // 之前已匯入，清空卡時可一併刪
                continue
            }

            let dayFolder = destinationRoot
                .appendingPathComponent(dateFolderName(info.date), isDirectory: true)
            do {
                try fm.createDirectory(at: dayFolder, withIntermediateDirectories: true)
            } catch {
                result.failed += 1
                continue
            }

            guard let dest = uniqueDestination(in: dayFolder,
                                               name: source.lastPathComponent,
                                               sourceSize: info.size) else {
                // 目的地已有相同大小的同名檔，視為已存在。
                ledger.insert(key)
                result.skipped += 1
                result.importedSources.append(source)
                continue
            }

            do {
                try fm.copyItem(at: source, to: dest)
                // 簡單驗證：大小一致才算成功。
                let copiedSize = (try? fm.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? nil
                if copiedSize == info.size {
                    ledger.insert(key)
                    result.copied += 1
                    result.importedSources.append(source)
                    result.newlyCopied.append(dest)
                    touched.insert(dayFolder)
                } else {
                    try? fm.removeItem(at: dest)
                    result.failed += 1
                }
            } catch {
                result.failed += 1
            }
        }

        ledger.save()
        result.touchedDayFolders = Array(touched)
        return result
    }

    /// 清空卡：刪除指定的來源檔。呼叫前務必已確認匯入成功。
    func eraseSources(_ sources: [URL]) -> Int {
        var deleted = 0
        for url in sources where fm.fileExists(atPath: url.path) {
            if (try? fm.removeItem(at: url)) != nil { deleted += 1 }
        }
        return deleted
    }

    // MARK: - 內部工具

    private func scanMedia(in volume: URL) -> [URL] {
        var results: [URL] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        guard let en = fm.enumerator(
            at: volume,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return results }

        for case let url as URL in en {
            let ext = url.pathExtension.lowercased()
            if Importer.mediaExtensions.contains(ext) {
                results.append(url)
            }
        }
        return results
    }

    private func fileInfo(_ url: URL) -> (size: Int, mtime: Date, date: Date) {
        let keys: Set<URLResourceKey> = [
            .fileSizeKey, .contentModificationDateKey, .creationDateKey
        ]
        let v = try? url.resourceValues(forKeys: keys)
        let size = v?.fileSize ?? 0
        let mtime = v?.contentModificationDate ?? Date(timeIntervalSince1970: 0)
        // 以建立日期（拍攝日）分資料夾；沒有就退而求其次用修改日期。
        let date = v?.creationDate ?? v?.contentModificationDate ?? Date()
        return (size, mtime, date)
    }

    private func dateFolderName(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    /// 回傳一個不衝突的目的地路徑；若已存在「相同大小」的同名檔，回傳 nil（視為重複）。
    private func uniqueDestination(in dir: URL, name: String, sourceSize: Int) -> URL? {
        var candidate = dir.appendingPathComponent(name)
        if !fm.fileExists(atPath: candidate.path) { return candidate }

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var i = 1
        while fm.fileExists(atPath: candidate.path) {
            if let size = try? fm.attributesOfItem(atPath: candidate.path)[.size] as? Int,
               size == sourceSize {
                return nil // 同名同大小，當作重複
            }
            let newName = ext.isEmpty ? "\(base)-\(i)" : "\(base)-\(i).\(ext)"
            candidate = dir.appendingPathComponent(newName)
            i += 1
        }
        return candidate
    }
}
