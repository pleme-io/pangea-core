# pleme-io Ruby Typing Standard

Canonical rules for type discipline in pangea Ruby — which tool goes where, what
each one actually catches, and what none of them catch. Every agent (human or AI)
adding types, signatures or a checker to a pangea gem must read this first.

These rules were not chosen from documentation. They come from a measured
differential run on 2026-09-03 against two real gems, with planted errors as
negative controls, and several of them contradict what the tools' own marketing
implies. Where a claim below has a number, the number was produced by a command.

---

## 0. The one-paragraph version

**The strictness that works in Ruby is at the VALUE BOUNDARY, not in the type
declarations.** `dry-types` at a parse boundary is doing more real enforcement
than either static checker managed, and pangea has largely opted out of it: 0 of
42 `Dry::Struct` classes refuse an unknown key, coercion outnumbers strictness
14:1, and 63% of all attributes are optional. Fix that first. A checker added on
top of a permissive boundary is decoration.

---

## 1. The measured state, 2026-09-03

| | count |
|---|---|
| `Dry::Struct` classes in pangea-core + pangea-architectures | 42 |
| ...that REFUSE an unknown key (`schema schema.strict`) | **0** |
| `Types::Coercible::` | 131 |
| `Types::Strict::` | **9** |
| `Types::Any` (the escape hatch) | 49 |
| required `attribute` | 398 |
| optional `attribute?` | **670** (63%) |
| generated `.rbs` files in the family | 86 (85 pangea-github + 1 pangea-config) |
| ...checked by anything | **0** |

A typo'd key in any of those 42 classes is silently discarded. That is the
default behaviour of `Dry::Struct`, and it is the same defect class that made a
YAML anchor leave one workspace un-renderable for a month with nothing failing.

---

## 2. What each tool actually catches — measured, not claimed

Four errors were planted in real code, identically for each tool, and reverted.
`✅` = reported it. `❌` = reported nothing.

| planted error | `dry-types` | `rbs validate` | `steep` | Sorbet (static) | `sorbet-runtime` |
|---|---|---|---|---|---|
| typo'd TYPE NAME in a signature | n/a | ✅ | n/a | ✅ | n/a |
| call to a method that does not exist | ❌ | n/a | ✅ | ✅ | n/a |
| **signature says `Integer`, Ruby supplies `String`** | ✅ at load | ❌ | ❌ | ❌ | ❌ |
| **signature declares a method the Ruby never defines** | n/a | ❌ | ❌ | ❌ († ) | ❌ |
| **signature drops an attribute the Ruby declares** | n/a | ❌ | ❌ | ❌ | ❌ |
| a value of the wrong type reaching a struct | ✅ | n/a | n/a | n/a | ✅ (but see §3) |

† Worse than a miss: Sorbet **statically blesses** a call to the phantom method,
converting a would-be `NoMethodError` into "verified".

**The three bold rows are the whole content of a generated signature file.** Their
entire body is `attr_reader <name>: <type>` lines modelling `attribute :<name>,
T::<Type>` calls. `attribute` is a runtime DSL call; neither RBS nor Sorbet
expands macros. So the signature is a hand-model of the DSL's effect and **no
type checker compares the model to the call.**

---

## 3. sorbet-runtime does not rescue this, and the reason matters

Measured, on a `Dry::Struct` attribute given an `Integer` where `Strict::String`
was declared:

```
Dry::Struct::Error: [Cfg.new] 12345 (Integer) has invalid type for :cluster_name
  violates constraints (type?(String, 12345) failed)
```

The same probe **raises identically with `sorbet-runtime` never required**. The
enforcer is `dry-struct`. Two structural reasons Sorbet cannot help here:

- an RBI has **no runtime presence** — it never executes
- a DSL-generated reader has **no `def` to attach a `sig` to**

So the runtime protection already exists, and it is not an argument for adopting
anything.

---

## 4. The rules

### 4.1 `Strict` at every boundary that parses untrusted input ✅

A YAML file, an env var, an API response and a CLI flag are all untrusted.

```ruby
# ✅ Correct — refuses at the boundary
attribute :cluster_name, Types::Strict::String
attribute :worker_count, Types::Coercible::Integer   # coercion is deliberate: ENV is a String

# ❌ Wrong — accepts anything and fails somewhere else, later
attribute :cluster_name, Types::Any
```

`Coercible` is legitimate **only** where the wire genuinely carries a different
type than the domain wants — an env var that must become an Integer. It is not a
default. 131-to-9 is the wrong ratio and every new `Coercible` needs a reason.

### 4.2 Every `Dry::Struct` refuses unknown keys ✅

