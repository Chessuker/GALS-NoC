#!/usr/bin/env python3
"""
analyze_ila.py - อ่าน iladata*.csv ที่ export จาก Vivado Hardware Manager
                 แล้วคำนวณ throughput / link utilisation / stall ให้อัตโนมัติ

    python analyze_ila.py <folder-that-has-iladata*.csv>

ตัวเลขพวกนี้ Vivado ไม่ได้รายงานให้ ต้องคำนวณจากตัวนับใน ILA เอง
"""
import csv, re, sys, glob, os
# Windows console default cp1252 พิมพ์ไทยไม่ได้ ต้องบังคับเป็น utf-8 ก่อน
try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

# ความถี่จาก MMCM (VCO 1000 MHz) - ดู clk_wiz_0.xci
CLK = {'agent_00': 1000/10.0,   # clk_out2  100.00 MHz
       'agent_01': 1000/14.0,   # clk_out3   71.43 MHz
       'agent_10': 1000/12.0,   # clk_out4   83.33 MHz
       'agent_11': 1000/14.0}   # clk_out5   71.43 MHz
CLK_NOC   = 1000/12.5           # clk_out1   80.00 MHz  (ความจุลิงก์ = 1 flit/cycle)
WINDOW_LOG = 24                 # ต้องตรงกับ parameter ใน traffic_node_agent
WINDOW     = 1 << WINDOW_LOG

def load(path):
    rows = list(csv.reader(open(path, newline='')))
    hdr  = rows[0]
    data = [r for r in rows[2:] if len(r) == len(hdr)]
    m = re.search(r'(agent_\d\d)', ' '.join(hdr))
    if not m:
        return None
    agent = m.group(1)
    cols = {}
    for i, h in enumerate(hdr):
        mm = re.search(r'agent_\d\d/(\w+)', h)
        if mm:
            cols[mm.group(1)] = i
    def col(name):
        return [int(r[cols[name]], 16) for r in data] if name in cols else None
    return agent, {k: col(k) for k in cols}, len(data)

