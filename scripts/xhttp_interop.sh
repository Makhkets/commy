#!/usr/bin/env bash
#
# Proves the XHTTP transport — and the REALITY client under it — against a REAL
# Xray, not against our own idea of one.
#
#   XRAY_BIN=/path/to/xray scripts/xhttp_interop.sh            # the whole matrix
#   XRAY_BIN=/path/to/xray scripts/xhttp_interop.sh reality    # names matching "reality"
#
# For every scenario it starts that Xray as a VLESS server over XHTTP, starts
# the pinned core (core/cmd/devbox, built here with the build overlay) as the
# client, and moves 24 MiB down and 16 MiB up through the pair, comparing
# SHA-256 at both ends. Everything listens on 127.0.0.1.
#
# The server on the other end of this transport is always Xray, so Xray's
# behaviour is the specification — and it moves. Two defects were found only
# this way (docs/adr/0010-xhttp-transport.md), and a third, in REALITY, that
# has nothing to do with XHTTP (docs/adr/0011-reality-client-hello.md). Run it
# against the newest Xray before a release, and against an old one after
# touching the REALITY edit.
#
# Xray is NOT downloaded by this script: get a release from
# https://github.com/XTLS/Xray-core/releases and point XRAY_BIN at it. Also
# needs go, python3, curl and openssl.

set -uo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly CORE_DIR="${REPO_ROOT}/core"
readonly WORK="${TMPDIR:-/tmp}/commy-xhttp-interop.$$"
readonly UUID="4f6a3b2c-9d1e-4c5a-8b7f-0123456789ab"
# A throwaway x25519 pair for REALITY, good for 127.0.0.1 and nothing else.
readonly REALITY_PRIVATE="OM6hs0J8f634S9InrMZ1IHVgiqRD4vtOM48EkKZFPW0"
readonly REALITY_PUBLIC="EDz_uy9HLU1rYpRN9VKIPOpFqCGbvs9oHlxZBwwwWSc"
readonly SHORT_ID="0123456789abcdef"
readonly TARGET_PORT=21080 SERVER_PORT=21443 CLIENT_PORT=21090 DECOY_PORT=21444

die() { printf '\n\033[31merror:\033[0m %s\n\n' "$*" >&2; exit 1; }
say() { printf '\033[36m==>\033[0m %s\n' "$*"; }

[[ -x "${XRAY_BIN:-}" ]] || die "XRAY_BIN must point at an xray binary.
   Get one from https://github.com/XTLS/Xray-core/releases — this script
   downloads nothing."
for tool in go python3 curl openssl; do
  command -v "${tool}" >/dev/null 2>&1 || die "${tool} is not on PATH."
done

mkdir -p "${WORK}"
pids=()
stop_all() {
  local pid
  for pid in "${pids[@]:-}"; do [[ -n "${pid}" ]] && kill "${pid}" 2>/dev/null; done
  wait 2>/dev/null
  pids=()
}
trap 'stop_all; rm -rf "${WORK}"' EXIT

say "building the pinned core with the overlay"
tags="$(grep -oP '(?<=^readonly TAGS=")[^"]+' "${REPO_ROOT}/scripts/build_core.sh")"
overlay="$(cd "${CORE_DIR}" && go run ./cmd/overlaygen)" || die "overlaygen failed."
( cd "${CORE_DIR}" && GODEBUG=goindex=0 go build -overlay="${overlay}" -tags "${tags}" \
    -ldflags "-checklinkname=0" -o "${WORK}/devbox" ./cmd/devbox ) || die "the core did not build."

openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
  -keyout "${WORK}/key.pem" -out "${WORK}/cert.pem" -days 2 -subj "/CN=xhttp.test" \
  -addext "subjectAltName=DNS:xhttp.test,IP:127.0.0.1" 2>/dev/null || die "openssl failed."

# What the traffic is fetched from and sent to: a blob with a known digest,
# and an endpoint that answers with the digest of what it was sent.
cat > "${WORK}/target.py" <<'PY'
import hashlib, http.server, os, socketserver, sys
BLOB = os.urandom(1 << 20) * 24
DIGEST = hashlib.sha256(BLOB).hexdigest().encode()
class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *args): pass
    def _reply(self, body):
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_GET(self):
        self._reply(DIGEST if self.path == "/digest" else BLOB)
    def do_PUT(self):
        digest, left = hashlib.sha256(), int(self.headers.get("Content-Length", "0"))
        while left > 0:
            chunk = self.rfile.read(min(left, 1 << 16))
            if not chunk: break
            digest.update(chunk); left -= len(chunk)
        self._reply(digest.hexdigest().encode())
