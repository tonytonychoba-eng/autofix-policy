"""特徵工程與標籤建立。

重點：嚴格避免「未來函數」(look-ahead bias)
  - 所有特徵只使用「到當天 t 為止」的資訊。
  - 標籤 y 使用「未來 horizon 天」的報酬方向，因此最後 horizon 筆沒有標籤、需丟棄。
"""

from __future__ import annotations

import numpy as np
import pandas as pd


def _rsi(close: pd.Series, window: int = 14) -> pd.Series:
    """相對強弱指標 RSI。"""
    delta = close.diff()
    gain = delta.clip(lower=0.0)
    loss = -delta.clip(upper=0.0)
    avg_gain = gain.rolling(window).mean()
    avg_loss = loss.rolling(window).mean()
    rs = avg_gain / avg_loss.replace(0.0, np.nan)
    rsi = 100.0 - (100.0 / (1.0 + rs))
    return rsi.fillna(50.0)


def make_features(df: pd.DataFrame) -> pd.DataFrame:
    """從 OHLCV 產生技術指標特徵。回傳只含特徵欄位的 DataFrame。"""
    out = pd.DataFrame(index=df.index)
    close = df["Close"]
    ret1 = np.log(close / close.shift(1))  # 當日對數報酬

    # 1) 多期落後報酬（動量）。
    for lag in (1, 2, 3, 5, 10):
        out[f"ret_lag{lag}"] = ret1.shift(lag - 1) if lag == 1 else ret1.rolling(lag).sum()

    # 2) 收盤相對移動平均（趨勢偏離）。
    for w in (5, 10, 20, 50):
        sma = close.rolling(w).mean()
        out[f"close_sma{w}"] = close / sma - 1.0

    # 3) 滾動波動度。
    for w in (5, 10, 20):
        out[f"vol{w}"] = ret1.rolling(w).std()

    # 4) RSI。
    out["rsi14"] = _rsi(close, 14)

    # 5) 當日高低區間（相對 close）。
    out["hl_range"] = (df["High"] - df["Low"]) / close

    # 6) 成交量相對其移動平均。
    vol_sma = df["Volume"].rolling(20).mean()
    out["vol_ratio"] = df["Volume"] / vol_sma - 1.0

    # 7) 收盤在當日區間中的位置（0=最低, 1=最高）。
    rng = (df["High"] - df["Low"]).replace(0.0, np.nan)
    out["close_pos"] = ((close - df["Low"]) / rng).fillna(0.5)

    return out


def make_label(df: pd.DataFrame, horizon: int = 1) -> pd.Series:
    """標籤：未來 horizon 天後的收盤是否高於今天收盤（1=漲, 0=跌/平）。"""
    future = df["Close"].shift(-horizon)
    y = (future > df["Close"]).astype(int)
    y.name = f"up_{horizon}d"
    return y


def build_dataset(df: pd.DataFrame, horizon: int = 1):
    """組出對齊好的 (X, y)，並丟掉含 NaN 的列與最後 horizon 筆無標籤資料。"""
    X = make_features(df)
    y = make_label(df, horizon=horizon)
    data = X.copy()
    data["__y__"] = y
    # 丟掉特徵暖機期的 NaN，以及尾端沒有未來值的列。
    data = data.iloc[:-horizon] if horizon > 0 else data
    data = data.dropna()
    y_out = data.pop("__y__").astype(int)
    return data, y_out
