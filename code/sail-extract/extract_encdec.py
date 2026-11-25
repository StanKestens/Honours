#!/usr/bin/env python3
"""Extract every `encdec` / `encdec_compressed` clause from a sail-riscv checkout.

For each clause it records the instruction constructor, the bit layout of the
encoding (MSB first, as written in Sail), a mask/value pair, set-valued field
constraints coming from partial helper mappings, and the `when` guard.

Usage:  python3 extract_encdec.py <path-to-sail-riscv> <output-dir> [files.txt]
"""
import json, os, re, sys, csv, collections

SAIL = sys.argv[1]
OUT = sys.argv[2]
MODEL = os.path.join(SAIL, 'model')
WIDTH_OF = {'encdec': 32, 'encdec_compressed': 16}

# ------------------------------------------------------------------ files
def sail_files():
    res = []
    for dp, dn, fn in os.walk(MODEL):
        for f in fn:
            if f.endswith('.sail'):
                res.append(os.path.join(dp, f))
    return res

def project_order():
    """File order. Preferably the order Sail itself uses (respecting `before`/`requires`
    in riscv.sail_project), given as a third argument: a file with one path per line, made with
      sail riscv.sail_project --all-modules --list-files-separated $'\\n' > files.txt
    Without it: textual order of riscv.sail_project, which is WRONG for clauses whose module
    says `before I_insts` (ZICBOP, NTL, PAUSE, LPAD, ...)."""
    if len(sys.argv) > 3:
        return [l.strip() for l in open(sys.argv[3]) if l.strip()]
    txt = open(os.path.join(MODEL, 'riscv.sail_project')).read()
    return re.findall(r'([A-Za-z0-9_./-]+\.sail)\b', txt)

def strip_comments(s):
    s = re.sub(r'/\*.*?\*/', ' ', s, flags=re.S)
    return re.sub(r'//[^\n]*', '', s)

FILES = {p: strip_comments(open(p).read()) for p in sail_files()}
RAWLINES = {p: open(p).read().split('\n') for p in FILES}

# ------------------------------------------------------------------ type aliases
ALIAS = {}
for p, t in FILES.items():
    for m in re.finditer(r'^type\s+(\w+)\s*=\s*bits\((\d+)\)', t, re.M):
        ALIAS[m.group(1)] = int(m.group(2))
    for m in re.finditer(r'^type\s+(\w+)\s*=\s*bits\((\w+)\)', t, re.M):
        pass

def type_width(ty):
    ty = ty.strip()
    m = re.fullmatch(r'bits\((\d+)\)', ty)
    if m: return int(m.group(1))
    return ALIAS.get(ty)

# ------------------------------------------------------------------ helper mappings X <-> bits(N)
HELPERS = {}
for p, t in FILES.items():
    for m in re.finditer(r'^mapping\s+(\w+)\s*:\s*([^=\n]+?)\s*<->\s*([^=\n]+?)\s*=\s*\{', t, re.M):
        name, a, b = m.group(1), m.group(2), m.group(3)
        wa, wb = type_width(a), type_width(b)
        if wb is not None: bits_side, w, other = 1, wb, a
        elif wa is not None: bits_side, w, other = 0, wa, b
        else: continue
        # body
        i = m.end(); depth = 1; j = i
        while depth and j < len(t):
            if t[j] == '{': depth += 1
            elif t[j] == '}': depth -= 1
            j += 1
        body = t[i:j-1]
        info = dict(name=name, width=w, other_type=other.strip(), file=os.path.relpath(p, SAIL))
        if re.search(r'\b(forwards|backwards)\b', body):
            info['kind'] = 'total'
            info['note'] = 'forwards/backwards clauses' + (' with a guard' if re.search(r'\bif\b', body) else '')
            info['body'] = ' '.join(body.split())
        else:
            vals = []; nonlit = False
            for cl in re.split(r',|\n', body):
                if '<->' not in cl: continue
                l, r = [x.strip() for x in cl.split('<->', 1)]
                sym, lit = (l, r) if bits_side == 1 else (r, l)
                if re.fullmatch(r'0b[01_]+', lit): vals.append((sym, int(lit[2:].replace('_', ''), 2)))
                elif re.fullmatch(r'0x[0-9a-fA-F_]+', lit): vals.append((sym, int(lit[2:].replace('_', ''), 16)))
                else: nonlit = True
            if nonlit and not vals:
                info['kind'] = 'total'; info['note'] = 'bits side is a variable (bijection on bits(%d))' % w
                info['body'] = ' '.join(body.split())
            elif nonlit:
                info['kind'] = 'unknown'; info['values'] = vals
            else:
                info['values'] = vals
                info['kind'] = 'total' if len({v for _, v in vals}) == 2 ** w else 'partial'
        HELPERS[name] = info

