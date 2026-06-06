#!/usr/bin/env python3
"""把指定資料夾的素材匯入「正在執行」的 DaVinci Resolve（Studio）。

用法：
    python3 davinci_import.py [--bin-parent AutoImport] <資料夾或檔案> [更多...]

每個傳入的資料夾，會在媒體池的 parent bin（預設 "AutoImport"）底下，
建立一個以資料夾名稱（通常是日期，如 2026-06-06）命名的 bin，
再把該資料夾的素材匯入那個 bin。

前提：
    - DaVinci Resolve **Studio** 正在執行（免費版不支援外部腳本）
    - 已開啟一個專案
    - 偏好設定 → 系統 → 一般 → External scripting using 設為 Local
"""
import os
import sys
import argparse

# macOS 預設安裝路徑；若使用者已設環境變數則沿用其值。
DEFAULT_LIB = ("/Applications/DaVinci Resolve/DaVinci Resolve.app/"
               "Contents/Libraries/Fusion/fusionscript.so")
DEFAULT_API = ("/Library/Application Support/Blackmagic Design/"
               "DaVinci Resolve/Developer/Scripting")


def get_resolve():
    os.environ.setdefault("RESOLVE_SCRIPT_LIB", DEFAULT_LIB)
    os.environ.setdefault("RESOLVE_SCRIPT_API", DEFAULT_API)
    module_dir = os.path.join(os.environ["RESOLVE_SCRIPT_API"], "Modules")
    if module_dir not in sys.path:
        sys.path.append(module_dir)
    try:
        import DaVinciResolveScript as bmd
    except ImportError:
        sys.stderr.write("找不到 DaVinciResolveScript 模組，"
                         "請確認 DaVinci Resolve 已正確安裝。\n")
        return None
    resolve = bmd.scriptapp("Resolve")
    if resolve is None:
        sys.stderr.write("無法連上 DaVinci Resolve，"
                         "請確認 Resolve 正在執行、且 External scripting 已設為 Local。\n")
    return resolve


def find_or_create_bin(media_pool, parent_folder, name):
    for sub in parent_folder.GetSubFolderList():
        if sub.GetName() == name:
            return sub
    return media_pool.AddSubFolder(parent_folder, name)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bin-parent", default="AutoImport",
                        help="媒體池中放置匯入素材的上層 bin 名稱")
    parser.add_argument("paths", nargs="+", help="要匯入的資料夾或檔案")
    args = parser.parse_args()

    resolve = get_resolve()
    if resolve is None:
        return 2

    project = resolve.GetProjectManager().GetCurrentProject()
    if project is None:
        sys.stderr.write("DaVinci Resolve 目前沒有開啟的專案。\n")
        return 3

    media_pool = project.GetMediaPool()
    media_storage = resolve.GetMediaStorage()
    root = media_pool.GetRootFolder()
    parent = find_or_create_bin(media_pool, root, args.bin_parent)

    total = 0
    for path in args.paths:
        path = os.path.abspath(path)
        if os.path.isdir(path):
            bin_name = os.path.basename(os.path.normpath(path))
            target = find_or_create_bin(media_pool, parent, bin_name)
        else:
            target = parent
        media_pool.SetCurrentFolder(target)
        items = media_storage.AddItemListToMediaPool([path]) or []
        total += len(items)

    # 匯完把當前資料夾移回根目錄，避免影響使用者後續操作。
    media_pool.SetCurrentFolder(root)
    print(f"已匯入 {total} 個項目到 DaVinci Resolve。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
