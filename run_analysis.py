"""
run_analysis.py - runs the whole project end to end.

  1. Downloads the Dunnhumby "The Complete Journey" grocery data
     (2,469 households, 1.47M purchases, 2017) from the public
     completejourney GitHub repository
  2. Saves it as CSVs in data/
  3. Runs the three SQL files with DuckDB (same SQL works in PostgreSQL)
  4. Saves result tables (CSV) and the three charts (PNG) next to this script
  5. Prints the headline numbers

Works in Google Colab: upload this file and the four .sql files, then run
    %run run_analysis.py
"""

import os
import subprocess
import sys
import urllib.request

for pkg in ["duckdb", "pyreadr"]:
    try:
        __import__(pkg)
    except ImportError:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", pkg])

import duckdb
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pyreadr

SOURCE = "https://raw.githubusercontent.com/bradleyboehmke/completejourney/master/data/"
FILES = {  # table name -> file in the source repo
    "transactions": "transactions.rds",
    "products": "products.rda",
    "campaigns": "campaigns.rda",
    "campaign_descriptions": "campaign_descriptions.rda",
}
os.makedirs("data", exist_ok=True)

# ---------------------------------------------------------------- 1-2. data
for table, fname in FILES.items():
    csv_path = f"data/{table}.csv"
    if os.path.exists(csv_path):
        continue
    raw_path = f"data/{fname}"
    print(f"Downloading {fname} ...")
    urllib.request.urlretrieve(SOURCE + fname, raw_path)
    frame = next(iter(pyreadr.read_r(raw_path).values()))
    # a few IDs in the source are stored as text in scientific notation
    # (e.g. "9e+05"); turn every *_id column into a plain whole number
    for col in [c for c in frame.columns if c.endswith("_id")]:
        frame[col] = pd.to_numeric(frame[col]).round().astype("Int64")
    frame.to_csv(csv_path, index=False)
    os.remove(raw_path)

con = duckdb.connect()
for table in FILES:
    con.execute(f"CREATE OR REPLACE TABLE {table} AS "
                f"SELECT * FROM read_csv_auto('data/{table}.csv')")
print("Loaded:", {t: con.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0] for t in FILES})


def run_sql(name):
    with open(f"{name}.sql") as f:
        result = con.execute(f.read()).df()
    result.to_csv(f"{name}_results.csv", index=False)
    return result


habit = run_sql("01_produce_habit_retention")
winback = run_sql("02_winback_timing")
lift = run_sql("03_campaign_true_lift")

# ---------------------------------------------------------------- 4. charts
INK, MUTED, GRID = "#1a1a19", "#52514e", "#e6e5e0"
BLUES = ["#9ec5f4", "#3987e5", "#184f95"]        # Low, Mid, High habit
BLUE, ORANGE = "#2a78d6", "#eb6834"
plt.rcParams.update({"font.family": "DejaVu Sans", "axes.edgecolor": GRID,
                     "axes.labelcolor": MUTED, "xtick.color": MUTED,
                     "ytick.color": MUTED, "axes.spines.top": False,
                     "axes.spines.right": False})


def headline(fig, title, sub):
    fig.text(0.06, 0.97, title, fontsize=14, fontweight="bold", color=INK, va="top")
    fig.text(0.06, 0.905, sub, fontsize=10, color=MUTED, va="top")


# Chart 1: produce habit vs lost regulars
bands = ["0. All households", "1. 4-7 weeks", "2. 8-10 weeks", "3. 11-13 weeks"]
band_labels = ["All households", "Shopped 4-7\nof 13 weeks",
               "Shopped 8-10\nof 13 weeks", "Shopped 11-13\nof 13 weeks"]