class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True
Server(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
PY
head -c 16777216 /dev/urandom > "${WORK}/upload.bin"
readonly UPLOAD_DIGEST="$(sha256sum "${WORK}/upload.bin" | cut -d' ' -f1)"

passed=0 failed=0

# scenario <name> <security> <server mode> <client mode> [server extra] [client extra]
#   security: none | tls | tls-h1 | tls-h3 | reality
#   extras are JSON fragments starting with a comma: Xray's spelling for the
#   server (inside xhttpSettings), the core's for the client (inside transport).
scenario() {
  local name="$1" security="$2" server_mode="$3" client_mode="$4"
  local server_extra="${5:-}" client_extra="${6:-}"
  [[ -z "${FILTER}" || "${name}" == *"${FILTER}"* ]] || return 0

  local certs="\"certificates\": [{\"certificateFile\": \"${WORK}/cert.pem\", \"keyFile\": \"${WORK}/key.pem\"}]"
  local server_security client_tls
  case "${security}" in
    none)
      server_security='"security": "none"'; client_tls='' ;;
    tls)
      server_security="\"security\": \"tls\", \"tlsSettings\": {\"alpn\": [\"h2\"], ${certs}}"
      client_tls=', "tls": {"enabled": true, "server_name": "xhttp.test", "insecure": true, "utls": {"enabled": true, "fingerprint": "chrome"}}' ;;
    tls-h1)
      server_security="\"security\": \"tls\", \"tlsSettings\": {\"alpn\": [\"http/1.1\"], ${certs}}"
      client_tls=', "tls": {"enabled": true, "server_name": "xhttp.test", "insecure": true, "alpn": ["http/1.1"]}' ;;
    tls-h3)
      server_security="\"security\": \"tls\", \"tlsSettings\": {\"alpn\": [\"h3\"], ${certs}}"
      client_tls=', "tls": {"enabled": true, "server_name": "xhttp.test", "insecure": true, "alpn": ["h3"]}' ;;
    reality)
      server_security="\"security\": \"reality\", \"realitySettings\": {\"target\": \"127.0.0.1:${DECOY_PORT}\", \"dest\": \"127.0.0.1:${DECOY_PORT}\", \"serverNames\": [\"xhttp.test\"], \"privateKey\": \"${REALITY_PRIVATE}\", \"shortIds\": [\"${SHORT_ID}\"]}"
      client_tls=", \"tls\": {\"enabled\": true, \"server_name\": \"xhttp.test\", \"utls\": {\"enabled\": true, \"fingerprint\": \"chrome\"}, \"reality\": {\"enabled\": true, \"public_key\": \"${REALITY_PUBLIC}\", \"short_id\": \"${SHORT_ID}\"}}" ;;
    *) die "unknown security: ${security}" ;;
  esac

  # `finalRules` lets a recent Xray reach 127.0.0.1, which it otherwise
  # blackholes as a private target; older versions ignore the key.
  cat > "${WORK}/server.json" <<JSON
{ "log": {"loglevel": "info"},
  "inbounds": [{ "listen": "127.0.0.1", "port": ${SERVER_PORT}, "protocol": "vless",
    "settings": {"clients": [{"id": "${UUID}"}], "decryption": "none"},
    "streamSettings": {"network": "xhttp", ${server_security},
      "xhttpSettings": {"path": "/xh", "mode": "${server_mode}" ${server_extra}}} }],
  "outbounds": [{"protocol": "freedom", "settings": {"finalRules": [{"action": "allow"}]}}] }
