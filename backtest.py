"""Daily swing-trading backtester.

Signals are computed on a bar's close and filled at the NEXT bar's open, so no
strategy can trade on information it would not have had. Long-only, all-in /
all-out, with a per-side cost to cover commission and slippage.

Usage:
    python backtest.py data/FCEL_daily.csv
"""
import sys

import numpy as np
import pandas as pd

COST = 0.002  # 0.20% per side (slippage on a volatile small cap; commission is $0)
SPLIT_DATE = "2025-01-01"  # results are also reported before / after this date


# --------------------------------------------------------------------------- #
# Indicators
# --------------------------------------------------------------------------- #
def sma(s, n):
    return s.rolling(n).mean()


def ema(s, n):
    return s.ewm(span=n, adjust=False).mean()


def rsi(s, n):
    delta = s.diff()
    up = delta.clip(lower=0).ewm(alpha=1 / n, adjust=False).mean()
    down = (-delta.clip(upper=0)).ewm(alpha=1 / n, adjust=False).mean()
    return 100 - 100 / (1 + up / down)


def atr(df, n=14):
    prev = df.close.shift()
    tr = pd.concat([df.high - df.low, (df.high - prev).abs(), (df.low - prev).abs()], axis=1).max(axis=1)
    return tr.ewm(alpha=1 / n, adjust=False).mean()


# --------------------------------------------------------------------------- #
# Strategies: each returns (entry, exit) boolean Series evaluated at the close.
# --------------------------------------------------------------------------- #
def ma_cross(fast, slow, kind=sma):
    def f(df):
        a, b = kind(df.close, fast), kind(df.close, slow)
        return (a > b) & (a.shift() <= b.shift()), (a < b) & (a.shift() >= b.shift())
    return f


def macd_cross(df):
    line = ema(df.close, 12) - ema(df.close, 26)
    sig = ema(line, 9)
    return (line > sig) & (line.shift() <= sig.shift()), (line < sig) & (line.shift() >= sig.shift())


def rsi_reversion(n, lo, hi):
    def f(df):
        r = rsi(df.close, n)
        return r < lo, r > hi
    return f


def bollinger_reversion(n=20, k=2.0):
    def f(df):
        mid = sma(df.close, n)
        lower = mid - k * df.close.rolling(n).std()
        return df.close < lower, df.close > mid
    return f


def donchian_breakout(entry_n, exit_n):
    def f(df):
        hi = df.high.rolling(entry_n).max().shift()
        lo = df.low.rolling(exit_n).min().shift()
        return df.close > hi, df.close < lo
    return f


def trend_pullback(df):
    """Buy short-term dips (RSI3 < 20) only while price is above its 50-day EMA."""
    trend = df.close > ema(df.close, 50)
    r3 = rsi(df.close, 3)
    return trend & (r3 < 20), (r3 > 70) | ~trend


def volume_breakout(df):
    """Close at a 20-day high on 2x average volume; exit on a close below the 10-day EMA."""
    hi = df.high.rolling(20).max().shift()
    vol_ok = df.volume > 2 * df.volume.rolling(20).mean().shift()
    return (df.close > hi) & vol_ok, df.close < ema(df.close, 10)


def buy_and_hold(df):
    entry = pd.Series(False, index=df.index)
    entry.iloc[0] = True
    return entry, pd.Series(False, index=df.index)


# --------------------------------------------------------------------------- #
# Engine
# --------------------------------------------------------------------------- #
def run(df, strategy, atr_stop=None, max_hold=None):
    """Simulate one strategy. Returns (equity Series, list of trade returns)."""
    entry, exit_ = strategy(df)
    entry, exit_ = entry.fillna(False).values, exit_.fillna(False).values
    o, h, l, c = df.open.values, df.high.values, df.low.values, df.close.values
    a = atr(df).values

    equity = np.empty(len(df))
    cash, shares = 1.0, 0.0
    in_pos, entry_px, stop, held = False, 0.0, -np.inf, 0
    trades = []
    pending_entry = pending_exit = False

    for i in range(len(df)):
        # 1) fill orders decided at yesterday's close, at today's open
        if pending_exit and in_pos:
            px = o[i] * (1 - COST)
            cash, trades = shares * px, trades + [px / entry_px - 1]
            in_pos, shares = False, 0.0
        elif pending_entry and not in_pos:
            entry_px = o[i] * (1 + COST)
            shares, cash, in_pos, held = cash / entry_px, 0.0, True, 0
            stop = o[i] - atr_stop * a[i - 1] if atr_stop else -np.inf
        pending_entry = pending_exit = False

        # 2) intraday protective stop (gap-down fills at the open, not the stop)
        if in_pos and l[i] <= stop:
            px = min(o[i], stop) * (1 - COST)
            cash, trades = shares * px, trades + [px / entry_px - 1]
            in_pos, shares = False, 0.0

        # 3) end-of-day bookkeeping and signals for tomorrow
        if in_pos:
            held += 1
            if atr_stop:  # trailing ATR stop only ratchets up
                stop = max(stop, c[i] - atr_stop * a[i])
            if exit_[i] or (max_hold and held >= max_hold):
                pending_exit = True
        elif entry[i]:
            pending_entry = True
        equity[i] = cash + shares * c[i]

    if in_pos:  # mark open trade to market at the final close
        trades.append(c[-1] * (1 - COST) / entry_px - 1)
    return pd.Series(equity, index=df.index), trades


