# sail-plugin - AI generated!

Sail-plugin die elke clause van `encdec` en `encdec_compressed` afdrukt als bitpatroon,
in de volgorde die Sail zelf gebruikt. Doel: zelfde uitvoer als `../sail-extract`.

**Nog niet gecompileerd.** Geschreven tegen de ontwikkelversie van Sail in `Honours/sail`
(commit `ef5dca5`, 12 nov 2026), geïnstalleerd met `cd Honours/sail && opam pin add . -y`.
Die versie is nodig omdat de uitgebrachte 0.20.3 de Rocq-code van de huidige sail-riscv niet kan
genereren (registers met een tuple-type). De uitgebrachte `libsail` 0.20.3 gebruikt ook andere
constructornamen (`DEF_aux` i.p.v. `Def_aux`).

## 1. Toolchain (eenmalig, macOS)

```bash
brew install opam z3 gmp cmake
opam init                      # als je dat nog niet deed
opam switch create sail 5.2.0  # aparte switch, los van je Rocq-switch; weigert opam deze OCaml-versie voor sail, kies de versie die het voorstelt
eval $(opam env --switch=sail)
opam update
opam install dune
cd <Honours>/sail && opam pin add . -y   # ontwikkelversie, alle 13 pakketten
sail --version
```

## 2. Bouwen

```bash
cd code/sail-plugin
dune build
ls _build/default/sail_plugin_rows.cmxs
```

De plugin moet met dezelfde OCaml en dezelfde `libsail` gebouwd zijn als de `sail` die hem laadt,
dus bouw in dezelfde opam-switch.

## 3. Draaien op sail-riscv

```bash
cd <Honours>/sail-riscv/model
sail -plugin <Honours>/git/Honours/code/sail-plugin/_build/default/sail_plugin_rows.cmxs \
     --rows --strict-var --strict-bitvector --strict-exponentials \
     --all-modules riscv.sail_project > rows.txt
```

`-plugin` moet vóór `--rows` staan: de optie bestaat pas als de plugin geladen is.
Klaagt Sail over de configuratie, genereer dan eerst de config-bestanden met
`cmake -S <Honours>/sail-riscv -B build` en geef er een mee met `--config build/config/<...>.json`.

## 4. Vergelijken met het script

```bash
./compare.sh <Honours>/sail-riscv/model/rows.txt ../sail-extract/out/encdec_patterns.txt
```

Verwachte verschillen: clauses waar een hulpmapping op een constante wordt toegepast
(script: vaste bits, plugin: `-`). Elk ander verschil is een bug in één van de twee.

## Volgende mijlpalen

2. Segmenten met soort (`Const` / `Field` / `Helper`) en positie, tabellen van hulpmappings.
3. JSON- en Rocq-uitvoer, zoals beschreven in het gesprek van 20 nov.
