# GALS Packet-Based Fabric: a walkthrough from zero

Written 2026-09-14 against `main` at `afce6cd` (PR #7 merged). `v1.0` is tagged at
`f07ddca`, two PRs earlier.

This is the long-form companion to `HANDOFF.md`. `HANDOFF.md` is the working log for
someone who already knows the design and needs the current state, the numbers, and the
traps, in the order they were discovered. This document is for someone who has never seen
the project: it explains what the thing is, how every module works, how a flit travels
through it, what every defect was and how it was found and fixed, how the verification is
done and what it does and does not cover, and how to extend the design. Where the two
disagree on a number, `HANDOFF.md` has the dated log entry behind it; where they disagree on
an explanation, this document is the more careful one.

Read it top to bottom the first time. After that, section 6 (module reference), section 9
(verification, including the property catalogue), section 11 (parameters) and section 18
(file map) are the parts you come back to.

---

## Contents

1. What this project is
2. Background you need (NoC, GALS, virtual channels, packets and flits, CDC, ECC, resets)
3. The hardware: board, clocks, node numbering, resets, JTAG control
4. The flit contract: what travels on every wire, and who enforces each rule
5. Architecture, top to bottom
6. Module reference (every RTL file, every IP, every testbench, every script)
7. Life of a flit: one packet end to end, one rejected flit, one reset
8. Every defect found: the seven numbered bugs and the ones that were not numbered
9. How it is verified: simulation, formal (full property catalogue), silicon, and a coverage matrix
10. On the board: hardware-specific behaviour
11. Parameters and knobs
12. Design decisions and the alternatives that were rejected
13. Extending the design
14. Timeline
15. Things that cost real time (gotchas)
16. What is still open
17. Reproducing the results
18. File map
19. Glossary

---

## 1. What this project is

A small **network-on-chip (NoC)** on a Xilinx Artix-7 FPGA. Four endpoints ("hosts" or
"nodes") sit at the corners of a 2x2 grid. Each host runs on its **own clock**, at its own
frequency, with no phase relationship to the others or to the network. The network itself
runs on a fifth clock. Hosts hand packets to the network; the network delivers them to the
addressed host.

That is the GALS part: **Globally Asynchronous, Locally Synchronous**. Each island is
ordinary synchronous logic. The boundaries between islands are asynchronous FIFOs with
gray-coded pointers and two-stage synchronisers, the textbook clock-domain crossing. Since
2026-09-12 each island also has its own reset synchroniser, which is the part of the
textbook the design had skipped.

The network is **packet-based**: a host sends a packet as a sequence of 8-bit flits, the
last one tagged `tlast`. A router holds an output port for the whole packet so flits of
different packets never interleave inside one channel. There are **two virtual channels
(VCs)** per link, so a high-priority packet can overtake a low-priority one.

The RTL is SystemVerilog, comments mostly in Thai. The design predates the git history
(source files carry create dates from April to July 2026); the repository begins on
2026-08-17 and everything after that is verification, bug fixing, and hardening. Seven
numbered RTL bugs were found and fixed; a further set of defects in tooling, tests and
verification claims were found on the way and are listed in section 8 too. Every guard
now has a silicon demonstration, most of them from a JTAG-driven fault-injection campaign
that runs from a single bitstream.

The word "we" below means whoever was working on the repo at the time. The commits say who.

---

## 2. Background you need

If you know what a wormhole-routed NoC with virtual channels is, skim 2.8 and skip to
section 3.

### 2.1 Why a network instead of wires

When a chip has many blocks that need to talk to each other, point-to-point wires do not
scale (N blocks need on the order of N² connections) and a shared bus serialises
everything through one arbiter. A NoC puts a small router at each block and connects
routers to their neighbours. Traffic is broken into packets and hops router to router.
Several packets can be in flight on different links at once.

### 2.2 Mesh, XY routing

Our topology is a 2x2 **mesh**: four routers, each connected to its neighbours (east/west
and north/south) and to its own local host. A router has five ports: LOCAL, NORTH, SOUTH,
EAST, WEST.

Routing is **dimension-ordered XY**: a flit first moves along X until its X matches the
destination, then along Y. Each router decides this locally from the destination address
and its own coordinates. XY routing on a mesh is deadlock-free by construction because it
never turns from Y back to X, which rules out cyclic channel dependencies.

### 2.3 Packets, flits, wormhole switching

A **packet** is the unit the host cares about. It is transmitted as a sequence of
**flits** (flow-control units), one per link cycle. Here a flit is 8 bits of data plus a
few control bits. The last flit of a packet carries `tlast = 1`.

**Wormhole switching** means a router forwards a packet flit by flit as it arrives rather
than buffering the whole packet first. The head flit claims an output port; body flits
follow it; the tail (`tlast`) releases the port. A packet can therefore be strung across
several routers at once like a worm in a hole. The consequence that matters for this
project: while a packet holds a port, nothing else can use that port. If the tail never
comes, the port is held forever. Four of the seven bugs are variations on that sentence.

### 2.4 Virtual channels

A **virtual channel** is a separate buffer and separate flow control on the same physical
link. With two VCs, a link carries two independent queues. If a VC0 packet is blocked
downstream, a VC1 packet can still use the wire. VCs are also used here for priority: VC1
is "the ambulance", VC0 is "the truck". VC1 gets the link whenever it can move; VC0 gets
it otherwise, with an anti-starvation override so a continuous VC1 flood cannot lock VC0
out forever.

### 2.5 Valid/ready handshake

Every interface uses an AXI4-Stream-style handshake: the sender raises `valid` with the
data; the receiver raises `ready`; the transfer happens on a clock edge where both are
high. `ready` here is **per VC**: a 2-bit vector saying which VC can accept a flit. A
sender presenting a flit on VC0 looks only at `ready[0]`.

### 2.6 GALS and clock-domain crossing

Two clock domains with no known relationship cannot exchange multi-bit data on plain
wires; the receiver would sample some bits before and some after a change. The standard
answer is an **asynchronous FIFO**: memory written in one domain and read in the other,
with each side's pointer passed to the other side through a two-flop synchroniser. The
pointers are **gray-coded** so that only one bit changes per increment, which makes a
sampled-mid-change pointer merely stale rather than wrong.

Single-bit flags that only ever go from 0 to 1 and stay there (sticky flags) can cross
with just the two-flop synchroniser; there is no multi-bit consistency problem. But the
flag must come straight from a register: if it is computed by a LUT (an OR of several
flags, say) the LUT can glitch while its inputs change and the synchroniser will capture
the glitch as a real 1. That is what `report_cdc` calls CDC-10, and it was in this design
until 2026-09-12.

### 2.7 ECC

The FIFO memories protect the 8-bit payload with **SECDED** (single-error-correct,
double-error-detect) Hamming code: 8 data bits become a 13-bit codeword (4 Hamming parity
bits plus one overall parity). On read, a single flipped bit is corrected and flagged;
two flipped bits are detected and flagged as uncorrectable. Three or more can be
misreported; that limit is stated in `HANDOFF.md`.

### 2.8 Reset domain crossing

A reset that is asserted asynchronously is fine: every flop drops into reset immediately,
no clock needed. The problem is *deassertion*. If the reset releases at some arbitrary
moment relative to a domain's clock, two flops in that domain can leave reset on different
clock edges, and a flop whose recovery time is violated can go metastable. The standard
answer is a **reset synchroniser** per domain: assert asynchronously, deassert through two
flops clocked by that domain. This design ran without one until 2026-09-12 and got away
with it because every agent idles for 1024 cycles after reset before sending anything.

---

## 3. The hardware

### 3.1 Board

Digilent **Arty A7-100T** (xc7a100tcsg324-1, board serial 210319C088F2A in the logs).
Out-of-context synthesis experiments were done on the smaller xc7a35ticsg324-1L part;
the numbers in `HANDOFF.md` section 3 say which.

### 3.2 Clocks

One MMCM (`clk_wiz_0`, 100 MHz in, VCO 1000 MHz with multiplier 10) produces five clocks:

| clock | net | divider | frequency | used by |
|---|---|---|---|---|
| clk_out1 | `clk_noc` | 12.5 | 80.00 MHz | the mesh, all four routers, the NoC side of every wrapper |
| clk_out2 | `clk_h00` | 10 | 100.00 MHz | host 00 (the sink in the hot-spot test; the UART host in the UART build), the VIO, the LED logic |
| clk_out3 | `clk_h01` | 14 | 71.43 MHz | host 01 |
| clk_out4 | `clk_h10` | 12 | 83.33 MHz | host 10 |
| clk_out5 | `clk_h11` | 14 | 71.43 MHz | host 11 (the one the fault injector sits on) |

Simulation uses these ratios when `HW_CLOCKS` is defined, otherwise a faster set (NoC 250,
sink 500, senders 125/333/100 MHz) that runs quicker and was the original testbench
default. Both configurations are part of the regression.

The MMCM reset is tied low in both tops. The reset button only resets the logic; if it also
reset the MMCM the ILA debug hub would lose its clock and every hardware capture would die
with the reset. `arty_stress_top` had this right from the start; `arty_gals_noc_wrapper`
got it on 2026-09-12.

### 3.3 Node numbering (read this twice)

A node has a coordinate `(x, y)`, an index, a destination address and, unfortunately,
two naming conventions.

    idx   = y*2 + x
    tdest = {x[1:0], y[1:0]}      (4 bits: x in [3:2], y in [1:0])

| idx | (x,y) | tdest | `gals_noc_top` port name | testbench label | in the stress build |
|---|---|---|---|---|---|
| 0 | (0,0) | `0000` | `h00` | Node00 | sink under `PATTERN=1`; the UART host in the UART build |
| 1 | (1,0) | `0100` | `h01` | Node10 | sender |
| 2 | (0,1) | `0001` | `h10` | Node01 | sender |
| 3 | (1,1) | `0101` | `h11` | Node11 | sender, with the fault injector on its TX |

`gals_noc_top` names ports by index written as two digits; `tb_noc_mesh_2x2_gals` names
them by `xy`. They disagree for idx 1 and 2. Always map through the index. This is gotcha
3 in `HANDOFF.md` and it has bitten more than once.

### 3.4 Two board builds

- **Stress build** (`arty_stress_top`): four synthetic traffic agents hammer the network
  and check what arrives. Pass/fail on LEDs, detail through the ILA, fault injection and
  soft reset through a VIO. This is the build used for every performance number, every
  bug confirmation and the fault campaign.
- **UART build** (`arty_gals_noc_wrapper`): host 00 is a UART bridge to a PC; the other
  three hosts are loopback echoes. A Python script sends packets and reads the echoes.
  This is the interactive demo, the round-trip data-integrity check, and the only build
  where node 00's destination filters are live on silicon (section 10.8 explains why).

### 3.5 Reset architecture (since 2026-09-12)

    rst_n_btn ──┐
                ├─ global_rst_n (unclocked, async)
    pll_locked ─┘         │
                          ├─ reset_sync (clk_noc) ── rst_n_noc ── mesh, NoC side of wrappers
                          ├─ reset_sync (clk_h00) ── rst_n_h00 ── wrapper 00 host side, agent 00, perf mons, LEDs
                          ├─ reset_sync (clk_h01) ── rst_n_h01 ── wrapper 01 host side, agent 01
                          ├─ reset_sync (clk_h10) ── rst_n_h10 ── ...
                          └─ reset_sync (clk_h11) ── rst_n_h11 ── ..., fault injector
    vio soft reset (clk_h00 flop) ── srst input of every reset_sync (synchronised inside)

Each `reset_sync` asserts asynchronously from `global_rst_n` and deasserts through two
flops of its own clock. The VIO soft reset does not touch the async net at all: it enters
each `reset_sync` as a separate input that is synchronised there and applied
synchronously. Before this, one `global_rst_n` net went straight to every flop in all five
domains.

### 3.6 JTAG control (stress build)

A VIO core (`vio_fault`, on `clk_h00`) gives Hardware Manager an 8-bit output and an 8-bit
input:

| `probe_out` bit | meaning | | `probe_in` bit | meaning |
|---|---|---|---|---|
| 0 | soft reset (active high) | | 0 | `pass_group1` |
| 1 | arm the fault injector | | 1 | `pass_group2` |
| 5:2 | fault mode (section 6.4, `fault_injector`) | | 2 | `any_fail` |
| 7:6 | unused | | 3 | `ecc_dbe` (synced) |
| | | | 4 | `dest_err` (synced) |
| | | | 5 | `tid_err` (synced) |
| | | | 6 | `fault_active` (synced from `clk_h11`) |
| | | | 7 | `fault_fired` (synced from `clk_h11`) |

This is what lets one bitstream run every fault mode from a batch script, with no serial
port involved (opening the serial port resets the board, section 10.12).

---

## 4. The flit contract

Every link in the design carries the same five signals plus a per-VC ready:

| signal | width | meaning |
|---|---|---|
| `tdata` | 8 | payload |
| `tdest` | 4 | destination node, `{x, y}` |
| `tid` | 2 | virtual channel, **one-hot**: `01` = VC0, `10` = VC1 |
| `tlast` | 1 | this is the last flit of the packet |
| `tvalid` | 1 | the four fields above are meaningful this cycle |
| `tready` | 2 | back from the receiver, one bit per VC |

A transfer on VC v happens when `tvalid && tid[v] && tready[v]`.

Inside FIFOs the three payload fields are packed as `{tlast, tdest, tdata}` = 13 bits
(`PACK_W`). `tid` is not stored; it selects which FIFO the flit goes into.

The rules the fabric relies on, and where each is enforced, proved and demonstrated. As of
`afce6cd` every one of them is enforced in RTL; none is only an assumption any more.

| rule | enforced where | violation → | proved | shown on silicon |
|---|---|---|---|---|
| `tid` is one-hot | `gals_node_wrapper` host ingress (the one that catches a real host) and `noc_mesh_2x2_vc` ingress | flit dropped, `tid_err[node]`, open packet force-closed | mesh bmc + wrapper prove, one-hot `assume` removed at both | campaign modes 2 and 3; UART `tid=00` |
| `tdest` is on the board (x ≤ 1, y ≤ 1) | mesh ingress `dest_ok` | dropped, `dest_err[node]`, force-close | mesh bmc, range `assume` removed | campaign mode 5 |
| `tdest` is constant within a packet | mesh ingress `frame_ok` against the recorded head dest | dropped, `dest_err[node]`, force-close | mesh bmc, `assert_local_dest_stable` with the `assume` removed; the router's own proof keeps its `f_wf` assume because there its inputs are free | campaign mode 4 |
| every packet ends in a `tlast` | (a) a rejected flit that carried the `tlast`: both ingress trackers force-close the packet (bug #7); (b) a source that just stops: `packet_arbiter` abandons the locked port after 1024 silent cycles (bug #5) | (a) truncated packet delivered to the head's destination; (b) port released, orphan dropped downstream | (a) mesh bmc, wrapper prove; (b) `packet_arbiter` prove (unbounded) | (a) modes 2-5 truncate; (b) mode 1 |

A note on what "dropped" means at the mesh ingress: the flit is *consumed* (the host sees
`ready` as normal) and not presented to the router. Backpressure was rejected because it
just moves the stall to the sender; clamping the address was rejected because it delivers
the packet somewhere nobody intended, silently (section 12).

---

## 5. Architecture, top to bottom

    arty_stress_top  /  arty_gals_noc_wrapper          (board top: MMCM, reset_sync x5, LEDs, agents, VIO)
        |
        +-- gals_noc_top                                (glue: 4 wrappers + mesh + flag aggregation)
              |
              +-- gals_node_wrapper  x4                 (GALS boundary, one per host, two resets)
              |     +-- async_fifo_fwft  x4             (TX VC0, TX VC1, RX VC0, RX VC1)
              |           +-- async_fifo
              |           |     +-- gray_counter x2, sync_2stage x2
              |           |     +-- dual_port_ram_ecc  (payload, 8b -> 13b codeword)
              |           |     |     +-- ecc_secded_encode_8b, ecc_secded_decode_8b, dual_port_ram
              |           |     +-- dual_port_ram      (control bits, no ECC)
              |           +-- fwft_wrapper
              |
              +-- noc_mesh_2x2_vc                       (wiring + ingress filters + force-close)
                    +-- router_5port_mesh_vc  x4
                          +-- vc_input_buffer  x5       (one per input port)
                          |     +-- sync_fifo  x2       (one per VC)
                          +-- vc_port_arbiter  x5       (one per output port)
                          |     +-- packet_arbiter  x2  (one per VC)
                          +-- XY decoder, crossbar      (inline)

    noc_stress_tester (stress build only)
        +-- traffic_node_agent x4
        +-- fault_injector                              (between agent_11 and the fabric)
        +-- sync_2stage x2                              (flags to clk_h00; VIO control to clk_h11)

Data direction, host to host:

    host TX  ->  wrapper TX FIFO (clk_host -> clk_noc)  ->  mesh ingress filters
             ->  router LOCAL input buffer  ->  arbiter  ->  crossbar  ->  link
             ->  next router's input buffer  -> ...  ->  router LOCAL output
             ->  wrapper RX FIFO (clk_noc -> clk_host)  ->  host RX

Everything from the mesh ingress filter to the wrapper RX FIFO write port is in the
`clk_noc` domain. The wrappers are the only place two clocks meet for data; the flag
aggregation in `gals_noc_top` and the two tops are where sticky flags cross.

---

## 6. Module reference

All RTL is in `GALS_Packet-Based_Fabric.srcs/sources_1/new/`; IP in `.../sources_1/ip/`.
Line counts are as of `afce6cd`. "Formal" says whether the module has a `FORMAL` block and
what `formal/*.sby` proves about it; "prove" means unbounded (k-induction passed), "bmc"
means bounded. Section 9.2 has the full property list.

### 6.1 Primitives

#### `dual_port_ram.sv` (57 lines)
Simple dual-port RAM: write port on `wclk`, read port on `rclk`, registered read data.
Infers block or distributed RAM depending on size. No reset on the memory array (Xilinx
RAM primitives cannot be reset and a reset in the sensitivity list would force the array
into flip-flops). Formal: none; it is a primitive.

#### `sync_fifo.sv` (90 lines)
Single-clock FIFO, `DEPTH` entries, pointer width `$clog2(DEPTH)+1` so full and empty
are distinguished by the top pointer bit. Read data is combinational from the head
(`r_data = mem[r_ptr]`), so it behaves as first-word-fall-through: the head is visible
before `r_en`. Used inside `vc_input_buffer` (depth 16) and in `uart_noc_host` (depth
256). Formal: covered by `vc_input_buffer`'s shadow-FIFO proof.

#### `gray_counter.sv` (133 lines)
Binary counter with a gray-coded copy of the pointer (`ptr_g = bin ^ (bin >> 1)`) and
the binary low bits as the RAM address. One instance per side of every `async_fifo`.
Formal: prove (gray equals `bin ^ bin>>1`, exactly one bit changes per step, the MSB
flips on wrap; cover reaches the wrap, which needs depth 40 with a 5-bit pointer).

#### `sync_2stage.sv` (97 lines)
Two-flop synchroniser, `WIDTH` bits, with `ASYNC_REG` on the output register so Vivado
packs the pair and treats the first stage's metastability window correctly. Used for gray
pointers inside `async_fifo` and for sticky flags everywhere else (ECC, `dest_err`,
`tid_err`, agent `done`/`err`, VIO control and status). Formal: prove (reset clears both
stages; data passes in two cycles).

#### `reset_sync.sv` (43 lines, added 2026-09-12)
Per-domain reset. `arst_n` (the unclocked `button & pll_locked`) asserts asynchronously;
deassertion goes through two `ASYNC_REG` flops on the domain's clock. A separate `srst`
input (the VIO soft reset, from another domain) is synchronised through its own two flops
and applied synchronously: `rst_n = q2 & ~s2`. Keeping `srst` out of the async net is what
turned 572 CDC-7 and 4 CDC-10 criticals into zero. Formal: none (four flops).

#### `ecc_secded_encode_8b.sv` (44 lines) / `ecc_secded_decode_8b.sv` (78 lines)
Hamming(12,8) plus overall parity = SECDED(13,8). Encoder computes p1, p2, p4, p8 over
the usual bit positions, assembles the 12-bit Hamming word with parity bits at positions
1, 2, 4, 8, then adds p0 = XOR of all twelve as bit 12. Decoder recomputes the syndrome
and overall parity:

| syndrome | overall parity mismatch | verdict |
|---|---|---|
| 0 | no | clean |
| 0 | yes | single error in p0 itself, data fine |
| ≠0 | yes | single error at position `syndrome`, corrected |
| ≠0 | no | double error, uncorrectable |

Formal: none directly; `tb_ecc_secded` proves it exhaustively (all 256 values clean,
all 256x13 single flips, all 256xC(13,2) double flips, 23,792 cases, 0 failures; mutating
the decoder fails thousands of them, so the test has teeth).

#### `dual_port_ram_ecc.sv` (182 lines)
`dual_port_ram` widened to 13 bits with the encoder on the write side and the decoder on
the read side. Exposes `ecc_single_err` / `ecc_double_err` as combinational flags on the
current read data. Contains a build-time **fault injector**: define `ECC_INJECT_SBE` to
flip bit 0 of every codeword written, `ECC_INJECT_DBE` to flip bits 0 and 5. With neither
defined the write path is the bare encoder output and the normal bitstream is unchanged.
It is a `` `define `` rather than a parameter because a parameter would have to be
threaded through five hierarchy levels of already-proved modules. Formal: prove
(`assert_ram_address_integrity`, `cover_clean_read`; the plain-RAM path).

#### `async_fifo.sv` (187 lines)
The clock-domain-crossing FIFO. Two `gray_counter`s, two `sync_2stage`s for the pointers,
full computed on the write side from the synchronised read pointer, empty on the read
side from the synchronised write pointer. Also `almost_full` / `almost_empty` with
programmable thresholds and a `w_level` output.

Storage is split: the low 8 bits (`tdata`) go through `dual_port_ram_ecc`; any bits above
8 (`tlast`, `tdest`) go through a plain `dual_port_ram`. So the ECC covers the payload
only.

The raw decoder flags are qualified with `ecc_read_valid`, a one-cycle register set the
cycle after a real read. Without it the decoder runs on the uninitialised RAM output
before anything was written and raises a false alarm at power-up. The qualified flags
are one-cycle pulses; every consumer latches them sticky.

When `FORMAL` is defined the ECC RAM is replaced by a plain RAM and the flags are tied
to 0.

**Formal: none of its own, and this is an open gap (section 16).** `formal/async_fifo.sby`
reads the sub-modules with `-D FORMAL_TOP_INTEGRATION`, which switches their properties
off, and `async_fifo.sv` contains no assertions, so the "prove PASS" that script reports is
a proof with zero assertions in it (verified 2026-09-14: the generated model holds only
`$assume` cells). The pointer logic, full/empty, and ordering of the CDC FIFO are covered
by simulation and by silicon (zero sequence errors over millions of flits) but by no formal
property. `vc_input_buffer`'s shadow-FIFO proof covers `sync_fifo`, not this module.

#### `fwft_wrapper.sv` (175 lines)
Turns a standard FIFO read interface (data valid the cycle after `r_en`) into
first-word-fall-through (data valid whenever not empty). Implemented as a two-slot
output stage (`out` and `skid`) with a `data_arriving` register tracking the one-cycle
RAM latency, and a `can_read` rule that keeps at most two words in flight. Formal: prove
(`assert_no_overflow`, `assert_skid_physics`, `assert_empty_status`, reset asserts), run
through `async_fifo_fwft.sby`.

#### `async_fifo_fwft.sv` (109 lines)
`async_fifo` plus `fwft_wrapper` on the read side. This is what `gals_node_wrapper`
instantiates. Formal: `async_fifo_fwft.sby` passes prove, but the six assertions in its
model are `gray_counter`'s and `fwft_wrapper`'s; there is nothing about the FIFO itself
(same gap as above).

### 6.2 Router core

#### `packet_arbiter.sv` (235 lines)
The heart of the design and the site of bugs #1, #2 and #5. One instance per (output
port, VC). Inputs: `valid[PORTS]`, `tlast[PORTS]` from the input buffers that want this
output on this VC, and one `ready` from downstream. Output: one-hot `grant[PORTS]`.

Two states. In `IDLE`, a round-robin picker chooses `next_grant`: requests above the
current `mask` position win first (`masked_grant`), otherwise the lowest requester wins
(`unmasked_grant`), both via the isolate-lowest-set-bit trick `x & (~x + 1)`. If the
chosen flit is a single-flit packet (`tlast` and `ready` in the same cycle) the arbiter
stays in `IDLE`; otherwise it goes to `LOCKED` and remembers `locked_grant`.

In `LOCKED` the grant is frozen. Exits:

1. `eop_transfer`: the locked input transfers a flit with `tlast`. Normal.
2. `force_release`: the locked input has had `valid` low for `2**STALL_LOG` = 1024
   consecutive cycles **and** is still silent this cycle. The source is gone (bug #5).
3. Emergency unlock: nothing has ever transferred on this grant and the source has gone
   quiet. A head that was requested and then withdrawn.

`has_transferred` is what distinguishes 2 from 3. It is set at lock time if the very
first flit already went out in the same cycle (bug #1), and on every subsequent transfer.

`stall_cnt` counts only cycles where `valid` is low on the locked input. Downstream
backpressure keeps `valid` high, so a blocked but alive source can never trip the
timeout. Legitimate GALS gaps (a wrapper FIFO momentarily dry) are tens of cycles;
1024 is about 100x that. On the board, the 1024-cycle release shows up as a 608/611-cycle
gap on the surviving senders (campaign mode 1).

The round-robin `mask` advances on every `eop_transfer` (bug #2).

Formal: prove. `assert_onehot`, `assert_channel_lock` (while `LOCKED` and the locked
source still has data, grant does not change), `assert_abort_only_when_source_gone`.
Guarded by `` `ifndef FORMAL_TOP_INTEGRATION `` so the router-level run does not repeat
these.

#### `vc_port_arbiter.sv` (252 lines)
One per output port. Wraps two `packet_arbiter`s (VC1 and VC0) and decides which VC
drives the single physical output this cycle. Site of bug #3.

VC1 has strict priority: `vc1_is_active` gives VC1 the link and forces `ready_vc0 = 0`.
The fix for bug #3 made that decision depend on whether VC1 **can move** this cycle
(`|raw_grant_vc1 && ready_out_vc1`) rather than whether it merely holds a grant.

Anti-starvation: `starve_cnt` counts cycles VC0 has a request while VC1 is active; at
`STARVE_LIMIT` (64) it sets `vc0_override`, which hands the link to VC0. The override
clears when VC0 finishes a packet, or when VC0's request disappears (a safety net added
with the bug #3 fix so an override cannot outlive its cause). While overridden, VC1 is
only blocked if VC0 is itself making progress; if both are stuck VC1 gets the link back.

`SIM_DEBUG` enables `$display` tracing of override trigger/release; it was used to prove
the bug #3 diagnosis (51 triggers, 4 never released before the fix; 36/36 after).

Formal: prove. `assert_vc_mutex`, `assert_vc1_yields_when_stalled`,
`assert_no_vc1_during_override`, `assert_no_grant_without_credit`,
`assert_override_only_at_limit`, `assert_bounded_starvation` (the liveness argument: a
waiting VC0 is served within the limit), plus three invariants that tie the formal
shadow counters to the RTL ones.

#### `vc_input_buffer.sv` (241 lines)
One per router input port. Demultiplexes an incoming flit on `tid` into one of `NUM_VCS`
`sync_fifo`s (depth 16, 13 bits wide), and exposes the head of each VC's queue as a
separate `m_valid/m_tlast/m_tdest/m_tdata` set. `s_ready[v] = ~full[v]`. A flit is
written only when `s_valid && s_tid[v] && !full[v]`; a multi-hot `tid` would write one
flit into two queues, which is why one-hot is enforced upstream.

Formal: bmc depth 16, with a black-box **shadow FIFO**: the formal block keeps its own
model of what should be queued and checks the real head-of-queue against it every cycle
(`assert_head_tdata/tdest/tlast`). That single comparison covers the demux, the
pack/unpack slicing, and FIFO ordering. `assert_no_cross_vc_write`,
`assert_ready_iff_room`, `assert_valid_iff_occupied`. Bounded rather than proved because
induction can start from a shadow queue that disagrees with the real one.

#### `router_5port_mesh_vc.sv` (440 lines)
The router. Parameters `MY_X`, `MY_Y`. Five `vc_input_buffer`s, five `vc_port_arbiter`s,
and two combinational blocks:

- **XY decoder**: for each (input port, VC) with a valid head, compare
  `tdest` with `(MY_X, MY_Y)`: `dx > MY_X` → EAST, `dx < MY_X` → WEST, else
  `dy > MY_Y` → NORTH, `dy < MY_Y` → SOUTH, else LOCAL. Produces `route_req` which is
  then transposed to per-output request vectors for the arbiters.
- **Crossbar**: an AND-OR mux. For each output, OR together every input's data ANDed
  with that input's grant. Correct only when grants are one-hot per output, which the
  arbiters guarantee. `m_tid` is derived from which VC's arbiter granted.

The ready path back to the input buffers is the OR over outputs of "this output granted
me and its arbiter says ready".

Formal: bmc depth 16 with `abc bmc3` (z3 stalled at step 8 after 40 minutes; abc does 16
steps in 99 s). Properties in three groups: decoder (`assert_route_iff_valid`,
`assert_route_onehot`, `assert_eject_here`, `assert_no_false_eject`), arbitration
structure (`assert_grant_matches_route_*`, `assert_no_grant_fanout_*` which is the one
that would catch a cloned flit, `assert_ready_needs_grant_*`), crossbar
(`assert_xbar_onehot`, `assert_xbar_data/dest/last/valid_*`, `assert_tid_*`,
`assert_no_valid_without_grant`). The block is switched off with `-D FORMAL_NO_ROUTER`
when the mesh is proved, because its input assumptions would then land on driven internal
wires and could make everything pass vacuously. Its `f_wf` block still *assumes* constant
`tdest` per packet, which is correct for a standalone proof whose inputs are free; the
mesh enforces it upstream.

### 6.3 Mesh and GALS boundary

#### `noc_mesh_2x2_vc.sv` (634 lines)
Instantiates four routers with `(x, y)` from `idx = y*2 + x`, wires EAST↔WEST and
NORTH↔SOUTH between neighbours, and ties the off-board edges to `valid = 0`,
`ready = 0`. Exposes the four LOCAL ports as `s_*` (host into mesh) and `m_*` (mesh out
to host).

Sections 0 and 0b are the **ingress filters**: `dest_ok[i]` (x and y both ≤ 1) and
`tid_ok[i]` (exactly one bit set). Section 2.3 (2026-09-12) is the **constant-`tdest`
check** `frame_ok[i]`: a flit that targets a VC with an open packet must carry that
packet's recorded head destination. A flit failing any of the three is consumed but not
presented to the router, and the sticky per-node flag `dest_err[i]` (for `dest_ok` and
`frame_ok`: "this flit's destination is unacceptable") or `tid_err[i]` is raised. The flag
is raised when the bad flit is offered, not when it is accepted.

Section 2.2 is the **force-close** logic added for bug #7: per node and per VC,
`pkt_open` and `pkt_dest` track whether a packet has started and where it is going. A
rejected flit sets `close_pend` for every open VC. While any close is pending the node
presents a synthetic flit to the router (`tlast = 1`, `tid` = that VC, `tdest` = recorded
head dest, data 0) and holds `s_ready = 0` so the host cannot interleave. Closes go out
one per cycle because the LOCAL port takes one flit per cycle. The same tracker is what
the constant-`tdest` check compares against.

Formal: bmc depth 10 with `abc bmc3` (about 7 minutes), cover depth 12 with z3. The
environment no longer assumes one-hot `tid`, in-range `tdest`, or constant `tdest` per
packet; the solver sends anything and the filters have to cope. Headline properties:
`assert_eject_dest` (a flit ejected at node i is addressed to node i; this is what fails
if the index wiring is crossed, and what bug #7 broke), `assert_edge_*` (nothing drives
valid off the board), `assert_local_in_range` / `assert_local_tid_onehot` /
`assert_local_dest_stable` (everything the router sees on LOCAL is in range, one-hot, and
keeps its head's address), the filter asserts, and the force-close invariants
(`assert_close_pend_only_open`, `assert_host_held_while_closing`). Covers show every node
delivers, both links carry traffic, both VCs run at once, each of the three filters fires,
the mesh keeps delivering afterwards, and a synthetic tail is reached and delivered.

Parameters are shrunk for formal (`DATA_W=2`, `DEPTH=2`) and arrays are flattened with
`memory_map`; without that the solver does not finish.

#### `gals_node_wrapper.sv` (485 lines)
The GALS boundary, one per host. Takes two resets, `rst_host_n` and `rst_noc_n`. Four
`async_fifo_fwft`s: TX VC0/VC1 (written on `clk_host`, read on `clk_noc`) and RX VC0/VC1
(the reverse), each side reset by its own domain. The host writes into the TX FIFO
selected by `tid`; a combinational mux presents the head of TX VC1 if non-empty, else TX
VC0, as `m_noc_*` with the matching one-hot `m_noc_tid`. The mux does not lock per packet;
it interleaves flit by flit, which is legal because the far side demuxes on `tid` again.
Packet integrity within a VC is preserved by FIFO order. The RX side is symmetrical.

Host-side `tid` guard: `host_tid_ok` gates every TX write enable; a bad `tid` is consumed
and dropped and `host_tid_err` goes sticky. This is the layer that actually catches a
misbehaving host, because the mesh only ever sees the mux's by-construction one-hot `tid`.
The mesh-level guard stays as a second line. There is no host-side `tdest` check: `tdest`
passes through the mux unchanged, so the mesh ingress sees the host's value directly.

Force-close for bug #7, same tracker as the mesh: `tx_pkt_open`, `tx_pkt_dest`,
`tx_close_pend`. Because each VC has its own FIFO write port, both VCs can be closed in
the same cycle. `s_host_ready` is held low while a close is pending.

Flags: TX FIFO ECC flags are latched sticky on `clk_noc`; RX FIFO ECC flags and the host
`tid` error are latched on `clk_host` and crossed to `clk_noc` through a `sync_2stage`
(safe because sticky and straight from a register). Outputs `ecc_single_err`,
`ecc_double_err`, `host_tid_err`.

Formal: prove with `multiclock on` (a real two-clock proof), the two resets assumed equal
(the properties were written for a common reset; `reset_sync` releases the two within a
few idle cycles). Properties: the mux presents exactly the right VC's data, `tid` is
one-hot when valid and zero when idle, never pop an empty FIFO
(`assert_tx_no_pop_empty_*`, `assert_rx_no_pop_empty_*`, the ones that would catch
garbage-as-flit), ready equals not-full except while closing, no host write while
closing, close pending only for open VCs, external flags equal the OR of both domains'
latches. Covers reach the force-close path for one VC and for both.

#### `gals_noc_top.sv` (396 lines)
Glue plus flag aggregation. Takes five resets (`rst_n_noc`, `rst_n_h00..h11`). Four
`gals_node_wrapper`s, one `noc_mesh_2x2_vc`, the wiring between them, and the per-node
flag vectors (`ecc_sbe_node`, `ecc_dbe_node`, `dest_err_node`, `tid_err_node`) with
edge-counted totals (`ecc_sbe_cnt`, `ecc_dbe_cnt`, `dest_err_cnt`, `tid_err_cnt`), all
`mark_debug` + `dont_touch` so the ILA can see them. The `_cnt` values count nodes that
have ever raised the flag, not events, because the flags are sticky levels. The four
single-bit outputs (`ecc_single_err`, `ecc_double_err`, `dest_err`, `tid_err`) are the
OR of the node vectors **registered in `clk_noc`** before leaving; they used to be bare
ORs, which was CDC-10.

Two `axis_perf_mon`s watch host 00's TX and RX links and give the utilisation numbers
quoted everywhere. The monitor's `ready` is `|(tid & tready)`, the ready of the VC the
flit is actually on; an earlier version watched `tready[0]` only and counted every VC1
flit as a stall.

Formal: none (glue; covered by simulation and the board).

#### `axis_perf_mon.sv` (72 lines)
Four 32-bit counters on a valid/ready/last interface: flits transferred, packets
completed, stall cycles (valid without ready), active cycles. Utilisation is
`flit_cnt / active_cnt`.

### 6.4 Traffic and test agents

#### `traffic_gen.sv` (130 lines)
Simple command-driven packet source used by `tb_noc_mesh_2x2_gals`: given target x/y,
length and `tid`, it emits one packet. Not used on the board.

#### `traffic_node_agent.sv` (294 lines)
The board-side traffic source and checker, one per host. Site of bug #4 and of the
"green light that lied" (gotcha 2).

State machine `S_WARMUP → S_RUN → S_DRAIN → S_DONE`. During `S_RUN` it sends
`PKT_FLITS`-flit packets (16) back to back to `DEST_ID`, alternating VCs per packet under
`VC_MODE=2`, with a per-VC 6-bit sequence number in the payload (`tdata = {SRC_TAG,
seq}`). With `TX_EN=0` it is a pure sink (used for node 00 in the hot-spot pattern).

The RX side accepts at full rate (`rx_tready = 11`) and checks, per (source, VC), that
each received sequence number equals the previous plus one; a mismatch increments
`rx_err_cnt`. The check is per flit and 6-bit-modulo, which matters when interpreting
error counts after deliberate corruption: two lanes that each saw one jump give "2".

Liveness watchdog: `stuck_cnt` resets on every transfer during `S_RUN` and sets
`stuck_seen` after `2**STUCK_LOG` (65,536) silent cycles. `done` is gated on it, so the
pass LEDs cannot light on a dead fabric. `max_gap` records the longest silence actually
seen so thresholds are set from measurement, not guesses (measured worst: 136 cycles in
sim, 219 on the board).

Window end (bug #4 fix): the agent finishes its current packet before leaving `S_RUN`,
with `stuck_seen` as the escape if the fabric is dead.

`done` and `err` are **registered** (2026-09-12); they used to be `test_done &&
!stuck_seen` and a 32-bit compare feeding a synchroniser directly, which was CDC-10.

Counters (`tx_flit_cnt`, `rx_vc0_cnt`, `rx_vc1_cnt`, `rx_err_cnt`, `max_gap`, ...) are
`mark_debug` + `dont_touch` and are what `analyze_ila.py` reads.

#### `fault_injector.sv` (111 lines, added 2026-09-12)
Runtime fault injector between agent_11 and the fabric. Counts `2**FIRE_LOG` cycles from
reset (2^20 on the board, about 15 ms into the 235 ms window; 2^12 in the testbench),
then waits until a non-`tlast` flit is accepted so the fault lands mid-packet, then
applies the mode:

| mode | effect | for | exercises |
|---|---|---|---|
| 0 | none | | |
| 1 | `tvalid` forced 0 | permanently | bug #5 stall timeout |
| 2 | `tid = 00` | `HOLD` = 2000 cycles | tid guard (flit matches no VC) |
| 3 | `tid = 11` | 2000 | tid guard (flit would clone into both VCs), force-close |
| 4 | `tdest = 0001` (node idx2, in range) | 2000 | constant-tdest guard, force-close |
| 5 | `tdest = 1000` (x=2, off board) | 2000 | bug #6 range filter |

`tready` passes through, so agent_11 keeps advancing on its own `tid` exactly as the
testbench `force`s did; the fabric's reaction is what is under test, not the agent's
watchdog. `mode`/`arm` arrive from the VIO through a `sync_2stage` in `clk_h11`.
`active`, `fired` and `mode_dbg` are `mark_debug`. A deliberate side effect: routing
agent_11's `tdest` through a runtime mux stops synthesis constant-folding node 3's
destination filters, which is why `dest_err` is observable on the stress build at all
(section 10.8).

#### `noc_stress_tester.sv` (197 lines)
Instantiates four `traffic_node_agent`s with destinations chosen by `PATTERN`, each on
its own clock and reset:

- `PATTERN=0` permutation: 00↔11, 01↔10. Every flow has its own path; no output-port
  contention. Good for raw bandwidth, useless for arbiter testing.
- `PATTERN=1` hot-spot: 01, 10 and 11 all send to 00; 00 is a sink. This is the
  configuration that exposed bugs #3 and #4 and is used for every silicon regression.

agent_11's TX goes through `fault_injector`. `done`/`err` from the four clock domains are
crossed to `clk_h00` with a `sync_2stage` and combined into `pass_group1`, `pass_group2`,
`any_fail`. Exposes `fault_mode`/`fault_arm` inputs and `fault_active`/`fault_fired`
outputs.

#### `loopback_node_agent.sv` (150 lines)
Echo node for the UART build: whatever arrives on VC v is queued (depth 256, per VC with
independent credit) and sent back to node 00 on the same VC. Because every echo goes to
node 00, the three loopback nodes' destination filters are constant-folded in that build
(only node 00's, driven by the PC, is live).

#### `uart_transceiver.sv` (121 lines)
`uart_rx` and `uart_tx`, 8N1, parameterised by `CLK_FREQ` and `BAUD_RATE` (3 Mbaud on
the board).

#### `uart_noc_host.sv` (215 lines)
PC bridge for host 00. Protocol: **two bytes per flit**. Byte 0 is the header
`[7] tlast | [6:5] tid | [4] 0 | [3:0] tdest`, byte 1 is the payload. Incoming bytes go
through a 256-entry `sync_fifo`; a three-state parser assembles a flit and presents it to
the NoC until the flit's VC is ready. The reverse direction serialises each received
flit as header then data. The header's `tid` field is sent through unchanged, so the PC
must send one-hot values; `noc_host.py` was fixed on 2026-09-04 to do so. A `tid=00`
flit from the PC leaves this module waiting in `P_PUSH_NOC` for a `vc_ready` that never
comes; the fabric flags it, the bridge stalls until the next reset, and that is the
designed behaviour for a host that is sending garbage.

### 6.5 Board tops and IP

#### `arty_stress_top.sv` (225 lines)
MMCM, five `reset_sync`s, `vio_fault`, `gals_noc_top`, `noc_stress_tester`, LEDs.
Parameters `PATTERN` and `VC_MODE` are overridden from `setup_stress_build.tcl`. LED map
(`PATTERN=1`): `led[0]` heartbeat (`heartbeat_cnt[26]` on `clk_h00`, about 0.75 Hz);
`led[1]` all agents finished their window with liveness intact; `led[2]` finished and
node 00 saw no error; `led[3]` any of `any_fail`, ECC double-bit, `dest_err`, `tid_err`.
`led[1]` and `led[2]` are gated off by `led[3]`'s sources so a corrupt run cannot show
green. The VIO's input byte is section 3.6.

#### `arty_gals_noc_wrapper.sv` (167 lines)
MMCM (reset tied low since 2026-09-12), five `reset_sync`s, `gals_noc_top`,
`uart_noc_host` on host 00, three `loopback_node_agent`s. LEDs are activity indicators
(`led[1]` mirrors `uart_rxd`, `led[2]` mirrors `uart_txd`, `led[3]` any loopback node
transmitting), not verdicts.

#### `clk_wiz_0` (IP)
The MMCM, configured as in section 3.2. `.xci` tracked; output products regenerated by
Vivado.

#### `vio_fault` (IP, added 2026-09-12)
Xilinx VIO 3.0, one 8-bit output probe with initial value 0, one 8-bit input probe, on
`clk_h00`. Created by `hw_scripts/create_vio_fault.tcl` (one-off; the `.xci` is tracked).
Hardware Manager names its probes after the connected nets (`vio_out_1`, `vio_in_1`), not
after the IP ports, which `batch_fault_campaign.tcl` handles by looking them up by type.

### 6.6 Testbenches

#### `tb_noc_mesh_2x2_gals.sv` (615 lines)
The six-test regression, driven by `traffic_gen`s with a scoreboard (`sb_predict`) that
predicts what each node should receive and reports `Matched / Mismatched / Pending`.

| test | what it exercises | baseline `Matched` |
|---|---|---|
| 1 | one packet across the diagonal (two hops) | 4 |
| 2 | VC preemption: a 30-flit VC0 packet, then a 5-flit VC1 packet from another node to the same output; VC1 must overtake | 20 |
| 3 | random all-to-all with both VCs | 20 |
| 4 | three nodes send one packet each to the same destination; delivery under contention | 23 |
| 5 | starvation override: a 50-flit VC0 packet against ten 15-flit VC1 packets; VC0 must finish | 34 |
| 6 | **sustained** hot-spot: three nodes send back to back into node 0 with no gaps; asserts each source gets at least its share. Added 2026-08-18 because tests 1-5 prove delivery, not bandwidth sharing, and bug #2 was invisible to them | 136 (140 with `HS_VC_ALT`) |

Switches: `HW_CLOCKS`, `HS_VC_ALT` (test 6 alternates VCs like the board), `SIM_DEBUG`.
All four combinations of the first two must pass with `Mismatched=0 Pending=0`, and the
`Matched` totals must equal the baselines above; a change that moves them needs an
explanation.

#### `tb_noc_stress_tester.sv` (526 lines)
The board's stress build in simulation, with the same clock ratios and a window shrunk
from 2^24 to 2^18 cycles. Reports per-agent flit counts, `max_gap`, sequence errors,
`stuck`, the EAST/NORTH split at node 0's LOCAL arbiter, ECC counters, `dest_err`,
`tid_err`. Clean baseline: 142112 / 61104 / 81072 flits sent, 203504 received, worst gap
136, EAST 49% / NORTH 51%. Its predictions have matched the board to within a fraction of
a percent (bug #4 deltas), so it stands in for a board build when chasing this class of
problem.

Fault modes, all measurement modes that report `FAIL` on the sequence-error or fairness
line by design:

| parameter | what it does | note |
|---|---|---|
| `INJECT_ECC=1` | flips two bits in live FIFO data; the flag must reach the top and the endpoint must see errors (247) | the only end-to-end demonstration of data corruption under an uncorrectable error |
| `KILL_MIDPKT=1` | `force`s agent_11's `tvalid` low mid-packet | the original bug #5 reproduction |
| `BAD_TID=1/2` | `force`s node 11's `tid` to `00`/`11` for 2000 cycles | the original tid-guard measurement |
| `BAD_DEST=1` | `force`s node 11's `tdest` to `0001` for 2000 cycles | forces the true value back for one cycle before `release` (gotcha 11) |
| `FAULT_MODE=1..5` | drives `fault_injector` itself (no `force`), `FAULT_FIRE_LOG=12` | the same RTL path the board uses; reproduces every signature above |

#### `tb_ecc_secded.sv` (215 lines)
Exhaustive SECDED test, described under the encoder/decoder above.

#### `tb_traffic_node_agent.sv` (182 lines)
Ten liveness-watchdog checks: healthy, dead, dies midway, dies then revives, heavy
backpressure but alive (to catch a too-tight threshold). Reverting the `done` gating
fails six of ten.

### 6.7 Scripts and tooling

| file | purpose |
|---|---|
| `run_sim_regression.tcl` | runs `tb_noc_mesh_2x2_gals` from the Vivado project, writes `sim_logs/regress_<tag>_<stamp>.log` |
| `setup_stress_build.tcl` | switches the project to `arty_stress_top` with `PATTERN`/`VC_MODE`, adds `fault_injector.sv` / `reset_sync.sv` if missing, re-synthesises |
| `setup_uart_build.tcl` | same for `arty_gals_noc_wrapper` |
| `setup_debug.tcl` | builds ILA cores from `MARK_DEBUG` nets, one core per clock domain, writes `constrs_1/new/debug_auto.xdc`; replaces the GUI Set Up Debug wizard; reports constant-driven nets separately from unresolved ones |
| `analyze_ila.py` | reads exported `iladata*.csv`, computes throughput, utilisation, conservation, liveness, ECC, `dest_err`, `tid_err` verdicts, and explains why `dest_err_node` is absent on a stress build |
| `hw_scripts/batch_stress_synth_debug.tcl`, `batch_uart_synth_debug.tcl` | session A of the batch flow: synth + scripted Set Up Debug, then exit. Success marker is `SESSION_A_DONE` in the log, not the exit code (Vivado has crashed in its exit handler after finishing) |
| `hw_scripts/batch_impl.tcl <top>` | session B: implementation + bitstream in a fresh session, then `report_cdc` on the routed design with severity counts printed |
| `hw_scripts/batch_program_capture.tcl <dir> <top> [noprog]` | session C: program, Trigger Immediately on every ILA, CSV export |
| `hw_scripts/batch_fault_campaign.tcl <dir> [modes]` | program once, then per mode: VIO soft reset → mode + arm → release → 2 s → capture |
| `hw_scripts/summarize_campaign.py <dir>` | one row per mode with the deciding counters and the expected signature |
| `hw_scripts/create_vio_fault.tcl` | one-off creation of the VIO IP |
| `hw_scripts/batch_uart_session.tcl <dir>` | one hw_server session with a file handshake so PC-driven UART traffic can run between captures without the COM-port reset wiping counters |
| `hw_scripts/uart_roundtrip.py [pos\|neg]` | six positive round-trips (both VCs, all three loopback nodes) and the `tid=00` negative case |
| `hw_scripts/read_ila_flags.py <dir>` | last-sample dump of every flag/counter probe (for builds without agents) |
| `noc_host.py` | PC side of the UART build: send a packet, print echoes |
| `image_noc_test.py`, `video_noc_stream.py`, `bulk_test.py`, `vc_*_test.py`, `multi_node_stress_test.py`, `fault_recovery_test.py`, `single_probe_test.py` | UART demos and experiments; `recovered_from_fpga.png` is an image round-tripped through the fabric. Not regression-ised |
| `formal/*.sby` | one SymbiYosys script per RTL module (eleven), plus `run_wsl.sh` to run them from Git Bash on Windows |
| `combine_sv.py` | concatenates sources into `combined*.sv` for sharing |
| `hw_logs/` | every ILA capture that backs a number in `HANDOFF.md`, plus the after-fix CDC report |
| `sim_logs/` | regression logs; the `_FIXED` ones are the baselines |
| `sources_1/new/old/`, `final_src/`, `backup_20260804/` | historical. `old/` contains `.sby` files for a different project (`gals_mpmc_scalable`) that never verified anything here; `final_src/` is a stale July snapshot. Do not build from either |
| `constrs_1/new/arty.xdc`, `timing.xdc`, `debug_auto.xdc`, `debug.xdc` | pins; clock groups (the five clocks are asynchronous to each other); the script-generated ILA constraints; a legacy debug file removed from the fileset by the build scripts |
| `.gitattributes` | `*.sh` pinned to LF so `run_wsl.sh` survives a Windows checkout |

---

## 7. Life of a flit

### 7.1 One packet, end to end

Follow one 16-flit packet from agent_11 (idx 3, 71.43 MHz) to agent_00 (idx 0, sink)
in the hot-spot stress build. Node 11 is at (1,1); node 00 is at (0,0).

1. **Agent.** `traffic_node_agent` in `S_RUN` presents `tvalid=1`, `tdest=0000`,
   `tid=01` (VC0 this packet), `tdata={2'b11, seq}`, `tlast=0`, on `clk_h11`. It advances
   when `tready[0]` is high.

2. **Fault injector.** Mode 0: everything passes through unchanged, `tready` included.

3. **Wrapper host ingress** (`gals_node_wrapper`, `clk_h11`). `host_tid_ok` is true
   (`01` is one-hot), no close is pending, TX VC0 is not full, so `tx_host_acc[0]` fires:
   `{tlast, tdest, tdata}` is written into TX FIFO VC0. `tx_pkt_open[0]` becomes 1 and
   `tx_pkt_dest[0]` records `0000`. Inside the FIFO, `dual_port_ram_ecc` encodes the 8
   data bits to 13 and stores them; the 5 control bits go to the plain RAM. The write
   pointer increments in binary and gray.

4. **Clock crossing.** The gray write pointer passes through two flops on `clk_noc`.
   Two `clk_noc` cycles later the read side sees the FIFO as non-empty. `fwft_wrapper`
   pre-reads the word so it is already sitting on `rdata` when someone looks.

5. **Wrapper NoC egress** (`clk_noc`). TX VC1 is empty, TX VC0 is not, so the mux
   presents `m_noc_valid=1`, `m_noc_tid=01`, with the FIFO head's `tlast/tdest/tdata`.
   The FIFO pops when `m_noc_ready[0]` is high. On the pop, the decoder checks the 13-bit
   word; if a bit had flipped it would be corrected and `tx_sbe[0]` would pulse, to be
   latched sticky.

6. **Mesh ingress** (`noc_mesh_2x2_vc`, sections 0/0b/2.2/2.3, node 3). `dest_ok[3]`:
   x=0, y=0, both ≤ 1, true. `tid_ok[3]`: true. `frame_ok[3]`: VC0 has a packet open
   with `pkt_dest[0]=0000`, this flit says `0000`, true. Not closing. So
   `r_valid[3][LOCAL]` follows `s_valid[3]` and the fields pass straight through.

7. **Router 3, LOCAL input buffer.** `vc_input_buffer` writes the packed flit into its
   VC0 `sync_fifo`. `s_ready[LOCAL][0]` was `~full`, and that is what the wrapper saw as
   `m_noc_ready[0]` in step 5.

8. **Router 3, XY decoder.** Head of VC0 at LOCAL: `dx = 0 < MY_X = 1` → request
   **WEST**. `route_req[LOCAL][0][WEST] = 1`, transposed into `req_out_vc0[WEST][LOCAL]`.

9. **Router 3, WEST output arbiter.** `vc_port_arbiter` for WEST: VC1's
   `packet_arbiter` has no requests. VC0's is `IDLE`, sees `valid[LOCAL]`, picks it
   (`next_grant = 00001`), and since `tlast` is 0 it goes `LOCKED` on LOCAL with
   `has_transferred` set if the flit moved this cycle. `vc1_can_move` is false, so
   `vc1_is_active` is false, so `ready_vc0 = ready_out_vc0 = m_ready[WEST][0]`, which is
   router 2's EAST input buffer's VC0 `~full`.

10. **Router 3, crossbar.** `grant_vc0[WEST] = 00001`, so `m_*[WEST]` = the LOCAL VC0
    head, `m_tid[WEST] = 01`. `buf_ready[LOCAL][0]` = `ready_from_arb_vc0[WEST]`. The
    input FIFO pops.

11. **Link 3→2.** `noc_mesh_2x2_vc` wires `m_*[3][WEST]` to `r_*[2][EAST]`. Same clock,
    no crossing.

12. **Router 2.** EAST input buffer VC0 → decoder: `dx = 0 = MY_X`, `dy = 0 < MY_Y = 1`
    → **SOUTH**. SOUTH arbiter locks on EAST. Crossbar drives `m_*[SOUTH]`, wired to
    `r_*[0][NORTH]`.

13. **Router 0.** NORTH input buffer VC0 → decoder: `dx = 0`, `dy = 0`, both equal →
    **LOCAL**. Here is the contention: agent_01's packets arrive on router 0's EAST port
    and agent_10's and agent_11's on NORTH (they merged at router 2), all wanting LOCAL.
    The LOCAL `packet_arbiter` for VC0 round-robins between EAST and NORTH per packet;
    the stress tester measures this split at 49/51, the board at 48.3/51.7. Our packet,
    once granted, holds LOCAL for all 16 flits.

14. **Mesh egress → wrapper 0 RX.** `m_*[0][LOCAL]` becomes `s_noc_*` of wrapper 0. RX
    VC0 FIFO written on `clk_noc`, gray pointer crosses to `clk_h00`, `fwft_wrapper`
    pre-reads, the RX mux presents it as `m_host_*` with `m_host_tid = 01`.

15. **Sink.** agent_00's `rx_tready = 11`; each flit is checked against
    `exp_seq[src=11][vc=0]`, counted into `rx_vc0_cnt`, and resets `stuck_cnt`. The
    16th flit carries `tlast`; at every arbiter along the way `eop_transfer` fires, the
    lock releases, the round-robin mask advances, and at both ingress trackers
    `pkt_open[0]` clears.

Latency for one hop is roughly: FIFO write, two synchroniser cycles, FWFT pre-read, one
cycle in the input buffer, one in the crossbar. The per-hop cost inside the mesh is one
`sync_fifo` stage; the expensive part is the two GALS crossings at the ends.

### 7.2 One rejected flit (campaign mode 4)

Same setup, but the injector is active with mode 4: the flit leaving agent_11 says
`tdest=0001` while VC0's packet to `0000` is open.

1. **Wrapper host ingress.** `tid` is one-hot, so the wrapper accepts the flit into TX
   VC0 as any other body flit. (The wrapper has no `tdest` check; it does not need one.)
2. **Mesh ingress, node 3.** `dest_ok` true (in range), `tid_ok` true, **`frame_ok` false**:
   VC0 is open with `pkt_dest[0]=0000` and this flit says `0001`. `reject` = 1. The flit
   is consumed (`s_ready` still reflects the router's ready) and not presented.
   `dest_err[3]` goes sticky. `close_pend[0]` is set because VC0 is open.
3. **Next cycle, closing.** `s_ready[3]` is forced to 0; the router's LOCAL port is
   presented with a synthetic flit: `tlast=1`, `tid=01`, `tdest=0000`, data 0. When the
   input buffer accepts it (`r_rdy`), `close_pend[0]` and `pkt_open[0]` clear.
4. **Downstream.** Router 3's WEST arbiter, locked on LOCAL for this packet, sees the
   synthetic `tlast` and releases. The truncated packet (its flits so far plus a zero
   tail) reaches node 00; the sink sees one sequence jump on this lane.
5. **The following flits** from agent_11 say `0001` too (the injector holds 2000 cycles).
   `pkt_open[0]` is 0, so the first of them is a **new head** with `pkt_dest[0]=0001`;
   `frame_ok` is true for the rest. They route to node idx2 (agent_10), which counts
   them (1777 on the board) as a fresh stream from source 11.
6. **Injector releases.** agent_11's `tdest` returns to `0000` mid-packet: `frame_ok`
   false again, one more reject, one more `dest_err` offer (the flag is already sticky;
   `dest_err_cnt` counts nodes, so it stays 1), one more synthetic close, and the next
   flit is a new head to `0000`. The sink sees its second sequence jump. From here on
   everything is normal.

Before bug #7 the flit in step 2 would have been dropped and nothing else: the packet on
VC0 would stay open, and the next head would have ridden its grant to `0000` while
saying `0001`. Before the constant-`tdest` guard, step 2 would not have rejected at all,
and the router would have sent the `0001` flit out the port locked for `0000`.

### 7.3 One reset (stress build, soft reset from the VIO)

1. Hardware Manager writes `vio_out[0] = 1`. The VIO's output register on `clk_h00`
   drives `srst` of all five `reset_sync`s.
2. Each `reset_sync` synchronises `srst` through two flops of its own clock and pulls
   its `rst_n` low: five domains go into reset within a few of their own cycles, in no
   particular order. Nothing is being transferred at this point in the campaign, so the
   order does not matter; the design does not rely on it.
3. The script writes mode and arm with the reset still held, then clears `vio_out[0]`.
   Each domain releases two of its clocks later, still in no particular order.
4. Every `traffic_node_agent` starts in `S_WARMUP` and idles for 1024 cycles; the async
   FIFO pointers on both sides are 0; nothing is presented to the fabric. This idle is
   what made the old unsynchronised deassert survivable.
5. `S_RUN` starts; the injector's counter is at a few hundred and will fire at 2^20.

A button press behaves the same except that step 1 is the asynchronous `arst_n` input,
so assertion is immediate in every domain; deassertion is still synchronised per domain.

---

## 8. Every defect found

### 8.1 The seven numbered RTL bugs

In the order they were found. For each: what was seen, how it was found, why it
happened, what changed, how it was checked. `HANDOFF.md` has the measurement tables; this
has the story.

#### Bug #1: the arbiter released a port mid-packet

**Found by** simulation, before the git history. Recorded in the comments of
`packet_arbiter.sv`.

**Symptom.** Packets from two inputs interleaved on the same VC of the same output.
The receiver saw flits of packet B in the middle of packet A.

**Cause.** `packet_arbiter` had an emergency unlock: if the locked input's `valid`
dropped, release the port. That is right for a request that was withdrawn before
anything moved, but in a GALS system a source's `valid` drops routinely for a cycle or
two whenever its wrapper FIFO runs momentarily dry. The arbiter treated every such gap as
"source gone" and released mid-packet.

A second, subtler piece: at lock time the arbiter set `has_transferred <= 0`. But in
`IDLE` the grant is already combinationally active, so if `ready` was high the first flit
went out in the same cycle the lock was taken. The next cycle the FIFO could be dry,
`has_transferred` said nothing had moved, and the emergency unlock fired.

**Fix.** The emergency unlock is gated on `!has_transferred`, and `has_transferred` is
initialised at lock time to "did the first flit go out this cycle". Once anything has
moved on a grant, only `tlast` (or, later, the bug #5 timeout) releases it.

**Checked by** the six-test regression (test 2 and 4 in particular), and since
2026-09-04 by `assert_channel_lock` in `formal/packet_arbiter.sby`: while `LOCKED` and
the locked source still has data, `grant` does not change. That property was actually
false on the original code and nobody knew, because the `.sby` that claimed to cover the
arbiter pointed at a module from a different project.

#### Bug #2: round-robin starvation

**Found by** simulation, commit `2ac2e05` (2026-08-18).

**Symptom.** With three sources contending for one output, one source took ~100% and the
others starved. Tests 1-5 did not see it because they send one packet each and stop;
test 6 (sustained contention) was written to expose it.

**Cause.** The round-robin mask was only advanced when the winner had won "from the
mask" (`current_from_mask`), the intent being not to penalise a source that won by
falling through to the unmasked picker. In practice: after a high-numbered port won, the
mask pointed at ports nobody was requesting, `masked_req` was zero, the unmasked picker
chose the lowest port, `current_from_mask` was 0, the mask never moved again, and the
lowest port kept winning. It does not show when all ports request together, only when a
subset does, which is every real case.

**Fix.** Advance the mask on every `eop_transfer`, unconditionally.

**Checked by** test 6 (min share per source ≥ threshold) and later on the board:
node 0's LOCAL arbiter splits EAST 48.3% / NORTH 51.7% (49/51 in sim). The apparent
50/25/25 per-agent split is topology (two agents share NORTH), not the arbiter.

#### Bug #3: the two VCs cross-blocked each other

**Found by** simulation and confirmed on hardware, commits `04cd562`, `e1571ba`
(2026-08-19), `cba4e60` (2026-09-01).

**Symptom.** Node 00's LOCAL port utilisation was 100% with VC0 only, 57.5% with
alternating VCs, on the board. In simulation the alternating case collapsed and then
deadlocked (`Pending` never reached zero).

**Cause** (`vc_port_arbiter.sv`). VC1 owned the shared output whenever its
`packet_arbiter` **held a grant**, and while VC1 owned it `ready_vc0` was forced to 0.
The two VCs have independent downstream credits, so a VC1 packet stalled on a full
downstream VC1 buffer blocked VC0 even though VC0's own downstream buffer had room. The
VC separation the design was built for was undone at the output mux.

The anti-starvation override made it worse: it took 64 idle cycles to fire, and it only
released when VC0 completed a whole packet. If VC0 then stalled, the override latched and
now VC1 was blocked. Blocking in both directions is a circular wait.

**Fix.** VC1 owns the link only on cycles it can actually move a flit
(`vc1_can_move = |raw_grant_vc1 && ready_out_vc1`). When its credit runs out it yields
that cycle and VC0 takes the link. The override only blocks VC1 while VC0 is itself
making progress (`&& vc0_can_move`); if both are stuck, VC1 gets the link back. Plus a
release path when VC0's request disappears. Interleaving VC0 and VC1 flits on one physical
link is fine because the downstream buffer demuxes on `tid`.

**Checked by** the regression in all four configurations (TB clocks alternating: 9.5% →
77.8%; HW clocks alternating: 44.5% → 97.2%), the `SIM_DEBUG` override trace (4 latched
overrides → 0), out-of-context synthesis (no latches, 76 ps timing cost, ~100 LUTs per
router), formal (`assert_vc1_yields_when_stalled`, `assert_no_vc1_during_override`), and
the board: 57.5% → **97.0%**, VC split 50/50.

#### Bug #4: the agent truncated a packet at window end and wedged a port

**Found by** the liveness watchdog on its first hardware run, commit `8fd67c7`
(2026-09-01).

**Symptom.** A board run showing 97.0% utilisation and zero sequence errors reported
`liveness FAIL` on agent_01 and agent_11, the two 71.43 MHz nodes. It looked like a false
positive. It was not.

**Cause** (`traffic_node_agent.sv`). The agent left `S_RUN` the instant its cycle
counter saturated, and `tx_tvalid` is `(state == S_RUN)`, so it could drop valid
mid-packet. Half a packet was left in the fabric with no `tlast` behind it. The
downstream `packet_arbiter` was `LOCKED` on that input with `has_transferred = 1`, so
the bug #1 guard kept it locked forever. Because windows count cycles, not time, the
faster nodes finish first; whichever stops first strands a packet that kills the port
for everyone still running. Measured at node 00's LOCAL port with the fabric silent:
locked on NORTH (nothing there), EAST has data and starves.

**Fix.** Finish the current packet before leaving `S_RUN`
(`win_full && (tx_fire && last_flit)`), with `stuck_seen` as the escape if the fabric is
dead. A sink has no packet to finish and leaves immediately.

**Checked by** `tb_noc_stress_tester` (agent_01 worst gap 37,171 → 41; agent_11 37,245
→ 106; +16% and +33% flits) and the board (+16.4% and +32.9%, liveness PASS, total
injected 69.3 → 80.2 MB/s). Simulation predicted each delta to within a fraction of a
percent.

Bug #4 was in the test agent, not the fabric. The fabric fragility it exposed is bug #5.

#### Bug #5: a source that vanishes mid-packet locks the port forever, and the fix had a hole

**Found by** simulation (`KILL_MIDPKT=1`) and then formal, commit `e9f8197` (2026-09-04).

**Symptom.** Cutting agent_11's `tx_tvalid` mid-packet: both surviving senders into node
00 saturated their gap counters at 8,388,609 cycles. One node dying took down every flow
through that port, until global reset.

**Cause.** After bug #1's fix, once `has_transferred` is set the only exit from `LOCKED`
was `eop_transfer`, which needs a `tlast` that a dead source never sends.

**Fix.** A timeout: `stall_cnt` counts consecutive cycles where the locked input has
`valid` low; at `2**STALL_LOG` (1024) the arbiter releases. Backpressure keeps `valid`
high, so a blocked-but-alive source cannot trip it. Legitimate GALS gaps are tens of
cycles.

**The hole formal found.** `stall_cnt` is a register. If the source came back with a
real flit on exactly the cycle the counter hit its maximum, `force_release` fired with
data present: a mid-packet release, bug #1 again. Simulation never hit the one-cycle
window. The fix gates the release on the source being silent in the same cycle
(`&& !(|(locked_grant & valid))`), pinned by `assert_abort_only_when_source_gone`.

**Checked by** `formal/packet_arbiter.sby` passing `prove` (basecase and induction, so
unbounded), `KILL_MIDPKT` (survivors keep running with gaps of 886 and 1104), the
regression unchanged, and on 2026-09-12 by campaign mode 1 on silicon: the survivors'
gap is 608/611 cycles and the fabric stays alive.

#### Bug #6: an off-board destination hangs the whole fabric

**Found by** formal on the mesh, commit `a9a0fd2` (2026-09-04).

**Symptom.** In the mesh's formal environment, removing the assumption that `tdest`
stays on the board made `assert_edge_*` fail: a router drove `valid` off the edge.

**Cause.** `tdest` is 4 bits and accepts x or y up to 3, but the mesh is 2x2. A flit
with x=2 makes every router see `dx > MY_X` and send it EAST; at the east edge
`m_ready` is tied to 0, so the flit stalls there forever, holding its arbiter's lock and
head-of-line blocking everything behind it. No flag, no timeout. A single host with a
typo in `tdest` could hang the fabric.

**Fix.** `dest_ok[i]` at the mesh ingress. A bad flit is consumed and dropped, and a
sticky per-node `dest_err[i]` is raised. Two alternatives were rejected: dropping
`ready` moves the stall to the sender; clamping the address delivers the packet somewhere
nobody intended, silently. Reporting follows the ECC path (per-node flag → `gals_noc_top`
aggregate → ILA counter → `led[3]`, which also gates the pass LEDs off).

**Checked by** the mesh formal run with the range assumption removed and `s_tdest`
free over all 16 values (`assert_edge_*` holds, `assert_bad_dest_blocked` and
`assert_good_flit_passes` added, covers show the filter fires and the mesh keeps
delivering), `tb_noc_stress_tester` reporting `DEST: err_cnt=0` on clean traffic with
numbers identical to before, and on silicon by campaign mode 5 (`dest_err` node `1000`,
nothing delivered, fabric alive). Note that every earlier "`dest_err_cnt` 0 on the
board" reading was structural, not evidence (section 8.2).

An incidental fix came with it: `arty_stress_top.sv` declared two nets after the
instance that drove them, which Vivado synthesis tolerated and `xvlog` did not.

#### Bug #7: a rejected flit eats its packet's `tlast`

**Found by** formal on the mesh, root-caused 2026-09-11 (`31d4cba`), fixed the same
day (`de8cac3`), confirmed on the board 2026-09-12.

**Symptom.** After the `tid` guard was added (2026-09-10), the mesh formal environment
still could not drop its one-hot-`tid` assumption: `assert_eject_dest` failed at step 4,
node 0 ejecting a flit with `tdest = 0100`. The first write-up guessed the crossbar's
AND-OR mux was ORing two flits because a non-one-hot grant got through. That guess was
wrong; zeroing the rejected flit's entire payload did not make the failure go away.

**Cause.** Decoding the counterexample stimulus at node 0:

| step | tid | tdest | tlast | filter | effect |
|---|---|---|---|---|---|
| 1 | `10` | `0000` | 0 | pass | opens a VC1 packet to node 0 |
| 2 | `11` | `0000` | **1** | dropped | the only `tlast` for that packet is gone |
| 3 | `10` | `0100` | 0 | pass | appended to the still-open packet, rides its grant, ejected at node 0 |

The ingress filters (both `dest_ok` and `tid_ok`, at both the mesh and the wrapper)
dropped a rejected flit by simply not presenting it. `packet_arbiter` knows packet
boundaries only from `tlast` passing through. If the dropped flit was the tail, the
packet on that VC stayed open, the next accepted head became a body flit of it, went
wherever the old head was addressed, and meanwhile the destination router's grant was
held. Confirmed by isolation: assuming a rejected flit never carries `tlast` made BMC
pass twelve steps with the one-hot assumption still removed.

Two things made it broader than the assertion showed. The wrapper's host-side guard had
the same shape, and there the consequence is misdelivery to the node the previous packet
was addressed to. And the `dest_err` filter had the same hazard; the argument that
`tdest` is constant per packet is something the host must honour, not something the RTL
enforces, and a host that garbles `tid` is not a host to trust with framing.

**Fix** ("design A, force-close on reject"). Track `pkt_open` / `pkt_dest` per VC at
each ingress. On a rejected flit, write a synthetic `tlast` (recorded head dest, data 0)
into every open VC and hold the host off until it lands. The truncated packet arrives
short at the correct node; `dest_err` / `tid_err` are raised as before; the next packet
starts as a clean head. The alternative ("B", close only the VC the bad flit appears to
target) was rejected as more logic for a benefit that only matters when the host is
already sending garbage.

**Checked by:**

- Mesh formal with the one-hot assumption **removed**: bmc depth 10 PASS,
  `assert_eject_dest` holding on its own; covers reach the force-close and a synthetic
  tail arriving.
- Wrapper formal with its one-hot assumption removed: prove PASS basecase + induction;
  covers reach a single and a double force-close.
- Six-test regression in both clock configurations, totals identical to the `_FIXED`
  baselines. Stress tester clean run identical to before.
- `BAD_TID` runs, comparing the pre-fix RTL and the fix: the other three agents'
  `max_gap` went from **1209 / 886 / 1104** cycles to 65 / 41 / 150. Before the fix, one
  bad flit from one host was a ~1100-cycle stall for every other node, on top of the
  misdelivery; that stall was in the pre-fix data all along (the same 886/1104 appear in
  the `KILL_MIDPKT` numbers of bug #5) and had not been recognised for what it was.
- On the board (2026-09-12): clean run identical to the pre-fix clean run, which is the
  point; then campaign modes 2 and 3 with the guard in place.

The sequence-error count under `tid=11` moved from 1 to 2; the checker is per-flit and
6-bit-modulo so that number is "how many VC lanes saw a jump that was not a multiple of
64", which shifts with a one-cycle timing change. It is not a regression signal. The
misdelivery itself cannot be shown in this simulation because every agent has a fixed
destination; that rests on the proof.

#### What the seven have in common

Four of them (#1, #4, #5, #7) are the same sentence from section 2.3: a port is held
until `tlast`, and something made `tlast` not arrive or arrive for the wrong packet.
Two (#3 and #2) are arbitration policy that looked right and was wrong under sustained
contention. One (#6) is an address range nobody checked. None of the first three was
caught by the original five simulation tests or by the permutation hardware run; they
would have shipped. Every later one was found by a check written specifically because
the previous bug showed a blind spot: test 6 after #2, the liveness watchdog after #3,
formal after #4, dropping assumptions one at a time after formal existed.

### 8.2 The defects that were not numbered

These are not RTL bugs in the fabric's datapath, but each one was a real defect in the
design, the tests, the tooling, or the verification claims, and each cost time or would
have. They are listed here so nobody rediscovers them.

| # | where | what | found by | fixed |
|---|---|---|---|---|
| A | `gals_node_wrapper`, `arty_gals_noc_wrapper` | ECC error outputs left unconnected: uncorrectable errors detected and discarded, corrupt data flowed on silently | reading the top | 2026-09-03: wired end to end to counters and `led[3]` |
| B | `dual_port_ram_ecc` | The ECC alarm path had never been shown to work on silicon; a 0 counter looked the same as a disconnected one | reasoning about evidence | 2026-09-10: build-time injector, `ecc_sbe_cnt = 3`, node `1111` on the board; double-bit 2026-09-12 |
| C | `traffic_node_agent` | Pass LEDs lit on a deadlocked fabric: `done` came from a cycle counter | the `VC_MODE=2` board run | liveness watchdog, `done` gated on observed transfers |
| D | `loopback_node_agent`, `uart_noc_host` | Every ILA tap behind `` `ifdef DEBUG_BUILD ``, which nothing defined; the UART build had zero instrumentation | reading the UART top | guards deleted, probes unconditional, `dont_touch` added |
| E | `noc_host.py` | Sent the VC *number* in the `tid` field; `vc_id=0` became `tid=00` and every VC0 packet vanished silently | UART round-trip on the board | 2026-09-04: one-hot header |
| F | `arty_stress_top` | Reset button also reset the MMCM, killing the ILA clocks | first ILA capture | MMCM reset tied low (UART top got the same fix 2026-09-12) |
| G | `sources_1/new/old/*.sby` | `arbiter_formal.sby` and `mpmc.sby` targeted a module from another project; HANDOFF's claim that bug #1 was formally guarded was false | writing `packet_arbiter.sby` | first real arbiter proof 2026-09-04, and it found bug #5's hole |
| H | `gals_noc_top`, `traffic_node_agent` | Sticky flags OR-reduced / gated in a LUT straight into a `sync_2stage` (CDC-10 ×5): a LUT glitch would be captured as a permanent false alarm | first `report_cdc` run, 2026-09-12 | registered in the source domain |
| I | both tops | One unsynchronised async reset into every flop of every domain (CDC-7 ×572 once a clocked source touched the net); survived on the 1024-cycle warm-up idle | `report_cdc` after adding the VIO soft reset | `reset_sync` per domain, per-domain reset ports |
| J | stress build, `dest_err` | The destination filters were constant-folded away because the agents' `tdest` is a parameter; every `dest_err_cnt = 0` reading was structural, and one silicon claim in the docs was vacuous | tracing the "unclocked" `dest_err_node` probe to a `LUT1` of `GND` | injector mux makes node 3 live; `setup_debug.tcl` reports constants; docs corrected |
| K | `formal/async_fifo.sby`, `async_fifo_fwft.sby` | "prove PASS" with zero assertions of the FIFO's own (sub-modules read with their properties disabled); the CDC FIFO has no formal properties | cataloguing labels for this document, 2026-09-14 | **open** (section 16) |
| L | `tb_noc_stress_tester` `BAD_DEST` | `release` on a `logic` driven by a constant keeps the forced value forever; node 11 fired at the wrong node for the whole window | fairness reading 56/44 | force the true value for a cycle first |
| M | `setup_debug.tcl` and the GUI flow | six separate Vivado traps: wizard writes into the pins file, `save_constraints` misorders cores, clock lookup silently narrows probes, stale cores follow a build switch, `debug_auto.xdc` read by synthesis, deleted cores leave their clocks, implementation in the same session ignores the new xdc | each by a broken capture | all handled in `setup_debug.tcl` / the batch flow |
| N | PC side | Opening the COM port resets the FPGA (FTDI DTR/RTS), wiping sticky flags and counters | counters reading "2 seconds old" after a minute | read the ILA before the next port open; `batch_uart_session.tcl` |
| O | Vivado 2025.2 | Crash in the exit handler after `close_project`, outputs already written, exit code 139 | one session A | batch scripts use the `SESSION_A_DONE` marker |
| P | `xelab.bat` | `-generic_top "X=2"` mangled on Windows shells | trying to pass `BAD_TID` | wrap the testbench in a one-line top |
| Q | `HANDOFF.md` | Said the arbiter could not recover from a truncated packet, months after bug #5's timeout | writing this document | corrected |
| R | GitHub | PR #7's merge commit was created but the PR record stayed open and "dirty" | trying to merge | branch re-synced with `main`, record closed normally |

---

## 9. How it is verified

### 9.1 Simulation

Three testbenches plus the stress tester, section 6.6. Run from the Vivado project
(`run_sim_regression.tcl`) or straight off the sources with `xvlog`/`xelab`/`xsim`;
section 17 gives the compile order. Pass criteria for the six-test regression: 6/6,
`Mismatched=0`, `Pending=0`, in all four `HW_CLOCKS` × `HS_VC_ALT` combinations, with the
`Matched` totals of section 6.6. The checked-in `_FIXED` logs are the baselines.

Every RTL change on 2026-09-11/12 was followed by the full regression in both clock
configurations plus the stress tester's clean run, and every one came back number-for-
number identical. That identity is the regression signal; the fault modes are
measurements, not pass/fail.

### 9.2 Formal

SymbiYosys under WSL (`Ubuntu-24.04`, OSS CAD Suite in `/opt/eda/oss-cad-suite`:
Yosys 0.68, SBY 0.68, Z3 4.15.5). One script per module in `formal/`, eleven modules,
22 tasks, all green at `afce6cd`, with the caveat in row K above.

#### Property catalogue

Every labelled assertion and cover, by module. Unlabelled asserts (`gray_counter`,
`sync_2stage`) are described in prose.

**`packet_arbiter` (prove, unbounded)**

| property | meaning |
|---|---|
| `assert_onehot` | `grant` is one-hot or zero |
| `assert_channel_lock` | while `LOCKED` and the locked source still has data, `grant` does not change (the bug #1 property; false on the original RTL) |
| `assert_abort_only_when_source_gone` | `force_release` never fires while the locked source has `valid` high (the bug #5 hole) |

**`vc_port_arbiter` (prove, unbounded)**

| property | meaning |
|---|---|
| `assert_vc_mutex` | VC0 and VC1 never both drive the output in one cycle |
| `assert_vc1_yields_when_stalled` | VC1 does not own the link on a cycle it cannot move (bug #3) |
| `assert_no_vc1_during_override` | while VC0's override is active and VC0 can move, VC1 is blocked |
| `assert_no_grant_without_credit` | no grant is passed downstream without the corresponding `ready_out` |
| `assert_override_only_at_limit` | `vc0_override` rises only when `starve_cnt` reached `STARVE_LIMIT` |
| `assert_bounded_starvation` | a waiting VC0 is served within the limit (the liveness argument, expressed as a bound) |
| `assert_inv_starve_cap`, `assert_inv_wait_cap`, `assert_inv_sync` | shadow-counter invariants that tie the formal counters to the RTL ones so induction closes |
| covers | `cover_vc1_preempts`, `cover_override_activated`, `cover_override_completed`, `cover_override_released_on_idle`, `cover_vc0_uses_link_while_vc1_stalled` |

**`vc_input_buffer` (bmc depth 16)**

| property | meaning |
|---|---|
| `assert_head_tdata`, `assert_head_tdest`, `assert_head_tlast` | the head of each VC's queue equals what the shadow FIFO says was written there: nothing lost, duplicated, reordered or cross-laned |
| `assert_no_cross_vc_write` | a flit with `tid[v]=0` never lands in VC v |
| `assert_ready_iff_room` | `s_ready[v]` is exactly "count < DEPTH" |
| `assert_valid_iff_occupied` | `m_valid[v]` is exactly "count > 0" |
| `assert_inv_cnt_cap` | shadow count never exceeds `DEPTH` |
| covers | `cover_flit_through`, `cover_eop_out`, `cover_fifo_full`, `cover_both_vcs_busy`, `cover_vc0_full_vc1_open` |

**`router_5port_mesh_vc` (bmc depth 16, `abc bmc3`)**

| property | meaning |
|---|---|
| `assert_route_iff_valid` | a (port, VC) requests an output iff its head is valid |
| `assert_route_onehot` | exactly one output requested per valid head |
| `assert_eject_here` | a head addressed to this router requests LOCAL |
| `assert_no_false_eject` | a head not addressed here never requests LOCAL |
| `assert_grant_matches_route_vc0/1` | a granted input is one that requested that output (with `tdest` constant per packet assumed in `f_wf`) |
| `assert_no_grant_fanout_vc0/1` | no input is granted by two outputs at once (a cloned flit otherwise) |
| `assert_ready_needs_grant_vc0/1` | credit returns to an input only when it holds a grant |
| `assert_xbar_onehot` | crossbar select one-hot across inputs and VCs |
| `assert_xbar_data/dest/last/valid_vc0/1` | output fields equal the granted input's head |
| `assert_tid_vc0/1`, `assert_tid_idle` | `m_tid` names the granting VC; zero when nothing is granted |
| `assert_no_valid_without_grant` | no output `valid` without a grant behind it |
| covers | `cover_eject_local`, `cover_forward_east`, `cover_turn_xy`, `cover_two_outputs`, `cover_both_vcs` |

**`noc_mesh_2x2_vc` (bmc depth 10, `abc bmc3`; cover depth 12, z3)**

| property | meaning |
|---|---|
| `assert_eject_dest` | a flit ejected at node i's LOCAL is addressed to node i (the property bug #7 broke) |
| `assert_eject_tid`, `assert_eject_tid_onehot0` | ejected `tid` is one-hot when valid, never multi-hot |
| `assert_edge_north/south/east/west` | no router drives `valid` off the board |
| `assert_bad_dest_blocked` | a flit with out-of-range `tdest` never reaches the router (a synthetic tail may) |
| `assert_frame_err_blocked` | a flit whose `tdest` differs from its open packet's head never reaches the router |
| `assert_good_flit_passes` | a flit that passes all three filters is presented (the filter does not over-reject) |
| `assert_local_in_range`, `assert_local_tid_onehot`, `assert_local_dest_stable` | everything entering via LOCAL, synthetic flits included, is in range, one-hot, and carries its packet head's address (the property the router's `f_wf` assumes) |
| `assert_close_pend_only_open` | never synthesise a `tlast` into a VC with no open packet |
| `assert_host_held_while_closing` | `s_ready` is 0 while a close is pending |
| covers | delivery at all four nodes, both links busy, both VCs at once, each filter raised (`cover_dest_err_raised`, `cover_tid_err_raised`, `cover_frame_err_raised`), mesh alive after a bad dest, `cover_force_close`, `cover_deliver_after_close` |

**`gals_node_wrapper` (prove, unbounded, `multiclock on`)**

| property | meaning |
|---|---|
| `assert_tx_valid_iff_data`, `assert_rx_valid_iff_data` | the mux asserts valid exactly when some FIFO is non-empty |
| `assert_tx_pick_vc1/vc0`, `assert_rx_pick_vc1/vc0` | strict priority: VC1 first, and the `tid` says so |
| `assert_tx_data_vc1/vc0`, `assert_rx_data_vc1/vc0` | the presented fields are the chosen FIFO's head |
| `assert_tx_idle_tid`, `assert_rx_idle_tid` | `tid` is zero when idle |
| `assert_tx_tid_onehot`, `assert_rx_tid_onehot` | one-hot when valid |
| `assert_tx_no_pop_empty_vc0/1`, `assert_rx_no_pop_empty_vc0/1` | `r_en` never pops an empty FIFO (garbage-as-flit) |
| `assert_host_ready_map_vc0/1`, `assert_noc_ready_map_vc0/1` | ready equals not-full (host side: and not closing) |
| `assert_no_host_write_while_closing` | host writes are blocked while a close is pending |
| `assert_close_pend_only_open` | pending closes only for open VCs; not gated on `f_past_valid` on purpose (induction artefact otherwise) |
| `assert_ecc_sbe_out`, `assert_ecc_dbe_out` | external flags are the OR of both domains' latches |
| covers | `cover_tx_vc1`, `cover_tx_vc0`, `cover_rx_vc1`, `cover_both_paths`, `cover_vc0_waits_behind_vc1`, `cover_tx_force_close`, `cover_tx_force_close_both` |

**`fwft_wrapper` (prove, via `async_fifo_fwft.sby`)**: `assert_no_overflow` (never more
than two words in flight), `assert_skid_physics` (the skid slot is only filled when the
output slot is), `assert_empty_status` (the user-facing empty reflects the output
register), `assert_reset_out/skid/arr` (reset clears all three).

**`dual_port_ram_ecc` (prove)**: `assert_ram_address_integrity`, `cover_clean_read`.

**`gray_counter` (prove)**: after reset both are zero; `ptr_g == bin ^ (bin >> 1)`
always; on an enabled step exactly one bit of `ptr_g` changes, on a disabled step none;
the MSB flips on wrap. Cover: the wrap (depth 40).

**`sync_2stage` (prove)**: reset clears both stages; `assert_stage2` (output equals the
input two edges ago); `cover_data_pass`.

**`async_fifo`, `async_fifo_fwft`**: see row K in section 8.2. The scripts pass; they
contain no properties of the FIFO's own.

#### Conventions

- `FORMAL` blocks live inside the RTL under `` `ifdef FORMAL ``. A module's own block is
  disabled with `` `ifndef FORMAL_TOP_INTEGRATION `` (arbiters, counters) or
  `-D FORMAL_NO_ROUTER` (router) when a parent is being proved, so assumptions never land
  on driven wires. The flip side is row K: a parent script that reads every sub-module
  with the guard set and has no properties of its own proves nothing, and `sby` will
  happily report PASS.
- Modules with unpacked-array ports need the slang frontend (`plugin -i slang;
  read_slang`); slang has no `$onehot`, hence the `f_onehot` helpers, and it names assert
  cells from labels, so labels inside plain `for` loops must be in `generate` blocks.
- `memory_map` flattens FIFO arrays; without it z3 does not finish.
- Router and mesh use `abc bmc3` for bmc; z3 is used for cover and for every `prove`.
- `prove` means k-induction passed and the property is unbounded. `bmc` means bounded;
  the three bounded modules tie arbiter or shadow state to FIFO contents, which induction
  can violate from an unreachable start state. The bounded depths go deep enough to fill
  and drain the queues several times.
- State-only invariants must not be gated on `f_past_valid`; induction will start in the
  bad state while the assert is off.
- Assumptions are removed as soon as the RTL enforces the property. `tdest` range (bug
  #6), one-hot `tid` (bug #7) and constant `tdest` (2026-09-12) all went from assumption
  to proof in the mesh environment.

Two properties written during this work turned out to be wrong and the runs said so:
`assert_idle_tid` (stricter than AXI4-Stream allows) and the ECC sticky-latch asserts
(vacuous and induction-breaking). Both are recorded in `HANDOFF.md` so nobody re-adds
them.

### 9.3 Silicon

Flow (all batch, section 17): `batch_stress_synth_debug.tcl` → `batch_impl.tcl` (fresh
session, ends with `report_cdc`) → `batch_program_capture.tcl` or
`batch_fault_campaign.tcl` → `analyze_ila.py` / `summarize_campaign.py`.

The ILA carries about 1123 `MARK_DEBUG` bits across five cores (one per clock domain):
every agent counter, the perf monitors, the ECC/`dest_err`/`tid_err` nodes and counters,
`stuck_seen`/`max_gap`, and the injector's `active`/`fired`/`mode`. `analyze_ila.py`
computes throughput per agent in MB/s (each agent's window is a different wall-clock
length, gotcha 4), link utilisation, a conservation check (flits in = flits out), the
arbiter split, and verdicts for liveness, ECC, `dest_err` and `tid_err`. It says
"unprovable" rather than "pass" when a probe is missing, and it explains a missing
`dest_err_node` on a stress build.

`report_cdc` runs on every routed design since 2026-09-12. Its expected output is CDC-3
(1-bit synchronised), CDC-6 (the 37 gray pointers), CDC-9 (the two ILA reset
synchronisers) and CDC-15 (FIFO RAM read ports and ILA internals); anything Critical is
printed by the impl script as `CDC_CRITICAL_PRESENT` and must be explained before the
bitstream is trusted.

Every number in `HANDOFF.md` has a log in `hw_logs/`. The lesson that shaped all of it:
**a green light must be evidence, not absence of evidence.** The pass LEDs used to light
on a deadlocked fabric; `done` now requires flits to have moved, the pass LEDs are gated
off by every error flag, every analyser verdict says "unprovable" when its probe is
absent, the ECC path was proved by injecting faults, and the destination filters were only
counted as demonstrated once a runtime mux made them impossible to fold away.

### 9.4 Coverage matrix

What each mechanism is covered by. "sim" means a testbench reproduces the failure and the
fix; "formal" names the script; "silicon" names the log.

| mechanism | sim | formal | silicon |
|---|---|---|---|
| packet lock held for the whole packet (bug #1) | regression tests 2, 4 | `packet_arbiter` `assert_channel_lock` | every clean run (0 seq errors) |
| round-robin fairness (bug #2) | test 6 | (policy; not a formal property) | EAST/NORTH 48.3/51.7 |
| VC independence + starvation override (bug #3) | test 5, `HS_VC_ALT` | `vc_port_arbiter` | 57.5% → 97.0%, VC 50/50 |
| agent finishes its packet (bug #4) | `tb_noc_stress_tester` | | liveness PASS, +15.7% |
| stall timeout releases an orphaned port (bug #5) | `KILL_MIDPKT`, `FAULT_MODE=1` | `packet_arbiter` `assert_abort_only_when_source_gone` | campaign mode 1 (gap 608/611) |
| off-board `tdest` rejected (bug #6) | `FAULT_MODE=5` | mesh, range `assume` removed | campaign mode 5 |
| rejected flit closes its packet (bug #7) | `BAD_TID`, `FAULT_MODE=2/3` | mesh + wrapper, one-hot `assume` removed | campaign modes 2, 3 |
| one-hot `tid` guard | `BAD_TID`, `FAULT_MODE=2/3`, UART `neg` | mesh + wrapper | campaign 2/3, UART `tid=00` |
| constant `tdest` guard | `BAD_DEST`, `FAULT_MODE=4` | mesh `assert_local_dest_stable` | campaign mode 4 |
| ECC correct/detect | `tb_ecc_secded` exhaustive | (`dual_port_ram_ecc` address only) | `ECC_INJECT_SBE` / `_DBE` builds |
| ECC alarm reaches counters and LEDs | `INJECT_ECC` | | `ecc_sbe_cnt=3` node `1111`; `ecc_dbe_cnt=3` |
| liveness watchdog | `tb_traffic_node_agent` 10/10 | | first board run caught bug #4 |
| async FIFO pointer/ordering correctness | every regression, indirectly | **none** (row K) | 0 seq errors over millions of flits |
| reset deassert synchronised per domain | | | `report_cdc` Critical 0 |
| UART byte integrity, both VCs, all nodes | | | `uart_roundtrip.py` 6/6 |

---
## 10. On the board: hardware-specific behaviour

Everything above is true in simulation as well. This section is what is only true, or
only visible, on the Arty. Resource numbers are from the 2026-09-10 stress build (the
last one whose utilisation report was kept); timing and CDC numbers are from the
2026-09-12 fault-campaign build; everything else from the logs in `hw_logs/`.

### 10.1 What the bitstream contains

| | |
|---|---|
| part | xc7a100tcsg324-1 (Arty A7-100T, Digilent 210319C088F2A) |
| top | `arty_stress_top`, `PATTERN=1 VC_MODE=2` |
| clocking | one `MMCME2_ADV`: 100 MHz in, VCO 1000 MHz (mult 10), outputs divided by 12.5 / 10 / 14 / 12 / 14 |
| slice LUTs | 10,898 of 63,400 (17%) |
| slice registers | 16,244 of 126,800 (13%) |
| block RAM tiles | 31.5 of 135 (23%) |
| timing (09-10) | WNS +0.711 ns, WHS +0.014 ns, TPWS +3.0 ns; every constraint met |
| timing (09-12, campaign build) | WNS **+0.977 ns**, WHS +0.016 ns; `report_cdc` Critical 0 |
| debug (09-12) | 1126 `MARK_DEBUG` nets → 5 ILA cores / 61 probes / 1123 bits, plus `dbg_hub` and `vio_fault` |

Most of the block RAM is ILA capture memory, not the fabric. The fabric's own storage is
small: each router has 5 ports x 2 VCs x 16 entries x 13 bits in distributed RAM, and
each wrapper has 4 async FIFOs of 16 x 13 bits. The MMCM is the only clock resource.

For comparison, the UART build (`arty_gals_noc_wrapper`) closes at WNS +0.326 ns (09-12,
with reset synchronisers; +1.204 before) with 484 `MARK_DEBUG` nets in 5 cores, CDC
Critical 0. Across every build the worst path is the same one: router 0's input-buffer
read pointer → crossbar → wrapper 00's RX FIFO RAM, 8 logic levels, ~80% routing. WNS
moves by a few hundred picoseconds between builds from placement alone; none of the RTL
changes on 2026-09-12 touched that path.

### 10.2 The five clocks are declared asynchronous, so STA does not check between them

`timing.xdc` is one statement: `set_clock_groups -asynchronous` over the five MMCM
outputs. Vivado therefore analyses timing **within** each domain and ignores every path
**between** domains. That is correct for this design, and it means correctness at the
boundaries is not something the timing report can confirm. It comes from construction:

- multi-bit data crosses only inside `async_fifo`, through RAM addressed by pointers
  that are gray-coded and passed through `sync_2stage`, so a pointer sampled mid-change
  is at worst one step stale;
- single-bit flags cross only if they are sticky (set once, never cleared), through
  `sync_2stage`;
- `sync_2stage`'s output register carries `ASYNC_REG = "TRUE"`, which tells Vivado to
  place the two flops in the same slice and not to optimise them apart.

Anything that crosses domains by another route is a bug the timing report will not flag.
`report_cdc` is the tool that does, and since 2026-09-12 `batch_impl.tcl` runs it on every
routed design. Its first run found five criticals, all one pattern: a sticky flag
OR-reduced or gated in a LUT and fed straight into a two-flop synchroniser (`|ecc_dbe`,
`|tid_err_node`, `test_done && !stuck_seen`). A LUT can glitch while its inputs change
and the synchroniser captures the glitch as a real 1, so a sticky error flag could
false-alarm. Fixed by registering the result in the source domain first. The remaining
report entries are the gray pointers (CDC-6), the FIFO RAM read ports (CDC-15) and the
reset synchronisers (CDC-9), all expected.

Simulation has no metastability. Every crossing in xsim resolves cleanly whatever the
phase. The board is the only place the synchroniser design is actually exercised, and
the evidence that it works is indirect: zero sequence errors over 3.9 million flits per
sender, every run.

### 10.3 Reset and power-up

`global_rst_n = rst_n_btn & pll_locked`. The design is held in reset until the MMCM
locks, and the button resets the logic only. The MMCM's own reset is tied to 0 in both
tops: an earlier build wired the button to it, and pressing the button killed all five
clocks, including the one `dbg_hub` and the ILAs run on, so every capture died with the
reset.

Since 2026-09-12 that net feeds five `reset_sync`s, one per clock (section 3.5), so each
domain's flops leave reset on their own clock edges. The VIO soft reset is a synchronous
input to each `reset_sync`. Before this, `global_rst_n` went straight to every flop's
async clear in all five domains, and `report_cdc` showed 572 unsynchronised reset
deasserts the moment a clocked source (the VIO) was ANDed into it. The design had
survived because of the warm-up idle described below.

RAM contents are not reset (Xilinx RAM primitives cannot be), which is why `async_fifo`
qualifies the ECC flags with `ecc_read_valid`: before the first real read the decoder is
looking at whatever the RAM powered up with.

`traffic_node_agent` starts in `S_WARMUP` for `2**WARMUP_LOG` = 1024 cycles before
sending anything, to let the async FIFOs on both sides come out of reset and the
synchronisers settle. Then `S_RUN` for `2**WINDOW_LOG` = 16,777,216 cycles, `S_DRAIN`
for 4096, then `S_DONE` where every counter freezes. The ILA is read after `S_DONE`;
`analyze_ila.py` reports the `state` column so a capture taken too early is obvious.

### 10.4 The same window is a different length on every node

`WINDOW_LOG` counts cycles of the agent's own clock:

| agent | clock | 2^24 cycles = |
|---|---|---|
| agent_00 (sink) | 100.00 MHz | 168 ms |
| agent_10 | 83.33 MHz | 201 ms |
| agent_01, agent_11 | 71.43 MHz | 235 ms |

Three consequences, all of which cost time before they were understood:

- Raw flit counts are not comparable across agents. `analyze_ila.py` converts to MB/s
  using each agent's own frequency and does a conservation check (flits in = flits out)
  over the overlap instead.
- The sink stops **first**, 67 ms before the slowest senders. Whatever those senders do in
  the last 67 ms is not counted at the sink. The 97.0% utilisation figure is node 00's
  window, which closes before the tail effects begin.
- Senders stop at different times, and whichever stops first while a packet is in flight
  leaves that packet stranded. That stagger is exactly what triggered bug #4 on the two
  71.43 MHz nodes and nowhere else. Simulation with `HW_CLOCKS` reproduces the stagger;
  simulation with the default clocks does not, which is why both are in the regression.

### 10.5 Where the bottleneck actually is

The sink runs at 100 MHz and always asserts `rx_tready = 11`; the NoC runs at 80 MHz and
delivers at most one flit per cycle per LOCAL port. So the sink never backpressures and
node 00's LOCAL output is the hard limit: 80 Mflit/s. The board measures 77.6 Mflit/s
delivered = **97.0%**. The senders together offer 80.2 MB/s and see 46-77% stall on their
own TX links, which is the arbiter telling them to wait, not a fault.

The three senders split the port 48.3 / 24.2 / 27.5%. That is not arbiter unfairness:
node 0's LOCAL arbiter sees two input ports, EAST (agent_01 alone) and NORTH (agent_10
and agent_11, already merged at router 2), and splits those 48.3 / 51.7. Simulation says
49 / 51. Within NORTH, agent_11 gets more than agent_10 partly because its window is
17% longer in wall-clock time (section 10.4 again).

### 10.6 Real GALS gaps

In simulation the worst silent stretch any sender sees is 136 cycles; on the board it is
**219** (`max_gap`, 2026-09-04 run; 219 / 40 / 138 / 108 per agent). The difference is
real clock jitter and phase drift the simulator does not model. Two thresholds are set
against this number:

- `STUCK_LOG = 16` → 65,536 cycles ≈ 300x the measured worst gap, so the liveness
  watchdog cannot false-trip on a legitimate gap. The first guess (2^16 borrowed from
  a different module) happened to be fine; the point of `max_gap` is that it is no longer
  a guess.
- `STALL_LOG = 10` in `packet_arbiter` → 1024 cycles of *source silence* before a locked
  port is abandoned, ≈ 5x the worst gap ever seen at the agent level and far above the
  tens-of-cycles gaps seen at a router input when a wrapper FIFO runs dry.

### 10.7 What the LEDs mean (stress build)

| LED | meaning |
|---|---|
| `led[0]` | heartbeat, `heartbeat_cnt[26]` on `clk_h00`, about 0.75 Hz. The design is alive and clocked |
| `led[1]` | `pass_group1` and no ECC double-bit, no `dest_err`, no `tid_err`. `PATTERN=1`: every agent finished its window with liveness intact |
| `led[2]` | `pass_group2` under the same gates. `PATTERN=1`: finished and node 00 saw zero sequence errors |
| `led[3]` | `any_fail` or ECC double-bit or `dest_err` or `tid_err` |

Two rules behind this table. A green LED needs positive evidence: `done` requires flits
to have moved during `S_RUN` (the liveness watchdog), so a deadlocked fabric shows
`led[1]`/`led[2]` dark, where it used to show them lit. And every error flag that means
"data did not arrive or is corrupt" turns the green LEDs **off**, not merely the red one
on. Both came from the same incident: a `VC_MODE=2` build showed green on a fabric that
had deadlocked.

The flags reach the LEDs through a `sync_2stage` from `clk_noc` to `clk_h00`, safe
because they are sticky. A single-bit ECC error (corrected) does not touch the LEDs at
all; it is visible only in the ILA counters.

The UART build's LEDs are activity indicators (`led[1]` mirrors `uart_rxd`, `led[2]`
mirrors `uart_txd`, `led[3]` is any loopback node transmitting). No verdict there.

### 10.8 The ILA: what you can and cannot see

One ILA core per clock domain, because a core samples on one clock. `setup_debug.tcl`
groups nets by the clock of their driving flop and merges `name[n]` bits into one
wide probe. The cores are read with **Trigger Immediately** after the run has settled,
so every value is a final, frozen count; there is no waveform-style capture of the
traffic itself.

Things that only show up here:

- A counter that reads 0 means either "nothing happened" or "the net was swept and the
  probe is on a stub". `mark_debug` alone does not stop synthesis removing a
  fanout-free register; `dont_touch` does. Every counter in the design now has both,
  and `analyze_ila.py` says "unprovable" rather than "pass" when a probe is missing.
- The ECC counters were 0 on every run until 2026-09-10, and that proved nothing until a
  bitstream with `ECC_INJECT_SBE` read `ecc_sbe_cnt = 3`, `node_sbe = 1111`,
  `ecc_dbe_cnt = 0` with traffic still error-free. Now a 0 means silent. The double-bit
  injector has only been run in simulation.
- `dest_err_node[3:0]` is missing from the stress build's ILA because it is **constant**:
  every agent's `tx_tdest` is the parameter `DEST_ID`, synthesis proves the destination
  filters can never reject anything, deletes the `dest_err` register, and `dont_touch`
  leaves a buffer of ground with no clock. `dest_err_cnt` reads 0 for the same reason. A
  probe that is constant by construction is not evidence; `setup_debug.tcl` now lists such
  nets separately. `tid_err_node` is live because `tid` alternates per packet.
- Since the fault injector muxes agent_11's `tdest` at runtime, `dest_err_node[3]` is
  live and `dest_err` has been observed on a stress bitstream (campaign modes 4 and 5).
  Bits `[2:0]` are still constant, and `setup_debug.tcl` lists them under "constant after
  synthesis" rather than "no clock".
- The `MARK_DEBUG` net count is the fingerprint of what was instrumented: 924 (original),
  928 (+watchdog), 1024 (+`max_gap`), 1064 (+ECC), 1084 (+`dest_err`), 1104
  (+`tid_err`), 1126 (+injector). Any other number means Set Up Debug was not re-run
  after an RTL change, and the analyser will refuse to pass liveness.

### 10.9 The build flow has state that follows you

These are the traps in section 15 restated as behaviour, because on the board they look
like RTL bugs:

- Implementation run in the same Vivado session that just wrote `debug_auto.xdc` builds
  a bitstream with **no ILA and no error**. Session A: synth + `setup_debug.tcl`.
  Session B: implement.
- `open_run synth_1` loads the previous build's `debug_auto.xdc`, so switching between
  the stress and UART tops carries the old cores along; the script deletes them first.
- `debug_auto.xdc` must be `USED_IN = implementation` only, or synthesis bakes the old
  cores into the netlist and the clock names come back as `u_ila_0_clk_out1_clk_wiz_0`.
- Deleting a debug core does not delete the clocks it created in that session.
- `verilog_define {ECC_INJECT_SBE}` persists in the project; clear it after the injection
  build or the next "normal" bitstream is not normal.

### 10.10 UART build specifics

Host 00 is a UART bridge at 3 Mbaud on a 100 MHz clock (33.3 clocks per bit). Two bytes
per flit means at most ~150 kflit/s in either direction, three orders of magnitude below
the fabric, so the UART path never exercises contention; it exercises addressing, VC
selection, packet framing and byte integrity. What was shown on the board: a 149-byte
packet to node 3 on VC1 echoes back byte-identical with `tlast` in the right place;
all four (destination, VC) combinations round-trip; ECC and `dest_err` counters read 0
over 1024 ILA samples; and a `tid = 00` flit (the pre-fix `noc_host.py` behaviour) never
comes back, which is the silent-drop that the `tid` guard now flags. The demo scripts
(`image_noc_test.py`, `video_noc_stream.py`) push an image and a video stream through the
same path; `recovered_from_fpga.png` is the result.

Host-side: run `python -u`, set `PYTHONIOENCODING=utf-8`, and check `COM_PORT`.

### 10.11 Simulation vs silicon, side by side

| quantity | simulation | board |
|---|---|---|
| node 00 LOCAL utilisation, `VC_MODE=2` after bug #3 | 97.2% | 97.0% |
| bug #4 fix, agent_01 / agent_11 throughput delta | +16% / +32.9% | +16.4% / +32.9% |
| node 0 LOCAL split EAST / NORTH | 49 / 51 | 48.3 / 51.7 |
| VC split at the sink | 50 / 50 | 50.0 / 50.0 |
| worst `max_gap` (cycles) | 136 | 219 |
| sequence errors, clean run | 0 | 0 |
| ECC single-bit injection, `ecc_sbe_cnt` | 3 | 3 (`node_sbe = 1111`) |
| ECC double-bit injection, `ecc_dbe_cnt` | 3 | 3 (`node_dbe = 1111`), 0 seq errors (two flips of the same bit cancel across TX and RX FIFOs) |
| kill agent_11 mid-packet, survivors' `max_gap` | 871 / 1087 | 608 / 611 |
| `tdest=0001` for 2000 cycles, flits redirected to agent_10 | 1787 | 1777 |

`tb_noc_stress_tester` with `HW_CLOCKS` predicts the board to within a fraction of a
percent on every throughput figure, and is pessimistic only on the gap. That is what
justifies treating a passing stress run as evidence before a board is available.

### 10.12 Opening the COM port resets the board

Found 2026-09-12 while re-running the UART build. `serial.Serial('COM3')` from the PC
toggles the FTDI's DTR/RTS and the Arty's reset circuit follows, so every host script
starts by resetting the fabric: sticky flags clear, `mon_*` counters restart, a wedged
`uart_noc_host` recovers. Opening the JTAG target does not do this (two captures 5 s
apart in one session advance `mon_active_cnt` by 5.1 s). So: read the ILA before the
next port open, and take all captures of one experiment in one `hw_server` session.
`hw_scripts/batch_program_capture.tcl` with `noprog` does that.

The same session showed what a `tid=00` flit from the PC does: nothing echoes,
`tid_err_cnt` 1 / `node` `0001`, and `uart_noc_host` sits in `P_PUSH_NOC` with
`mon_stall_cnt` climbing one per cycle until the next reset. Flagged and attributed, not a
fabric hang.

### 10.13 Fault-injection campaign

One bitstream, one JTAG session, six modes, `hw_scripts/batch_fault_campaign.tcl`. Each
mode: VIO soft reset, set mode + arm, release, wait 2 s for the 235 ms window, Trigger
Immediately on every ILA. Full log in `hw_logs/fault_campaign_20260912.log`; the
deciding numbers:

| mode | fault | `max_gap` 00/01/10/11 | seq err | `tid_err` | `dest_err` | flits at agent_10 |
|---|---|---|---|---|---|---|
| 0 | none | 217 / 38 / 119 / 105 | 0 | 0 | 0 | 0 |
| 1 | `tvalid` cut mid-packet, permanent | 217 / **608** / **611** / 105 | 0 | 0 | 0 | 0 |
| 2 | `tid = 00`, 2000 cycles | 217 / 40 / 119 / 106 | 2 | node `1000` | 0 | 0 |
| 3 | `tid = 11`, 2000 cycles | 218 / 55 / 166 / 106 | 2 | node `1000` | 0 | 0 |
| 4 | `tdest = 0001`, 2000 cycles | 217 / 61 / 119 / 105 | 2 | 0 | node `1000` | 1777 |
| 5 | `tdest = 1000` (off board), 2000 cycles | 218 / 46 / 119 / 106 | 2 | 0 | node `1000` | 0 |

Reading it: cutting agent_11 mid-packet costs the other senders one 608/611-cycle gap
(the bug #5 release at 1024 `clk_noc` cycles, expressed in each agent's own clock) and
nothing else; before bug #5 this was a permanent wedge. Every bad `tid`/`tdest` is
dropped, flagged with the right node, and the other agents' gaps stay at their clean
values. The two sequence errors in modes 2-5 are the two truncation points (entering and
leaving the 2000-cycle hold), one resync per affected lane. Mode 4's 1777 flits at
agent_10 are the redirected packets, which arrive as a clean new stream. `stuck` reads
0000 even in mode 1 because the injector passes `tready` through and agent_11 keeps
"firing" into it; the fabric's reaction, not the agent's watchdog, is what is being
tested. The 2 s wait is generous: the window ends at ~235 ms and the ILA reads frozen
counters.

### 10.14 Silicon status at `afce6cd`

Every mechanism in section 4 has a silicon demonstration; the coverage matrix in 9.4 lists
them. The last board runs were on 2026-09-12: the fault campaign (stress build, all six
modes), the clean stress run with the CDC fixes (97.0%, WNS +0.977), and the UART build
with per-domain resets (6/6 round-trips, `tid=00` flagged). Both builds report `report_cdc`
Critical 0. Every build, program and capture since 2026-09-12 has been done by the batch
scripts in `hw_scripts/`, no GUI.

---


---

## 11. Parameters and knobs

Everything that can be changed without editing logic, where it lives, its default, and
what else has to move with it. Widths are in bits, depths in entries, `*_LOG` values are
powers of two.

### 11.1 Fabric

| parameter | module(s) | default | meaning | coupled to |
|---|---|---|---|---|
| `DATA_W` | `noc_mesh_2x2_vc`, `router_5port_mesh_vc`, `vc_input_buffer`, `gals_node_wrapper` | 8 | flit payload width | the ECC is hard-wired to 8 bits (`dual_port_ram_ecc` splits `[7:0]` off); `async_fifo` only ECC-protects the low 8 bits; `traffic_node_agent` packs `{SRC_TAG, seq}` into 8; the UART protocol is 2 bytes/flit. Changing it is a project, not a parameter tweak (section 13.4) |
| `CORD_W` | same | 2 | coordinate width; `tdest` is `2*CORD_W` | the mesh is hard-coded 2x2 in `noc_mesh_2x2_vc` (four router instances, `MAX_X/MAX_Y = 1`); `CORD_W` alone does not grow the mesh |
| `NUM_VCS` | same, `vc_port_arbiter` (fixed at 2 by its two arbiters) | 2 | virtual channels | `vc_port_arbiter` and the wrapper mux are written for exactly two |
| `DEPTH` | `vc_input_buffer`, `gals_node_wrapper`, mesh, router | 16 | per-VC FIFO depth (router input buffers and wrapper async FIFOs) | `ADDR_WIDTH = $clog2(DEPTH)` in the async FIFOs; the formal mesh run shrinks it to 2 |
| `PORTS` | `packet_arbiter`, `vc_port_arbiter` | 4 (5 in the router) | requesters per arbiter | |
| `STALL_LOG` | `packet_arbiter` | 10 | a locked port is abandoned after `2**STALL_LOG` cycles of source silence (bug #5) | must stay far above legitimate GALS gaps (measured ≤ 219 agent cycles); on the board it shows as a ~610-cycle gap to the survivors |
| `STARVE_LIMIT` | `vc_port_arbiter` | 64 | cycles VC0 may wait behind an active VC1 before the override | `assert_bounded_starvation` |
| `MY_X`, `MY_Y` | `router_5port_mesh_vc` | 0, 0 | router coordinates; set by the mesh from `idx = y*2 + x` | |
| `MAX_X`, `MAX_Y` | `noc_mesh_2x2_vc` (localparams) | 1, 1 | the range filter's bound | change with the mesh size |
| `ADDR_WIDTH` | `async_fifo`, `gray_counter`, `dual_port_ram*` | 4 | FIFO address bits; pointers are one bit wider | |
| `DATA_WIDTH` | `async_fifo*`, `fwft_wrapper`, `sync_fifo`, `dual_port_ram*` | 8 / 13 | storage word; the wrappers use `PACK_W = 13` | |
| `WIDTH` | `sync_2stage` | 5 | synchroniser width | |

### 11.2 Traffic agents and stress build

| parameter | module(s) | default | meaning | note |
|---|---|---|---|---|
| `PATTERN` | `arty_stress_top`, `noc_stress_tester`, `tb_noc_stress_tester` | 0 (top), 1 (tb) | 0 permutation, 1 hot-spot into node 00 | every silicon regression uses 1 |
| `VC_MODE` | same, `traffic_node_agent` | 2 | 0 VC0 only, 1 VC1 only, 2 alternate per packet | 2 is the mode that exposed bug #3 |
| `DEST_ID`, `SRC_TAG` | `traffic_node_agent` | per instance | where to send, what to stamp in `tdata[7:6]` | `DEST_ID` is a constant, which is why `dest_err` folds away for nodes without the injector |
| `PKT_FLITS` | `traffic_node_agent` | 16 | flits per packet | the sequence field is 6 bits, so the checker is modulo 64 |
| `TX_EN` | `traffic_node_agent` | 1 | 0 makes a pure sink | node 00 under `PATTERN=1` |
| `WINDOW_LOG` | `traffic_node_agent`, `noc_stress_tester`, `analyze_ila.py` | 24 (board), 18 (tb) | `S_RUN` length in the agent's own cycles | `analyze_ila.py` must agree with the RTL |
| `WARMUP_LOG` | same | 10 | idle cycles after reset before sending | this idle is what made the old unsynchronised reset survivable |
| `DRAIN_LOG` | same | 12 (board), 8 (tb) | idle cycles after the window | |
| `STUCK_LOG` | same | 16 (board), 23 (tb) | liveness threshold; `2**STUCK_LOG` silent cycles in `S_RUN` = dead | ~300x the measured worst gap; the tb sets it high on purpose to measure, not to trip |
| `GAP_W` | same | 24 | width of `max_gap` so it can report values beyond the threshold | |
| `FAULT_FIRE_LOG` | `noc_stress_tester` → `fault_injector.FIRE_LOG` | 20 (board), 12 (tb) | injector fires `2**FIRE_LOG` `clk_h11` cycles after reset | must land inside `S_RUN`: 2^20 ≈ 15 ms into a 235 ms window |
| `HOLD` | `fault_injector` | 2000 | cycles a mode 2-5 fault is held | matches the old `force` durations |
| `DEPTH` | `loopback_node_agent` | 256 | echo queue per VC | |
| `CLK_FREQ`, `BAUD_RATE` | `uart_noc_host`, `uart_transceiver` | 100 MHz, 3 Mbaud | | `noc_host.py` and `uart_roundtrip.py` hard-code 3,000,000 |

### 11.3 Testbench switches and parameters

| switch | testbench | effect |
|---|---|---|
| `-d HW_CLOCKS` | `tb_noc_mesh_2x2_gals` | board clock ratios instead of the fast TB set |
| `-d HS_VC_ALT` | `tb_noc_mesh_2x2_gals` | test 6 alternates VCs per packet (mirrors `VC_MODE=2`) |
| `-d SIM_DEBUG` | `vc_port_arbiter` (via either tb) | `$display` on override trigger/release |
| `INJECT_ECC`, `KILL_MIDPKT`, `BAD_TID`, `BAD_DEST`, `FAULT_MODE` | `tb_noc_stress_tester` | section 6.6; pass through a one-line wrapper top on Windows shells (gotcha 8) |

### 11.4 Build-time defines

| define | where | effect |
|---|---|---|
| `ECC_INJECT_SBE` / `ECC_INJECT_DBE` | `dual_port_ram_ecc` | flip one / two codeword bits on every write; set with `set_property verilog_define {...} [current_fileset]`, and clear it afterwards |
| `FORMAL` | every module with a `FORMAL` block; `async_fifo` swaps to a plain RAM | |
| `FORMAL_TOP_INTEGRATION` | arbiters, counters, synchroniser | disables a sub-module's own properties when a parent is proved; the trap in section 8.2 row K |
| `FORMAL_NO_ROUTER` | `router_5port_mesh_vc` | same, for the mesh proof |
| `DEBUG_BUILD` | nothing any more | used to gate the UART build's probes; deleted because it was lost once and would be again |

---

## 12. Design decisions and the alternatives that were rejected

Recorded so the next person does not re-argue them without the context. Each entry says
what was chosen, what else was on the table, and why.

**Drop a bad flit, do not backpressure or clamp (bug #6, tid guard, constant-tdest
guard).** Three options for a flit the fabric will not carry: refuse `ready` (the sender
stalls forever with no diagnosis, and a stalled sender was the failure mode being
prevented); clamp the address into range (the packet arrives somewhere nobody intended,
silently, which is worse than losing it); consume and drop, raise a sticky flag (the
sender keeps running, the loss is attributed to a node, and the flag reaches the LEDs).
The third. A flag that says "a bad flit was offered" is raised on the offer, not on the
handshake, because the fault is aiming wrong, not timing.

**Close the packet on a reject rather than just dropping (bug #7, design A over B).**
A rejected flit may have carried the packet's `tlast`. Design A writes a synthetic tail
into every open VC at that ingress; B would identify which VC the bad flit meant and close
only that one. B is more logic and more corner cases (`tid=00` names no VC, `tid=11`
names both) for a benefit that exists only when the host is already sending garbage,
where "a neighbouring packet was also cut short" is not disproportionate harm and
"nothing is silently misdelivered" is the property that matters. A.

**One `dest_err` flag for two conditions (off-board, inconsistent with the head).** Both
mean "this flit's destination is unacceptable"; a second flag would need ports through
`gals_noc_top`, both tops, the ILA, the LEDs and `analyze_ila.py` for a distinction the
node bit already narrows. Reused.

**Constant-`tdest` check at the mesh ingress only, not in the wrapper.** `tdest` passes
through the wrapper's mux unchanged, so a host fault lands at the mesh ingress anyway;
the `tid` guard needed the wrapper because the mux rebuilds `tid` one-hot by
construction. One site.

**A `` `define `` for the ECC injector, not a parameter.** A parameter would be threaded
through `async_fifo` → `async_fifo_fwft` → `gals_node_wrapper` → `gals_noc_top` → top,
touching five proved modules to reach one. A define reaches it without touching any, and
the normal bitstream is byte-identical.

**Stall timeout counts source silence, not elapsed time (bug #5).** A timeout on wall
time would fire on legitimate downstream backpressure. Counting only cycles with `valid`
low means a blocked-but-alive source cannot trip it, and the extra `&& !valid` on the
release cycle (found by formal) means a source that returns on the last cycle keeps its
lock.

**VC1 owns the link only when it can move (bug #3).** The alternative fix, a shorter
starvation limit, would have cut the wait from 64 cycles to fewer but left the circular
wait in place. The deciding change was to make ownership a per-cycle question.

**Registered `done`/`err` and OR-reduced flags before every synchroniser (CDC-10).** The
alternative was a `set_false_path` or CDC waiver on those crossings. A waiver hides a
glitch path; a register removes it. One cycle of latency on sticky signals.

**Per-domain reset synchronisers with the soft reset as a separate synchronous input
(CDC-7/CDC-10).** Alternatives: waive the 572 CDC-7 paths (they were real, just
previously invisible); synchronise the combined reset once on `clk_h00` and fan it out
(still asynchronous to the other four domains); AND the VIO soft reset into the async net
before the synchronisers (a LUT before a `CLR` pin, CDC-10). Per-domain `reset_sync` with
`srst` synchronised inside is the only shape the tool and the textbook both accept.

**VIO over JTAG for the fault campaign, not UART or buttons.** Opening the COM port
resets the board (section 10.12), so a PC-driven control path would reset the design it
was trying to steer; buttons are not scriptable; the VIO runs in the same `hw_server`
session as the ILA capture. One bitstream, six modes, no hands.

**The injector passes `tready` through.** The alternative, having the injector also
withhold `tready` in mode 2 so agent_11 stalls like a real host with `tid=00` would, was
considered and not done: it would test the agent's watchdog, which `tb_traffic_node_agent`
already covers, and hide the fabric's reaction, which is the point. The host-side stall
is shown separately by the UART build.

**Fault modes are measurements, not pass/fail.** `BAD_TID`, `BAD_DEST`, `KILL_MIDPKT`,
`FAULT_MODE` and the campaign all report `FAIL` on the sequence-error or fairness line
by design. The pass criterion for those runs is the printed signature (flag, node, other
agents' gaps), read by a person or by `summarize_campaign.py`, because the "right" number
of sequence errors depends on 6-bit modulo arithmetic and one-cycle timing.

**Scripted debug flow instead of the GUI wizard.** After the wizard wrote ILA cores into
the pins file, `save_constraints` misordered them and clock lookup silently narrowed a
probe, the choice was to script the whole thing and never touch the wizard again. Every
capture since 2026-09-04 has gone through `setup_debug.tcl`; every build since 2026-09-12
through `hw_scripts/`.

**Formal assumes the wrapper's two resets are equal.** A proof with independent resets
would need most of the wrapper's properties rewritten to reason about one side being in
reset while the other runs. The real `reset_sync`s release the two within a few idle
cycles, and the wrapper's FIFOs are proved (elsewhere) to tolerate that. Documented as an
assumption, not hidden.

**Bounded proofs for the three FIFO-coupled modules.** `vc_input_buffer`, the router and
the mesh tie arbiter or shadow state to FIFO contents; induction invents unreachable
starting states. The alternatives were to write the invariants that would make induction
close (weeks) or to run bmc deep enough to fill and drain every queue several times
(minutes). bmc, with the depth recorded.

---

## 13. Extending the design

Recipes for the changes people are likely to want, each with the files touched and the
checks that must stay green.

### 13.1 Add a fault mode to the campaign

1. `fault_injector.sv`: add a `case` arm in the output mux and, if it needs a different
   trigger or hold, extend the small FSM. Keep `tready` pass-through unless the mode is
   about the agent.
2. `tb_noc_stress_tester.sv`: add the mode's expected signature to the `FAULT_MODE`
   `case` at the end, and run it (`FAULT_MODE=N` through the wrapper top).
3. `hw_scripts/summarize_campaign.py`: add the expectation string; extend `modes` in
   `batch_fault_campaign.tcl` if the default list should include it.
4. Rebuild (section 17), run the campaign, save the log to `hw_logs/`, add a row to
   `HANDOFF.md`'s campaign table.

The VIO has 4 mode bits (16 modes) and two spare output bits.

### 13.2 Add an ILA probe

Mark the register `(* mark_debug = "true", dont_touch = "true" *)`. Both attributes: a
fanout-free register is swept before Set Up Debug ever sees it. Rebuild; `setup_debug.tcl`
picks it up, groups it by clock, and prints the new net count. Update the fingerprint list
in section 10.8 and, if `analyze_ila.py` should read it, add it there. If the script
reports the net as "constant after synthesis", the value is not evidence; find out why
before relying on it.

### 13.3 Add a formal property

Put it in the module's `FORMAL` block under a unique label. If the label is inside a
`for` loop, use `generate`/`genvar` or slang will crash on the duplicate cell name. State
invariants must not be gated on `f_past_valid`. Run the module's `.sby`, then every
`.sby` that includes the module with its properties enabled (the top-level scripts read
sub-modules with `FORMAL_TOP_INTEGRATION`, so usually only its own). If you add a script,
check the generated model actually contains `$assert` cells (section 8.2 row K):

    grep -c '\$assert' formal/<task>_prove/model/design_smt2.smt2

### 13.4 Widen the flit

`DATA_W` is a parameter but four things assume 8: `dual_port_ram_ecc` and the SECDED
(13,8) pair (a 32-bit flit needs a (39,32) code and a new `tb_ecc_secded`); `async_fifo`'s
split of `[7:0]` into the ECC RAM; `traffic_node_agent`'s `{SRC_TAG, seq}` packing and
the 6-bit checker; and the UART framing (2 bytes/flit becomes 5). `PACK_W = 1 + 4 +
DATA_W` follows automatically. Re-prove `dual_port_ram_ecc`, `async_fifo_fwft` (and write
the missing `async_fifo` properties first, since they would be the ones to catch a width
bug), the wrapper, and the mesh with `DATA_W` left at 2 for solver speed. Re-run every
simulation; the regression baselines will change and need re-deriving.

### 13.5 Grow the mesh

`noc_mesh_2x2_vc` hard-codes four routers, the 36 inter-router assigns, the edge tie-offs
and `MAX_X/MAX_Y = 1`. A 2x4 or 4x4 mesh means a new mesh module (generate the wiring from
`(x, y)` rather than writing it by hand), `MAX_*` from parameters, `gals_noc_top` with N
wrappers and N+1 resets, `noc_stress_tester` with N agents and a `PATTERN` table,
`analyze_ila.py` and `summarize_campaign.py` with N agents, and a bigger MMCM output set
or shared host clocks. 4-bit `tdest` allows up to 4x4. Expect the mesh bmc to grow
super-linearly (2x2 is 7 minutes on abc); plan to prove a router pair and the wiring
generator separately rather than the whole mesh. Multi-hop XY routing and the range filter
with real out-of-range values would be exercised for the first time.

### 13.6 Add a host

A host is anything that speaks the flit contract of section 4 on `h*_tx_*`/`h*_rx_*` of
`gals_noc_top`, on its own clock, with its own `rst_n_h*`. Keep `tid` one-hot and
`tdest` constant per packet, or expect the guards to drop your flits and flag you. If the
host may stop mid-packet, the fabric recovers after 1024 silent NoC cycles. The UART
bridge (`uart_noc_host`) is the smallest example; `loopback_node_agent` the smallest that
also receives.

### 13.7 Change a clock

Edit `clk_wiz_0` (the `.xci`), then: `timing.xdc` (the async groups are by clock name, so
they follow), `analyze_ila.py`'s `CLK` table, `tb_noc_stress_tester`'s half-periods, and
the `WINDOW_LOG` arithmetic in section 10.4. Re-derive `max_gap` on the board before
touching `STUCK_LOG` or `STALL_LOG`.

### 13.8 Add a testbench check to the stress tester

The report block at the end of `tb_noc_stress_tester.sv` is a sequence of `[PASS]`/
`[FAIL]` prints with a `fails` counter; add yours there, reading counters through the
hierarchy (`uut_noc_top.*`, `u_stress.agent_*.*`). If the check depends on a fault mode,
gate it the way `BAD_TID`/`FAULT_MODE` are, so the clean run stays a strict pass/fail.

---

## 14. Timeline

| date | commit / PR | what |
|---|---|---|
| Apr–Jul 2026 | (pre-git) | RTL written: FIFOs, ECC, router, mesh, wrapper, agents, UART host |
| 2026-08-17 | `f9b73a9` | initial commit |
| 2026-08-18 | `2ac2e05` | test 6 added; bug #2 fixed |
| 2026-08-19 | `04cd562`..`e1571ba` | `VC_MODE` selector; bug #3 isolated, root-caused with `SIM_DEBUG`, fixed; `HANDOFF.md` created |
| 2026-09-01 | `cba4e60`..`cbc4514`, PR #1 | bug #3 confirmed on board (57.5% → 97.0%); liveness watchdog added; bug #4 found by it, fixed, confirmed (+15.7%) |
| 2026-09-03 | `b2b5a14`..`0d62c26` | arbiter fairness shown to be topology; ECC proved exhaustively; ECC flags wired end to end; `analyze_ila.py` ECC section |
| 2026-09-04 | `e9f8197`..`94d5c1d` | bug #5 fixed, first real arbiter proof; formal for every datapath module; bug #6 found by formal and fixed; scripted debug flow; UART build restored; `noc_host.py` one-hot fix; silicon regression for #4/#5/#6 |
| 2026-09-09 | `153d12a`, PR #2 | `.gitignore`; first merge to `main` |
| 2026-09-10 | `8853d5c`, `0815e10`, PR #3 | ECC fault injector, alarm path proved on silicon; `tid` guard at both layers; two debug-flow traps fixed |
| 2026-09-11 | `31d4cba`, `de8cac3` | bug #7 root-caused and fixed; one-hot `tid` assumption removed from formal |
| 2026-09-12 | `3f73b67`, `9b4fa2d`, PR #4 | `WALKTHROUGH.md`; bug #7, ECC double-bit and the UART build on silicon; batch build/capture scripts; COM-port reset found |
| 2026-09-12 | `1cdf66e`, PR #5 | constant-`tdest` guard, assumption → proof, on silicon; `.gitattributes`; **`v1.0` tagged at the merge `f07ddca`** |
| 2026-09-12 | `c60117a`, PR #6 | `report_cdc` in the flow, 5 CDC-10 criticals fixed; `dest_err_node` found to be constant-folded; docs corrected |
| 2026-09-12/13 | `8deb828`, `d256864`, PR #7 | fault injector + VIO, silicon campaign (six modes); per-domain `reset_sync` (CDC-7 ×572 → 0); UART build rebuilt and re-run |
| 2026-09-14 | `671d655`, `afce6cd` | PR #7's stuck record re-synced and merged |
| 2026-09-14 | (this document) | `async_fifo` proofs found to contain no assertions (section 8.2 row K) |

---

## 15. Things that cost real time

Condensed from `HANDOFF.md` section 4 and the dated entries in section 5. Read the
originals before touching the build flow.

1. `mark_debug` alone does not stop synthesis sweeping a net with no fanout; add
   `dont_touch` or give it a real load.
2. The pass LEDs lied until `done` was gated on observed transfers.
3. Node naming differs between `gals_noc_top` and the testbench; map through the index.
4. Windows count cycles, so agents on slower clocks run longer in wall-clock time and
   stop later. Never compare raw totals across agents; this stagger is what exposed bug #4.
5. A `` `define `` that gates instrumentation will eventually be lost; the guards were
   deleted and the probes made unconditional.
6. Set Up Debug writes into whatever `TargetConstrsFile` names; it now names
   `debug_auto.xdc`, and the GUI step is replaced by `setup_debug.tcl`, which works
   around `save_constraints` misordering, clock lookup silently narrowing probes, stale
   cores carried across a build switch, `debug_auto.xdc` being read by synthesis, deleted
   cores leaving their clocks behind, and implementation needing a fresh session.
7. Tests that send one packet and stop cannot see fairness bugs.
8. `xelab.bat -generic_top "X=2"` mangles `=` on Windows shells; wrap the testbench in
   a one-line top instead.
9. Opening the COM port from the PC resets the FPGA (FTDI DTR/RTS). Read the ILA before
   the next port open; keep one `hw_server` session across an experiment. JTAG target
   open does not reset.
10. Vivado 2025.2 can crash in its exit handler after `close_project` with all outputs
    already written; the batch scripts' `SESSION_A_DONE` marker is the success signal.
11. `release` on a `logic` variable driven by a constant leaves the forced value in
    place forever; force the true value for a cycle first.
12. `wsl bash -c '... $PATH ...'` from Git Bash expands `$PATH` locally; use
    `formal/run_wsl.sh`, and keep it LF (`.gitattributes` does).
13. Window-buffered console output is lost when a process is killed by `timeout`;
    flush or write to a file (`python -u`, `PYTHONIOENCODING=utf-8`).
14. A probe that synthesis has folded to a constant reads the same value forever; a 0
    on it is not evidence. `setup_debug.tcl` now says which nets those are.
15. An `.sby` script that reads every sub-module with `FORMAL_TOP_INTEGRATION` and has
    no properties of its own reports PASS with nothing proved. Count the `$assert` cells.
16. `final_src/` and `sources_1/new/old/` are stale; the old `.sby` files there verified
    a different project.
17. Hardware Manager names VIO probes after the connected nets, not the IP port names;
    look them up by `TYPE`.
18. Vivado's own `python` shadows the system one inside a Tcl `exec`; drive PC-side
    scripts from outside Vivado and hand-shake through files.

---

## 16. What is still open

- **`async_fifo` has no formal properties of its own** (section 8.2 row K). The CDC FIFO
  is the heart of the GALS boundary and its correctness rests on simulation and silicon.
  A shadow-FIFO model like `vc_input_buffer`'s, in the single-clock abstraction the
  script already uses, would close this; the `async_fifo.sby` header should stop
  claiming a proof until then. HANDOFF's formal table row for `async_fifo` is wrong in
  the same way.
- **`dest_err_node[2:0]` remain constant in the stress build** (nodes 0-2 have parameter
  destinations). Only node 3 is live. Extending the injector mux to every agent would fix
  it at the cost of three more copies.
- **ECC covers the payload only**, and SECDED misreports three or more flipped bits.
- **The UART media demos are not regression-ised** (`image_noc_test.py`,
  `video_noc_stream.py`).
- **Mode 2 does not reproduce the host-side stall** a real `tid=00` sender experiences;
  the UART build shows it separately.
- **`v1.1` is not tagged.** `main` at `afce6cd` is a materially different validated
  state from `v1.0` (constant-tdest guard, CDC-clean resets, fault campaign).

---

## 17. Reproducing the results

All paths relative to the repo root. Vivado 2025.2 at `C:/AMDDesignTools/2025.2`. WSL
`Ubuntu-24.04` with the OSS CAD Suite at `/opt/eda/oss-cad-suite` for formal.

Six-test regression, from the Vivado Tcl console:

    set HW_CLOCKS 1 ; set HS_VC_ALT 1 ; source run_sim_regression.tcl

Same thing without the project (faster, no project state). Compile order that elaborates
cleanly:

    sync_fifo dual_port_ram dual_port_ram_ecc ecc_secded_encode_8b ecc_secded_decode_8b
    gray_counter sync_2stage reset_sync async_fifo async_fifo_fwft fwft_wrapper axis_perf_mon
    traffic_gen traffic_node_agent fault_injector packet_arbiter vc_port_arbiter vc_input_buffer
    router_5port_mesh_vc noc_mesh_2x2_vc gals_node_wrapper gals_noc_top noc_stress_tester
    tb_noc_mesh_2x2_gals  (or tb_noc_stress_tester)

Elaborate `work.tb_noc_mesh_2x2_gals`, pass switches as `-d HW_CLOCKS -d HS_VC_ALT`, run
with `run all; quit`. Expected totals in section 6.6.

Stress tester with a parameter (gotcha 8):

    module tb_wrap; tb_noc_stress_tester #(.FAULT_MODE(4)) u(); endmodule

compiled alongside and elaborated as `work.tb_wrap`.

Formal, one module:

    MSYS_NO_PATHCONV=1 wsl -d Ubuntu-24.04 -- bash /mnt/d/.../formal/run_wsl.sh packet_arbiter.sby

or inside WSL, `cd formal && sby -f packet_arbiter.sby`. The mesh bmc takes ~7 minutes,
the router ~2, everything else under a minute. To confirm a script proves something:

    grep -c '\$assert' formal/<name>_prove/model/design_smt2.smt2

Board, scripted (three sessions on purpose; section 10.9):

    vivado -mode batch -source hw_scripts/batch_stress_synth_debug.tcl        # look for SESSION_A_DONE
    vivado -mode batch -source hw_scripts/batch_impl.tcl -tclargs arty_stress_top   # prints CDC_Critical N
    vivado -mode batch -source hw_scripts/batch_program_capture.tcl -tclargs <csv-dir> arty_stress_top
    python analyze_ila.py <csv-dir>

Fault campaign (same bitstream):

    vivado -mode batch -source hw_scripts/batch_fault_campaign.tcl -tclargs <out-root>
    python hw_scripts/summarize_campaign.py <out-root>

UART build:

    vivado -mode batch -source hw_scripts/batch_uart_synth_debug.tcl
    vivado -mode batch -source hw_scripts/batch_impl.tcl -tclargs arty_gals_noc_wrapper
    vivado -mode batch -source hw_scripts/batch_uart_session.tcl -tclargs <dir>   # then, from another shell:
    python -u hw_scripts/uart_roundtrip.py pos ; touch <dir>/go_b ; python -u hw_scripts/uart_roundtrip.py neg ; touch <dir>/go_c
    python hw_scripts/read_ila_flags.py <dir>/cap_b

ECC injection build: set `verilog_define {ECC_INJECT_SBE}` (or `_DBE`) on the fileset
before session A, and clear it afterwards. Expect `ecc_sbe_cnt` (or `_dbe_`) = 3 with node
`1111`.

Board, from the Vivado Tcl console (the interactive flow still works):

    set PATTERN 1 ; set VC_MODE 2 ; source setup_stress_build.tcl
    open_run synth_1 ; source setup_debug.tcl
    # new Vivado session:
    launch_runs impl_1 -to_step write_bitstream -jobs 8

Expect ~1126 `MARK_DEBUG` nets on the stress build; other counts mean a stale Set Up
Debug (section 10.8 has the decoder ring).

---

## 18. File map

Everything tracked at `afce6cd` (117 files outside the historical folders), one line each.
Paths under `GALS_Packet-Based_Fabric.srcs/` are abbreviated to `srcs/`.

**Repo root**

| file | what |
|---|---|
| `HANDOFF.md` | the dated working log: status, numbers, gotchas, every silicon result |
| `WALKTHROUGH.md`, `WALKTHROUGH.th.md` | this document; the Thai translation follows it (English is the source of truth) |
| `README.md` | four Tcl snippets (define, debug xdc, report_cdc, utilisation); not a readme |
| `GALS_Packet-Based_Fabric.xpr` | the Vivado project |
| `.gitignore`, `.gitattributes` | build artefacts out; `*.sh` LF |
| `run_sim_regression.tcl`, `setup_stress_build.tcl`, `setup_uart_build.tcl`, `setup_debug.tcl` | section 6.7 |
| `analyze_ila.py` | section 6.7 |
| `noc_host.py`, `image_noc_test.py`, `video_noc_stream.py`, `bulk_test.py`, `vc_dual_test.py`, `vc_preempt_test.py`, `multi_node_stress_test.py`, `fault_recovery_test.py`, `single_probe_test.py` | PC-side UART scripts; only `noc_host.py` is maintained |
| `combine_sv.py`, `combined.sv`, `combined_noc.sv`, `combined_gals_noc.sv`, `combined.txt` | concatenated sources for sharing; regenerate, do not edit |
| `6_test_sim.log`, `6_test_sim-old.log`, `HWClock1_6_test_sim.log` | early regression logs, superseded by `sim_logs/` |
| `hee.png`, `recovered_from_fpga.png` | an image before and after a round trip through the fabric over UART |
| `dfx_runtime.txt` | Vivado litter; ignored |

**`srcs/sources_1/new/`**: the 32 `.sv` files of section 6, plus `old/` (26 files from
an earlier project, including the `.sby` scripts that verified nothing here).

**`srcs/sources_1/ip/`**: `clk_wiz_0/clk_wiz_0.xci`, `vio_fault/vio_fault.xci`.

**`srcs/constrs_1/new/`**: `arty.xdc` (pins), `timing.xdc` (async clock groups),
`debug_auto.xdc` (generated ILA constraints, `USED_IN = implementation` only),
`debug.xdc` (legacy; the build scripts remove it from the fileset).

**`srcs/utils_1/imports/synth_1/arty_gals_noc_wrapper.dcp`**: a checkpoint Vivado
imported at some point; not used by any script.

**`formal/`**: `async_fifo.sby`, `async_fifo_fwft.sby`, `dual_port_ram_ecc.sby`,
`gals_node_wrapper.sby`, `gray_counter.sby`, `noc_mesh_2x2_vc.sby`, `packet_arbiter.sby`,
`router_5port_mesh_vc.sby`, `sync_2stage.sby`, `vc_input_buffer.sby`,
`vc_port_arbiter.sby`, `run_wsl.sh`, `.gitignore` (task output directories).

**`hw_scripts/`**: the ten files of section 6.7.

**`hw_logs/`** (chronological):

| file | what it backs |
|---|---|
| `ila_vc2_pattern1_20260901_FIXED.log` | bug #3 on silicon, 57.5% → 97.0% |
| `ila_bug4_watchdog_fix_vc2_pattern1_20260901.log` | bug #4 fix, +15.7%, liveness PASS |
| `ila_ecc_hw_validation_vc2_pattern1_20260902.log` | ECC flags wired, clean run |
| `ila_stress_vc2_pattern1_20260904.log` | silicon regression for #4/#5/#6 |
| `ila_stress_vc2_pattern1_20260910_clean.log`, `..._eccinject_sbe.log` | tid guard clean; ECC single-bit path proved |
| `ila_stress_vc2_pattern1_20260912_bug7_clean.log` | bug #7 on silicon |
| `ila_stress_vc2_pattern1_20260912_eccinject_dbe.log` | ECC double-bit path proved (with the cancellation explanation) |
| `uart_roundtrip_20260912_tidguard_bug7.log` | UART 6/6 + `tid=00`, COM-port reset discovered |
| `ila_stress_vc2_pattern1_20260912_destguard_clean.log` | constant-tdest guard clean (with the vacuous-`dest_err` caveat) |
| `ila_stress_vc2_pattern1_20260912_cdcfix_clean.log`, `cdc_arty_stress_top_20260912_after_fix.rpt` | CDC-10 fixes, Critical 0 |
| `fault_campaign_20260912.log` | the six-mode campaign |
| `uart_roundtrip_20260912_reset_sync.log` | UART build with per-domain resets |

**`sim_logs/`**: `regress_<tag>_<stamp>.log`; the five `_FIXED` ones are the baselines.

**`backup_20260804/`, `final_src/`**: snapshots from before the repository; reference
only.

---

## 19. Glossary

- **flit**: flow-control unit, the 8-bit-plus-control word that moves one link per cycle.
- **packet**: a sequence of flits ending in one with `tlast = 1`.
- **head / body / tail**: first flit (routes the packet), middle flits, last flit.
- **wormhole switching**: forward flit by flit; the head claims a port, the tail releases it.
- **VC, virtual channel**: an independent queue and credit on a shared physical link.
  VC0 = normal, VC1 = priority. `tid` selects it, one-hot.
- **XY routing**: move in X until aligned, then Y. Deadlock-free on a mesh.
- **GALS**: globally asynchronous, locally synchronous. Islands on their own clocks,
  async FIFOs between them.
- **CDC**: clock-domain crossing. `report_cdc` IDs used here: CDC-3 one-bit synchronised,
  CDC-6 multi-bit with `ASYNC_REG` (gray pointers), CDC-7 unsynchronised async reset
  deassert, CDC-9 synchronised reset, CDC-10 logic before a synchroniser, CDC-15
  clock-enable structure (FIFO RAM read ports).
- **gray code**: encoding where consecutive values differ in one bit; used for pointers
  that cross clock domains.
- **FWFT**: first-word-fall-through; FIFO output is valid whenever non-empty, no read
  latency.
- **SECDED**: single-error-correct, double-error-detect Hamming code.
- **sticky flag**: a bit that is set once and never cleared until reset.
- **force-close**: writing a synthetic `tlast` into an open VC when a flit of that
  packet had to be dropped (bug #7).
- **reset synchroniser**: asynchronous assert, deassert through two flops of the target
  clock (`reset_sync`).
- **soft reset**: the VIO-driven reset on the stress build, applied synchronously per
  domain.
- **backpressure**: the receiver deasserting `ready`, holding the sender.
- **head-of-line blocking**: a stuck flit at the front of a queue blocking everything
  behind it.
- **starvation**: a requester that never wins arbitration.
- **round-robin**: arbitration that rotates priority after each grant.
- **BMC**: bounded model checking; explores all inputs up to N steps from reset.
- **k-induction / prove**: shows the property holds in every reachable state, unbounded.
- **cover**: a formal check that some state is reachable, guarding against vacuous proofs.
- **vacuous**: a proof that passes because the assumptions rule out every interesting
  case, or because there is nothing to prove (section 8.2 row K).
- **shadow FIFO**: a formal-only model of what a queue should contain, compared against
  the real one (`vc_input_buffer`).
- **ILA / VIO**: Xilinx integrated logic analyser (captures `mark_debug` nets) and
  virtual I/O (register read/write over JTAG).
- **MMCM**: the clock generator on the FPGA.
- **hot-spot / permutation**: several senders target one node (`PATTERN=1`) / every
  node sends to one distinct partner (`PATTERN=0`).
- **liveness**: "something eventually happens"; here, flits keep moving during `S_RUN`.
- **utilisation**: flits transferred / cycles observed on one link.
- **campaign**: the six-mode silicon fault-injection run of section 10.13.
