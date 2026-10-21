// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

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

const EEmptyName: u64 = 0;
const ENameTooLong: u64 = 1;
const EInvalidNameChar: u64 = 2;

// === Constants ===

/// In bytes.
const MAX_NAME_LENGTH: u64 = 64;

// === Structs ===

public struct Genre has key {
    id: UID,
    name: String,
}

public struct GenreRegistry has key {
    id: UID,
}

public struct GenreKey(String) has copy, drop, store;

// === Events ===

public struct GenreCreatedEvent has copy, drop {
    genre_id: ID,
    name: String,
}

// === Public Functions ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(GenreRegistry { id: object::new(ctx) });
}

/// Permissionless. A second `new` for the same name aborts in `derived_object`.
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

public fun derive_address(self: &GenreRegistry, name: String): address {
    derived_object::derive_address(self.id.to_inner(), GenreKey(name))
}

public fun name(self: &Genre): &String {
    &self.name
}

// === Test Functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx)
}

#[test_only]
public fun genre_created_event_fields(event: &GenreCreatedEvent): (ID, String) {
    (event.genre_id, event.name)
}
