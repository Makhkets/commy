//go:build tools

// Package tools keeps build-only dependencies in the module graph.
//
// gobind resolves github.com/sagernet/gomobile/bind *from the module being
// bound*, not from its own installation. Without this import `gomobile bind`
// fails with
//
//	"github.com/sagernet/gomobile/bind" is not found
//
// which reads like a broken gomobile install rather than a missing dependency.
//
// Note this is SagerNet's fork, not upstream golang.org/x/mobile: sing-box pins
// github.com/sagernet/gomobile v0.1.12, and the upstream tool does not
// understand the -libname flag the build needs.
package tools

import _ "github.com/sagernet/gomobile/bind"
