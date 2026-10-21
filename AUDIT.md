# Security Audit — `genre`

Audited at `4c47bd1cd78c4bf1dad0e72e6598060fe8a553cd` (2026-10-21). Scope: package `genre`, module `genre::genre` (`sources/genre.move`); depends only on the Sui framework.

## What it does

A shared singleton `GenreRegistry` parents permissionlessly created, name-derived, frozen `Genre` objects. See [README](./README.md).

## Trust model

- **Publisher:** `init` shares the `GenreRegistry` (`genre.move:44-46`). No admin cap exists; the publisher has no further powers.
- **Anyone:** may call `new` (`genre.move:48-60`) with any name that passes validation. The caller contributes nothing but the name, which fully determines the object's contents and its derived id.
- **Nobody** can mutate, transfer, wrap or delete a `Genre` (`key` only, frozen at `genre.move:58`), or remove or replace the registry. The registry's `UID` is private, so no other package can `claim` under it.

## Findings

**G-1 · Low · Open — underscore placement is not canonicalized.** The charset check (`genre.move:51-54`) allows `_` anywhere and in any count, so `HIPHOP`, `HIP_HOP`, `HIP__HOP`, `_HIP_HOP_` and `_` are all distinct, valid, permanent genres (verified by probe). The README's claim that the vocabulary "cannot accumulate near-duplicate spellings" does not hold. Since creation is permissionless and genres are frozen, such variants can never be removed. Suggested fix: reject leading, trailing and consecutive underscores.

**G-2 · Info · Accepted — vocabulary is open.** Any well-formed word (`ASDF`) becomes a permanent genre. Which genres are shown or allowed is a consumer or curation concern, not something this package enforces.

**G-3 · Info · Accepted — shared-object contention on creation.** Each `new` takes `&mut GenreRegistry` (`genre.move:48`). Reads and use of existing frozen genres never touch the registry.

**G-4 · Info · Accepted — `init` emits no event.** Indexers take the registry id from the publish transaction's effects (`genre.move:44-46`).

## Checked, no finding

- Validation order is empty → length → charset (`genre.move:49-54`). A 65-byte lowercase name aborts `ENameTooLong`, not `EInvalidNameChar`. Each abort code is reachable (unit tests plus probes).
- Charset boundaries: `@` (0x40), `[` (0x5B) and `` ` `` (0x60) abort, as does a multibyte UTF-8 name. A 64-byte name is accepted (probes).
- `String::length` counts bytes, so the 64-byte bound and the README's event-size note hold (`genre.move:50`).
- Duplicates abort in `derived_object::claim` with `EObjectAlreadyExists` (`genre.move:56`; `duplicate_genre_aborts`). Genres are never deleted, so no name can be re-claimed.
- `derive_address` (`genre.move:64-66`) matches the id of the claimed object (`create_genre_and_derive`). It does not validate, so an invalid name yields an address with no object behind it. That is harmless because consumers take `&Genre`, which is type-checked.
- There is exactly one registry (from `init`), so the derived ids form one namespace with no bypass.
- `GenreCreatedEvent` carries the id and name. Exactly one is emitted per `new`, in call order, and views emit nothing (tests).
- Limits: one object and one event per `new`; names are at most 64 bytes. The per-transaction event limit caps batch creation at about 1,024 genres per transaction.

## Operational requirements

- `Published.toml` records mainnet and testnet publications from before the 2026-10-21 event and style changes. The current source must be published fresh before integrators rely on the `GenreCreatedEvent { genre_id, name }` shape.
- Tooling should create genres in canonical form, because the contract accepts underscore variants (G-1).

## Verification

- `sui move test --coverage`: 10/10 pass. `sui move coverage summary`: 100.00% (`genre`).
- `sui move build -e mainnet --warnings-are-errors` and `-e testnet`: both succeed with no warnings (sui 1.82.1).
- 10 throwaway probe tests (charset boundaries, max length, abort order, near-duplicate names, unvalidated derive, frozen take) all passed. They were not committed.
