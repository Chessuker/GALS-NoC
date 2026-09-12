# GALS Packet-Based Fabric: a walkthrough from zero

Written 2026-09-12 against commit `de8cac3` on `feature/2-ecc-injection-and-tid-guard`.

This is the long-form companion to `HANDOFF.md`. `HANDOFF.md` is the working log for
someone who already knows the design and needs the current state, the numbers, and the
traps. This document is for someone who has never seen the project: it explains what the
thing is, how every module works, how a flit travels through it, what each of the seven
bugs was and how it was found and fixed, and how the verification was done. Where the two
disagree, `HANDOFF.md` is more recent for numbers; this document is more complete for
explanation.

Read it top to bottom the first time. After that, section 6 (module reference) and
section 8 (the bugs) are the parts you come back to.

---

## Contents

1. What this project is
2. Background you need (NoC, GALS, virtual channels, packets and flits)
3. The hardware: board, clocks, node numbering
4. The flit contract: what travels on every wire
5. Architecture, top to bottom
6. Module reference (every RTL file)
7. Life of a flit: one packet, end to end
8. The seven bugs
9. How it is verified: simulation, formal, silicon
10. On the board: hardware-specific behaviour
11. Timeline
12. Things that cost real time (condensed gotchas)
13. What is still open
14. Reproducing the results
15. Glossary

---

## 1. What this project is

A small **network-on-chip (NoC)** on a Xilinx Artix-7 FPGA. Four endpoints ("hosts" or
"nodes") sit at the corners of a 2x2 grid. Each host runs on its **own clock**, at its own
frequency, with no phase relationship to the others or to the network. The network itself
runs on a fifth clock. Hosts hand packets to the network; the network delivers them to the
addressed host.

That is the GALS part: **Globally Asynchronous, Locally Synchronous**. Each island is
ordinary synchronous logic. The boundaries between islands are asynchronous FIFOs with
gray-coded pointers and two-stage synchronisers, the textbook clock-domain crossing.

The network is **packet-based**: a host sends a packet as a sequence of 8-bit flits, the
last one tagged `tlast`. A router holds an output port for the whole packet so flits of
different packets never interleave inside one channel. There are **two virtual channels
(VCs)** per link, so a high-priority packet can overtake a low-priority one.

The RTL is SystemVerilog. The design work predates the git history (source files carry
create dates from April to July 2026); the repository begins on 2026-08-17 and everything
after that is verification, bug fixing, and hardening. Seven real RTL bugs were found and
fixed in that period. Five were confirmed on the board; one cannot happen any more so it is
proved and simulated; the latest one is proved and simulated but has not yet been built
for the board.

The word "we" below means whoever was working on the repo at the time. The commits say
who.

---

## 2. Background you need

If you know what a wormhole-routed NoC with virtual channels is, skip to section 3.

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
with just the two-flop synchroniser; there is no multi-bit consistency problem.

### 2.7 ECC

The FIFO memories protect the 8-bit payload with **SECDED** (single-error-correct,
double-error-detect) Hamming code: 8 data bits become a 13-bit codeword (4 Hamming parity
bits plus one overall parity). On read, a single flipped bit is corrected and flagged;
two flipped bits are detected and flagged as uncorrectable. Three or more can be
misreported; that limit is stated in `HANDOFF.md`.

---

## 3. The hardware

### 3.1 Board

Digilent **Arty A7-100T** (xc7a100tcsg324). Out-of-context synthesis experiments were
done on the smaller xc7a35ticsg324-1L part; the numbers in `HANDOFF.md` section 3 say
which.

### 3.2 Clocks

One MMCM (`clk_wiz_0`, VCO 1000 MHz) produces five clocks:

| clock | net | frequency | used by |
|---|---|---|---|
| clk_out1 | `clk_noc` | 80.00 MHz | the mesh, all four routers |
| clk_out2 | `clk_h00` | 100.00 MHz | host 00 |
| clk_out3 | `clk_h01` | 71.43 MHz | host 01 |
| clk_out4 | `clk_h10` | 83.33 MHz | host 10 |
| clk_out5 | `clk_h11` | 71.43 MHz | host 11 |

Simulation uses these ratios when `HW_CLOCKS` is defined, otherwise a faster set (NoC 250,
sink 500, senders 125/333/100 MHz) that runs quicker and was the original testbench
default. Both configurations are part of the regression.

The MMCM reset is tied low on purpose. The reset button only resets the logic; if it also
reset the MMCM the ILA debug hub would lose its clock and every hardware capture would
die with it.

### 3.3 Node numbering (read this twice)

A node has a coordinate `(x, y)`, an index, a destination address and, unfortunately,
two naming conventions.

    idx   = y*2 + x
    tdest = {x[1:0], y[1:0]}      (4 bits: x in [3:2], y in [1:0])

| idx | (x,y) | tdest | `gals_noc_top` port name | testbench label |
|---|---|---|---|---|
| 0 | (0,0) | `0000` | `h00` | Node00 |
| 1 | (1,0) | `0100` | `h01` | Node10 |
| 2 | (0,1) | `0001` | `h10` | Node01 |
| 3 | (1,1) | `0101` | `h11` | Node11 |

`gals_noc_top` names ports by index written as two digits; `tb_noc_mesh_2x2_gals` names
them by `xy`. They disagree for idx 1 and 2. Always map through the index. This is gotcha
3 in `HANDOFF.md` and it has bitten more than once.

### 3.4 Two board builds

- **Stress build** (`arty_stress_top`): four synthetic traffic agents hammer the network
  and check what arrives. Pass/fail on LEDs, detail through the ILA. This is the build
  used for every performance number and every bug confirmation.
- **UART build** (`arty_gals_noc_wrapper`): host 00 is a UART bridge to a PC; the other
  three hosts are loopback echoes. A Python script sends packets and reads the echoes.
  This is the interactive demo and the round-trip data-integrity check.

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

Rules the design relies on, and where they are enforced:

- `tid` is one-hot. Enforced since 2026-09-10 at both the host ingress
  (`gals_node_wrapper`) and the mesh ingress (`noc_mesh_2x2_vc`); a violation drops the
  flit and raises `tid_err`. Before that it was only an assumption.
