"""用訓練好的模型對最新資料做漲跌方向預測。

用法：
  python predict.py --model model.joblib --source yfinance --ticker AAPL
  python predict.py --model model.joblib --source synthetic
"""

from __future__ import annotations

import argparse

import joblib

from data import load_data
from features import make_features


def main():
    ap = argparse.ArgumentParser(description="用模型預測下一期漲跌方向")
    ap.add_argument("--model", default="model.joblib")
    ap.add_argument("--source", default="synthetic",
                    choices=["synthetic", "yfinance", "csv"])
    ap.add_argument("--ticker", default="AAPL")
    ap.add_argument("--period", default="1y")
    ap.add_argument("--path", default=None)
    args = ap.parse_args()

    bundle = joblib.load(args.model)
    model, feat_cols, horizon = bundle["model"], bundle["features"], bundle["horizon"]

    df = load_data(source=args.source, ticker=args.ticker,
                   period=args.period, path=args.path)
    X = make_features(df).dropna()
    if X.empty:
        raise RuntimeError("資料不足以產生特徵。")

    latest = X[feat_cols].iloc[[-1]]
    pred = int(model.predict(latest)[0])
    try:
        proba = float(model.predict_proba(latest)[0, 1])
    except Exception:
        proba = float("nan")

    asof = X.index[-1].date()
    arrow = "📈 漲" if pred == 1 else "📉 跌"
    print(f"基準日 {asof}（最新一筆資料）")
    print(f"預測未來 {horizon} 天方向：{arrow}  (上漲機率 {proba:.1%})")
    print("提醒：僅供技術學習，非投資建議。")


if __name__ == "__main__":
    main()
