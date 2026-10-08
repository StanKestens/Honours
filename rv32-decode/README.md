# rv32-decode

A small, verified parser.



## Build

Needs Rocq 9 with stdpp and Equations (included in the Rocq Platform).
Katamaran must be cloned next to this folder:

```bash
cd ..            # the Honours folder
git clone https://github.com/katamaran-project/katamaran.git
cd rv32-decode
rocq makefile -f _CoqProject -o Makefile && make
```

Only three files of Katamaran are compiled (`Notations.v`, `Prelude.v`,
`Bitvector.v`), not the whole project.

