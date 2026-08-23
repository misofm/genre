// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module genre::genre_tests;

// Alias the module so the bare address `genre` resolves in
// `#[expected_failure(location = genre::genre)]` (avoids the addr==module
// name collision).
use genre::genre as g;
use genre::genre::{GenreRegistry, GenreRegistryCap, Genre, GenreCreatedEvent};
use std::unit_test::assert_eq;
use sui::event;
use sui::test_scenario::{Self as ts, Scenario};

const CURATOR: address = @0xC0;

// === Helpers ===

/// Creates a genre in the registry (cap-gated) and returns its derived id.
fun create_genre(scenario: &Scenario, name: vector<u8>): ID {
    let cap = scenario.take_from_sender<GenreRegistryCap>();
    let mut registry = scenario.take_shared<GenreRegistry>();
    let id = g::derive_address(&registry, name.to_string()).to_id();
    g::new(&cap, &mut registry, name.to_string());
    ts::return_shared(registry);
    scenario.return_to_sender(cap);
    id
}

// === Vocabulary ===

#[test]
fun test_create_genre_and_derive() {
    let mut scenario = ts::begin(CURATOR);
    g::init_for_testing(scenario.ctx());

    scenario.next_tx(CURATOR);
    let genre_id = create_genre(&scenario, b"HIP_HOP");

    // `new` emits exactly one `GenreCreatedEvent` with the full payload pinned.
    // Read back in the same transaction as the emit — `test_scenario` clears
    // the recorded event log across a `next_tx` boundary.
    let events = event::events_by_type<GenreCreatedEvent>();
    assert_eq!(events.length(), 1);
    let (event_genre_id, event_name) = g::created_event_fields(&events[0]);
    assert_eq!(event_genre_id, genre_id);
    assert_eq!(event_name, b"HIP_HOP".to_string());

    // The frozen Genre lives at the derived id, with the canonical name.
    scenario.next_tx(CURATOR);
    let genre = scenario.take_immutable_by_id<Genre>(genre_id);
    assert!(object::id(&genre) == genre_id);
    assert!(g::name(&genre) == b"HIP_HOP".to_string());
    ts::return_immutable(genre);

    scenario.end();
}

#[test]
#[expected_failure]
fun test_create_duplicate_aborts() {
    let mut scenario = ts::begin(CURATOR);
    g::init_for_testing(scenario.ctx());

    // Both creates on one registry borrow so the second hits the real dedup
    // abort (derived-object id already claimed), not test-scenario inventory.
    scenario.next_tx(CURATOR);
    let cap = scenario.take_from_sender<GenreRegistryCap>();
    let mut registry = scenario.take_shared<GenreRegistry>();
    g::new(&cap, &mut registry, b"HIP_HOP".to_string());
    g::new(&cap, &mut registry, b"HIP_HOP".to_string()); // same name -> aborts
    ts::return_shared(registry);
    scenario.return_to_sender(cap);

    scenario.end();
}

#[test]
#[expected_failure(abort_code = 20, location = genre::genre)] // EEmptyName
fun test_empty_name_aborts() {
    let mut scenario = ts::begin(CURATOR);
    g::init_for_testing(scenario.ctx());

    scenario.next_tx(CURATOR);
    create_genre(&scenario, b"");

    scenario.end();
}

#[test]
#[expected_failure(abort_code = 22, location = genre::genre)] // EInvalidNameChar
fun test_invalid_name_char_aborts() {
    let mut scenario = ts::begin(CURATOR);
    g::init_for_testing(scenario.ctx());

    scenario.next_tx(CURATOR);
    create_genre(&scenario, b"Hip-Hop"); // lowercase + hyphen -> rejected

    scenario.end();
}

// Same error as `test_invalid_name_char_aborts`, but the offending byte is
// below 'A' (0x41) rather than above 'Z' (0x5A) — covers both sides of the
// `>= 0x41 && <= 0x5A` short-circuit.
#[test]
#[expected_failure(abort_code = 22, location = genre::genre)] // EInvalidNameChar
fun test_invalid_name_char_below_range_aborts() {
    let mut scenario = ts::begin(CURATOR);
    g::init_for_testing(scenario.ctx());

    scenario.next_tx(CURATOR);
    create_genre(&scenario, b"1HIPHOP"); // digit -> below 'A', rejected

    scenario.end();
}

#[test]
#[expected_failure(abort_code = 21, location = genre::genre)] // ENameTooLong
fun test_name_too_long_aborts() {
    let mut scenario = ts::begin(CURATOR);
    g::init_for_testing(scenario.ctx());

    scenario.next_tx(CURATOR);
    // 65 'A's — one over the 64-byte MAX_NAME_LENGTH.
    let mut name = vector[];
    65u64.do!(|_| name.push_back(0x41u8));
    create_genre(&scenario, name);

    scenario.end();
}
