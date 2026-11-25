# Architectuur van het project

Doel: Sails decoder (een cascade die elke clause één voor één probeert) vervangen door een
beslisboom die automatisch uit de Sail-specificatie wordt opgebouwd en in Rocq correct bewezen is.

## 1. Pijplijn

Grijs = Sail en gegenereerde code (vertrouwd), paars = jouw Rocq-bibliotheek (bewezen).

```mermaid
flowchart TB
  SPEC["sail-riscv model"]
  BACKEND["Sail Rocq-backend"]
  EXTRACT["Extractie<br/>(script nu, plugin later)"]
  CASCADE["rv32d.v<br/>cascade, referentie"]
  ROWS["Rijen<br/>mask/value"]
  HEUR["Heuristics.v"]
  CC["Compile.v<br/>stelling 1"]
  FUSE["Fuse.v<br/>stelling 2"]
  DEC["Decoder.v<br/>stelling 3"]
  VAL["Validation.v<br/>stelling 4"]

  SPEC --> BACKEND --> CASCADE
  SPEC --> EXTRACT --> ROWS --> CC
  HEUR --> CC
  CC --> FUSE --> DEC --> VAL
  CASCADE --> VAL

  classDef sail fill:#F1EFE8,stroke:#5F5E5A,color:#444441
  classDef mine fill:#EEEDFE,stroke:#534AB7,color:#3C3489
  class SPEC,BACKEND,EXTRACT,CASCADE,ROWS sail
  class HEUR,CC,FUSE,DEC,VAL mine
```

## 2. De vier stellingen

| # | Module | Stelling | Betekenis |
|---|---|---|---|
| 1 | `Compile.v` | `eval (CC choose P) w = first_match P w` | de boom kiest dezelfde rij als first-match, voor elke heuristiek |
| 2 | `Fuse.v` | `eval (fuse t) w = eval t w` | switchen op meerdere bits tegelijk (Theiling) verandert niets |
| 3 | `Decoder.v` | `decode (encode i) = Some i` | roundtrip |
| 4 | `Validation.v` | `decode w = encdec_backwards w` | jouw decoder doet hetzelfde als die van Sail |

## 3. Modules

| Module | Bevat | Status |
|---|---|---|
| Katamaran `Bitvector.v` | `bv n` en bewerkingen | bestaat |
| `EncdecRows.v` | de rijen, gegenereerd uit Sail | gegenereerd (met `N`, nog om te zetten naar `bv 32`) |
| `Rows.v` | `row` (mask, value), `matches`, `first_match` | te doen |
| `Tree.v` | `tree` (Leaf, Fail, Test i t0 t1), `eval` | te doen |
| `Heuristics.v` | Theiling-stap, Maranget p, q, n, d, b | te doen |
| `Compile.v` | `specialize`, `CC`, Lemma 1, stelling 1 | te doen |
| `Fuse.v` | bomen met multi-bit switch, `fuse`, stelling 2 | te doen |
| `Decoder.v` | `decode`, `encode`, stelling 3 | te doen |
| `Validation.v` | stelling 4 tegen `rv32d.v` | te doen |

## 4. Volgorde van werken

1. `Rows.v`, `Tree.v`, `Compile.v` met stelling 1, op RV32I zonder guards.
2. `Heuristics.v`: Theiling-stap + Marangets heuristieken; meten (diepte, grootte).
3. `Fuse.v` met stelling 2.
4. Guards (vaste configuratie), dan `Decoder.v` met roundtrip.
5. Plugin afwerken; `Validation.v` tegen `rv32d.v`.
