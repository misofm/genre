# Security Audit — `genre`

**Revision:** working tree @ 2026-08-24. No dependencies beyond the Sui
framework. **Date:** 2026-08-24 · **Toolchain:** sui
1.77.2-51d177ad7d65

Audit of `genre` (`sources/genre.move`), the canonical genre *vocabulary*
primitive: a shared `GenreRegistry` parenting permissionlessly created,
name-derived, frozen `Genre` objects.
Verdict: **safe to publish — no exploitable findings.**

## What it does

- `init` creates and shares the singleton `GenreRegistry`; it creates no admin
  capability.
- `new` is permissionless. It validates the name (non-empty, ≤ 64
  bytes, charset restricted to `A`-`Z` and `_`), then `claim`s a derived
  object under `GenreKey(name)` and `freeze_object`s the `Genre`: immutable, globally
  readable, one object per canonical name forever.
- `derive_address` (renamed from `derive_genre_id` on
  2026-08-24 — same derivation, returns `address` instead of `ID`) is a
  permissionless read-only derivation helper.

## Threat model

- **Vocabulary extension / squatting:** any caller can create a validated name,
  but caller identity contributes nothing to the result. The canonical name
  fixes both the immutable contents and derived id, so creating a name first
  cannot grant ownership, redirect resolution, or alter later assignments.
- **Duplicate/forked names ("hip-hop" vs "Hip Hop"):** the charset gate
  forces a single canonical form (uppercase + `_`), and
  name-derived addressing makes a second `new` with the same name abort in
  `derived_object::claim` (address already claimed). Dedup is structural, not
  a remembered check.
- **Post-creation mutation:** `Genre` is frozen and has no
  mutable accessors — impossible.
- **DoS:** names are bounded to 64 bytes and each canonical name can be claimed
  only once. Permissionless creation does contend on `&mut GenreRegistry`, but
  it cannot modify or remove an existing `Genre`.
- **`string::utf8(*name.as_bytes())` copy:** cannot abort or
  mangle — bytes were just validated as pure ASCII, a UTF-8 subset.

## Findings

- **F1 (Informational): permissionless shared-object contention.** Every new
  genre needs mutable access to the singleton registry. Creation may contend,
  but reads and all use of existing immutable genres do not touch the registry.
  **Disposition (2026-08-24):** accepted — genre creation is infrequent and
  deterministic; normal release/party operations use the frozen objects.
- **F2 (Informational): no `init` event.** Unlike `miso::release`'s registry,
  `init` emits nothing, so indexers must discover the `GenreRegistry` id from
  the publish transaction's object effects rather than an event. Discoverability
  nit, not a vulnerability.
  **Disposition (2026-08-24):** accepted — the registry id is discoverable
  from the publish transaction's object effects; indexer ergonomics only.

## Edge cases verified

- Empty name, >64-byte name, lowercase/digit/space/punctuation names — all
  abort (`EEmptyName`/`ENameTooLong`/`EInvalidNameChar`), including the
  boundary characters just outside `0x41..=0x5A` (`invalid_name_char_below_range_aborts`).
- Duplicate `new` with the same name aborts at `claim`
  (`duplicate_genre_aborts`).
- A sender other than the initializer can create a genre
  (`a_sender_other_than_the_initializer_can_create`).
- `derive_address` cannot create anything — it only hashes.

## Verification

- **7/7 unit tests pass** (`sui move test --warnings-are-errors`, sui 1.77.2):
  happy path + derive, cross-sender creation, duplicate abort, and the
  empty/too-long/invalid-char matrix.
