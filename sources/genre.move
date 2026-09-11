// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Genre vocabulary for Miso — a canonical, deduplicated set of `Genre` objects.
///
/// Genre is a classification, not protocol-verifiable state, so it lives in an
/// extension rather than core. This module owns the **vocabulary**: `Genre`
/// objects are created permissionlessly and derived by canonical name, so the
/// set stays deduplicated and canonical (no "hip-hop" vs "Hip Hop" forks).
///
/// Genre *assignment* — classifying a release and its individual tracks — lives
/// in the `release_genre` module. How a recording is presented and classified
/// is a property of the release (the consumer object), not of the recording's
/// objective sound data, so nothing here touches `Recording`.
module genre::genre;

use std::string::{Self, String};
use sui::derived_object::{Self, claim};
use sui::event::emit;

// === Errors ===

// Validation errors (20-29)
/// Genre name must not be empty.
const EEmptyName: u64 = 20;
/// Genre name exceeds the maximum length.
const ENameTooLong: u64 = 21;
/// Genre name contains a character other than `A`-`Z` or `_`.
const EInvalidNameChar: u64 = 22;

// === Constants ===

/// Maximum length of a genre name in bytes.
const MAX_NAME_LENGTH: u64 = 64;

// === Structs ===

/// Shared registry that parents the derived `Genre` objects.
public struct GenreRegistry has key {
    id: UID,
}

/// A genre in the canonical vocabulary. Immutable (frozen) once created.
/// Derived from the registry by `GenreKey(name)`, so a given name maps to a
/// single, deterministic object id.
public struct Genre has key {
    id: UID,
    /// Canonical genre name (e.g. "HIP_HOP").
    name: String,
}

/// Derivation key for a `Genre`, keyed by its canonical name.
public struct GenreKey(String) has copy, drop, store;

// === Events ===

/// Emitted once when package initialization creates and shares the canonical
/// genre registry.
public struct GenreRegistryCreatedEvent has copy, drop {
    registry_id: address,
    initializer: address,
    is_shared: bool,
}

/// Emitted when a genre is added to the vocabulary.
public struct GenreCreatedEvent has copy, drop {
    registry_id: address,
    genre_id: address,
    name: vector<u8>,
    is_frozen: bool,
}

// === Public Functions ===

fun init(ctx: &mut TxContext) {
    let registry = GenreRegistry { id: object::new(ctx) };
    let registry_id = object::id_address(&registry);
    let initializer = ctx.sender();
    let is_shared = true;

    transfer::share_object(registry);
    emit(GenreRegistryCreatedEvent { registry_id, initializer, is_shared });
}

/// Creates a genre in the canonical vocabulary. Creation is permissionless;
/// the validated canonical name fully determines the derived object, so caller
/// identity cannot change its id or contents. Creating the same name twice
/// aborts (dedup is automatic). The `Genre` is frozen — immutable and globally
/// readable by reference.
public fun new(registry: &mut GenreRegistry, name: String) {
    assert!(!name.is_empty(), EEmptyName);
    assert!(name.length() <= MAX_NAME_LENGTH, ENameTooLong);
    // Canonical form: uppercase `A`-`Z` and `_` only (e.g. "HIP_HOP"). Keeps the
    // vocabulary uniform so name-derived dedup is meaningful.
    assert!(
        name.as_bytes().all!(|c| (*c >= 0x41 && *c <= 0x5A) || *c == 0x5F),
        EInvalidNameChar,
    );

    // Copy the name for the object field/event before the original is moved
    // into the derivation key.
    let name_copy = string::utf8(*name.as_bytes());
    let genre = Genre {
        id: claim(&mut registry.id, GenreKey(name)),
        name: name_copy,
    };

    let registry_id = object::id_address(registry);
    let genre_id = object::id_address(&genre);
    let name = *genre.name().as_bytes();
    let is_frozen = true;

    transfer::freeze_object(genre);
    emit(GenreCreatedEvent { registry_id, genre_id, name, is_frozen });
}

/// Derives the address a `Genre` with the given name would have, without
/// creating it. Lets clients resolve/check a genre address offline.
public fun derive_address(self: &GenreRegistry, name: String): address {
    derived_object::derive_address(self.id.to_inner(), GenreKey(name))
}

// === View Functions ===

/// Returns the genre's canonical name.
public fun name(self: &Genre): &String {
    &self.name
}

// === Test Functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx)
}

/// Test-only accessor for the primitive `GenreRegistryCreatedEvent` payload in
/// declaration order.
#[test_only]
public fun genre_registry_created_event_fields(
    event: &GenreRegistryCreatedEvent,
): (address, address, bool) {
    (event.registry_id, event.initializer, event.is_shared)
}

/// Test-only accessor for the primitive `GenreCreatedEvent` payload in
/// declaration order.
#[test_only]
public fun genre_created_event_fields(
    event: &GenreCreatedEvent,
): (address, address, vector<u8>, bool) {
    (event.registry_id, event.genre_id, event.name, event.is_frozen)
}

/// Compatibility accessor for the legacy `GenreCreatedEvent` payload shape.
/// The event now stores primitive addresses and bytes, so convert them back to
/// the prior `ID` and `String` values for existing test callers.
#[test_only]
public fun created_event_fields(event: &GenreCreatedEvent): (ID, String) {
    (event.genre_id.to_id(), string::utf8(event.name))
}
