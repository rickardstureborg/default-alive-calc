# Default Alive Calculator

A tiny local Mac app for Paul Graham's question in [Default Alive or Default Dead?](https://paulgraham.com/aord.html): *assuming expenses stay constant and revenue keeps growing at its recent rate, does the company reach profitability on the money it has left?*

The math is [Trevor Blackwell's calculator](https://growth.tlb.org) with expense growth fixed at zero. Revenue compounds continuously, so profitability arrives at `T = ln(E/R) / ln(1+g)`, and reaching it costs `C = E·T − (E−R)/ln(1+g)`. The company is **default alive** when cash ≥ C. Otherwise the app reports when the money runs out. The tests pin parity with TLB's own output: its defaults give 25.8236 months and $118,907.71.

Type amounts like `250k`, `$1.2M` or `1,500`, and growth like `8` or `8%`. **Esc**, **C** or **⌘⌫** clears everything. The app stores only the last input.

## Build

```sh
make            # test, build, install to ~/Applications, relaunch
make preview    # browser mock for trying design changes first
```

Requires Xcode (Swift 6) and macOS 14+. Node is needed for the preview's parity tests, and [uv](https://docs.astral.sh/uv/) for the preview server. See `CLAUDE.md` for the design → port loop.
