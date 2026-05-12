# ALU — what we need to build

Style: copy how the existing files look. Every datapath = structural (instantiate modules, no `+` or `&` operators). Every control = FSM like `cu_booth.sv`.

---

## Who builds what

> fill in your names

| File | Builds on | Person |
|---|---|---|
| `csa.sv` | `gates.sv` | |
| `lut_quotient.sv` | `gates.sv` | |
| `shifter.sv` | `register.sv`, `counter_n_bits.sv` | |
| `add_sub.sv` | `adder.sv`, `gates.sv` | |
| `logic_unit.sv` | `gates.sv`, `mux.sv` | |
| `cu_srt4.sv` | — | |
| `srt4_div.sv` | everything above | |
| `cu_alu.sv` | — | |
| `alu_top.sv` | everything | |

---

## The files

### `csa.sv` — Carry-Save Adder
Takes 3 inputs, outputs sum + carry separately. No ripple carry — each bit is independent. Used inside the SRT-4 loop so we don't stall waiting for carries.

### `lut_quotient.sv` — Quotient digit selector
Given the top bits of the partial remainder and divisor, picks a digit from {-2, -1, 0, +1, +2}. Just a big `always_comb` case block — the one place a behavioural block is fine because it's literally a lookup table.

### `shifter.sv` — Variable left shifter
Shifts an 8-bit value left by N positions. Use `register.sv` + `counter_n_bits.sv` internally. Needed to normalise operands before division starts.

### `add_sub.sv` — Adder/subtractor
Wrapper around `adder.sv`. When `sub=1`, XORs the second operand and sets `cin=1` (same trick booth already uses for negation).

### `logic_unit.sv` — Bitwise operations
AND, OR, XOR, NOT selected by a 2-bit opcode. Use gate primitives + muxes. No clock needed.

### `cu_srt4.sv` — Division FSM
Controls the divider. Same idea as `cu_booth.sv` — outputs a control word `c[9:0]`, one bit per action. States: `IDLE → LOAD_D → LOAD_N → NORMALIZE → ITERATE → CHECK → FINALIZE → CORRECT → OUTPUT_Q → OUTPUT_R → STOP`.

### `srt4_div.sv` — Divider datapath
The big one. Mirror of `booth.sv` but for division. Instantiates `csa`, `lut_quotient`, `shifter`, `register`s, `adder`, `counter`. Controlled by `cu_srt4`.

### `cu_alu.sv` — Master FSM
Decodes the opcode, fires the right sub-unit, waits for `done`, then outputs. States: `IDLE → DECODE → DISPATCH → WAIT → OUTPUT → DONE`.

### `alu_top.sv` — Top level
Plugs all units together. Shared `inbus`/`outbus` via tri-state buffers (same as `booth.sv`). Opcode table:

| opcode | op |
|---|---|
| `0000` | ADD |
| `0001` | SUB |
| `0010` | MUL |
| `0011` | DIV |
| `0100` | AND |
| `0101` | OR |
| `0110` | XOR |
| `0111` | NOT |

---

## Build order

Don't start `srt4_div` before `csa`, `lut_quotient`, and `shifter` are done. Everything else can be done in parallel.

```
1. csa, lut_quotient, shifter, add_sub, logic_unit  ← parallel
2. cu_srt4
3. srt4_div
4. cu_alu
5. alu_top
```
