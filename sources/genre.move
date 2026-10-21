// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Genre vocabulary for Miso: a canonical, deduplicated set of `Genre` objects.
///
/// `Genre` objects are created permissionlessly, frozen, and derived from the
/// `GenreRegistry` by canonical name (`A`-`Z` and `_`), so each name maps to
/// one object and the vocabulary cannot fork ("hip-hop" vs "Hip Hop"). Genre
/// assignment lives in consumer packages such as `release_genre`.
module genre::genre;

// === Imports ===

use std::string::String;
use sui::derived_object::{Self, claim};
use sui::event::emit;

// === Errors ===

/// Genre name must not be empty.
const EEmptyName: u64 = 0;
/// Genre name exceeds the maximum length.
const ENameTooLong: u64 = 1;
/// Genre name contains a character other than `A`-`Z` or `_`.
const EInvalidNameChar: u64 = 2;

// === Constants ===

/// Maximum length of a genre name in bytes.
const MAX_NAME_LENGTH: u64 = 64;

// === Structs ===

/// A genre in the canonical vocabulary. Immutable (frozen) once created.
/// Derived from the registry by `GenreKey(name)`, so a given name maps to a
/// single, deterministic object id.
public struct Genre has key {
    id: UID,
    /// Canonical genre name (e.g. "HIP_HOP").
    name: String,
}

/// Shared registry that parents the derived `Genre` objects.
public struct GenreRegistry has key {
    id: UID,
}

/// Derivation key for a `Genre`, keyed by its canonical name.
public struct GenreKey(String) has copy, drop, store;

// === Events ===

/// Emitted when a genre is added to the vocabulary, with its canonical name.
public struct GenreCreatedEvent has copy, drop {
    genre_id: ID,
    name: String,
}

// === Public Functions ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(GenreRegistry { id: object::new(ctx) });
}

/// Creates and freezes the genre `name`. Permissionless: the validated name
/// fully determines the object and its ID. A second `new` for the same name
/// aborts in `derived_object`.
public fun new(registry: &mut GenreRegistry, name: String) {
    assert!(!name.is_empty(), EEmptyName);
    assert!(name.length() <= MAX_NAME_LENGTH, ENameTooLong);
    // Canonical form: uppercase `A`-`Z` and `_` only (e.g. "HIP_HOP").
    assert!(
        name.as_bytes().all!(|c| (*c >= 0x41 && *c <= 0x5A) || *c == 0x5F),
        EInvalidNameChar,
    );

    let genre = Genre { id: claim(&mut registry.id, GenreKey(name)), name };
    let genre_id = object::id(&genre);
    transfer::freeze_object(genre);
    emit(GenreCreatedEvent { genre_id, name });
}

// === View Functions ===

/// Derives the address a `Genre` with the given name would have, without
/// creating it. Lets clients resolve/check a genre address offline.
public fun derive_address(self: &GenreRegistry, name: String): address {
    derived_object::derive_address(self.id.to_inner(), GenreKey(name))
}

/// Returns the genre's canonical name.
public fun name(self: &Genre): &String {
    &self.name
}

// === Test Functions ===

/// Runs the real module initializer, creating and sharing the registry.
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx)
}

/// Unpacks a `GenreCreatedEvent` (fields are module-private) for test
/// assertions.
#[test_only]
public fun genre_created_event_fields(event: &GenreCreatedEvent): (ID, String) {
    (event.genre_id, event.name)
}
