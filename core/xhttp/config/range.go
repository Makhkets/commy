package config

import (
	"crypto/rand"
	"encoding/json"
	"errors"
	"math/big"
	"strconv"
	"strings"
)

// Range is an inclusive pair of integers a value is drawn from.
//
// XHTTP randomises almost every number it puts on the wire — padding length,
// how many requests a connection serves, how long it lives — so that two
// clients of the same server do not look alike. A range with From == To is a
// fixed value.
type Range struct {
	From int32
	To   int32
}

// IsZero reports whether the range was left unset.
func (r Range) IsZero() bool {
	return r.From == 0 && r.To == 0
}

// Pick draws a value from the range, both ends included.
func (r Range) Pick() int32 {
	if r.To <= r.From {
		return r.From
	}
	span := int64(r.To) - int64(r.From) + 1
	n, err := rand.Int(rand.Reader, big.NewInt(span))
	if err != nil {
		// crypto/rand failing means the platform has no entropy source, which
		// nothing here can fix; the lower bound is always a legal answer.
		return r.From
	}
	return r.From + int32(n.Int64())
}

// String renders the range the way it is written in a config.
func (r Range) String() string {
	if r.From == r.To {
		return strconv.Itoa(int(r.From))
	}
	return strconv.Itoa(int(r.From)) + "-" + strconv.Itoa(int(r.To))
}

// MarshalJSON writes a fixed value as a number and a span as "from-to".
func (r Range) MarshalJSON() ([]byte, error) {
	if r.From == r.To {
		return json.Marshal(r.From)
	}
	return json.Marshal(r.String())
}

// UnmarshalJSON accepts what Xray accepts: a number, or a string holding a
// number or "from-to". Ends given in the wrong order are swapped, not refused.
func (r *Range) UnmarshalJSON(data []byte) error {
	var number int32
	if err := json.Unmarshal(data, &number); err == nil {
		r.From, r.To = number, number
		return nil
	}
	var text string
	if err := json.Unmarshal(data, &text); err != nil {
		return errors.New(`invalid range: expected a number or a string of the form "1-2"`)
	}
	parsed, err := ParseRange(text)
	if err != nil {
		return err
	}
	*r = parsed
	return nil
}

// ParseRange reads "5", "1-2" or the empty string (which is the zero range).
func ParseRange(text string) (Range, error) {
	text = strings.TrimSpace(text)
	if text == "" {
		return Range{}, nil
	}
	if value, err := strconv.ParseInt(text, 10, 32); err == nil {
		return Range{From: int32(value), To: int32(value)}, nil
	}
	// The separator is the first dash that is not a leading minus sign.
	split := strings.Index(text[1:], "-")
	if split < 0 {
		return Range{}, errors.New("invalid range: " + strconv.Quote(text))
	}
	split++
	from, errFrom := strconv.ParseInt(strings.TrimSpace(text[:split]), 10, 32)
	to, errTo := strconv.ParseInt(strings.TrimSpace(text[split+1:]), 10, 32)
	if errFrom != nil || errTo != nil {
		return Range{}, errors.New("invalid range: " + strconv.Quote(text))
	}
	if from > to {
		from, to = to, from
	}
	return Range{From: int32(from), To: int32(to)}, nil
}
