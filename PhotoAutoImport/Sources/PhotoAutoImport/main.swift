import AppKit

// 選單列 App：不在 Dock 顯示、沒有主視窗，只在右上角選單列放一個圖示。
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
