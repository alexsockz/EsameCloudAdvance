#!/usr/bin/env python3
"""Compare several HPCC output files (hpccoutf.txt) side by side.

Usage:
    python plot_hpcc.py                       # uses the default 3 files in cwd
    python plot_hpcc.py single.txt multi.txt dist.txt -l Single "Multi-container" Distributed
    python plot_hpcc.py a.txt b.txt -o out_dir --show

Every file is parsed from (a) the key=value "Summary section" and (b) the
"WR..." lines of HPL (one per problem size N).  One PNG per panel is saved,
plus a combined overview figure and a CSV with all the extracted metrics.
"""
import argparse
import csv
import os
import re
import sys

import matplotlib.pyplot as plt
import numpy as np

DEFAULTS = [
    ("hpccoutf-single.txt", "Single container"),
    ("hpccoutf-multi-container.txt", "Multi-container"),
    ("hpccoutf-distributed.txt", "Distributed"),
]
COLORS = ["#2a9d8f", "#e9c46a", "#e76f51", "#457b9d", "#8d6a9f", "#6c757d"]


# --------------------------------------------------------------------------- parsing
def parse_hpcc(path):
    """Return dict with 'summary' (key->float/str) and 'hpl' ({N: (time, gflops)})."""
    with open(path, errors="replace") as fh:
        text = fh.read()

    summary = {}
    m = re.search(r"Begin of Summary section\.(.*?)End of Summary section\.", text, re.S)
    if not m:
        sys.exit(f"[error] no Summary section found in {path} (run incomplete?)")
    for line in m.group(1).splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            try:
                summary[k.strip()] = float(v)
            except ValueError:
                summary[k.strip()] = v.strip()

    # HPL result lines:  WR11C2R4  N  NB  P  Q  Time  Gflops
    hpl = {}
    for line in text.splitlines():
        if line.startswith("WR"):
            t = line.split()
            hpl[int(t[1])] = (float(t[5]), float(t[6]))

    # PTRANS: average WALL GB/s per matrix size
    ptrans = {}
    for line in text.splitlines():
        if line.startswith("WALL"):
            t = line.split()
            ptrans.setdefault(int(t[1]), []).append(float(t[9]))
    ptrans = {n: float(np.mean(v)) for n, v in ptrans.items()}

    return {"summary": summary, "hpl": hpl, "ptrans": ptrans}


# --------------------------------------------------------------------------- plotting helpers
def grouped_bars(ax, groups, series, labels, colors, log=False, fmt="{:.3g}"):
    """groups: x categories; series: list (one per file) of lists (one per group)."""
    n = len(series)
    x = np.arange(len(groups))
    w = 0.8 / n
    for i, (vals, lab) in enumerate(zip(series, labels)):
        vals = np.array(vals, dtype=float)
        bars = ax.bar(x + (i - (n - 1) / 2) * w, vals, w, label=lab, color=colors[i], edgecolor="black", linewidth=0.4)
        for b, v in zip(bars, vals):
            if np.isfinite(v) and v > 0:
                ax.annotate(fmt.format(v), (b.get_x() + b.get_width() / 2, v),
                            ha="center", va="bottom", fontsize=7, xytext=(0, 2),
                            textcoords="offset points", rotation=90 if n > 2 else 0)
    ax.set_xticks(x)
    ax.set_xticklabels(groups)
    if log:
        ax.set_yscale("log")
        ax.set_ylim(top=ax.get_ylim()[1] * 4)   # room for annotations
    else:
        ax.set_ylim(top=ax.get_ylim()[1] * 1.15)
    ax.grid(axis="y", alpha=0.3, which="both" if log else "major")
    ax.set_axisbelow(True)


def get(d, key):
    return d["summary"].get(key, np.nan)


# --------------------------------------------------------------------------- panels
def panel_hpl(ax, data, labels, colors):
    sizes = sorted(set().union(*[d["hpl"].keys() for d in data]))
    series = [[d["hpl"].get(n, (np.nan, np.nan))[1] for n in sizes] for d in data]
    grouped_bars(ax, [f"N={n}" for n in sizes], series, labels, colors)
    ax.set_ylabel("Gflop/s")
    ax.set_title("HPL (Linpack), 2x2 grid")


def panel_hpl_time(ax, data, labels, colors):
    sizes = sorted(set().union(*[d["hpl"].keys() for d in data]))
    series = [[d["hpl"].get(n, (np.nan, np.nan))[0] for n in sizes] for d in data]
    grouped_bars(ax, [f"N={n}" for n in sizes], series, labels, colors, fmt="{:.0f}")
    ax.set_ylabel("seconds")
    ax.set_title("HPL wall time (lower is better)")


def panel_dgemm(ax, data, labels, colors):
    series = [[get(d, "StarDGEMM_Gflops"), get(d, "SingleDGEMM_Gflops")] for d in data]
    grouped_bars(ax, ["Star (all ranks)", "Single"], series, labels, colors)
    ax.set_ylabel("Gflop/s")
    ax.set_title("DGEMM")


def panel_stream(ax, data, labels, colors):
    ks = ["Copy", "Scale", "Add", "Triad"]
    series = [[get(d, f"SingleSTREAM_{k}") for k in ks] for d in data]
    grouped_bars(ax, ks, series, labels, colors)
    ax.set_ylabel("GB/s")
    ax.set_title("STREAM (Single)")


def panel_stream_star(ax, data, labels, colors):
    ks = ["Copy", "Scale", "Add", "Triad"]
    series = [[get(d, f"StarSTREAM_{k}") for k in ks] for d in data]
    grouped_bars(ax, ks, series, labels, colors)
    ax.set_ylabel("GB/s per process")
    ax.set_title("STREAM (Star, all ranks together)")


