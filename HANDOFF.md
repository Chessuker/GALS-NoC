# GALS NoC — handoff note

Last updated: 2026-08-19. Branch `feature/1-testbenchs`, last commit `3baabaf`.

Read this first if you're picking the project up cold.

---

## 1. Where things stand

Three real RTL bugs were found. **All three are fixed and verified in simulation.**
Bug #3's fix has NOT yet been confirmed on the board.

| # | bug | status |
|---|-----|--------|
| 1 | `packet_arbiter` released an output port mid-packet, corrupting packets | **fixed** |
| 2 | `packet_arbiter` round-robin mask latched; one input took 100% of a contended port | **fixed** |
| 3 | `vc_port_arbiter` cross-blocks the two VCs; throughput collapse + deadlock | **fixed in sim — needs a board run** |

All three predate this work and would have shipped. None was caught by the
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
All four switch combinations now pass; `HS_VC_ALT 1` used to fail on `Pending` (bug #3).

### Simulation without Vivado's project flow

`launch_simulation` is not required. The same regression runs straight off the sources with
`xvlog`/`xelab`/`xsim` from `C:/AMDDesignTools/2025.2/Vivado/bin`, which is much faster and
leaves no project state behind. Compile order that elaborates cleanly:

    sync_fifo dual_port_ram dual_port_ram_ecc ecc_secded_encode_8b ecc_secded_decode_8b
    gray_counter sync_2stage async_fifo async_fifo_fwft fwft_wrapper axis_perf_mon
    traffic_gen packet_arbiter vc_port_arbiter vc_input_buffer router_5port_mesh_vc
    noc_mesh_2x2_vc gals_node_wrapper gals_noc_top tb_noc_mesh_2x2_gals

Elaborate `work.tb_noc_mesh_2x2_gals` (not `xil_defaultlib.…` — that library only exists
inside the project), pass the switches as `-d HW_CLOCKS -d HS_VC_ALT -d SIM_DEBUG`, and
drive xsim with a `run all; quit` tclbatch. Verified to reproduce
`regress_hwclk_vcalt_dbg_20260819_150653.log` number-for-number before the fix went in.

### Hardware build (~5 min synth + impl)

    set PATTERN 1 ; set VC_MODE 0 ; source .../setup_stress_build.tcl

- `PATTERN` 0 = permutation (00<->11, 01<->10), 1 = hot-spot (01/10/11 -> node 00)
- `VC_MODE` 0 = VC0 only, 1 = VC1 only, 2 = alternate (the original default)

Then: Set Up Debug -> Run Implementation -> bitstream -> program -> Hardware Manager ->
**Trigger Immediately** -> export each ILA to CSV -> `python analyze_ila.py <csv-folder>`.

Expect ~924 `MARK_DEBUG` nets. 668 means the `mon_*` perf-monitor probes weren't picked
up (gotcha 6). 0 means the top module isn't `arty_stress_top`.

---

## 3. Bug #3 — fixed in simulation, not yet on hardware

### Symptom (before the fix)

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

`vc1_is_active` keyed off *"VC1's packet_arbiter holds a grant"*, **not** *"VC1 can actually
move a flit"*. The two VCs have genuinely independent downstream credits
(`ready_out_vc0` = `m_ready[out_p][0]`, `ready_out_vc1` = `m_ready[out_p][1]`), so gating
`ready_vc0` on VC1's grant re-coupled resources the VC design deliberately separated.
A VC1 packet stalled on a full downstream VC1 buffer blocked VC0 even when VC0's own
downstream buffer had room.

The anti-starvation override was the intended mitigation but had two problems:

1. It cost `STARVE_LIMIT` (64) idle cycles before firing, every episode.
2. Exit required VC0 to complete a **whole packet**:
   `if (|raw_grant_vc0 && ready_out_vc0 && |(tlast_vc0 & raw_grant_vc0))`.
   If VC0's packet then stalled, `vc0_override` latched and now **VC1** was blocked
   indefinitely. Blocking in both directions was the circular wait.

### The fix

Two changes, both in `vc_port_arbiter.sv`:

    assign vc1_can_move  = (|raw_grant_vc1) && ready_out_vc1;
    assign vc0_can_move  = (|raw_grant_vc0) && ready_out_vc0;
    assign vc1_is_active = vc1_can_move && !(vc0_override && vc0_can_move);

1. **VC1 only owns the shared output link on cycles it can actually move a flit.** The
   moment its downstream credit runs out it yields, and VC0 takes the link that same cycle
   instead of waiting 64. The two VCs share one physical link (`m_valid[out_p]` is a single
   wire), so the mutex itself is genuinely required — what was wrong was deciding it on
   grant-held rather than can-transfer.
2. **The override only blocks VC1 while VC0 is itself making progress** (`&& vc0_can_move`).
   If VC0 is also stuck, VC1 gets the link back. That is the edge that closed the circular
   wait; `vc0_override` can no longer block in both directions at once.

Plus a second override release path — `if (!(|valid_vc0))` — so an override can't outlive
the VC0 request that raised it. In practice this never fires in the regression (all 36
episodes release via normal packet completion); it's a safety net, not the fix.

Interleaving VC0 and VC1 flits on one physical link is legal by construction: the
downstream `vc_input_buffer` demuxes on `m_tid` into per-VC FIFOs. Packet continuity
*within* a VC is still held by `packet_arbiter`'s `LOCKED` state, which the fix doesn't
touch — `raw_grant_*` is unchanged, only which VC drives the link.

### Results

Regression, all four switch combinations, 6/6 tests, `Mismatched=0`, `Pending=0`:

| config | node 00 ingress, before | after | min fairness share |
|---|---|---|---|
| TB clocks, VC0 only    | 94.9% (Pending 0)  | **95.0%** | 26% |
| TB clocks, alternating | 9.5%  (Pending 13) | **77.8%** | 26% |
| HW clocks, VC0 only    | 99.5% (Pending 0)  | **99.5%** | 25% |
| HW clocks, alternating | 44.5% (Pending 11) | **97.2%** | 25% |

The VC0-only columns are unchanged to within run-to-run noise — the fix only touches
behaviour when both VCs contend. Test 2 (VC1 preemption) is byte-identical to the pre-fix
log, so VC1 keeps strict priority whenever it can actually move.

`SIM_DEBUG` override accounting, HW clocks + alternating:

| | before | after |
|---|---|---|
| triggers | 51 | 36 |
| releases | 47 | 36 |
| **latched (never released)** | **4** | **0** |
| median episode with VC1 blocked | 1.10 us | 0.39 us |
| total time VC1 blocked | 45.2 us | 19.2 us |

Logs: `sim_logs/regress_*_FIXED.log` (all five runs, headers say which switches).

Out-of-context synthesis of `router_5port_mesh_vc` (xc7a35ticsg324-1L, 80 MHz):
no latches, no combinational loops, WNS 3.207 ns -> **3.131 ns** (76 ps cost — `m_valid`
now depends on `m_ready`, one extra level), 866 -> **967 LUTs** per router, registers
unchanged at 199. About 400 extra LUTs across the 4-router mesh, ~2% of the part.

### Still to do

**Rebuild the board and confirm.** `set PATTERN 1 ; set VC_MODE 2` should now read close to
the `VC_MODE=0` number (100.0%) instead of 57.5%. That is the one claim here that
simulation cannot make for you.

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

- **Bug #3 has not been confirmed on hardware** — see the end of section 3.
- ECC (`ecc_secded_*`, `dual_port_ram_ecc`) has never been exercised — no error injection.
- Seven formal `.sby` files sit unused in `sources_1/new/old/`. `arbiter_formal.sby` claims
  to prove "channel cannot be stolen mid-packet" — plausibly catches bug #1 at source, and
  a liveness property would catch bug #2. The `FORMAL` block in `vc_port_arbiter.sv` was
  updated alongside the bug #3 fix (`assert_no_vc1_during_override` is now conditioned on
  `vc0_can_move`, plus new `assert_vc1_yields_when_stalled` and two covers), but **none of
  it has been run** — no solver is installed here.
- UART build (`arty_gals_noc_wrapper`) not rebuilt since `debug.xdc` was dropped (gotcha 5).
- `final_src/` diverges from `sources_1/new/` in 16 of 19 shared files. Stale July snapshot,
  historical reference only. Do not build from it.
