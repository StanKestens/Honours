# Honours - Stan Kestens

- `code/rv32-decode/`: parser and serializer for RISC-V I-type
- `code/format-lib/`: generic format language, `Bits.v` plus one file per stage
  (`Format1_Seq.v`, `Format2_Const.v`, ...)
- `tex/`: logbook (`logbook.tex`) and notes
- `Vragen.md`: questions
- `Notes bij Rocq.md`: notes

## Build

Open the repo root in VS Code, so VsRocq finds `_CoqProject`. Then:

```bash
rocq makefile -f _CoqProject -o Makefile && make
```
