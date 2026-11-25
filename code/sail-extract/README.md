# sail-extract

Haalt **alle** clauses uit de twee mappings waaruit Sail de RISC-V-decoder genereert,
en zet ze om naar mask/value-rijen (de invoer voor een Maranget-compiler).

- `encdec : instruction <-> bits(32)` → `ext_decode` (`model/postlude/decode_ext.sail`)
- `encdec_compressed : instruction <-> bits(16)` → `ext_decode_compressed`

Bron: `../../../../sail-riscv`, commit `bcc5a00` (12 nov 2026).

## Opnieuw draaien

```bash
python3 extract_encdec.py <sail-riscv> out files.txt
python3 order_from_rocq.py check <sail-riscv>/build/rocq/rv32d.v out/encdec_clauses.json
```

`files.txt` is de volgorde waarin Sail de bestanden verwerkt. Die bepaalt de first-match-volgorde.
Twee manieren om hem te maken:

- met Sail (gezaghebbend), in `sail-riscv/model`:
  `sail riscv.sail_project --all-modules --list-files-separated $'\n' > files.txt`
- zonder Sail, afgeleid uit de door Sail gegenereerde Rocq-decoder (zo is de huidige gemaakt):
  `python3 order_from_rocq.py derive <sail-riscv>/build/rocq/rv32d.v out/encdec_clauses.json > files.txt`

`order_from_rocq.py check` controleert dat de volgorde van de instructies gelijk is aan die in
Sails `encdec_backwards` en `encdec_compressed_backwards`. Huidige stand: beide OK.

## Uitvoer (`out/`)

| Bestand | Inhoud |
|---|---|
| `encdec_patterns.txt` | Eén regel per clause, in matchvolgorde: bitpatroon, constructor, bron, guard. Begin hier. |
| `encdec_clauses.csv` | Hetzelfde als tabel, met mask, value, beperkingen, gesplitste guards en de Sail-brontekst. |
| `encdec_clauses.json` | Alles: per clause de elementen (breedte, msb/lsb, veld/constante/hulpmapping), alternatieven, overlap; plus alle hulpmappings. |
| `EncdecRows.v` | Rocq: `encdec_rows` en `encdec_compressed_rows : list row`, één rij per alternatief. Guards staan in commentaar. Niet gecompileerd. |

Patroon: MSB eerst. `0`/`1` = vast bit, `-` = vrij veld, `?` = veld dat beperkt wordt door een partiële hulpmapping.

## Hoe het vertaalt naar Maranget

| Sail | Hier |
|---|---|
| clause | rij (volgorde = first match) |
| letterlijk bit | constructor in `mask`/`value` |
| veld (`rs1`, `imm[11..5]`, `x : bits(n)`) | wildcard |
| totale hulpmapping (`encdec_reg`, `encdec_vreg`, `bool_bit`, ...) | wildcard |
| partiële hulpmapping (`encdec_rounding_mode`, `encdec_iop`, funct6-mappings, ...) | or-patroon → uitgeklapt in `alternatives` |
| hulpmapping op een constante (`encdec_xxx(FOO)`) | constante bits |
| `when ...` | guard, gesplitst op `&` in `config` / `field` / `mixed` |

## Cijfers (met `files.txt`)

- 464 clauses: 405 × 32 bit (incl. `ILLEGAL`), 59 × 16 bit (incl. `C_ILLEGAL`).
  `STOP_FETCHING` en `THREAD_START` vallen weg: hun bestand (`rmem`) zit alleen in de rmem-build.
- 1166 rijen na het uitklappen van or-patronen. RV32I (`base_insts.sail`): 37 clauses, 48 rijen.
- 90 hulpmappings gebruikt: 82 partieel, 8 totaal.
- Bijna alle clauses hebben een guard; de meeste hangen alleen af van de configuratie
  (`currentlyEnabled`, `xlen`, `get_sew()`), een deel ook van de velden (`rd != zreg`, `nzimm != 0`).
- Overlap (een woord matcht ook een eerdere rij, guards genegeerd): 19 rijen in `encdec`, 13 in
  `encdec_compressed`, `ILLEGAL` niet meegeteld. In Sails volgorde staat de specifieke instructie
  (hint) telkens vóór de algemene: `LPAD` vóór `UTYPE`, `ZICBOP` vóór `ITYPE`, `NTL` vóór `RTYPE`,
  `PAUSE` vóór `FENCE`. De rest wordt opgelost door guards (`xlen`, extensies, `!= zreg`).

## Kanttekeningen

- **Volgorde.** Zonder `files.txt` neemt het script de tekstuele volgorde van `riscv.sail_project`,
  en die is fout voor modules met `before I_insts` (ZICBOP, NTL, PAUSE, LPAD). Gebruik altijd `files.txt`.
- **Guards worden niet geëvalueerd**, alleen bewaard en geclassificeerd. Sommige hangen af van
  runtime-toestand (`get_sew()`, `zicfiss_xSSE(cur_privilege)`): decoderen is dan geen pure functie
  van het woord.
- **`encdec_reg`** heeft zelf een guard (`not(base_E_enabled) | r[4] == 0b0`, voor RV32E). Hier als
  totaal behandeld.
- Veldbreedtes komen uit de annotatie, de slice of het `union clause instruction`-type. Eén breedte
  (`vtr` in `VSETIVLI`) is afgeleid uit het totaal. Alle 466 clauses komen op exact 32 resp. 16 bit uit.
