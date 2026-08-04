package safe

import (
	"errors"
	"strings"
	"testing"
)

func TestDoPassesThroughSuccess(t *testing.T) {
	if err := Do(func() error { return nil }); err != nil {
		t.Fatalf("want nil, got %v", err)
	}
}

func TestDoPassesThroughError(t *testing.T) {
	sentinel := errors.New("boom")
	err := Do(func() error { return sentinel })
	if !errors.Is(err, sentinel) {
		t.Fatalf("want the original error, got %v", err)
	}
}

func TestDoConvertsPanic(t *testing.T) {
	err := Do(func() error { panic("kaboom") })
	if err == nil {
		t.Fatal("a panic must not escape")
	}
	if !strings.Contains(err.Error(), "kaboom") {
		t.Fatalf("panic value lost: %v", err)
	}
	// The stack is the whole point: without it a crash report from a user's
	// device is unusable.
	if !strings.Contains(err.Error(), "recover_test.go") {
		t.Fatalf("stack not captured: %v", err)
	}
}

func TestDoConvertsNilDeref(t *testing.T) {
	var p *struct{ n int }
	err := Do(func() error {
		_ = p.n
		return nil
	})
	if err == nil {
		t.Fatal("a nil dereference must not escape")
	}
}

func TestValueReturnsZeroOnPanic(t *testing.T) {
	got, err := Value(func() (int, error) { panic("nope") })
	if err == nil {
		t.Fatal("want an error")
	}
	if got != 0 {
		t.Fatalf("want the zero value, got %d", got)
	}
}

func TestValuePassesThrough(t *testing.T) {
	got, err := Value(func() (string, error) { return "ok", nil })
	if err != nil || got != "ok" {
		t.Fatalf("want (ok, nil), got (%q, %v)", got, err)
	}
}

func TestMessageIsEmptyOnSuccess(t *testing.T) {
	if msg := Message(func() error { return nil }); msg != "" {
		t.Fatalf("success must be the empty string, got %q", msg)
	}
}

func TestMessageCarriesPanic(t *testing.T) {
	msg := Message(func() error { panic("fault") })
	if !strings.Contains(msg, "fault") {
		t.Fatalf("want the panic in the message, got %q", msg)
	}
}