habits = ["1. Low", "2. Mid", "3. High"]
habit_labels = ["Low produce habit (<1 in 3 weeks)", "Mid", "High (2 in 3 weeks or more)"]
fig, ax = plt.subplots(figsize=(10, 5.4))
x, w = np.arange(len(bands)), 0.26
for i, h in enumerate(habits):
    vals = [habit[(habit.q1_visit_band == b) & (habit.produce_habit == h)]
            .lost_regular_pct.iloc[0] for b in bands]
    bars = ax.bar(x + (i - 1) * w, vals, w - 0.03, color=BLUES[i], label=habit_labels[i])
    for bar, v in zip(bars, vals):
        ax.text(bar.get_x() + bar.get_width() / 2, v + 0.5, f"{v:.0f}%",
                ha="center", fontsize=9, color=INK)
ax.set_xticks(x, band_labels)
ax.set_ylabel("% no longer a regular by Q4")
ax.yaxis.set_major_formatter(plt.FuncFormatter(lambda v, _: f"{v:.0f}%"))
ax.yaxis.grid(True, color=GRID); ax.set_axisbelow(True)
ax.legend(frameon=False, fontsize=9, loc="upper right")
low = habit[(habit.q1_visit_band == bands[0]) & (habit.produce_habit == "1. Low")].iloc[0]
high = habit[(habit.q1_visit_band == bands[0]) & (habit.produce_habit == "3. High")].iloc[0]
headline(fig, f"Rare produce buyers were {low.times_vs_high_habit:.1f}x as likely to drift away",
         "Households regular in Q1, grouped by how often their weekly shop included "
         "fresh produce. Lost = shopped <4 of 13 weeks in Q4.")
fig.subplots_adjust(top=0.82, left=0.08, right=0.98, bottom=0.14)
fig.savefig("01_produce_habit_retention.png", dpi=200, facecolor="white")
plt.close(fig)

# Chart 2: win-back timing
fig, ax = plt.subplots(figsize=(10, 5.4))
d = winback.days_without_order
ax.plot(d, winback.pct_back_on_own_next_4_weeks, color=BLUE, lw=2, marker="o", ms=6,
        label="...who come back on their own within the next 4 weeks")
ax.plot(d, winback.pct_still_gone_after_120_days, color=ORANGE, lw=2, marker="o", ms=6,
        label="...who are still gone 120 days after their last order")
for col, color in [("pct_back_on_own_next_4_weeks", BLUE), ("pct_still_gone_after_120_days", ORANGE)]:
    for day in [28, 56, 84]:
        v = winback.loc[winback.days_without_order == day, col].iloc[0]
        ax.annotate(f"{v:.0f}%", (day, v), textcoords="offset points",
                    xytext=(-14 if day == 56 else 0, 9), ha="center", fontsize=9, color=INK)
ax.axvline(56, color=MUTED, lw=1, ls="--")
ax.text(57, 50, "Suggested win-back\ntrigger: day 56", fontsize=9, color=MUTED, va="center")
ax.set_xticks(d)
ax.set_xlabel("Days since the customer's last order")
ax.set_ylabel("% of customers still gone at that point...")
ax.yaxis.set_major_formatter(plt.FuncFormatter(lambda v, _: f"{v:.0f}%"))
ax.set_ylim(0, 100); ax.yaxis.grid(True, color=GRID); ax.set_axisbelow(True)
ax.legend(frameon=False, fontsize=9, loc="upper right", bbox_to_anchor=(1, 0.93))
w28 = winback.loc[winback.days_without_order == 28].iloc[0]
headline(fig, f"At day 28, {w28.pct_back_on_own_next_4_weeks:.0f}% of lapsed regulars return within 4 weeks with no offer",
         "Lapse = 28+ days without an order, regular households only. "
         "Offers sent too early mostly pay people who were returning anyway.")
fig.subplots_adjust(top=0.82, left=0.08, right=0.98, bottom=0.12)
fig.savefig("02_winback_timing.png", dpi=200, facecolor="white")
plt.close(fig)

