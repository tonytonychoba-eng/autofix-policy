"""訓練股票「漲跌方向」分類模型。

用法範例：
  # 在本沙箱（無網路）用模擬資料把流程跑通：
  python train.py --source synthetic

  # 在本機（有網路）用真實資料：
  python train.py --source yfinance --ticker AAPL --period 5y --horizon 1 --model gboost

  # 用自己的 CSV：
  python train.py --source csv --path mydata.csv

重要觀念：
  - 採時間序列切分（不可隨機洗牌）：用「過去」訓練、用「未來」測試。
  - 一定要和 baseline（總是猜多數類別）比較，否則看似 55% 準確率可能毫無意義。
  - 本程式僅供技術學習，非投資建議。
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import GradientBoostingClassifier, RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (accuracy_score, classification_report,
                             confusion_matrix, roc_auc_score)
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

from data import load_data
from features import build_dataset


def build_model(name: str) -> Pipeline:
    """回傳含標準化前處理的模型 pipeline。"""
    name = name.lower()
    if name == "logreg":
        clf = LogisticRegression(max_iter=1000, C=1.0)
    elif name == "rf":
        clf = RandomForestClassifier(
            n_estimators=300, max_depth=6, min_samples_leaf=20,
            random_state=0, n_jobs=-1,
        )
    elif name == "gboost":
        clf = GradientBoostingClassifier(
            n_estimators=200, max_depth=3, learning_rate=0.05, random_state=0,
        )
    else:
        raise ValueError(f"未知模型: {name}（可選 logreg / rf / gboost）")
    return Pipeline([("scaler", StandardScaler()), ("clf", clf)])


def time_split(X: pd.DataFrame, y: pd.Series, test_size: float = 0.2):
    """依時間先後切分：前段訓練、後段測試（不洗牌）。"""
    n = len(X)
    cut = int(n * (1.0 - test_size))
    return (X.iloc[:cut], X.iloc[cut:], y.iloc[:cut], y.iloc[cut:])


def naive_backtest(close: pd.Series, y_true: pd.Series, y_pred: np.ndarray,
                   index: pd.Index) -> dict:
    """極簡策略回測：模型預測漲(1)就持有當期報酬，預測跌(0)就空手。

    這是教學用的玩具回測，未計交易成本/滑價，切勿據此實盤。
    """
    fwd_ret = close.pct_change().shift(-1).reindex(index).fillna(0.0).to_numpy()
    strat_ret = fwd_ret * y_pred
    bh = float(np.prod(1.0 + fwd_ret) - 1.0)          # 買進持有
    strat = float(np.prod(1.0 + strat_ret) - 1.0)     # 策略
    return {"buy_hold_return": bh, "strategy_return": strat}


def main():
    ap = argparse.ArgumentParser(description="訓練股票漲跌方向分類模型")
    ap.add_argument("--source", default="synthetic",
                    choices=["synthetic", "yfinance", "csv"])
    ap.add_argument("--ticker", default="AAPL")
    ap.add_argument("--period", default="5y")
    ap.add_argument("--start", default=None)
    ap.add_argument("--end", default=None)
    ap.add_argument("--path", default=None, help="CSV 路徑（source=csv 時）")
    ap.add_argument("--horizon", type=int, default=1, help="預測未來幾天的方向")
    ap.add_argument("--model", default="gboost",
                    choices=["logreg", "rf", "gboost"])
    ap.add_argument("--test-size", type=float, default=0.2)
    ap.add_argument("--out", default="model.joblib")
    args = ap.parse_args()

    print(f"[1/5] 載入資料 source={args.source} ...")
    df = load_data(
        source=args.source, ticker=args.ticker, period=args.period,
        start=args.start, end=args.end, path=args.path,
    )
    print(f"      取得 {len(df)} 筆，日期 {df.index.min().date()} ~ {df.index.max().date()}")

    print(f"[2/5] 建立特徵與標籤 (horizon={args.horizon}d) ...")
    X, y = build_dataset(df, horizon=args.horizon)
    print(f"      樣本數 {len(X)}，特徵數 {X.shape[1]}，"
          f"漲跌比例 up={y.mean():.3f}")

    print(f"[3/5] 時間序列切分 (test_size={args.test_size}) ...")
    X_tr, X_te, y_tr, y_te = time_split(X, y, args.test_size)
    print(f"      訓練 {len(X_tr)} 筆，測試 {len(X_te)} 筆")

    print(f"[4/5] 訓練模型 model={args.model} ...")
    model = build_model(args.model)
    model.fit(X_tr, y_tr)

    print("[5/5] 評估：")
    y_pred = model.predict(X_te)
    try:
        proba = model.predict_proba(X_te)[:, 1]
        auc = roc_auc_score(y_te, proba)
    except Exception:
        auc = float("nan")

    acc = accuracy_score(y_te, y_pred)
    # Baseline：總是猜訓練集的多數類別。
    majority = int(round(y_tr.mean()))
    base_acc = accuracy_score(y_te, np.full(len(y_te), majority))

    print(f"      準確率 Accuracy : {acc:.4f}")
    print(f"      多數類 Baseline : {base_acc:.4f}  (總是猜 {majority})")
    print(f"      勝過 baseline   : {acc - base_acc:+.4f}")
    print(f"      ROC AUC         : {auc:.4f}")
    print("      混淆矩陣 [實際 x 預測]:")
    print(pd.DataFrame(confusion_matrix(y_te, y_pred),
                       index=["真跌", "真漲"], columns=["猜跌", "猜漲"]))
    print(classification_report(y_te, y_pred, target_names=["跌", "漲"],
                                zero_division=0))

    bt = naive_backtest(df["Close"], y_te, y_pred, X_te.index)
    print(f"      [玩具回測] 買進持有: {bt['buy_hold_return']:+.2%}  "
          f"策略: {bt['strategy_return']:+.2%}  (未計成本，僅供參考)")

    # 存模型與中繼資料。
    out_path = Path(args.out)
    joblib.dump({"model": model, "features": list(X.columns),
                 "horizon": args.horizon}, out_path)
    meta = {
        "source": args.source, "ticker": args.ticker, "model": args.model,
        "horizon": args.horizon, "n_samples": int(len(X)),
        "accuracy": float(acc), "baseline_accuracy": float(base_acc),
        "roc_auc": float(auc), **bt,
    }
    out_path.with_suffix(".meta.json").write_text(
        json.dumps(meta, ensure_ascii=False, indent=2))
    print(f"\n模型已存至 {out_path}，中繼資料 {out_path.with_suffix('.meta.json')}")
    print("提醒：本模型僅供技術學習，市場無法被可靠預測，請勿用於實際投資決策。")


if __name__ == "__main__":
    main()
