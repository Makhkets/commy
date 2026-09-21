// Package xhttp is a client for Xray's XHTTP transport, shaped to plug into
// sing-box as a V2Ray transport.
//
// sing-box does not have this transport and its author has declined to add
// it; a growing share of real-world servers speak nothing else. The server on
// the other end is always Xray, so Xray's implementation is the specification:
// this package was written against transport/internet/splithttp at Xray
// v26.9.9 and keeps its behaviour wherever the two could be told apart from
// the network.
//
// # What goes on the wire
//
// A proxied connection is carried by ordinary HTTP requests to one path.
//
//   - stream-one: a single POST. The request body is the upload, the response
//     body is the download. Needs a path that streams in both directions, which
//     in practice means HTTP/2 straight to the server (REALITY).
//   - stream-up: a GET whose response body is the download, plus one POST whose
//     body is the upload. The two are matched by a session id.
//   - packet-up: the same GET, but the upload is cut into many short POSTs, each
//     carrying a sequence number, which the server reorders. Every request is
//     finite, so this survives CDNs and reverse proxies that buffer a request
//     before forwarding it. It is the default whenever REALITY is not in use.
//
// Every request carries padding of a random length so that request sizes say
// nothing about what is inside.
//
// # What is not here
//
// The server half, the browser dialer, and `downloadSettings` (a second route
// for the download). The first two have no place in a client app; the third is
// named as a limitation in docs/adr/0010-xhttp-transport.md.
package xhttp
