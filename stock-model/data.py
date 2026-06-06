"""資料載入模組（可插拔資料來源）。

支援三種來源：
  - yfinance : 從 Yahoo Finance 線上抓取（需對外網路；在受限沙箱會失敗）。
  - csv      : 讀取本機 CSV（欄位需含 Open/High/Low/Close/Volume）。
  - synthetic: 產生模擬股價，讓整條流程在無網路環境也能跑通與測試。

所有來源都回傳統一格式的 DataFrame：
  index = DatetimeIndex（依日期排序）
  columns = ['Open', 'High', 'Low', 'Close', 'Volume']
"""

from __future__ import annotations

import numpy as np
import pandas as pd

OHLCV = ["Open", "High", "Low", "Close", "Volume"]


def _normalize(df: pd.DataFrame) -> pd.DataFrame:
    """把任意來源的資料整理成統一的 OHLCV 格式。"""
    # yfinance 在多檔下載時會回傳 MultiIndex 欄位，這裡攤平成單層。
    if isinstance(df.columns, pd.MultiIndex):
        df = df.copy()
        df.columns = [c[0] for c in df.columns]

    # 欄位名稱大小寫正規化（adj close / close 等）。
    rename = {}
    for col in df.columns:
        key = str(col).strip().lower().replace(" ", "_")
        mapping = {
            "open": "Open",
            "high": "High",
            "low": "Low",
            "close": "Close",
            "adj_close": "Close",
            "adjclose": "Close",
            "volume": "Volume",
        }
        if key in mapping:
            rename[col] = mapping[key]
    df = df.rename(columns=rename)

    missing = [c for c in OHLCV if c not in df.columns]
    if missing:
        raise ValueError(f"資料缺少必要欄位: {missing}；實際欄位: {list(df.columns)}")

    df = df[OHLCV].copy()
    df.index = pd.to_datetime(df.index)
    df = df[~df.index.duplicated(keep="last")].sort_index()
    df = df.apply(pd.to_numeric, errors="coerce").dropna()
    return df


def load_yfinance(ticker: str, start: str | None = None, end: str | None = None,
                  period: str = "5y", interval: str = "1d") -> pd.DataFrame:
    """從 Yahoo Finance 下載歷史資料（需對外網路）。"""
    import yfinance as yf

    kwargs = dict(interval=interval, auto_adjust=True, progress=False)
    if start:
        df = yf.download(ticker, start=start, end=end, **kwargs)
    else:
        df = yf.download(ticker, period=period, **kwargs)
    if df is None or len(df) == 0:
        raise RuntimeError(
            f"yfinance 未取得 {ticker} 的資料。可能是網路受限或代碼錯誤。"
        )
    return _normalize(df)


def load_csv(path: str) -> pd.DataFrame:
    """讀取本機 CSV。需含 Date 欄（或第一欄為日期）與 OHLCV 欄位。"""
    df = pd.read_csv(path)
    date_col = None
    for cand in ["Date", "date", "Datetime", "datetime", "timestamp"]:
        if cand in df.columns:
            date_col = cand
            break
    if date_col is None:
        date_col = df.columns[0]
    df = df.set_index(date_col)
    return _normalize(df)


def load_synthetic(n: int = 1500, seed: int = 42, start: str = "2018-01-02") -> pd.DataFrame:
    """產生模擬日線股價（含輕微可學習的動量訊號），供無網路測試用。

    用帶有溫和自相關（動量）的幾何布朗運動產生報酬，再組出 OHLCV。
    這只是為了把流程跑通，不代表任何真實市場行為。
    """
    rng = np.random.default_rng(seed)

    # 帶動量的日報酬：今天的漂移會受昨天報酬影響（AR(1)）。
    mu = 0.0003          # 每日平均漂移
    sigma = 0.012        # 每日波動
    phi = 0.10           # 動量係數
    rets = np.zeros(n)
    prev = 0.0
    for t in range(n):
        shock = rng.normal(0, sigma)
        r = mu + phi * prev + shock
        rets[t] = r
        prev = r

    close = 100.0 * np.exp(np.cumsum(rets))
    # 由 close 推回合理的 OHLV。
    daily_range = np.abs(rng.normal(0, 0.008, n)) * close
    open_ = close / np.exp(rets)  # 前一日 close 附近
    high = np.maximum(open_, close) + daily_range * rng.uniform(0.2, 1.0, n)
    low = np.minimum(open_, close) - daily_range * rng.uniform(0.2, 1.0, n)
    volume = rng.integers(1_000_000, 5_000_000, n).astype(float)
    # 波動大時量也大一點。
    volume *= 1.0 + 3.0 * np.abs(rets) / sigma

    idx = pd.bdate_range(start=start, periods=n)
    df = pd.DataFrame(
        {"Open": open_, "High": high, "Low": low, "Close": close, "Volume": volume},
        index=idx,
    )
    return _normalize(df)


def load_data(source: str = "synthetic", **kwargs) -> pd.DataFrame:
    """統一入口。source ∈ {'yfinance', 'csv', 'synthetic'}。"""
    source = source.lower()
    if source == "yfinance":
        return load_yfinance(
            ticker=kwargs.get("ticker", "AAPL"),
            start=kwargs.get("start"),
            end=kwargs.get("end"),
            period=kwargs.get("period", "5y"),
            interval=kwargs.get("interval", "1d"),
        )
    if source == "csv":
        return load_csv(kwargs["path"])
    if source == "synthetic":
        return load_synthetic(
            n=kwargs.get("n", 1500),
            seed=kwargs.get("seed", 42),
        )
    raise ValueError(f"未知的資料來源: {source}")