def panel_fft(ax, data, labels, colors):
    series = [[get(d, "StarFFT_Gflops"), get(d, "SingleFFT_Gflops"), get(d, "MPIFFT_Gflops")] for d in data]
    grouped_bars(ax, ["Star", "Single", "MPI"], series, labels, colors, log=True)
    ax.set_ylabel("Gflop/s (log)")
    ax.set_title("FFT")


def panel_ra(ax, data, labels, colors):
    keys = ["MPIRandomAccess_GUPs", "StarRandomAccess_GUPs", "SingleRandomAccess_GUPs"]
    series = [[get(d, k) for k in keys] for d in data]
    grouped_bars(ax, ["MPI", "Star", "Single"], series, labels, colors, log=True, fmt="{:.2g}")
    ax.set_ylabel("GUP/s (log)")
    ax.set_title("RandomAccess")


def panel_ptrans(ax, data, labels, colors):
    sizes = sorted(set().union(*[d["ptrans"].keys() for d in data]))
    series = [[d["ptrans"].get(n, np.nan) for n in sizes] for d in data]
    grouped_bars(ax, [f"{n}x{n}" for n in sizes], series, labels, colors, log=True)
    ax.set_ylabel("GB/s (log, mean of runs)")
    ax.set_title("PTRANS (parallel matrix transpose)")


def panel_latency(ax, data, labels, colors):
    keys = [("MinPingPongLatency_usec", "PingPong min"), ("AvgPingPongLatency_usec", "PingPong avg"),
            ("MaxPingPongLatency_usec", "PingPong max"), ("NaturallyOrderedRingLatency_usec", "Nat. ring"),
            ("RandomlyOrderedRingLatency_usec", "Rand. ring")]
    series = [[get(d, k) for k, _ in keys] for d in data]
    grouped_bars(ax, [n for _, n in keys], series, labels, colors, log=True)
    ax.set_ylabel("microseconds (log)")
    ax.set_title("MPI latency (lower is better)")
    plt.setp(ax.get_xticklabels(), rotation=20, ha="right")


def panel_bandwidth(ax, data, labels, colors):
    keys = [("MinPingPongBandwidth_GBytes", "PingPong min"), ("AvgPingPongBandwidth_GBytes", "PingPong avg"),
            ("MaxPingPongBandwidth_GBytes", "PingPong max"), ("NaturallyOrderedRingBandwidth_GBytes", "Nat. ring"),
            ("RandomlyOrderedRingBandwidth_GBytes", "Rand. ring")]
    series = [[get(d, k) for k, _ in keys] for d in data]
    grouped_bars(ax, [n for _, n in keys], series, labels, colors, log=True)
    ax.set_ylabel("GB/s (log)")
    ax.set_title("MPI bandwidth")
    plt.setp(ax.get_xticklabels(), rotation=20, ha="right")


PANELS = [
    ("hpl", panel_hpl), ("hpl_time", panel_hpl_time), ("dgemm", panel_dgemm),
    ("stream_single", panel_stream), ("stream_star", panel_stream_star), ("fft", panel_fft),
    ("randomaccess", panel_ra), ("ptrans", panel_ptrans),
    ("latency", panel_latency), ("bandwidth", panel_bandwidth),
]


# --------------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="*", help="HPCC output files (default: the 3 standard names)")
    ap.add_argument("-l", "--labels", nargs="*", help="legend labels, same order as files")
    ap.add_argument("-o", "--outdir", default="hpcc_plots")
    ap.add_argument("--dpi", type=int, default=150)
    ap.add_argument("--show", action="store_true", help="open an interactive window too")
    args = ap.parse_args()

    if args.files:
        files = args.files
        labels = args.labels or [os.path.splitext(os.path.basename(f))[0] for f in files]
    else:
        files = [f for f, _ in DEFAULTS]
        labels = args.labels or [l for _, l in DEFAULTS]
    if len(labels) != len(files):
        sys.exit("[error] number of labels must match number of files")

    data = [parse_hpcc(f) for f in files]
    colors = COLORS[: len(files)]
    os.makedirs(args.outdir, exist_ok=True)

    # individual panels
    for name, fn in PANELS:
        fig, ax = plt.subplots(figsize=(7, 4.5))
        fn(ax, data, labels, colors)
        ax.legend(fontsize=8)
        fig.tight_layout()
        fig.savefig(os.path.join(args.outdir, f"{name}.png"), dpi=args.dpi)
        plt.close(fig)

    # combined overview
    fig, axes = plt.subplots(5, 2, figsize=(14, 22))
    for ax, (_, fn) in zip(axes.ravel(), PANELS):
        fn(ax, data, labels, colors)
    axes[0, 0].legend(fontsize=8)
    fig.suptitle("HPCC comparison: " + " vs ".join(labels), fontsize=15, y=0.995)
    fig.tight_layout()
    fig.savefig(os.path.join(args.outdir, "overview.png"), dpi=args.dpi)

    # CSV of every summary metric
    keys = sorted({k for d in data for k in d["summary"] if not k.startswith(("sizeof", "HPL_dMACH", "HPL_sMACH"))})
    with open(os.path.join(args.outdir, "metrics.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["metric"] + labels)
        for k in keys:
            w.writerow([k] + [d["summary"].get(k, "") for d in data])
        for n in sorted(set().union(*[d["hpl"].keys() for d in data])):
            w.writerow([f"HPL_Gflops_N{n}"] + [d["hpl"].get(n, ("", ""))[1] for d in data])
            w.writerow([f"HPL_time_N{n}"] + [d["hpl"].get(n, ("", ""))[0] for d in data])

    print(f"Saved {len(PANELS)} panels + overview.png + metrics.csv in {args.outdir}/")
    if args.show:
        plt.show()


if __name__ == "__main__":
    main()