# ------------------------------------------------------------------ instruction constructor types
UNION = {}
for p, t in FILES.items():
    for m in re.finditer(r'^union clause instruction\s*=\s*(\w+)\s*:\s*(.+)$', t, re.M):
        ty = m.group(2).strip()
        if ty.startswith('('): ty = ty[1:ty.rindex(')')]
        UNION[m.group(1)] = split_top(ty, ',') if False else None
        UNION[m.group(1)] = ty

def split_top(s, sep):
    out, depth, cur = [], 0, ''
    i = 0
    while i < len(s):
        c = s[i]
        if c in '([{': depth += 1
        elif c in ')]}': depth -= 1
        if depth == 0 and s.startswith(sep, i):
            out.append(cur.strip()); cur = ''; i += len(sep); continue
        cur += c; i += 1
    if cur.strip(): out.append(cur.strip())
    return out

for k, v in list(UNION.items()):
    UNION[k] = split_top(v, ',')

# ------------------------------------------------------------------ collect clauses
TOPLEVEL = re.compile(r'^(mapping|function|union|val|type|enum|struct|register|overload|let|end|scattered|bitfield|newtype|\$)')

def collect():
    clauses = []
    for p, lines in RAWLINES.items():
        i = 0
        while i < len(lines):
            m = re.match(r'mapping clause (encdec|encdec_compressed)\s*=', lines[i])
            if m:
                j = i + 1
                while j < len(lines) and lines[j].strip() != '' and not TOPLEVEL.match(lines[j]):
                    j += 1
                txt = strip_comments('\n'.join(lines[i:j]))
                clauses.append(dict(file=os.path.relpath(p, SAIL), line=i + 1, mapping=m.group(1),
                                    sail=' '.join(txt.split())))
                i = j
            else:
                i += 1
    return clauses

ENV_WORDS = re.compile(r'currentlyEnabled|hartSupports|xlen|flen|vlen|get_sew|get_lmul|have\w+\(|sys_|base_E_enabled|\bsupports\w*\(|_supported\(|validDoubleRegs|zvk_check_encdec|valid_reg_overlap')

def classify_guard(g, vars_):
    """Split the guard on top-level `&` and label each conjunct:
    config = only machine configuration/state, field = only encoding fields,
    mixed = both (e.g. `width <= xlen_bytes`)."""
    if not g: return [], [], []
    env, field, mixed = [], [], []
    for a in split_top(g, '&'):
        uses_var = any(re.search(r'\b%s\b' % re.escape(v), a) for v in vars_)
        uses_env = bool(ENV_WORDS.search(a))
        if uses_var and uses_env: mixed.append(a)
        elif uses_var: field.append(a)
        else: env.append(a)
    return env, field, mixed

