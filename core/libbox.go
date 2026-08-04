// Package core pins the sing-box version Commy builds against and selects the
// build tags the mobile artifacts are produced with.
//
// There is deliberately almost no Go code here. sing-box already ships
// experimental/libbox, which is designed to be bound with gomobile and is what
// the official sing-box Android app uses. Writing our own wrapper around it
// would mean re-implementing, and then maintaining, a moving API for no gain.
//
// So this module exists to do three things:
//
//   - pin the sing-box version in go.mod (bumping it is its own PR, rule R8);
//   - keep the libbox package in the module graph so `gomobile bind` can reach it;
//   - hold the few Commy-specific helpers libbox does not provide, in internal/
//     and cshared/.
//
// The AAR and the XCFramework are produced by scripts/build_core.sh, which binds
// github.com/sagernet/sing-box/experimental/libbox directly. The exact API that
// the Kotlin and Swift sides must implement is documented, read from the pinned
// source rather than from memory, in docs/13-libbox-reference.md.
package core

import (
	// Blank import: nothing here calls into libbox, but the dependency has to
	// stay in the module graph for gomobile to bind it.
	_ "github.com/sagernet/sing-box/experimental/libbox"
)

// SingBoxVersion is the pinned core version, mirrored from go.mod so that
// tooling and the About screen can report it without parsing go.mod.
//
// Keep in step with go.mod and with scripts/build_core.sh. A test asserts they
// agree, because three places that must match is exactly the kind of thing that
// silently drifts.
const SingBoxVersion = "v1.13.16"
