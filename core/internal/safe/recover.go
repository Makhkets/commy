// Package safe turns Go panics into error strings at the language boundary.
//
// A panic that crosses cgo or JNI does not become a catchable exception on the
// other side — it takes the whole process down, and the crash report shows the
// host thread rather than the Go stack that caused it. Debugging that from a
// user's device is close to hopeless.
//
// So every exported entry point wraps its body here. This is not defensive
// programming for its own sake: it is the only place where the Go stack is still
// available to record.
package safe

import (
	"fmt"
	"runtime/debug"
)

// Do runs fn and converts a panic into an error.
//
// The returned error carries the panic value and the Go stack, so the caller can
// log something that identifies the fault instead of a bare "signal 11".
func Do(fn func() error) (err error) {
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("panic: %v\n%s", r, debug.Stack())
		}
	}()
	return fn()
}

// Value runs fn and converts a panic into an error, preserving its result.
//
// On panic the zero value of T is returned alongside the error; callers must
// check the error before using the value.
func Value[T any](fn func() (T, error)) (value T, err error) {
	defer func() {
		if r := recover(); r != nil {
			var zero T
			value = zero
			err = fmt.Errorf("panic: %v\n%s", r, debug.Stack())
		}
	}()
	return fn()
}

// Message runs fn and reduces the outcome to a string, empty meaning success.
//
// This is the shape the C ABI in cshared/ needs: it cannot return a Go error, and
// an out-parameter for the message would mean another allocation to free.
func Message(fn func() error) string {
	if err := Do(fn); err != nil {
		return err.Error()
	}
	return ""
}