def parse_clause(c):
    s = c['sail']
    s = re.sub(r'^mapping clause \w+\s*=\s*', '', s)
    lhs, rest = s.split('<->', 1)
    parts = re.split(r'\bwhen\b', rest, maxsplit=1)
    rhs = parts[0].strip(); guard = parts[1].strip() if len(parts) > 1 else ''
    lhs = lhs.strip()
    m = re.match(r'(\w+)\s*(\((.*)\))?\s*$', lhs)
    ctor = m.group(1); args = split_top(m.group(3), ',') if m.group(3) else []
    c.update(constructor=ctor, lhs=lhs, rhs=rhs, guard=guard)
    vars_ = set(re.findall(r'\b([a-z_][a-z0-9_]*)\b', ' '.join(args))) - {'true', 'false'}
    env, field, mixed = classify_guard(guard, vars_)
    c['guard_config'] = env; c['guard_field'] = field; c['guard_mixed'] = mixed
    # var -> type from union declaration
    vtypes = {}
    tys = UNION.get(ctor)
    if tys and len(tys) == len(args):
        for a, ty in zip(args, tys):
            if re.fullmatch(r'[a-z_]\w*', a): vtypes[a] = ty
            mm = re.fullmatch(r'([a-z_]\w*)\s*@\s*0b([01]+)', a) or re.fullmatch(r'0b([01]+)\s*@\s*([a-z_]\w*)', a)   # imm @ 0b0 / 0b0 @ vtr
            if mm and mm.group(1).startswith(('0','1')): mm = None
            if mm:
                w = type_width(ty)
                if w: vtypes[mm.group(1)] = 'bits(%d)' % (w - len(mm.group(2)))
    elems = []
    for e in split_top(rhs, '@'):
        e = e.strip()
        d = dict(text=e)
        if re.fullmatch(r'0b[01_]+', e):
            b = e[2:].replace('_', ''); d.update(kind='const', width=len(b), value=int(b, 2))
        elif re.fullmatch(r'0x[0-9a-fA-F_]+', e):
            h = e[2:].replace('_', ''); d.update(kind='const', width=4 * len(h), value=int(h, 16))
        elif re.fullmatch(r'(\w+)\s*:\s*bits\((\d+)\)', e):
            mm = re.fullmatch(r'(\w+)\s*:\s*bits\((\d+)\)', e); d.update(kind='field', var=mm.group(1), width=int(mm.group(2)))
        elif re.fullmatch(r'(\w+)\[(\d+)\.\.(\d+)\]', e):
            mm = re.fullmatch(r'(\w+)\[(\d+)\.\.(\d+)\]', e)
            d.update(kind='field', var=mm.group(1), hi=int(mm.group(2)), lo=int(mm.group(3)), width=int(mm.group(2)) - int(mm.group(3)) + 1)
        elif re.fullmatch(r'(\w+)\[(\d+)\]', e):
            mm = re.fullmatch(r'(\w+)\[(\d+)\]', e); d.update(kind='field', var=mm.group(1), hi=int(mm.group(2)), lo=int(mm.group(2)), width=1)
        elif re.fullmatch(r'(\w+)\s*\(\s*(\w+)\s*\)', e):
            mm = re.fullmatch(r'(\w+)\s*\(\s*(\w+)\s*\)', e); h, arg = mm.group(1), mm.group(2)
            hi = HELPERS.get(h)
            d.update(kind='helper', helper=h, var=arg, width=hi['width'] if hi else None)
            if hi and hi.get('values'):
                consts = {sym: v for sym, v in hi['values']}
                if arg in consts:  # helper applied to a constant symbol
                    d.update(kind='const', value=consts[arg])
                elif hi['kind'] == 'partial':
                    d['allowed'] = sorted({v for _, v in hi['values']})
            if not hi: d['note'] = 'unknown helper mapping'
        elif re.fullmatch(r'\w+', e):
            ty = vtypes.get(e)
            d.update(kind='field', var=e, width=type_width(ty) if ty else None, type=ty)
        else:
            d.update(kind='unparsed', width=None)
        elems.append(d)
    W = WIDTH_OF[c['mapping']]
    unknown = [d for d in elems if d.get('width') is None]
    known = sum(d['width'] for d in elems if d.get('width') is not None)
    notes = []
    if len(unknown) == 1:
        unknown[0]['width'] = W - known; unknown[0]['width_inferred'] = True
        notes.append('width of %s inferred from total' % unknown[0]['text'])
    elif len(unknown) > 1:
        notes.append('UNRESOLVED widths: ' + ', '.join(d['text'] for d in unknown))
    total = sum(d['width'] or 0 for d in elems)
    if total != W: notes.append('WIDTH MISMATCH: %d != %d' % (total, W))
    # positions, mask/value
    pos = W; mask = 0; val = 0; pat = ''
    constraints = []
    for d in elems:
        w = d['width'] or 0
        lsb = pos - w; d['lsb'] = lsb; d['msb'] = pos - 1; pos = lsb
        if d['kind'] == 'const':
            mask |= ((1 << w) - 1) << lsb; val |= d['value'] << lsb
            pat += format(d['value'], '0%db' % w) if w else ''
        elif d.get('allowed'):
            constraints.append(dict(msb=d['msb'], lsb=lsb, helper=d['helper'], allowed=[format(v, '0%db' % w) for v in d['allowed']]))
            pat += '?' * w
        else:
            pat += '-' * w
    # non-linear variables (same bits used twice)
    seen = collections.defaultdict(list)
    for d in elems:
        if d.get('var') and d['kind'] != 'const':
            seen[d['var']].append((d.get('hi'), d.get('lo')))
    for v, rs in seen.items():
        full = [r for r in rs if r == (None, None)]
        if len(full) > 1 or (full and len(rs) > 1):
            notes.append('variable %s occurs more than once (equality constraint)' % v)
        ranges = [set(range(lo, hi + 1)) for hi, lo in rs if hi is not None]
        for i in range(len(ranges)):
            for j in range(i + 1, len(ranges)):
                if ranges[i] & ranges[j]: notes.append('bits of %s used twice' % v)
    c.update(width=W, elements=elems, mask='0x%0*x' % (W // 4, mask), value='0x%0*x' % (W // 4, val),
             mask_int=mask, value_int=val, pattern=pat, constraints=constraints, notes=notes)
    return c

def main():
    os.makedirs(OUT, exist_ok=True)
    order = project_order()
    rank = {f: i for i, f in enumerate(order)}
    C = [parse_clause(c) for c in collect()]
    if len(sys.argv) > 3:   # only keep clauses from files that are part of the build
        dropped = [c for c in C if os.path.relpath(os.path.join(SAIL, c['file']), MODEL) not in rank]
        C = [c for c in C if c not in dropped]
        for c in dropped:
            print('dropped (file not in build):', c['constructor'], c['file'])
    def key(c):
        f = os.path.relpath(os.path.join(SAIL, c['file']), MODEL)
        return (c['mapping'], rank.get(f, 10 ** 6), c['line'])
    C.sort(key=key)
    for m in WIDTH_OF:
        k = 0
        for c in C:
            if c['mapping'] == m:
                c['order'] = k; k += 1
                f = os.path.relpath(os.path.join(SAIL, c['file']), MODEL)
                c['in_project_file'] = f in rank
    # expand set-valued helper fields into plain mask/value alternatives (or-patterns)
    for c in C:
        alts = [(c['mask_int'], c['value_int'])]
        for k in c['constraints']:
            w = k['msb'] - k['lsb'] + 1; fm = ((1 << w) - 1) << k['lsb']
            alts = [(m | fm, v | (int(a, 2) << k['lsb'])) for m, v in alts for a in k['allowed']]
        c['alternatives'] = alts
        c['n_alternatives'] = len(alts)
    # overlap analysis: is there a word matched by both rows (ignoring guards)?
    def compatible(a, b):
        for ma, va in a['alternatives']:
            for mb, vb in b['alternatives']:
                cm = ma & mb
                if (va & cm) == (vb & cm): return True
        return False
    for m in WIDTH_OF:
        rows = [c for c in C if c['mapping'] == m]
        for c in rows: c['overlaps_with_earlier'] = []
        for i, a in enumerate(rows):
            for b in rows[:i]:
                if compatible(a, b):
                    a['overlaps_with_earlier'].append(b['constructor'] + '@' + b['file'] + ':' + str(b['line']))
    for c in C:
        W = c['width'] // 4
        c['alternatives'] = [['0x%0*x' % (W, mm), '0x%0*x' % (W, vv)] for mm, vv in c['alternatives']]
    for c in C:
        c.pop('mask_int'); c.pop('value_int')
    json.dump(dict(source=SAIL, helpers=HELPERS, clauses=C), open(os.path.join(OUT, 'encdec_clauses.json'), 'w'), indent=1)
    with open(os.path.join(OUT, 'encdec_clauses.csv'), 'w', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(['mapping', 'order', 'constructor', 'pattern', 'mask', 'value', 'set_constraints', 'guard_config', 'guard_field', 'guard_mixed', 'n_overlaps_earlier', 'file', 'line', 'notes', 'sail'])
        for c in C:
            w.writerow([c['mapping'], c['order'], c['constructor'], c['pattern'], c['mask'], c['value'],
                        '; '.join('[%d:%d] in {%s} (%s)' % (k['msb'], k['lsb'], ','.join(k['allowed']), k['helper']) for k in c['constraints']),
                        ' & '.join(c['guard_config']), ' & '.join(c['guard_field']), ' & '.join(c['guard_mixed']), len(c['overlaps_with_earlier']),
                        c['file'], c['line'], ' | '.join(c['notes']), c['sail']])
    # readable listing, one line per clause, in matching order
    with open(os.path.join(OUT, 'encdec_patterns.txt'), 'w') as fh:
        fh.write('# MSB first. 0/1 = fixed bit, - = free field, ? = field restricted by a partial helper mapping\n')
        fh.write('# order = %s, then line number (first match wins)\n' % ('file order from ' + os.path.basename(sys.argv[3]) if len(sys.argv) > 3 else 'textual order of riscv.sail_project (NOT Sail\'s order)'))
        for m in WIDTH_OF:
            fh.write('\n## %s (%d bits)\n' % (m, WIDTH_OF[m]))
            for c in C:
                if c['mapping'] != m: continue
                g = ' & '.join(c['guard_config'] + c['guard_mixed'] + c['guard_field'])
                fh.write('%3d  %s  %-22s %s:%d%s\n' % (c['order'], c['pattern'], c['constructor'], c['file'].replace('model/', ''), c['line'], ('   when ' + g) if g else ''))
    # Rocq: one row per alternative, guards omitted (see comments)
    with open(os.path.join(OUT, 'EncdecRows.v'), 'w') as fh:
        fh.write('(** Generated by extract_encdec.py from %s. Do not edit.\n' % os.path.basename(os.path.abspath(SAIL)))
        fh.write('    A word [w] matches a row iff [N.land w (rmask r) = rvalue r].\n')
        fh.write('    Rows are in first-match order. Guards are NOT encoded; they are in the comments.\n')
        fh.write('    rname = constructor @ line in the Sail file (# alternative of an or-pattern). *)\n\n')
        fh.write('From Stdlib Require Import NArith String List.\nImport ListNotations.\n')
        fh.write('Local Open Scope string_scope.\nLocal Open Scope N_scope.\n\n')
        fh.write('Record raw_row := mk_raw { rname : string; rfile : string; rorder : nat; rmask : N; rvalue : N }.\n')
        for m in WIDTH_OF:
            fh.write('\nDefinition %s_rows : list raw_row := [\n' % m)
            items = []
            for c in C:
                if c['mapping'] != m: continue
                g = ' & '.join(c['guard_config'] + c['guard_mixed'] + c['guard_field']).replace('*)', '* )').replace('(*', '( *').replace('"', "'")
                f = c['file'].replace('model/', '')
                for i, (mm, vv) in enumerate(c['alternatives']):
                    nm = '%s@%d' % (c['constructor'], c['line']) + ('#%d' % i if len(c['alternatives']) > 1 else '')
                    items.append('  (* %s:%d%s *)\n  mk_raw "%s" "%s" %d %d %d' % (f, c['line'], (' when ' + g) if g else '', nm, f, c['order'], int(mm, 16), int(vv, 16)))
            fh.write(';\n'.join(items) + '\n].\n')
    print('clauses:', len(C), collections.Counter(c['mapping'] for c in C))

if __name__ == '__main__':
    main()
