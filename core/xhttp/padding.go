package xhttp

import (
	"crypto/rand"
	"math"
	"strings"

	"github.com/Makhkets/commy/core/xhttp/config"
	"golang.org/x/net/http2/hpack"
)

const charsetBase62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

// Huffman coding shrinks a base62 string by about a fifth.
const avgHuffmanBytesPerCharBase62 = 0.8

// How far the Huffman length of a tokenish padding may miss its target. The
// server allows the same slack when it validates.
const paddingTolerance = 2

// generatePadding returns a padding value of [length] bytes on the wire.
//
// "On the wire" is the point. HTTP/2 and HTTP/3 compress header values with a
// static Huffman table, so a value's length in memory is not its length in the
// packet. 'X' and 'Z' both cost exactly eight bits in that table, which is why
// repeat-x is made of them: what is asked for is what is sent. tokenish trades
// that for a value that looks like a token, and steers its Huffman length onto
// the target instead.
func generatePadding(method string, length int) string {
	if length <= 0 {
		return ""
	}
	if method == config.PaddingTokenish {
		if value := tokenishPadding(length); value != "" {
			return value
		}
	}
	return strings.Repeat("X", length)
}

func tokenishPadding(targetHuffmanBytes int) string {
	n := int(math.Ceil(float64(targetHuffmanBytes) / avgHuffmanBytesPerCharBase62))
	if n < 1 {
		n = 1
	}
	value := randomString(n, charsetBase62)
	if value == "" {
		return ""
	}
	adjust := byte('X')
	for range 150 {
		diff := int(hpack.HuffmanEncodeLength(value)) - targetHuffmanBytes
		if diff >= -paddingTolerance && diff <= paddingTolerance {
			return value
		}
		if diff < 0 {
			value += string(adjust)
			// Alternate, so the tail is not one long run of a single letter.
			if adjust == 'X' {
				adjust = 'Z'
			} else {
				adjust = 'X'
			}
			continue
		}
		if len(value) <= 1 {
			return value
		}
		value = value[:len(value)-1]
	}
	return value
}

// randomString draws [n] characters of [charset] without modulo bias.
//
// Returns "" when the platform has no entropy to give.
func randomString(n int, charset string) string {
	if n <= 0 || len(charset) == 0 || len(charset) > 256 {
		return ""
	}
	m := len(charset)
	limit := 256 - (256 % m)
	result := make([]byte, 0, n)
	scratch := make([]byte, 256)
	for len(result) < n {
		if _, err := rand.Read(scratch); err != nil {
			return ""
		}
		for _, b := range scratch {
			if int(b) >= limit {
				continue
			}
			result = append(result, charset[int(b)%m])
			if len(result) == n {
				break
			}
		}
	}
	return string(result)
}