# Chart 3: naive vs true campaign lift
fig, ax = plt.subplots(figsize=(10, 5.4))
labels = [f"Campaign {r.campaign_id}\n{pd.Timestamp(r.start_date):%b} - "
          f"{pd.Timestamp(r.end_date):%b %Y}" for r in lift.itertuples()]
y = np.arange(len(lift))
ax.barh(y + 0.18, lift.naive_lift_pct, 0.32, color="#b9b8b2", label="Naive: targeted vs non-targeted spend")
ax.barh(y - 0.18, lift.true_lift_pct, 0.32, color=BLUE, label="True lift (change vs before, both groups)")
ax.errorbar(lift.true_lift_pct, y - 0.18, xerr=[lift.true_lift_pct - lift.ci_low_pct,
            lift.ci_high_pct - lift.true_lift_pct], fmt="none", ecolor=INK, capsize=3, lw=1)
for yi, r in zip(y, lift.itertuples()):
    ax.text(r.naive_lift_pct + 3, yi + 0.18, f"+{r.naive_lift_pct:.0f}%", va="center", fontsize=9, color=INK)
    ax.text(max(r.ci_high_pct, 0) + 3, yi - 0.18,
            f"{r.true_lift_pct:+.1f}%  (95% CI {r.ci_low_pct:+.1f} to {r.ci_high_pct:+.1f})",
            va="center", fontsize=9, color=INK)
ax.axvline(0, color=MUTED, lw=1)
ax.set_yticks(y, labels); ax.invert_yaxis()
ax.set_xlabel("Spend lift during the campaign")
ax.xaxis.set_major_formatter(plt.FuncFormatter(lambda v, _: f"{v:+.0f}%"))
ax.set_xlim(min(-10, lift.ci_low_pct.min() - 5), lift.naive_lift_pct.max() * 1.2)
ax.xaxis.grid(True, color=GRID); ax.set_axisbelow(True)
ax.legend(frameon=False, fontsize=9, loc="upper right")
ratio = (lift.targeted_spend_before / lift.other_spend_before).mean()
headline(fig, f"Campaigns looked like +{lift.naive_lift_pct.min():.0f} to +{lift.naive_lift_pct.max():.0f}% "
         f"winners. Real lift: {lift.true_lift_pct.min():+.0f}% to {lift.true_lift_pct.max():+.0f}%",
         f"The ~1,100 targeted households already spent {ratio:.1f}x more than everyone else "
         "before each campaign started.")
fig.subplots_adjust(top=0.82, left=0.15, right=0.98, bottom=0.12)
fig.savefig("03_campaign_true_lift.png", dpi=200, facecolor="white")
plt.close(fig)

# ---------------------------------------------------------------- 5. summary
print("\n" + "=" * 72 + "\nHEADLINE NUMBERS\n" + "=" * 72)
print(f"1. Produce habit: {low.lost_regular_pct}% of low-produce households stopped being "
      f"regulars vs {high.lost_regular_pct}% of high-produce ({low.times_vs_high_habit}x), "
      f"n = {int(habit[habit.q1_visit_band == bands[0]].households.sum()):,} households")
print("   Same comparison inside each visit-frequency band:")
for b in bands[1:]:
    lo_ = habit[(habit.q1_visit_band == b) & (habit.produce_habit == "1. Low")].iloc[0]
    hi_ = habit[(habit.q1_visit_band == b) & (habit.produce_habit == "3. High")].iloc[0]
    print(f"     {b[3:]:<12} low {lo_.lost_regular_pct}% vs high {hi_.lost_regular_pct}%")
print("2. Win-back timing:")
print(winback.to_string(index=False))
print("3. Campaign lift:")
print(lift[["campaign_id", "targeted_households", "targeted_spend_before", "other_spend_before",
            "naive_lift_pct", "true_lift_pct", "ci_low_pct", "ci_high_pct"]].to_string(index=False))
print("\nSaved the 3 charts (.png) and 3 result tables (_results.csv)")