- `tdest` is on the board (x ≤ 1, y ≤ 1). Enforced since 2026-09-04 at the mesh ingress;
  a violation drops the flit and raises `dest_err`.
- `tdest` is constant across a packet. **Not enforced.** The router locks an output on
  the head flit's route; a body flit with a different `tdest` would go out the locked port
  regardless. The formal environment records this as an assumption
  (`router_5port_mesh_vc.sv`, block `f_wf`). All agents in this repo honour it.
- Every packet ends with a `tlast`. Enforced since 2026-09-11 in the sense that if an
  ingress filter has to drop a flit, it closes any open packet itself (bug #7). A host
  that simply stops mid-packet is handled by a timeout in `packet_arbiter` (bug #5).

---

## 5. Architecture, top to bottom

    arty_stress_top  /  arty_gals_noc_wrapper          (board top: MMCM, LEDs, agents)
        |
        +-- gals_noc_top                                (glue: 4 wrappers + mesh + flags)
              |
              +-- gals_node_wrapper  x4                 (GALS boundary, one per host)
              |     +-- async_fifo_fwft  x4             (TX VC0, TX VC1, RX VC0, RX VC1)
              |           +-- async_fifo
              |           |     +-- gray_counter x2, sync_2stage x2
              |           |     +-- dual_port_ram_ecc  (payload, 8b -> 13b codeword)
              |           |     |     +-- ecc_secded_encode_8b, ecc_secded_decode_8b, dual_port_ram
              |           |     +-- dual_port_ram      (control bits, no ECC)
              |           +-- fwft_wrapper
              |
              +-- noc_mesh_2x2_vc                       (wiring + ingress filters)
                    +-- router_5port_mesh_vc  x4
                          +-- vc_input_buffer  x5       (one per input port)
                          |     +-- sync_fifo  x2       (one per VC)
                          +-- vc_port_arbiter  x5       (one per output port)
                          |     +-- packet_arbiter  x2  (one per VC)
                          +-- XY decoder, crossbar      (inline)

Data direction, host to host:

    host TX  ->  wrapper TX FIFO (clk_host -> clk_noc)  ->  mesh ingress filter
             ->  router LOCAL input buffer  ->  arbiter  ->  crossbar  ->  link
             ->  next router's input buffer  -> ...  ->  router LOCAL output
             ->  wrapper RX FIFO (clk_noc -> clk_host)  ->  host RX

Everything from the mesh ingress filter to the wrapper RX FIFO write port is in the
`clk_noc` domain. The wrappers are the only place two clocks meet.

---

## 6. Module reference

All files are in `GALS_Packet-Based_Fabric.srcs/sources_1/new/`. Line counts are as of
`de8cac3`. "Formal" says whether the module has a `FORMAL` block and what `formal/*.sby`
proves about it; "prove" means unbounded (k-induction passed), "bmc" means bounded.

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
256). Formal: covered indirectly by `vc_input_buffer`'s shadow-FIFO proof.

#### `gray_counter.sv` (133 lines)
Binary counter with a gray-coded copy of the pointer (`ptr_g = bin ^ (bin >> 1)`) and
the binary low bits as the RAM address. One instance per side of every `async_fifo`.
Formal: prove. The wrap-around cover needs depth 40 with a 5-bit pointer (documented in
`HANDOFF.md`).

#### `sync_2stage.sv` (97 lines)
Two-flop synchroniser, `WIDTH` bits, with `ASYNC_REG` on the output register so Vivado
packs the pair and treats the first stage's metastability window correctly. Used for gray
pointers inside `async_fifo` and for sticky flags everywhere else (ECC, `dest_err`,
`tid_err`, agent `done`/`err`). Formal: prove.

#### `ecc_secded_encode_8b.sv` / `ecc_secded_decode_8b.sv` (78 lines)
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
threaded through five hierarchy levels of already-proved modules. Formal: prove (plain
RAM path only; see next entry).

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
to 0, so the formal proof covers pointer logic and data ordering but not ECC. Formal:
prove (single-clock abstraction, `multiclock` off; `HANDOFF.md` notes this is the easier
problem).

#### `fwft_wrapper.sv` (175 lines)
Turns a standard FIFO read interface (data valid the cycle after `r_en`) into
first-word-fall-through (data valid whenever not empty). Implemented as a two-slot
output stage (`out` and `skid`) with a `data_arriving` register tracking the one-cycle
RAM latency, and a `can_read` rule that keeps at most two words in flight. Formal:
covered by `async_fifo_fwft`.

#### `async_fifo_fwft.sv` (109 lines)
`async_fifo` plus `fwft_wrapper` on the read side. This is what `gals_node_wrapper`
instantiates. Formal: prove.

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
1024 is about 100x that.

The round-robin `mask` advances on every `eop_transfer` (bug #2).

Formal: prove. `assert_onehot` (grant is one-hot or zero), `assert_channel_lock` (while
`LOCKED` and the locked source still has data, grant does not change),
`assert_abort_only_when_source_gone` (`force_release` never fires with data present).
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

Formal: prove. `assert_vc1_yields_when_stalled`, `assert_no_vc1_during_override`, plus
one-hot and mutual-exclusion properties.

#### `vc_input_buffer.sv` (241 lines)
One per router input port. Demultiplexes an incoming flit on `tid` into one of `NUM_VCS`
`sync_fifo`s (depth 16, 13 bits wide), and exposes the head of each VC's queue as a
separate `m_valid/m_tlast/m_tdest/m_tdata` set. `s_ready[v] = ~full[v]`. A flit is
written only when `s_valid && s_tid[v] && !full[v]`; a multi-hot `tid` would write one
flit into two queues, which is why one-hot is enforced upstream.

Formal: bmc depth 16, with a black-box **shadow FIFO**: the formal block keeps its own
model of what should be queued and checks the real head-of-queue against it every cycle.
That single comparison covers the demux, the pack/unpack slicing, and FIFO ordering.
Bounded rather than proved because induction can start from a shadow queue that
disagrees with the real one.

#### `router_5port_mesh_vc.sv` (436 lines)
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
steps in 99 s). Properties: one output port per valid flit, eject to LOCAL iff the flit
is home, grant one-hot across inputs and across VCs, output data equals granted input's
data, `m_tid` matches the granting VC, and no input granted by two output ports at once
(`assert_no_grant_fanout_*`, the one that would catch a cloned flit). The block is
switched off with `-D FORMAL_NO_ROUTER` when the mesh is proved, because its input
assumptions would then land on driven internal wires and could make everything pass
vacuously.

### 6.3 Mesh and GALS boundary

#### `noc_mesh_2x2_vc.sv` (574 lines)
Instantiates four routers with `(x, y)` from `idx = y*2 + x`, wires EAST↔WEST and
NORTH↔SOUTH between neighbours, and ties the off-board edges to `valid = 0`,
`ready = 0`. Exposes the four LOCAL ports as `s_*` (host into mesh) and `m_*` (mesh out
to host).

Section 0 and 0b are the **ingress filters**, added for bugs #6 and the `tid` guard:
`dest_ok[i]` (x and y both ≤ 1) and `tid_ok[i]` (exactly one bit set). A flit failing
either is consumed (the host sees `ready` normally) but not presented to the router, and
the corresponding sticky per-node flag `dest_err[i]` / `tid_err[i]` is raised. The flag is
raised when the bad flit is offered, not when it is accepted.

Section 2.2 is the **force-close** logic added for bug #7: per node and per VC,
`pkt_open` and `pkt_dest` track whether a packet has started and where it is going. A
rejected flit sets `close_pend` for every open VC. While any close is pending the node
presents a synthetic flit to the router (`tlast = 1`, `tid` = that VC, `tdest` = recorded
head dest, data 0) and holds `s_ready = 0` so the host cannot interleave. Closes go out
one per cycle because the LOCAL port takes one flit per cycle.

Formal: bmc depth 10 with `abc bmc3` (7m42s at `de8cac3`), cover depth 12 with z3.
Headline properties: `assert_eject_dest` (a flit ejected at node i is addressed to node
i; this is what fails if the index wiring is crossed, and what bug #7 broke),
`assert_edge_*` (nothing drives valid off the board), `assert_bad_dest_blocked`,
`assert_local_in_range`, `assert_local_tid_onehot`, `assert_close_pend_only_open`,
`assert_host_held_while_closing`, plus one-hot/onehot0 checks on ejected `tid`. Since
`de8cac3` the environment no longer assumes one-hot `tid` or in-range `tdest`; the solver
sends anything and the filters have to cope. Covers show every node delivers, both links
carry traffic, both VCs run at once, the filters fire and the mesh keeps delivering
afterwards, and the force-close path is reached and its synthetic tail arrives.

Parameters are shrunk for formal (`DATA_W=2`, `DEPTH=2`) and arrays are flattened with
`memory_map`; without that the solver does not finish.

#### `gals_node_wrapper.sv` (478 lines)
The GALS boundary, one per host. Four `async_fifo_fwft`s: TX VC0/VC1 (written on
`clk_host`, read on `clk_noc`) and RX VC0/VC1 (the reverse). The host writes into the TX
FIFO selected by `tid`; a combinational mux presents the head of TX VC1 if non-empty,
else TX VC0, as `m_noc_*` with the matching one-hot `m_noc_tid`. The mux does not lock
per packet; it interleaves flit by flit, which is legal because the far side demuxes on
`tid` again. Packet integrity within a VC is preserved by FIFO order. The RX side is
symmetrical.

Host-side `tid` guard (2026-09-10): `host_tid_ok` gates every TX write enable; a bad
`tid` is consumed and dropped and `host_tid_err` goes sticky. This is the layer that
actually catches a misbehaving host, because the mesh only ever sees the mux's
by-construction one-hot `tid`. The mesh-level guard stays as a second line.

Force-close for bug #7 (2026-09-11), same tracker as the mesh: `tx_pkt_open`,
`tx_pkt_dest`, `tx_close_pend`. Because each VC has its own FIFO write port, both VCs can
be closed in the same cycle. `s_host_ready` is held low while a close is pending.

Flags: TX FIFO ECC flags are latched sticky on `clk_noc`; RX FIFO ECC flags and the host
`tid` error are latched on `clk_host` and crossed to `clk_noc` through a `sync_2stage`
(safe because sticky). Outputs `ecc_single_err`, `ecc_double_err`, `host_tid_err`.

Formal: prove with `multiclock on` (real two-clock proof). Properties: the mux presents
exactly the right VC's data, `tid` is one-hot when valid and zero when idle, never pop an
empty FIFO (`assert_tx_no_pop_empty_*`, `assert_rx_no_pop_empty_*`, the ones that would
catch garbage-as-flit), ready equals not-full except while closing, no host write while
closing, close pending only for open VCs. Since `de8cac3` the host-side one-hot assume is
removed and covers reach the force-close path.

#### `gals_noc_top.sv` (371 lines)
Pure glue. Four `gals_node_wrapper`s, one `noc_mesh_2x2_vc`, the wiring between them,
and the aggregation of flags: per-node ECC/`dest_err`/`tid_err` vectors
(`ecc_sbe_node`, `ecc_dbe_node`, `dest_err_node`, `tid_err_node`) and edge-counted
totals (`ecc_sbe_cnt`, `ecc_dbe_cnt`, `dest_err_cnt`, `tid_err_cnt`), all
`mark_debug` + `dont_touch` so the ILA can see them. The `_cnt` values count nodes that
have ever raised the flag, not events, because the flags are sticky levels.

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

#### `traffic_node_agent.sv` (283 lines)
The board-side traffic source and checker, one per host. Site of bug #4 and of the
"green light that lied" (gotcha 2).

State machine `S_WARMUP → S_RUN → S_DRAIN → S_DONE`. During `S_RUN` it sends
`PKT_FLITS`-flit packets (16) back to back to `DEST_ID`, alternating VCs per packet under
`VC_MODE=2`, with a per-VC 6-bit sequence number in the payload (`tdata = {SRC_TAG,
seq}`). With `TX_EN=0` it is a pure sink (used for node 00 in the hot-spot pattern).

The RX side accepts at full rate (`rx_tready = 11`) and checks, per (source, VC), that
each received sequence number equals the previous plus one; a mismatch increments
`rx_err_cnt`. The check is per flit and 6-bit-modulo, which matters when interpreting
error counts after deliberate corruption (see bug #7).

Liveness watchdog: `stuck_cnt` resets on every transfer during `S_RUN` and sets
`stuck_seen` after `2**STUCK_LOG` (65,536) silent cycles. `done` is gated on it, so the
pass LEDs cannot light on a dead fabric. `max_gap` records the longest silence actually
seen so thresholds are set from measurement, not guesses (measured worst: 136 cycles in
sim, 219 on the board).

Window end (bug #4 fix): the agent finishes its current packet before leaving `S_RUN`,
with `stuck_seen` as the escape if the fabric is dead.

Counters (`tx_flit_cnt`, `rx_vc0_cnt`, `rx_vc1_cnt`, `rx_err_cnt`, `max_gap`, ...) are
`mark_debug` + `dont_touch` and are what `analyze_ila.py` reads.

#### `noc_stress_tester.sv` (168 lines)
Instantiates four `traffic_node_agent`s with destinations chosen by `PATTERN`:

- `PATTERN=0` permutation: 00↔11, 01↔10. Every flow has its own path; no output-port
  contention. Good for raw bandwidth, useless for arbiter testing.
- `PATTERN=1` hot-spot: 01, 10 and 11 all send to 00; 00 is a sink. This is the
  configuration that exposed bugs #3 and #4 and is used for every silicon regression.

Aggregates `done`/`err` across agents (crossed with `sync_2stage`) into `pass_group1`,
`pass_group2`, `any_fail`.

#### `loopback_node_agent.sv` (150 lines)
Echo node for the UART build: whatever arrives on VC v is queued (depth 256, per VC with
independent credit) and sent back to the sender on the same VC.

#### `uart_transceiver.sv` (121 lines)
`uart_rx` and `uart_tx`, 8N1, parameterised by `CLK_FREQ` and `BAUD_RATE` (3 Mbaud on
the board).

#### `uart_noc_host.sv` (215 lines)
PC bridge for host 00. Protocol: **two bytes per flit**. Byte 0 is the header
`[7] tlast | [6:5] tid | [4] 0 | [3:0] tdest`, byte 1 is the payload. Incoming bytes go
through a 256-entry `sync_fifo`; a three-state parser assembles a flit and presents it to
the NoC until the flit's VC is ready. The reverse direction serialises each received
flit as header then data. The header's `tid` field is sent through unchanged, so the PC
must send one-hot values; `noc_host.py` was fixed on 2026-09-04 to do so (it used to send
the VC number, so VC0 became `tid = 00` and every VC0 packet vanished silently).

### 6.5 Board tops

#### `arty_stress_top.sv` (183 lines)
MMCM, `gals_noc_top`, `noc_stress_tester`, LEDs. Parameters `PATTERN` and `VC_MODE`
are overridden from `setup_stress_build.tcl`. LED map (`PATTERN=1`): `led[0]`
heartbeat; `led[1]` all agents finished their window; `led[2]` finished and node 00 saw
no error; `led[3]` any of ECC double-bit, `dest_err`, `tid_err`. `led[1]` and `led[2]`
are gated off by `led[3]`'s sources so a corrupt run cannot show green.

#### `arty_gals_noc_wrapper.sv` (155 lines)
MMCM, `gals_noc_top`, `uart_noc_host` on host 00, three `loopback_node_agent`s. LEDs
are activity indicators, not verdicts.

### 6.6 Testbenches

#### `tb_noc_mesh_2x2_gals.sv` (615 lines)
The six-test regression, driven by `traffic_gen`s with a scoreboard (`sb_predict`) that
predicts what each node should receive and reports `Matched / Mismatched / Pending`.

| test | what it exercises |
|---|---|
| 1 | one packet across the diagonal (two hops) |
| 2 | VC preemption: a 30-flit VC0 packet, then a 5-flit VC1 packet from another node to the same output; VC1 must overtake |
| 3 | random all-to-all with both VCs |
| 4 | three nodes send one packet each to the same destination; delivery under contention |
| 5 | starvation override: a 50-flit VC0 packet against ten 15-flit VC1 packets; VC0 must finish |
| 6 | **sustained** hot-spot: three nodes send back to back into node 0 with no gaps; asserts each source gets at least its share. Added 2026-08-18 because tests 1-5 prove delivery, not bandwidth sharing, and bug #2 was invisible to them |

Switches: `HW_CLOCKS`, `HS_VC_ALT` (test 6 alternates VCs like the board), `SIM_DEBUG`.
All four combinations of the first two must pass with `Mismatched=0 Pending=0`.

#### `tb_noc_stress_tester.sv` (447 lines)
The board's stress build in simulation, with the same clock ratios and a window shrunk
from 2^24 to 2^18 cycles. Reports per-agent flit counts, `max_gap`, sequence errors,
`stuck`, the EAST/NORTH split at node 0's LOCAL arbiter, ECC counters, `dest_err`,
`tid_err`. Its predictions have matched the board to within a fraction of a percent
(bug #4 deltas), so it stands in for a board build when chasing this class of problem.

Directed-fault parameters: `INJECT_ECC` (flip two bits in live FIFO data; the flag must
reach the top and the endpoint must see errors), `KILL_MIDPKT` (cut agent_11's valid
mid-packet; the survivors must keep running), `BAD_TID` (force node 11's `tid` to `00`
or `11` for 2000 cycles; the flag must rise and the other nodes must not stall). The
fault runs report `FAIL` on the sequence-error line by design; they are measurements.

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
| `setup_stress_build.tcl` | switches the project to `arty_stress_top` with `PATTERN`/`VC_MODE`, re-synthesises |
| `setup_uart_build.tcl` | same for `arty_gals_noc_wrapper` |
| `setup_debug.tcl` | builds ILA cores from `MARK_DEBUG` nets, one core per clock domain, writes `constrs_1/new/debug_auto.xdc`; replaces the GUI Set Up Debug wizard and works around four Vivado traps (gotcha 6 and the 2026-09-10 entries in `HANDOFF.md`) |
| `analyze_ila.py` | reads exported `iladata*.csv`, computes throughput, utilisation, conservation, liveness, ECC and `dest_err` verdicts |
| `noc_host.py` | PC side of the UART build: send a packet, print echoes |
| `image_noc_test.py`, `video_noc_stream.py`, `bulk_test.py`, `vc_*_test.py`, `multi_node_stress_test.py`, `fault_recovery_test.py`, `single_probe_test.py` | UART demos and experiments; `recovered_from_fpga.png` is an image round-tripped through the fabric |
| `formal/*.sby` | one SymbiYosys script per RTL module (eleven), plus `run_wsl.sh` to run them from Git Bash on Windows |
| `combine_sv.py` | concatenates sources into `combined*.sv` for sharing |
| `hw_logs/` | every ILA capture that backs a number in `HANDOFF.md` |
| `sim_logs/` | regression logs; the `_FIXED` ones are the baselines |
| `sources_1/new/old/`, `final_src/`, `backup_20260804/` | historical. `old/` contains `.sby` files for a different project (`gals_mpmc_scalable`) that never verified anything here; `final_src/` is a stale July snapshot. Do not build from either |
| `constrs_1/new/arty.xdc`, `timing.xdc`, `debug_auto.xdc` | pins, clock groups (the five clocks are asynchronous to each other), and the script-generated ILA constraints |

---

## 7. Life of a flit

Follow one 16-flit packet from agent_11 (idx 3, 71.43 MHz) to agent_00 (idx 0, sink)
in the hot-spot stress build. Node 11 is at (1,1); node 00 is at (0,0).

1. **Agent.** `traffic_node_agent` in `S_RUN` presents `tvalid=1`, `tdest=0000`,
   `tid=01` (VC0 this packet), `tdata={2'b11, seq}`, `tlast=0`, on `clk_h11`. It advances
   when `tready[0]` is high.

2. **Wrapper host ingress** (`gals_node_wrapper`, `clk_h11`). `host_tid_ok` is true
   (`01` is one-hot), no close is pending, TX VC0 is not full, so `tx_host_acc[0]` fires:
   `{tlast, tdest, tdata}` is written into TX FIFO VC0. `tx_pkt_open[0]` becomes 1 and
   `tx_pkt_dest[0]` records `0000`. Inside the FIFO, `dual_port_ram_ecc` encodes the 8
   data bits to 13 and stores them; the 5 control bits go to the plain RAM. The write
   pointer increments in binary and gray.

3. **Clock crossing.** The gray write pointer passes through two flops on `clk_noc`.
   Two `clk_noc` cycles later the read side sees the FIFO as non-empty. `fwft_wrapper`
   pre-reads the word so it is already sitting on `rdata` when someone looks.

4. **Wrapper NoC egress** (`clk_noc`). TX VC1 is empty, TX VC0 is not, so the mux
   presents `m_noc_valid=1`, `m_noc_tid=01`, with the FIFO head's `tlast/tdest/tdata`. The FIFO pops when `m_noc_ready[0]` is high. On the pop,
   the decoder checks the 13-bit word; if a bit had flipped it would be corrected and
   `tx_sbe[0]` would pulse, to be latched sticky.

5. **Mesh ingress** (`noc_mesh_2x2_vc`, section 0/0b/2.2, node 3). `dest_ok[3]`: x=0,
   y=0, both ≤ 1, true. `tid_ok[3]`: true. Not closing. So `r_valid[3][LOCAL]` follows
   `s_valid[3]` and the fields pass straight through. `pkt_open[0]` becomes 1 at node 3
   with `pkt_dest[0]=0000`.

6. **Router 3, LOCAL input buffer.** `vc_input_buffer` writes the packed flit into its
   VC0 `sync_fifo`. `s_ready[LOCAL][0]` was `~full`, and that is what the wrapper saw as
   `m_noc_ready[0]` in step 4.

7. **Router 3, XY decoder.** Head of VC0 at LOCAL: `dx = 0 < MY_X = 1` → request
   **WEST**. `route_req[LOCAL][0][WEST] = 1`, transposed into `req_out_vc0[WEST][LOCAL]`.

8. **Router 3, WEST output arbiter.** `vc_port_arbiter` for WEST: VC1's
   `packet_arbiter` has no requests. VC0's is `IDLE`, sees `valid[LOCAL]`, picks it
   (`next_grant = 00001`), and since `tlast` is 0 it goes `LOCKED` on LOCAL with
   `has_transferred` set if the flit moved this cycle. `vc1_can_move` is false, so
   `vc1_is_active` is false, so `ready_vc0 = ready_out_vc0 = m_ready[WEST][0]`, which is
   router 2's EAST input buffer's VC0 `~full`.

9. **Router 3, crossbar.** `grant_vc0[WEST] = 00001`, so `m_*[WEST]` = the LOCAL VC0
   head, `m_tid[WEST] = 01`. `buf_ready[LOCAL][0]` = `ready_from_arb_vc0[WEST]`. The
   input FIFO pops.

10. **Link 3→2.** `noc_mesh_2x2_vc` wires `m_*[3][WEST]` to `r_*[2][EAST]`. Same clock,
    no crossing.

11. **Router 2.** EAST input buffer VC0 → decoder: `dx = 0 = MY_X`, `dy = 0 < MY_Y = 1`
    → **SOUTH**. SOUTH arbiter locks on EAST. Crossbar drives `m_*[SOUTH]`, wired to
    `r_*[0][NORTH]`.

12. **Router 0.** NORTH input buffer VC0 → decoder: `dx = 0`, `dy = 0`, both equal →
    **LOCAL**. Here is the contention: agent_01's packets arrive on router 0's EAST port
    and agent_10's and agent_11's on NORTH (they merged at router 2), all wanting LOCAL.
    The LOCAL `packet_arbiter` for VC0 round-robins between EAST and NORTH per packet;
    `tb_noc_stress_tester` measures this split at 49/51. Our packet, once granted, holds
    LOCAL for all 16 flits.

13. **Mesh egress → wrapper 0 RX.** `m_*[0][LOCAL]` becomes `s_noc_*` of wrapper 0. RX
    VC0 FIFO written on `clk_noc`, gray pointer crosses to `clk_h00`, `fwft_wrapper`
    pre-reads, the RX mux presents it as `m_host_*` with `m_host_tid = 01`.

14. **Sink.** agent_00's `rx_tready = 11`; each flit is checked against
    `exp_seq[src=11][vc=0]`, counted into `rx_vc0_cnt`, and resets `stuck_cnt`. The
    16th flit carries `tlast`; at every arbiter along the way `eop_transfer` fires, the
    lock releases, the round-robin mask advances, and at both ingress trackers
    `pkt_open[0]` clears.

Latency for one hop is roughly: FIFO write, two synchroniser cycles, FWFT pre-read, one
cycle in the input buffer, one in the crossbar. The per-hop cost inside the mesh is one
`sync_fifo` stage; the expensive part is the two GALS crossings at the ends.

---

## 8. The seven bugs

In the order they were found. For each: what was seen, how it was found, why it
happened, what changed, how it was checked. `HANDOFF.md` has the measurement tables;
this has the story.

### Bug #1: the arbiter released a port mid-packet

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

### Bug #2: round-robin starvation

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

### Bug #3: the two VCs cross-blocked each other

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

### Bug #4: the agent truncated a packet at window end and wedged a port

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

### Bug #5: a source that vanishes mid-packet locks the port forever, and the fix had a hole

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
unbounded), `KILL_MIDPKT` (survivors keep running with gaps of 886 and 1104), and the
regression unchanged. There is no silicon failure to regress against because the fix
removes the trigger. Note that `HANDOFF.md` section 5's first bullet still says the
arbiter cannot recover from a truncated packet; that was written with bug #4 and is
stale since this commit.

### Bug #6: an off-board destination hangs the whole fabric

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
`assert_good_dest_passes` added, covers show the filter fires and the mesh keeps
delivering), `tb_noc_stress_tester` reporting `DEST: err_cnt=0` on clean traffic with
numbers identical to before, and the board reading `dest_err_cnt` 0 with the probe
present.

An incidental fix came with it: `arty_stress_top.sv` declared two nets after the
instance that drove them, which Vivado synthesis tolerated and `xvlog` did not.

### Bug #7: a rejected flit eats its packet's `tlast`

**Found by** formal on the mesh, root-caused 2026-09-11 (`31d4cba`), fixed the same
day (`de8cac3`). Not yet on the board.

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

- Mesh formal with the one-hot assumption **removed**: bmc depth 10 PASS in 7m42s,
  `assert_eject_dest` holding on its own; covers reach the force-close (step 4) and a
  synthetic tail arriving (step 5).
- Wrapper formal with its one-hot assumption removed: prove PASS basecase + induction;
  covers reach a single and a double force-close.
- Six-test regression in both clock configurations, totals identical to the `_FIXED`
  baselines. Stress tester clean run identical to before.
- `BAD_TID` runs, comparing the pre-fix RTL and the fix: the other three agents'
  `max_gap` went from **1209 / 886 / 1104** cycles to 65 / 41 / 150. Before the fix, one
  bad flit from one host was a ~1100-cycle stall for every other node, on top of the
  misdelivery; that stall was in the pre-fix data all along (the same 886/1104 appear in
  the `KILL_MIDPKT` numbers of bug #5) and had not been recognised for what it was.

The sequence-error count under `tid=11` moved from 1 to 2; the checker is per-flit and
6-bit-modulo so that number is "how many VC lanes saw a jump that was not a multiple of
64", which shifts with a one-cycle timing change. It is not a regression signal. The
misdelivery itself cannot be shown in this simulation because every agent has a fixed
destination; that rests on the proof.

**Still to do:** build `PATTERN=1 VC_MODE=2` and confirm on the board that the clean
run reads `tid_err` 0 / `dest_err` 0 with all four node probes present and zero
sequence errors.

### What the seven have in common

Four of them (#1, #4, #5, #7) are the same sentence from section 2.3: a port is held
until `tlast`, and something made `tlast` not arrive or arrive for the wrong packet.
Two (#3 and #2) are arbitration policy that looked right and was wrong under sustained
contention. One (#6) is an address range nobody checked. None of the first three was
caught by the original five simulation tests or by the permutation hardware run; they
would have shipped. Every later one was found by a check written specifically because
the previous bug showed a blind spot: test 6 after #2, the liveness watchdog after #3,
formal after #4, dropping assumptions one at a time after formal existed.

---

## 9. How it is verified

### 9.1 Simulation

Three testbenches plus the stress tester, section 6.6. Run from the Vivado project
(`run_sim_regression.tcl`) or straight off the sources with `xvlog`/`xelab`/`xsim`;
`HANDOFF.md` section 2 gives the compile order. Pass criteria for the six-test
regression: 6/6, `Mismatched=0`, `Pending=0`, in all four `HW_CLOCKS` × `HS_VC_ALT`
combinations. The checked-in `_FIXED` logs are the baselines; a change that alters any
`Matched` total needs an explanation.

### 9.2 Formal

SymbiYosys under WSL (`Ubuntu-24.04`, OSS CAD Suite in `/opt/eda/oss-cad-suite`:
Yosys 0.68, SBY 0.68, Z3 4.15.5). One script per module in `formal/`, eleven modules,
22 tasks (prove or bmc, plus cover), all green at `de8cac3`.

Conventions that matter:

- `FORMAL` blocks live inside the RTL under `` `ifdef FORMAL ``. A module's own block is
  disabled with `` `ifndef FORMAL_TOP_INTEGRATION `` (arbiters, counters) or
  `-D FORMAL_NO_ROUTER` (router) when a parent is being proved, so assumptions never land
  on driven wires.
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
  bad state while the assert is off (documented at `assert_close_pend_only_open` in the
  wrapper).
- Assumptions are removed as soon as the RTL enforces the property. `tdest` range
  (bug #6) and one-hot `tid` (bug #7) both went from assumption to proof.

Two properties written during this work turned out to be wrong and the runs said so:
`assert_idle_tid` (stricter than AXI4-Stream allows) and the ECC sticky-latch asserts
(vacuous and induction-breaking). Both are recorded in `HANDOFF.md` so nobody re-adds
them.

### 9.3 Silicon

Flow: `setup_stress_build.tcl` → synthesis → `setup_debug.tcl` in the same session →
implementation in a **fresh** session → program → Hardware Manager, Trigger Immediately →
export each ILA to CSV → `python analyze_ila.py <folder>`.

The ILA carries ~1080 `MARK_DEBUG` bits across five cores (one per clock domain): every
agent counter, the perf monitors, the ECC/`dest_err`/`tid_err` nodes and counters, and
`stuck_seen`/`max_gap`. `analyze_ila.py` computes throughput per agent in MB/s (each
agent's window is a different wall-clock length, gotcha 4), link utilisation, a
conservation check (flits in = flits out), the arbiter split, and verdicts for liveness,
ECC and `dest_err`. It says "unprovable" rather than "pass" when a probe is missing.

Every number in `HANDOFF.md` has a log in `hw_logs/`. The ECC alarm path was proved on
silicon on 2026-09-10 by building once with `ECC_INJECT_SBE`: all four nodes flagged
(`node_sbe = 1111`, `ecc_sbe_cnt = 3`), the double-bit counter stayed 0, traffic stayed
correct. A counter that reads 0 on a normal build now means "silent", not
"disconnected".

The lesson that shaped all of it: **a green light must be evidence, not absence of
evidence.** The pass LEDs used to light on a deadlocked fabric because the agent's FSM
advanced on a cycle counter. Now `done` requires flits to have moved, the pass LEDs are
gated off by every error flag, and every analyser verdict says "unprovable" when its
probe is absent.

---

## 10. On the board: hardware-specific behaviour

Everything above is true in simulation as well. This section is what is only true, or
only visible, on the Arty. It is written from the last bitstream on disk
(`impl_1/arty_stress_top.bit`, 2026-09-10, stress build with five ILA cores) and the
logs in `hw_logs/`.

### 10.1 What the bitstream contains

| | |
|---|---|
| part | xc7a100tcsg324-1 (Arty A7-100T, Digilent 210319C088F2A) |
| top | `arty_stress_top`, `PATTERN=1 VC_MODE=2` |
| clocking | one `MMCME2_ADV`: 100 MHz in, VCO 1000 MHz (mult 10), outputs divided by 12.5 / 10 / 14 / 12 / 14 |
| slice LUTs | 10,898 of 63,400 (17%) |
| slice registers | 16,244 of 126,800 (13%) |
| block RAM tiles | 31.5 of 135 (23%) |
| timing | WNS **+0.711 ns**, WHS +0.014 ns, TPWS +3.0 ns; every constraint met |
| debug | 1104 `MARK_DEBUG` nets → 5 ILA cores / 55 probes / 1100 bits, plus `dbg_hub` |

Most of the block RAM is ILA capture memory, not the fabric. The fabric's own storage is
small: each router has 5 ports x 2 VCs x 16 entries x 13 bits in distributed RAM, and
each wrapper has 4 async FIFOs of 16 x 13 bits. The MMCM is the only clock resource.

For comparison, the UART build (`arty_gals_noc_wrapper`) closes at WNS +1.120 ns with
463 `MARK_DEBUG` nets in 5 cores.

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

Anything that crosses domains by another route is a bug that no tool here will flag.
`README.md` suggests `report_cdc -details` as the check; it has not been made part of
the scripted flow.

Simulation has no metastability. Every crossing in xsim resolves cleanly whatever the
phase. The board is the only place the synchroniser design is actually exercised, and
the evidence that it works is indirect: zero sequence errors over 3.9 million flits per
sender, every run.

### 10.3 Reset and power-up

`global_rst_n = rst_n_btn & pll_locked`. The design is held in reset until the MMCM
locks, and the button resets the logic only. The MMCM's own reset is tied to 0: an
earlier build wired the button to it, and pressing the button killed all five clocks,
including the one `dbg_hub` and the ILAs run on, so every capture died with the reset.

Reset is asynchronous active-low in every domain. RAM contents are not reset (Xilinx RAM
primitives cannot be), which is why `async_fifo` qualifies the ECC flags with
`ecc_read_valid`: before the first real read the decoder is looking at whatever the RAM
powered up with.

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
- `dest_err_node[3:0]` is missing from the stress build's ILA: its clock did not resolve
  through the script's driver walk. `dest_err_cnt` is present, so the question "did it
  happen" is answerable and "which node" is not. `tid_err_node` did resolve.
- The `MARK_DEBUG` net count is the fingerprint of what was instrumented: 924 (original),
  928 (+watchdog), 1024 (+`max_gap`), 1064 (+ECC), 1084 (+`dest_err`), 1104
  (+`tid_err`). Any other number means Set Up Debug was not re-run after an RTL change,
  and the analyser will refuse to pass liveness.

### 10.9 The build flow has state that follows you

These are the traps in section 12 restated as behaviour, because on the board they look
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

`tb_noc_stress_tester` with `HW_CLOCKS` predicts the board to within a fraction of a
percent on every throughput figure, and is pessimistic only on the gap. That is what
justifies treating a passing stress run as evidence before a board is available.

### 10.12 Not yet on the board

- The bug #7 fix (`de8cac3`). Everything after `0815e10` is proved and simulated only.
- ECC double-bit injection (`ECC_INJECT_DBE`); only the single-bit path has been run on
  silicon.
- The UART build with the `tid` guard and bug #7 logic; its last bitstream is from
  2026-09-04.
- Bug #5's failure mode; the fix removes the trigger, so there is nothing to observe.

---

## 11. Timeline

| date | commit | what |
|---|---|---|
| Apr–Jul 2026 | (pre-git) | RTL written: FIFOs, ECC, router, mesh, wrapper, agents, UART host |
| 2026-08-17 | `f9b73a9` | initial commit |
| 2026-08-18 | `2ac2e05` | test 6 added; bug #2 fixed |
| 2026-08-19 | `04cd562`..`e1571ba` | `VC_MODE` selector; bug #3 isolated, root-caused with `SIM_DEBUG`, fixed; `HANDOFF.md` created |
| 2026-09-01 | `cba4e60`..`cbc4514` | bug #3 confirmed on board (57.5% → 97.0%); liveness watchdog added; bug #4 found by it, fixed, confirmed (+15.7%) |
| 2026-09-03 | `b2b5a14`..`0d62c26` | arbiter fairness shown to be topology; ECC proved exhaustively; ECC flags wired end to end (they had been left dangling); `analyze_ila.py` ECC section |
| 2026-09-04 | `e9f8197`..`94d5c1d` | bug #5 fixed, first real arbiter formal proof; formal for every datapath module; bug #6 found by formal and fixed; scripted debug flow; UART build restored; `noc_host.py` one-hot fix; silicon regression for #4/#5/#6 |
| 2026-09-09 | `153d12a`, `9f20a94` | `.gitignore`; PR #2 merged to `main` |
| 2026-09-10 | `8853d5c`, `0815e10` | ECC fault injector, alarm path proved on silicon; `tid` guard at both layers; two debug-flow traps fixed |
| 2026-09-11 | `31d4cba`, `de8cac3` | bug #7 root-caused and fixed; one-hot `tid` assumption removed from formal |

---

## 12. Things that cost real time

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
9. `wsl bash -c '... $PATH ...'` from Git Bash expands `$PATH` locally; use
   `formal/run_wsl.sh`.
10. Window-buffered console output is lost when a process is killed by `timeout`;
    flush or write to a file.
11. `final_src/` and `sources_1/new/old/` are stale; the old `.sby` files there verified
    a different project.

---

## 13. What is still open

- **Bug #7 on the board.** Build `PATTERN=1 VC_MODE=2`, confirm `tid_err` 0 / `dest_err`
  0 / 0 sequence errors / liveness PASS with the added ingress state. Timing should be
  unaffected; check the `clk_host` paths in `gals_node_wrapper`.
- **`tdest` constant per packet is still an assumption.** The router misroutes silently
  if it is broken. Recorded in `f_wf`; not enforced.
- **`dest_err_node[3:0]` is absent from the stress build's ILA** (clock did not resolve);
  `dest_err_cnt` survives.
- **ECC covers the payload only**, and SECDED misreports three or more flipped bits.
- **`HANDOFF.md` section 5, first bullet** ("`packet_arbiter` cannot recover from a
  truncated packet") is stale since bug #5's timeout. Worth correcting on the next
  documentation pass.
- **The branch is not merged.** `feature/2-ecc-injection-and-tid-guard` carries the ECC
  injector, the `tid` guard and bug #7 on top of `main`.

---

## 14. Reproducing the results

All paths relative to the repo root. Vivado 2025.2 at `C:/AMDDesignTools/2025.2`.

Six-test regression, from the Vivado Tcl console:

    set HW_CLOCKS 1 ; set HS_VC_ALT 1 ; source run_sim_regression.tcl

Same thing without the project (faster, no project state), compile order in
`HANDOFF.md` section 2; elaborate `work.tb_noc_mesh_2x2_gals`, pass switches as
`-d HW_CLOCKS -d HS_VC_ALT`, run with `run all; quit`.

Stress tester with a directed fault (parameters via a wrapper top, gotcha 8):

    module tb_wrap; tb_noc_stress_tester #(.BAD_TID(2)) u(); endmodule

Formal, one module:

    MSYS_NO_PATHCONV=1 wsl -d Ubuntu-24.04 -- bash /mnt/d/.../formal/run_wsl.sh packet_arbiter.sby

or inside WSL, `cd formal && sby -f packet_arbiter.sby`. The mesh bmc takes ~8 minutes,
the router ~2, everything else under a minute.

Board:

    set PATTERN 1 ; set VC_MODE 2 ; source setup_stress_build.tcl
    # after synth_1 completes, same session:
    open_run synth_1 ; source setup_debug.tcl
    # new Vivado session:
    launch_runs impl_1 -to_step write_bitstream -jobs 8
    # program, Hardware Manager, Trigger Immediately, export CSVs, then:
    python analyze_ila.py <csv-folder>

Expect ~1080 `MARK_DEBUG` nets; other counts mean a stale Set Up Debug (see `HANDOFF.md`
section 2 for the decoder ring). Clear `verilog_define` after any `ECC_INJECT_*` build.

UART build:

    source setup_uart_build.tcl
    python noc_host.py        # set COM_PORT first

---

## 15. Glossary

- **flit**: flow-control unit, the 8-bit-plus-control word that moves one link per cycle.
- **packet**: a sequence of flits ending in one with `tlast = 1`.
- **head / body / tail**: first flit (routes the packet), middle flits, last flit.
- **wormhole switching**: forward flit by flit; the head claims a port, the tail releases it.
- **VC, virtual channel**: an independent queue and credit on a shared physical link.
  VC0 = normal, VC1 = priority. `tid` selects it, one-hot.
- **XY routing**: move in X until aligned, then Y. Deadlock-free on a mesh.
- **GALS**: globally asynchronous, locally synchronous. Islands on their own clocks,
  async FIFOs between them.
- **CDC**: clock-domain crossing.
- **gray code**: encoding where consecutive values differ in one bit; used for pointers
  that cross clock domains.
- **FWFT**: first-word-fall-through; FIFO output is valid whenever non-empty, no read
  latency.
- **SECDED**: single-error-correct, double-error-detect Hamming code.
- **sticky flag**: a bit that is set once and never cleared until reset.
- **backpressure**: the receiver deasserting `ready`, holding the sender.
- **head-of-line blocking**: a stuck flit at the front of a queue blocking everything
  behind it.
- **starvation**: a requester that never wins arbitration.
- **round-robin**: arbitration that rotates priority after each grant.
- **BMC**: bounded model checking; explores all inputs up to N steps from reset.
- **k-induction / prove**: shows the property holds in every reachable state, unbounded.
- **cover**: a formal check that some state is reachable, guarding against vacuous proofs.
- **vacuous**: a proof that passes because the assumptions rule out every interesting
  case.
- **ILA**: Xilinx integrated logic analyser; captures nets marked `mark_debug`.
- **MMCM**: the clock generator on the FPGA.
- **hot-spot**: traffic pattern where several senders target one node (`PATTERN=1`).
- **permutation**: every node sends to one distinct partner (`PATTERN=0`).
- **liveness**: "something eventually happens"; here, flits keep moving during `S_RUN`.
- **utilisation**: flits transferred / cycles observed on one link.