JSON
  cat > "${WORK}/client.json" <<JSON
{ "log": {"level": "debug", "timestamp": false},
  "inbounds": [{"type": "mixed", "tag": "in", "listen": "127.0.0.1", "listen_port": ${CLIENT_PORT}}],
  "outbounds": [{"type": "vless", "tag": "proxy", "server": "127.0.0.1", "server_port": ${SERVER_PORT},
    "uuid": "${UUID}" ${client_tls},
    "transport": {"type": "xhttp", "mode": "${client_mode}", "path": "/xh" ${client_extra}}}] }
JSON

  python3 "${WORK}/target.py" "${TARGET_PORT}" & pids+=($!)
  if [[ "${security}" == reality ]]; then
    # What REALITY borrows its handshake from: any TLS 1.3 server will do.
    openssl s_server -accept "${DECOY_PORT}" -cert "${WORK}/cert.pem" -key "${WORK}/key.pem" \
      -tls1_3 -www -quiet >/dev/null 2>&1 & pids+=($!)
  fi
  "${XRAY_BIN}" run -c "${WORK}/server.json" > "${WORK}/server.log" 2>&1 & pids+=($!)
  "${WORK}/devbox" "${WORK}/client.json" > "${WORK}/client.log" 2>&1 & pids+=($!)

  # Wait for the target instead of guessing how long a loaded machine needs.
  local want="" _
  for _ in $(seq 1 60); do
    want="$(curl -s --max-time 2 "http://127.0.0.1:${TARGET_PORT}/digest")"
    [[ ${#want} -eq 64 ]] && break
    sleep 0.5
  done
  sleep 1.5

  local proxy="socks5h://127.0.0.1:${CLIENT_PORT}" got="" sent="" attempt
  # Three attempts: against a REALITY server older than Xray 25.5 the first
  # handshake is expected to fail and switch the ClientHello (ADR-0011).
  for attempt in 1 2 3; do
    got="$(curl -s --max-time 60 -x "${proxy}" "http://127.0.0.1:${TARGET_PORT}/blob" | sha256sum | cut -d' ' -f1)"
    [[ "${got}" == "${want}" ]] && break
  done
  sent="$(curl -s --max-time 60 -x "${proxy}" -T "${WORK}/upload.bin" "http://127.0.0.1:${TARGET_PORT}/put")"

  local how
  how="$(grep -ao 'mode [a-z-]*, HTTP/[0-9.]*' "${WORK}/client.log" | sort -u | tr '\n' ' ')"
  if [[ ${#want} -eq 64 && "${got}" == "${want}" && "${sent}" == "${UPLOAD_DIGEST}" ]]; then
    printf '\033[32mPASS\033[0m  %-28s %s(attempt %s)\n' "${name}" "${how}" "${attempt}"
    passed=$((passed + 1))
  else
    printf '\033[31mFAIL\033[0m  %-28s %s\n' "${name}" "${how}"
    [[ "${got}" == "${want}" ]] || echo "      download: want ${want:-<target never came up>} got ${got}"
    [[ "${sent}" == "${UPLOAD_DIGEST}" ]] || echo "      upload:   want ${UPLOAD_DIGEST} got ${sent}"
    grep -a 'ERROR\|WARN' "${WORK}/client.log" | sed 's/\x1b\[[0-9;]*m//g' | tail -3 | cut -c1-240 | sed 's/^/      client: /'
    grep -ai 'invalid\|failed\|not allowed\|too large' "${WORK}/server.log" | tail -3 | cut -c1-240 | sed 's/^/      server: /'
    failed=$((failed + 1))
  fi
  stop_all
  sleep 0.5
}

FILTER="${1:-}"
say "server: $("${XRAY_BIN}" version | head -1)"

# ── every mode over every HTTP version ────────────────────────────────────────
scenario h1-auto            none    auto auto
scenario h1-stream-up       none    auto stream-up
scenario h1-stream-one      none    auto stream-one
scenario h2-auto            tls     auto auto
scenario h2-packet-up       tls     auto packet-up
scenario h2-stream-up       tls     auto stream-up
scenario h2-stream-one      tls     auto stream-one
scenario h3-auto            tls-h3  auto auto
scenario h3-stream-up       tls-h3  auto stream-up
scenario h3-stream-one      tls-h3  auto stream-one
scenario tls-alpn-http1     tls-h1  auto auto
scenario reality-auto       reality auto auto
scenario reality-packet-up  reality auto packet-up
scenario reality-stream-up  reality auto stream-up

# ── what a link's `extra` can ask for ─────────────────────────────────────────
scenario extra-padding tls auto auto \
  ', "xPaddingBytes": "2000-3000"' ', "x_padding_bytes": "2000-3000"'
scenario extra-no-grpc-header reality auto auto \
  ', "noGRPCHeader": true' ', "no_grpc_header": true'
scenario extra-small-posts tls packet-up packet-up \
  ', "scMaxEachPostBytes": 30000' ', "sc_max_each_post_bytes": 30000, "sc_min_posts_interval_ms": 3'
scenario extra-xmux tls auto auto \
  '' ', "xmux": {"max_concurrency": "2-4", "h_max_request_times": "20-30", "c_max_reuse_times": 3}'
scenario extra-host-and-headers tls auto auto \
  ', "host": "cdn.example"' ', "host": "cdn.example", "headers": {"X-Test": "1"}'
# Both spellings of the session keys go to the server: Xray renamed them after
# v26.3.27 and ignores the one it does not know.
scenario extra-obfs-cookie tls packet-up packet-up \
  ', "xPaddingObfsMode": true, "xPaddingPlacement": "cookie", "xPaddingKey": "sid", "sessionPlacement": "header", "sessionIDPlacement": "header", "seqPlacement": "query"' \
  ', "x_padding_obfs_mode": true, "x_padding_placement": "cookie", "x_padding_key": "sid", "session_placement": "header", "seq_placement": "query"'
scenario extra-obfs-tokenish tls packet-up packet-up \
  ', "xPaddingObfsMode": true, "xPaddingMethod": "tokenish", "xPaddingPlacement": "header", "xPaddingHeader": "X-Trace"' \
  ', "x_padding_obfs_mode": true, "x_padding_method": "tokenish", "x_padding_placement": "header", "x_padding_header": "X-Trace"'
# An upload that rides in headers has to fit the server's header limit, so the
# packet size comes down with it — Xray's own client needs the same.
scenario extra-upload-in-headers tls packet-up packet-up \
  ', "uplinkDataPlacement": "header", "scMaxEachPostBytes": 4000, "sessionIDTable": "base36", "sessionIDLength": "16-24"' \
  ', "uplink_data_placement": "header", "sc_max_each_post_bytes": 4000, "sc_min_posts_interval_ms": 1, "session_id_table": "base36", "session_id_length": "16-24"'
scenario extra-upload-in-cookies tls packet-up packet-up \
  ', "uplinkDataPlacement": "cookie", "scMaxEachPostBytes": 3000' \
  ', "uplink_data_placement": "cookie", "sc_max_each_post_bytes": 3000, "sc_min_posts_interval_ms": 1'

echo
if [[ ${failed} -eq 0 && ${passed} -gt 0 ]]; then
  say "${passed} passed, none failed"
else
  die "${passed} passed, ${failed} failed"
fi
