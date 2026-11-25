#!/usr/bin/env python3
"""Derive the file order Sail used from the Rocq decoder Sail generated, and check an extraction.

Sail emits the encdec clauses in its own order (respecting `before`/`requires` in
riscv.sail_project). The generated `encdec_backwards` tries them in that order, so the first
occurrence of each instruction constructor in it gives the clause order.

  python3 order_from_rocq.py derive <rv32d.v> <encdec_clauses.json> > files.txt
  python3 order_from_rocq.py check  <rv32d.v> <encdec_clauses.json>

The authoritative alternative needs Sail itself (run in sail-riscv/model):
  sail riscv.sail_project --all-modules --list-files-separated $'\\n' > files.txt
"""
import json, re, sys, os

def body(rocq, name):
    txt = open(rocq).read()
    start = txt.index('Definition %s (' % name)
    end = txt.index('\nDefinition ', start + 1)
    return txt[start:end]

def ctor_sequence(rocq, name, ctors):
    seq, seen = [], set()
    for m in re.finditer(r'\b([A-Z][A-Za-z0-9_]*)\b', body(rocq, name)):
        c = m.group(1)
        if c in ctors and c not in seen:
            seen.add(c); seq.append(c)
    return seq

def main():
    mode, rocq, js = sys.argv[1:4]
    C = json.load(open(js))['clauses']
    chains = []
    ok = True
    for mapping, fn in [('encdec', 'encdec_backwards'), ('encdec_compressed', 'encdec_compressed_backwards')]:
        rows = [c for c in C if c['mapping'] == mapping]
        ctors = {c['constructor'] for c in rows}
        seq = ctor_sequence(rocq, fn, ctors)
        pos = {c: i for i, c in enumerate(seq)}
        if mode == 'derive':
            rank = {}
            for c in rows:
                if c['constructor'] in pos:
                    f = c['file'][len('model/'):] if c['file'].startswith('model/') else c['file']
                    rank[f] = min(rank.get(f, 10 ** 6), pos[c['constructor']])
            chains.append([f for f, _ in sorted(rank.items(), key=lambda kv: kv[1])])
            missing = sorted({c['constructor'] for c in rows} - set(pos))
            if missing: print('# %s: not in generated decoder: %s' % (mapping, ', '.join(missing)), file=sys.stderr)
        else:
            mine, seen = [], set()
            for c in sorted(rows, key=lambda c: c['order']):
                if c['constructor'] not in seen:
                    seen.add(c['constructor']); mine.append(c['constructor'])
            mine = [c for c in mine if c in pos]
            if mine == seq:
                print('%s: order OK (%d constructors)' % (mapping, len(seq)))
            else:
                ok = False
                for i, (a, b) in enumerate(zip(mine, seq)):
                    if a != b:
                        print('%s: first difference at %d: extraction %s, Sail %s' % (mapping, i, a, b)); break
                print('%s: lengths %d vs %d' % (mapping, len(mine), len(seq)))
    if mode == 'derive':
        # one global file order consistent with the order in every mapping (topological merge)
        files, succ, indeg = [], {}, {}
        for ch in chains:
            for f in ch:
                if f not in succ: files.append(f); succ[f] = set(); indeg[f] = 0
            for a, b in zip(ch, ch[1:]):
                if b not in succ[a]: succ[a].add(b); indeg[b] += 1
        prio = {f: i for i, f in enumerate(files)}
        ready = sorted([f for f in files if indeg[f] == 0], key=prio.get)
        out = []
        while ready:
            f = ready.pop(0); out.append(f)
            for g in succ[f]:
                indeg[g] -= 1
                if indeg[g] == 0: ready.append(g)
            ready.sort(key=prio.get)
        if len(out) != len(files): print('# cycle: no consistent file order', file=sys.stderr); sys.exit(1)
        print('\n'.join(out))
    sys.exit(0 if ok else 1)

if __name__ == '__main__':
    main()
