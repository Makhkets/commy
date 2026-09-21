package xhttp

import "crypto/tls"

// http2TLSConfig is the type x/net/http2 passes to its dial hook. The hook
// ignores it — the connection is dialled with sing-box's TLS stack, which is
// where uTLS and REALITY live — but the signature has to name it.
type http2TLSConfig = tls.Config
