# GALS NoC — handoff note

Last updated: 2026-08-19. Branch `feature/1-testbenchs`, last commit `04cd562`.

Read this first if you're picking the project up cold.

---

## 1. Where things stand

Three real RTL bugs were found. **Two are fixed and verified. One is diagnosed but NOT fixed.**

| # | bug | status |
|---|-----|--------|
| 1 | `packet_arbiter` released an output port mid-packet, corrupting packets | **fixed** |
| 2 | `packet_arbiter` round-robin mask latched; one input took 100% of a contended port | **fixed** |
| 3 | `vc_port_arbiter` cross-blocks the two VCs; throughput collapse + deadlock | **OPEN** |

Bugs 1 and 2 both predate this work and would have shipped. Neither was caught by the
five original simulation tests or by the permutation hardware stress run.

---

## 2. How to run things

All from the Vivado Tcl console. Variables persist in the session — reset them explicitly.

### Simulation regression (~20-45 s)

    source .../run_sim_regression.tcl

Switches (set before sourcing):
- `set HW_CLOCKS 1` — Arty clock ratios (NoC 80 MHz, sink 100, senders 71.4/83.3/71.4)
  instead of TB defaults (NoC 250, sink 500, senders 125/333/100)
- `set HS_VC_ALT 1` — Test 6 alternates VC0/VC1 per packet, mirroring hardware `VC_MODE=2`
- `set SIM_DEBUG 1` — `vc_port_arbiter` override tracing (noisy; leave off normally)

Each run writes a self-describing log to `sim_logs/regress_<tag>_<stamp>.log`
(config header + full xsim output + summary).

Pass criteria: 6/6 tests, `Mismatched=0`, `Pending=0`.
**Known-failing by design:** any run with `HS_VC_ALT 1` fails on `Pending` — that is bug #3.

### Hardware build (~5 min synth + impl)

    set PATTERN 1 ; set VC_MODE 0 ; source .../setup_stress_build.tcl

- `PATTERN` 0 = permutation (00<->11, 01<->10), 1 = hot-spot (01/10/11 -> node 00)
- `VC_MODE` 0 = VC0 only, 1 = VC1 only, 2 = alternate (the original default)

Then: Set Up Debug -> Run Implementation -> bitstream -> program -> Hardware Manager ->
**Trigger Immediately** -> export each ILA to CSV -> `python analyze_ila.py <csv-folder>`.

Expect ~924 `MARK_DEBUG` nets. 668 means the `mon_*` perf-monitor probes weren't picked
up (gotcha 6). 0 means the top module isn't `arty_stress_top`.

---

## 3. Bug #3 — diagnosed, not fixed

### Symptom

| config | node 00 local port utilisation |
|---|---|
| hardware, `VC_MODE=0` (VC0 only) | **100.0%** |
| hardware, `VC_MODE=2` (alternating) | **57.5%** |
| sim, VC0 only | 94.9% (TB clocks) / 99.5% (HW clocks) |
| sim, alternating | collapses, then **deadlocks** |

Fairness is identical in both VC modes (48/28/24), so bug #2's fix is independent of this.

### Root cause (`vc_port_arbiter.sv`)

    assign vc1_is_active = |raw_grant_vc1 && !vc0_override;
    assign ready_vc0     = !vc1_is_active ? ready_out_vc0 : 1'b0;

`vc1_is_active` keys off *"VC1's packet_arbiter holds a grant"*, **not** *"VC1 can actually
move a flit"*. The two VCs have genuinely independent downstream credits
(`ready_out_vc0` = `m_ready[out_p][0]`, `ready_out_vc1` = `m_ready[out_p][1]`), so gating
`ready_vc0` on VC1's grant re-couples resources the VC design deliberately separated.
A VC1 packet stalled on a full downstream VC1 buffer blocks VC0 even when VC0's own
downstream buffer has room.

The anti-starvation override is the intended mitigation but has two problems:

1. Costs `STARVE_LIMIT` (64) idle cycles before firing, every episode.
2. Exit requires VC0 to complete a **whole packet**:
   `if (|raw_grant_vc0 && ready_out_vc0 && |(tlast_vc0 & raw_grant_vc0))`.
   If VC0's packet then stalls, `vc0_override` latches and now **VC1** is blocked
   indefinitely. Blocking in both directions is the circular wait.

### Evidence — `sim_logs/regress_hwclk_vcalt_dbg_20260819_150653.log`

With `SIM_DEBUG` on: 51 override triggers, 47 releases -> **4 latched**. The four are
exactly the arbiters forming the converging tree into node 00:

    router idx1 out=WEST    (agent_01 -> idx0)
    router idx3 out=WEST    (agent_11 -> idx2)
    router idx2 out=SOUTH   (agent_10 + agent_11 -> idx0)
    router idx0 out=LOCAL   (delivery into node 00)

Last trigger 31.98 us; last flit delivered 32.13 us; nothing after. Non-latched episodes
last a median ~1.1 us (~88 NoC cycles) with VC1 fully blocked — that recurring tax is
what produces the board's 57.5%.

### Proposed fix (NOT applied — verify before trusting)

Make the gate depend on VC1 actually being able to transfer, roughly:

    assign vc1_is_active = |raw_grant_vc1 && ready_out_vc1 && !vc0_override;

so a stalled VC1 yields the port immediately instead of after 64 cycles or never. This may
also make the whole `starve_cnt` / `vc0_override` machinery unnecessary.

**Do not apply this blind.** Two independent bugs already came out of the adjacent arbiter.
Run the regression with `HS_VC_ALT 1` before and after; `Pending` and Test 6's utilisation
line are the pass/fail signal.

---

## 4. Gotchas that cost real time

1. **`mark_debug` does not prevent sweeping.** A register with no fanout is removed before
   Set Up Debug ever sees it. Use `dont_touch` too, or give it a real load.
2. **The pass LEDs can lie.** `traffic_node_agent` advances its FSM on a free-running cycle
   counter, so it reaches `S_DONE` and asserts pass whether or not traffic is moving. The
   `VC_MODE=2` hardware run lit green on a deadlocked fabric. A liveness check
   (`tx_flit_cnt` still advancing near the end of the window) is still missing.
3. **Node naming is inconsistent.** The testbench calls mesh idx1 "10" and idx2 "01";
   `gals_noc_top` calls idx1 "h01" and idx2 "h10". Map through the **index**
   (`idx = y*2 + x`, `tdest = {x[1:0], y[1:0]}`), never the label.
4. **Window durations differ per agent.** `WINDOW_LOG` counts cycles, not time, so a
   100 MHz node's window is shorter than a 71 MHz node's. Never compare raw counter totals
   across agents; `analyze_ila.py`'s conservation table handles this correctly.
5. **`DEBUG_BUILD` is no longer defined anywhere.** `loopback_node_agent` and
   `uart_noc_host` gate all their ILA taps on it, so the UART build currently has zero
   instrumentation and the old `debug.xdc` would fail against it.
6. **Set Up Debug wrote its cores into `arty.xdc`** (pins + debug in one file). New
   `mark_debug` nets aren't probed until you re-run Set Up Debug. A clean pins-only
   `arty.xdc` is in `backup_20260804/constrs/`.
7. **Simulation is blind to fairness by default.** Test 4 sends one packet per node then
   stops — proves delivery, not bandwidth sharing. Test 6 (sustained contention) was added
   for exactly this and is what catches bug #2 class failures.

---

## 5. Still open, beyond bug #3

- ECC (`ecc_secded_*`, `dual_port_ram_ecc`) has never been exercised — no error injection.
- Seven formal `.sby` files sit unused in `sources_1/new/old/`. `arbiter_formal.sby` claims
  to prove "channel cannot be stolen mid-packet" — plausibly catches bug #1 at source, and
  a liveness property would catch bug #2.
- UART build (`arty_gals_noc_wrapper`) not rebuilt since `debug.xdc` was dropped (gotcha 5).
- `final_src/` diverges from `sources_1/new/` in 16 of 19 shared files. Stale July snapshot,
  historical reference only. Do not build from it.