def main(folder):
    files = sorted(glob.glob(os.path.join(folder, 'iladata*.csv')))
    if not files:
        print(f'ไม่พบ iladata*.csv ใน {folder}')
        return 1
    A = {}
    for f in files:
        r = load(f)
        if r:
            A[r[0]] = (r[1], r[2], os.path.basename(f))

    print(f'พบ {len(A)} agent: {", ".join(sorted(A))}\n')

    res = {}
    for a in sorted(A):
        d, n, fn = A[a]
        st = set(d['state_dbg'])
        done = set(d['test_done'])
        frozen = (st == {3}) or (done == {1})
        # โหมด final: จบ window แล้ว ใช้ยอดรวมหารด้วยความยาว window
        # โหมด delta: จับกลางรัน ใช้ผลต่างหัวท้ายของหน้าต่าง
        if frozen:
            mode = 'final'
            div  = float(WINDOW)
            g = lambda k: d[k][-1]
        else:
            mode = 'delta'
            div  = float(n - 1)
            g = lambda k: d[k][-1] - d[k][0]
        rate_tx    = g('tx_flit_cnt')  / div
        rate_stall = g('tx_stall_cnt') / div
        rate_rx    = (g('rx_vc0_cnt') + g('rx_vc1_cnt')) / div
        res[a] = dict(mode=mode, n=n, file=fn, state=sorted(st),
                      rate_tx=rate_tx, rate_stall=rate_stall, rate_rx=rate_rx,
                      tx_mfs=rate_tx*CLK[a], rx_mfs=rate_rx*CLK[a],
                      err=max(d['rx_err_cnt']), dest=sorted(set(d['rx_tdest_dbg'])),
                      vc0=g('rx_vc0_cnt'), vc1=g('rx_vc1_cnt'),
                      tot_rx=d['rx_vc0_cnt'][-1]+d['rx_vc1_cnt'][-1],
                      tot_tx=d['tx_flit_cnt'][-1], tot_stall=d['tx_stall_cnt'][-1])

    senders = [a for a in res if res[a]['rate_tx'] > 1e-9]
    hotspot = len(senders) == 3 and 'agent_00' not in senders

    print(f'{"agent":<10}{"clk MHz":>9}{"mode":>7}{"state":>8}{"TX/cyc":>9}'
          f'{"stall%":>9}{"RX/cyc":>9}{"TX MB/s":>10}{"errors":>8}{"dest":>6}')
    print('-'*85)
    for a in sorted(res):
        r = res[a]
        stall_pct = 100.0*r['rate_stall']/(r['rate_tx']+r['rate_stall']) if (r['rate_tx']+r['rate_stall'])>0 else 0.0
        print(f'{a:<10}{CLK[a]:>9.2f}{r["mode"]:>7}{str(r["state"]):>8}'
              f'{r["rate_tx"]:>9.4f}{stall_pct:>9.1f}{r["rate_rx"]:>9.4f}'
              f'{r["tx_mfs"]:>10.2f}{r["err"]:>8}{str(r["dest"]):>6}')

    # ---- VC split: ยืนยันว่า build ที่จับมาใช้ VC_MODE ตัวไหนจริง
    print()
    print('  VC split ของ flit ที่รับได้:')
    for a in sorted(res):
        r = res[a]
        trx = r['vc0'] + r['vc1']
        if trx == 0:
            print(f'    {a}: (ไม่ได้รับ flit)')
        else:
            print(f'    {a}: VC0 {r["vc0"]:>10,} ({100.0*r["vc0"]/trx:5.1f}%)   '
                  f'VC1 {r["vc1"]:>10,} ({100.0*r["vc1"]/trx:5.1f}%)')
    tot_vc1 = sum(res[a]['vc1'] for a in res)
    tot_vc0 = sum(res[a]['vc0'] for a in res)
    if tot_vc1 == 0 and tot_vc0 > 0:
        print('    -> VC1 เป็น 0 ทุกตัว : build นี้คือ VC_MODE=0 (VC0 อย่างเดียว)')
    elif tot_vc0 == 0 and tot_vc1 > 0:
        print('    -> VC0 เป็น 0 ทุกตัว : build นี้คือ VC_MODE=1 (VC1 อย่างเดียว)')
    elif tot_vc0 > 0 and tot_vc1 > 0:
        print('    -> มีทั้งสอง VC : build นี้คือ VC_MODE=2 (สลับทุกแพ็กเกจ)')

    total_tx = sum(res[a]['tx_mfs'] for a in res)
    total_rx = sum(res[a]['rx_mfs'] for a in res)
    print('-'*85)
    print(f'\nรวม injected : {total_tx:7.1f} Mflit/s = {total_tx:7.1f} MB/s (flit ละ 8 บิต)')
    print(f'(ยอด RX รวม {total_rx:.1f} MB/s เอามาเทียบกับ TX ตรงๆ ไม่ได้ '
          'เพราะแต่ละ agent ปิดหน้าต่างคนละเวลา ดูตาราง conservation ข้างล่างแทน)')

    print(f'\nรูปแบบทราฟฟิก : {"HOT-SPOT (3 -> node 00)" if hotspot else "PERMUTATION (00<->11, 01<->10)"}')
    if hotspot:
        u = total_rx / CLK_NOC * 100.0
        print(f'  local output port ของ node 00 : {total_rx:.1f} / {CLK_NOC:.0f} Mflit/s = {u:.1f}% utilisation')
        print(f'\n  ความยุติธรรมของ arbiter (ยิ่งใกล้กันยิ่งแฟร์):')
        sh = {a: res[a]['tx_mfs'] for a in senders}
        mx, mn = max(sh.values()), min(sh.values())
        for a in sorted(sh):
            print(f'    {a}: {sh[a]:6.2f} Mflit/s  ({sh[a]/total_tx*100:5.1f}% ของทั้งหมด)')
        print(f'    spread = {(mx-mn)/mx*100:.1f}%   (0% = แบ่งเท่ากันเป๊ะ)')
    else:
        per = total_tx/4.0
        print(f'  แต่ละ flow ใช้ลิงก์คนละเส้น ไม่ทับกัน -> ต่อลิงก์ = {per:.1f} / {CLK_NOC:.0f} Mflit/s'
              f' = {per/CLK_NOC*100:.1f}% utilisation')
        print(f'\n  ตรวจโมเดล GALS (อัตราถูกจำกัดโดยนาฬิกาฝั่งที่ช้ากว่าในคู่):')
        pair = {'agent_00':'agent_11','agent_11':'agent_00','agent_01':'agent_10','agent_10':'agent_01'}
        worst = 0.0
        for a in sorted(res):
            p = pair[a]
            if p not in res: continue
            pred = min(1.0, CLK[p]/CLK[a])
            meas = res[a]['rate_tx']
            e = abs(meas-pred)/pred*100 if pred else 0
            worst = max(worst, e)
            print(f'    {a}: predicted {pred:.4f}  measured {meas:.4f}  error {e:5.2f}%')
        print(f'    worst-case error = {worst:.2f}%')

    # ---- conservation ราย flow (ใช้ได้เฉพาะ mode final)
    if all(res[a]['mode'] == 'final' for a in res) and not hotspot:
        WS = {a: WINDOW/(CLK[a]*1e6) for a in CLK}
        PAIR = {'agent_00':'agent_11','agent_11':'agent_00',
                'agent_01':'agent_10','agent_10':'agent_01'}
        print('')
        print('  ตรวจ conservation ราย flow:')
        hdr = '    {:<14}{:>14}{:>14}{:>12}{:>14}{:>7}'.format(
              'flow','TX flits','RX flits','window','คาดว่าได้','ผล')
        print(hdr)
        allok = True
        for src in sorted(res):
            dst = PAIR.get(src)
            if dst not in res:
                continue
            ntx = res[src]['tot_tx']
            nrx = res[dst]['tot_rx']
            covered = WS[dst] >= WS[src] - 1e-12
            exp = ntx*min(1.0, WS[dst]/WS[src])
            ok  = abs(exp-nrx)/max(exp,1) < 0.002
            allok = allok and ok
            print('    {:<14}{:>14,}{:>14,}{:>12}{:>14,.0f}{:>7}'.format(
                  src[-2:]+' -> '+dst[-2:], ntx, nrx,
                  'ครบ' if covered else 'ถูกตัด', exp, 'OK' if ok else 'FAIL'))
        print('    "ครบ"    = หน้าต่างผู้รับยาวกว่าผู้ส่ง -> TX ต้องเท่า RX เป๊ะ (พิสูจน์ว่าไม่มี flit หาย)')
        print('    "ถูกตัด" = ผู้รับปิดหน้าต่างก่อน ตัวเลขน้อยกว่าตามสัดส่วนเวลา ไม่ใช่ของหาย')
        print('    -> ' + ('ผ่านทุก flow' if allok else 'มี flow ที่ไม่ตรง'))

    tot_err = sum(res[a]['err'] for a in res)
    print(f'\nsequence errors รวมทุก agent : {tot_err}   ->  {"PASS" if tot_err==0 else "FAIL"}')
    if any(res[a]['mode']=='delta' for a in res):
        print('\nหมายเหตุ: บาง agent จับกลางรัน (mode=delta) ค่าที่ได้คืออัตรา ณ ช่วงนั้น')
        print('          ห้ามเอายอดสะสมของคนละ agent มาเทียบกันตรงๆ เพราะ trigger คนละจังหวะ')
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv)>1 else '.'))
