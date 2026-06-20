import Foundation

/// 把匯入好的資料夾送進 DaVinci Resolve（Studio）的媒體池。
/// 透過執行隨附的 Python 腳本 davinci_import.py 完成。
enum DavinciBridge {
    /// 在背景執行緒呼叫；會阻塞到腳本結束。
    static func sendFolders(_ folders: [URL]) {
        guard !folders.isEmpty else { return }
        guard let script = scriptURL() else {
            Notifier.notify(title: "找不到達芬奇匯入腳本",
                            body: "缺少 davinci_import.py。")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path] + folders.map { $0.path }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let out = String(
                data: pipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if process.terminationStatus != 0 {
                Notifier.notify(
                    title: "送進達芬奇失敗",
                    body: out.isEmpty ? "請確認 Resolve Studio 已開啟專案。" : out
                )
            } else if !out.isEmpty {
                Notifier.notify(title: "達芬奇", body: out)
            }
        } catch {
            Notifier.notify(title: "無法執行達芬奇腳本",
                            body: error.localizedDescription)
        }
    }

    /// 找腳本：打包成 .app 時在 Resources；用 swift run 開發時從原始碼旁找。
    private static func scriptURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "davinci_import",
                                         withExtension: "py") {
            return bundled
        }
        // 開發備援：<package>/davinci/davinci_import.py
        let dev = URL(fileURLWithPath: #filePath)   // .../Sources/PhotoAutoImport/DavinciBridge.swift
            .deletingLastPathComponent()            // .../Sources/PhotoAutoImport
            .deletingLastPathComponent()            // .../Sources
            .deletingLastPathComponent()            // <package root>
            .appendingPathComponent("davinci/davinci_import.py")
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }
}