def stats(equity, trades):
    rets = equity.pct_change().fillna(0)
    years = (equity.index[-1] - equity.index[0]).days / 365.25
    total = equity.iloc[-1] / equity.iloc[0] - 1
    dd = (equity / equity.cummax() - 1).min()
    t = np.array(trades)
    wins, losses = t[t > 0].sum(), -t[t < 0].sum()
    return {
        "total_%": 100 * total,
        "cagr_%": 100 * ((1 + total) ** (1 / years) - 1) if total > -1 else -100,
        "max_dd_%": 100 * dd,
        "sharpe": np.sqrt(252) * rets.mean() / rets.std() if rets.std() > 0 else 0,
        "trades": len(t),
        "win_%": 100 * (t > 0).mean() if len(t) else 0,
        "avg_trade_%": 100 * t.mean() if len(t) else 0,
        "profit_factor": wins / losses if losses > 0 else np.inf,
        "exposure_%": 100 * (rets != 0).mean(),
    }


STRATEGIES = {
    "Buy & hold": (buy_and_hold, {}),
    "SMA 10/30 cross": (ma_cross(10, 30), {}),
    "SMA 20/50 cross": (ma_cross(20, 50), {}),
    "EMA 9/21 cross": (ma_cross(9, 21, ema), {}),
    "EMA 9/21 + 2.5 ATR trail": (ma_cross(9, 21, ema), {"atr_stop": 2.5}),
    "MACD 12/26/9": (macd_cross, {}),
    "RSI14 <30 -> >70": (rsi_reversion(14, 30, 70), {}),
    "RSI14 <30 -> >50": (rsi_reversion(14, 30, 50), {}),
    "RSI2 <10 -> >70 (max 10d)": (rsi_reversion(2, 10, 70), {"max_hold": 10}),
    "Bollinger 20/2 -> mid": (bollinger_reversion(), {}),
    "Bollinger 20/2 + 3 ATR stop": (bollinger_reversion(), {"atr_stop": 3}),
    "Donchian 20/10 breakout": (donchian_breakout(20, 10), {}),
    "Donchian 20/10 + 2 ATR trail": (donchian_breakout(20, 10), {"atr_stop": 2}),
    "Turtle 55/20 breakout": (donchian_breakout(55, 20), {}),
    "Trend pullback (EMA50+RSI3)": (trend_pullback, {}),
    "Volume breakout (20d hi, 2x vol)": (volume_breakout, {}),
    "Vol breakout + 2 ATR trail": (volume_breakout, {"atr_stop": 2}),
}


def table(df):
    rows = {}
    for name, (strat, kw) in STRATEGIES.items():
        eq, tr = run(df, strat, **kw)
        rows[name] = stats(eq, tr)
    return pd.DataFrame(rows).T


def main(path):
    df = pd.read_csv(path, parse_dates=["date"]).set_index("date")
    pd.set_option("display.width", 200, "display.float_format", "{:,.2f}".format)
    print(f"{path}: {len(df)} bars, {df.index[0].date()} -> {df.index[-1].date()}, cost {COST:.2%}/side\n")

    print("=== Full period ===")
    full = table(df)
    print(full.sort_values("total_%", ascending=False).to_string(), "\n")

    # Indicators warm up on the slice itself, so each period stands alone.
    for label, part in (("Before " + SPLIT_DATE, df[:SPLIT_DATE]), ("From " + SPLIT_DATE, df[SPLIT_DATE:])):
        print(f"=== {label} ({part.index[0].date()} -> {part.index[-1].date()}) ===")
        print(table(part)[["total_%", "max_dd_%", "sharpe", "trades", "win_%", "profit_factor"]]
              .sort_values("total_%", ascending=False).to_string(), "\n")

    # Robustness: is a good result a lucky parameter or a broad plateau?
    print("=== Robustness: EMA fast/slow cross, total return % (full period) ===")
    grid = pd.DataFrame({s: {f: stats(*run(df, ma_cross(f, s, ema)))["total_%"] for f in (5, 9, 13, 20)}
                         for s in (21, 30, 50, 100)})
    print(grid.rename_axis("fast \\ slow").to_string(), "\n")

    print("=== Robustness: Donchian entry/exit, total return % (full period) ===")
    grid = pd.DataFrame({x: {e: stats(*run(df, donchian_breakout(e, x)))["total_%"] for e in (10, 20, 40, 55)}
                         for x in (5, 10, 20)})
    print(grid.rename_axis("entry \\ exit").to_string())


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "data/FCEL_daily.csv")
