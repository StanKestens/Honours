# format-lib

Generic format language for bit parsing, one file per stage.

- `Bits.v`: bit strings and `take_bits`, shared by all stages
- `Format1_Seq.v`: fixed-width fields and sequencing
- `Format2_Const.v`: + constants

## Build

Needs Rocq 9. The stages import `Bits.v`, so it has to be compiled
first. From the repo root:

```bash
rocq makefile -f _CoqProject -o Makefile && make
```

Rerun `make` after changing `Bits.v`.
