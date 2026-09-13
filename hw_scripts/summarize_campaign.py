#!/usr/bin/env python3
"""summarize_campaign.py - one row per fault mode from a batch_fault_campaign.tcl run.

    python hw_scripts/summarize_campaign.py <out_root>

Reads <out_root>/mode_N/iladata*.csv (the same files analyze_ila.py reads) and prints the
counters that decide each mode, with the expected signature next to them. The full
per-mode analysis is still available with  python analyze_ila.py <out_root>/mode_N
"""
import csv, glob, os, re, sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

EXPECT = {
    0: "clean: 0 err, liveness 4/4, no flags",
    1: "agent_11 tvalid cut mid-packet: others' max_gap ~1k (bug #5 release), agent_11 liveness may FAIL, no seq err",
    2: "tid=00 for 2000 cyc: tid_err node 1000, others' gap normal, <=2 resync err",
    3: "tid=11 for 2000 cyc: tid_err node 1000, others' gap normal, <=2 resync err",
    4: "tdest=0001 for 2000 cyc: dest_err node 1000, agent_10 rx>0, others' gap normal",
    5: "tdest=1000 (off-board) for 2000 cyc: dest_err node 1000, fabric alive, others' gap normal",
}

def val(v, rdx):
    try:
        if 'HEX' in rdx.upper(): return int(v, 16)
        if 'BIN' in rdx.upper(): return int(v, 2)
        return int(v)
    except Exception:
        return None

def load_mode(folder):
    last = {}
    for f in sorted(glob.glob(os.path.join(folder, 'iladata*.csv'))):
        rows = list(csv.reader(open(f, newline='')))
        if len(rows) < 3: continue
        hdr, rdx = rows[0], rows[1]
        data = [r for r in rows[2:] if len(r) == len(hdr)]
        if not data: continue
        for h, r, v in zip(hdr, rdx, data[-1]):
            last[h] = val(v, r)
    return last

def pick(d, pat):
    for k, v in d.items():
        if re.search(pat, k): return v
    return None

def pick_node(d, base):
    # a 4-bit bus arrives either as one 'base[3:0]' column or, when synthesis folded some bits
    # to constants (dest_err_node[2:0] in the stress build), as single-bit 'base[N]' columns
    v = pick(d, rf'{base}\[3:0\]')
    if v is not None: return v
    bits = 0; found = False
    for k, val in d.items():
        m = re.search(rf'{base}\[(\d)(?::(\d))?\]$', k)   # 'base[3]' or a slice 'base[3:3]'
        if not m: continue
        found = True
        hi = int(m.group(1)); lo = int(m.group(2)) if m.group(2) else hi
        if val: bits |= (val & ((1 << (hi - lo + 1)) - 1)) << lo
    return bits if found else None

def row(m, d):
    g = {a: pick(d, rf'agent_{a}/max_gap') for a in ('00', '01', '10', '11')}
    st = {a: pick(d, rf'agent_{a}/stuck_seen') for a in ('00', '01', '10', '11')}
    err = pick(d, r'agent_00/rx_err_cnt')
    rx10 = pick(d, r'agent_10/rx_vc0_cnt') or 0
    rx10 += pick(d, r'agent_10/rx_vc1_cnt') or 0
    return dict(
        mode=m, fired=pick(d, r'fault.*fired'), active=pick(d, r'fault.*active'),
        seq_err=err, gaps=[g[a] for a in ('00', '01', '10', '11')],
        stuck=''.join('1' if st[a] else '0' for a in ('00', '01', '10', '11')),
        tid_cnt=pick(d, r'tid_err_cnt'), tid_node=pick_node(d, 'tid_err_node'),
        dest_cnt=pick(d, r'dest_err_cnt'), dest_node=pick_node(d, 'dest_err_node'),
        dbe=pick(d, r'ecc_dbe_cnt'), rx10=rx10,
    )

def main(root):
    print(f"{'mode':4} {'fired':5} {'seq':4} {'max_gap 00/01/10/11':24} {'stuck':5} {'tid cnt/node':12} {'dest cnt/node':13} {'dbe':3} {'rx@10':7}  expected")
    for m in range(6):
        folder = os.path.join(root, f'mode_{m}')
        if not os.path.isdir(folder): continue
        r = row(m, load_mode(folder))
        node = lambda v: f'{v:04b}' if isinstance(v, int) else '----'
        gaps = '/'.join(str(x) if x is not None else '-' for x in r['gaps'])
        print(f"{m:4} {str(r['fired']):5} {str(r['seq_err']):4} {gaps:24} {r['stuck']:5} "
              f"{str(r['tid_cnt'])+'/'+node(r['tid_node']):12} {str(r['dest_cnt'])+'/'+node(r['dest_node']):13} "
              f"{str(r['dbe']):3} {r['rx10']:7}  {EXPECT[m]}")

if __name__ == '__main__':
    main(sys.argv[1])
