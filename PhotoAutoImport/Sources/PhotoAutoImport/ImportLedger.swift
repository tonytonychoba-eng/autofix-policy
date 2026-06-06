import Foundation

/// 記錄已匯入過的檔案，避免下次插同一張卡時重複複製。
///
/// 以「檔名 | 位元組大小 | 修改時間」當作識別鍵，不需逐位元組比對，
/// 既快又足以判斷是不是同一個檔案。資料存在
/// ~/Library/Application Support/PhotoAutoImport/ledger.json。
final class ImportLedger {
    private var keys: Set<String>
    private let url: URL

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PhotoAutoImport", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("ledger.json")

        if let data = try? Data(contentsOf: url),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            keys = Set(arr)
        } else {
            keys = []
        }
    }

    static func key(name: String, size: Int, mtime: Date) -> String {
        "\(name)|\(size)|\(Int(mtime.timeIntervalSince1970))"
    }

    func contains(_ k: String) -> Bool { keys.contains(k) }

    func insert(_ k: String) { keys.insert(k) }

    func save() {
        if let data = try? JSONEncoder().encode(Array(keys).sorted()) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