```ruby
# ✅ Correct — a typo is an error
class Config < Dry::Struct
  schema schema.strict
end

# ❌ Wrong — `cluster_nmae:` is silently discarded, and this is the DEFAULT
class Config < Dry::Struct
end
```

This is one line per class, it is the single highest-value change in this
document, and it is currently applied 0 times out of 42.

### 4.3 `attribute?` is a decision, not a default ✅

63% optional means the schema has stopped saying anything about what a valid
config looks like. An attribute is optional when absence is MEANINGFUL — not when
you are unsure whether every caller supplies it.

### 4.4 A signature is GENERATED or it does not exist ✅

`pangea-forge` emits `.rbs` alongside the Ruby from one schema in one run. That is
why RBS and not Sorbet for this surface: **a generated signature cannot drift from
what generated it.** Hand-writing an `.rbs` for generated code reintroduces
exactly the drift the generator removed — and §2 proves nothing would catch it.

### 4.5 `rbs validate` runs in CI ✅

0.5s over 85 signatures. It caught a real generator defect the day it was first
run: all 85 files declare `< Pangea::Resources::BaseAttributes` and pangea-core
ships no `sig/`, so every signature was unresolvable. A 12-line stub takes it to
exit 0.

Cheap, non-vacuous, and it checks the one thing it can actually see: whether a
signature is internally coherent.

### 4.6 `steep` does NOT run in CI ❌ — for now

Never reached clean: 1584 diagnostics on a bare repo, 369 after 77 lines of
hand-written stubs. The cause is not the repo — **no gem in the runtime closure
ships `sig/`**: dry-struct, dry-types, terraform-synthesizer, pangea-core, none.
Getting one gem green means hand-authoring signatures for the whole dry-rb stack.

Revisit if the dry-rb ecosystem ships signatures. Not before.

### 4.7 Sorbet ONLY on hand-written `def`s, and not in the schema layer ⚠️

Sorbet has one genuine capability neither RBS nor Steep has, measured:

```
Expected `Integer` but found `String` for method result type
```

on a hand-written method with an inline `sig`. That is real and worth having —
where there are real methods.

It is the wrong tool for the DSL surface, measured: at `# typed: true` across
pangea-config, **322 of 333 errors were the DSL and 0 were real defects** (96.7%
noise, against a suite of 55 green examples). `T.reveal_type` on a `Dry::Struct`
instance returns `T.untyped`, so every attribute access is unchecked — real or
invented. `tapioca` ships 38 DSL compilers and **none for dry-struct or
dry-types**.

Also: `T = Pangea::Config::Types` **shadows Sorbet's reserved `T`**. The house
idiom is structurally hostile to it. Adopting Sorbet anywhere means `::T` or a
rename.

**Never both on the same code.** An `.rbs` and a `sig` for the same method is the
drift class in a type checker's clothing.

### 4.8 The comparator is the gate that actually works ✅

~60 lines comparing each generated `.rbs` against the `attribute` calls in its
`.rb`: attribute-name set, optionality, base type. It catches all three errors
both checkers missed. Planted with all three, it named all three while Steep
named none; run clean across 85 pairs / 406 attributes it found 0 disagreements.

**If you write a generator that emits types, you own a comparator that checks
them.** No off-the-shelf checker will do it.

---

## 5. Tier honesty — say which rung, never round up

| rung | mechanism | example |
|---|---|---|
| **statically checked** | `steep` / `srb tc` in CI | *unreached in this family — nothing checks 86 signature files* |
| **parse-time rejected** | dry-types at a boundary | a wrong type in YAML raises at load |
| **CI-caught** | rspec, `rbs validate`, the comparator | a signature that does not resolve |
| **only-mitigated** | a runtime guard someone remembered | — |

Ruby has **no compile error**. Nothing in this document makes a bad state
unrepresentable, and no README here may borrow that language from
[shikumi](https://github.com/pleme-io/shikumi), whose Rust types genuinely do.

---

## 6. Two traps that make a green run meaningless

Both were hit during the differential and both produce a passing checker that
examined nothing.

**Steep reports success on an empty file set.** With a `Steepfile` outside the
repo: `No type error detected. 🫖`, **exit 0, 0 of 175 files checked**. Absolute
paths did not fix it. `steep stats` — header row, no data rows — was the only
thing that revealed it.

**Sorbet fails closed on a fully empty scope but not a narrow one.** `--dir` on
one file prints `No errors! Great job.`

So whichever runs, **the file count is part of the result**:

```bash
steep stats | tail -n +3 | grep -c ','          # must equal the expected file count
srb tc --print=file-table-json:ft.json          # then count the entries
```

A checker that does not report its denominator is not evidence.
