# 股票漲跌方向分類模型（教學範例）

用技術指標特徵 + scikit-learn 分類器，預測某檔股票**未來 N 天的收盤是漲還是跌**。

> ⚠️ **重要聲明**：本專案僅供機器學習技術學習與研究。金融市場接近效率市場，方向預測本質上極其困難，回測表現好**不代表**實盤能獲利。請**勿**將本模型用於任何實際投資決策，作者不承擔任何投資損失。

## 專案結構

```
stock-model/
├── data.py          # 資料載入（yfinance / csv / synthetic 三種可插拔來源）
├── features.py      # 技術指標特徵 + 標籤（嚴格避免未來函數）
├── train.py         # 訓練、時間序列評估、玩具回測、存模型
├── predict.py       # 載入模型對最新資料預測下一期方向
├── requirements.txt
└── README.md
```

## 安裝

```bash
pip install -r requirements.txt
```

## 快速開始

```bash
# 1) 無網路也能跑：用模擬資料把整條流程跑通
python train.py --source synthetic --model logreg

# 2) 真實資料（需對外網路，建議在本機執行）
python train.py --source yfinance --ticker AAPL --period 5y --horizon 1 --model gboost

# 3) 用自己的 CSV（需含 Date 與 Open/High/Low/Close/Volume 欄）
python train.py --source csv --path your_data.csv

# 訓練後用最新資料預測下一期方向
python predict.py --model model.joblib --source yfinance --ticker AAPL
```

> 注意：在受限的雲端沙箱中，Yahoo Finance / Stooq 等資料站可能被網路政策擋掉（回 403）。
> 此時請改用 `--source csv` 或 `--source synthetic`，或在本機網路無限制的環境執行 `yfinance`。

## 主要參數（train.py）

| 參數 | 說明 | 預設 |
|------|------|------|
| `--source` | 資料來源 `synthetic` / `yfinance` / `csv` | `synthetic` |
| `--ticker` | 股票代碼（yfinance） | `AAPL` |
| `--period` | 抓取期間，如 `5y`、`max` | `5y` |
| `--horizon` | 預測未來幾天的方向 | `1` |
| `--model` | `logreg` / `rf` / `gboost` | `gboost` |
| `--test-size` | 測試集比例（取時間序列尾段） | `0.2` |

## 特徵（features.py）

- 多期落後對數報酬（動量）：1/2/3/5/10 日
- 收盤相對移動平均偏離：SMA 5/10/20/50
- 滾動波動度：5/10/20 日
- RSI(14)
- 當日高低區間、收盤在區間中的位置
- 成交量相對 20 日均量

## 方法論重點

1. **時間序列切分**：用過去訓練、用未來測試，**絕不隨機洗牌**，避免資訊洩漏。
2. **避免未來函數**：特徵只用到當天為止的資料；標籤用未來報酬，並丟棄尾端無標籤列。
3. **一定要比 baseline**：和「總是猜多數類別」比較。股票漲跌約各半，看到 ~52% 準確率
   很可能只是猜多數，沒有實質預測力。請看 `勝過 baseline` 與 `ROC AUC`。
4. **玩具回測**：附一個極簡策略回測（未計交易成本/滑價），僅供直覺參考，**不可當實盤依據**。

## 下一步可以怎麼延伸

- 加入更多特徵（總經指標、其他標的的相關性、新聞情緒等）。
- 改用 walk-forward / `TimeSeriesSplit` 做更嚴謹的滾動驗證與超參數搜尋。
- 加入交易成本、停損、部位控管後再回測。
- 進階：改成 LSTM / Temporal CNN 等時間序列深度模型。
