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
// # A second route for the download
//
// Xray's `downloadSettings`, here the `download` block: the GET of stream-up
// and packet-up goes to another address — usually a CDN in front of the same
// server — with its own TLS, HTTP version, path, headers, padding and XMUX
// pool. Nothing is inherited from the main route but the session id, which is
// what the server pairs the two by. The uploads stay on the main route; the
// mode is decided by the main route alone, and with REALITY, where auto would
// pick stream-one, it picks stream-up, since one request cannot take two
// routes. stream-one with a download route is refused, as Xray refuses it.
//
// The download route dials through the outbound's own dialer, so its sockets
// are protected like the main route's; Xray's per-route sockopt and
// dialerProxy have no equivalent. A server given by name is resolved through
// the route's default domain resolver.
//
// # What is not here
//
// The server half and the browser dialer: neither has a place in a client app.
package xhttp
