# Security Audit — `genre`

**Revision:** working tree @ 2026-08-23 (the `misonetwork` workspace is not a
git repository — `git rev-parse` fails; no commit hash exists). No dependencies
beyond the Sui framework. **Date:** 2026-08-23 · **Toolchain:** sui
1.77.2-51d177ad7d65

Audit of `genre` (130 LOC, `sources/genre.move`), the curated genre
*vocabulary* primitive: a shared `GenreRegistry` parenting name-derived,
frozen `Genre` objects, extended only by the `GenreRegistryCap` holder.
Verdict: **safe to publish — no exploitable findings.**

## What it does

- `init` (`genre.move:74`) creates and shares the singleton `GenreRegistry`
  and transfers the single `GenreRegistryCap` to the deployer.
- `new` (`genre.move:83`) — cap-gated — validates the name (non-empty, ≤ 64
  bytes, charset restricted to `A`-`Z` and `_`, `genre.move:84-91`), then
  `claim`s a derived object under `GenreKey(name)` (`genre.move:97`) and
  `freeze_object`s the `Genre` (`genre.move:102`): immutable, globally
  readable, one object per canonical name forever.
- `derive_address` (`genre.move:107`, renamed from `derive_genre_id` on
  2026-08-24 — same derivation, returns `address` instead of `ID`) is a
  permissionless read-only derivation helper.

## Threat model

- **Unauthorized vocabulary extension / squatting:** only the cap holder can
  create genres. `GenreRegistryCap` is minted exactly once, in `init`, to
  `ctx.sender()`; there is no other constructor (fields are private,
  `genre.move:48-50`). A squatter cannot pre-register names.
- **Duplicate/forked names ("hip-hop" vs "Hip Hop"):** the charset gate
  (`genre.move:88-91`) forces a single canonical form (uppercase + `_`), and
  name-derived addressing makes a second `new` with the same name abort in
  `derived_object::claim` (address already claimed). Dedup is structural, not
  a remembered check.
- **Post-creation mutation:** `Genre` is frozen (`genre.move:102`) and has no
  mutable accessors — impossible.
- **DoS:** bounded — names ≤ 64 bytes; one object per name; `new` takes
  `&mut GenreRegistry` so only the cap holder contends on the shared registry.
- **`string::utf8(*name.as_bytes())` copy (`genre.move:95`):** cannot abort or
  mangle — bytes were just validated as pure ASCII, a UTF-8 subset.

## Findings

- **F1 (Informational): curator-cap availability.** `GenreRegistryCap` has
  `key, store` and is a singleton. If its holder wraps it irrecoverably or
  loses the key, the vocabulary can never grow (no genres are lost — existing
  ones are frozen objects). Mitigation is operational (hold the cap in a
  multisig); the team's planned full-stack immutable republish also resets
  this at deploy time. No security impact on existing data.
- **F2 (Informational): no `init` event.** Unlike `miso::release`'s registry,
  `init` emits nothing, so indexers must discover the `GenreRegistry` id from
  the publish transaction's object effects rather than an event. Discoverability
  nit, not a vulnerability.

## Edge cases verified

- Empty name, >64-byte name, lowercase/digit/space/punctuation names — all
  abort (`EEmptyName`/`ENameTooLong`/`EInvalidNameChar`), including the
  boundary characters just outside `0x41..=0x5A` (test
  `test_invalid_name_char_below_range_aborts`).
- Duplicate `new` with the same name aborts at `claim`
  (`test_create_duplicate_aborts`).
- `derive_address` requires no cap and cannot create anything — it only
  hashes.

## Verification

- **6/6 unit tests pass** (`sui move test`, sui 1.77.2): happy path + derive,
  duplicate abort, empty/too-long/invalid-char matrix.
