#!/usr/bin/env bash
#
# A panel and a set of live servers for the app running in an Android emulator.
#
#   XRAY_BIN=/path/to/xray scripts/emulator_stand.sh start   # servers + subscription
#   scripts/emulator_stand.sh links                          # the links, one per line
#   scripts/emulator_stand.sh probe                          # a traffic probe, into the emulator
#   scripts/emulator_stand.sh stop
#
# Everything listens on 127.0.0.1. Inside the emulator that is 10.0.2.2 — the
# emulator maps its gateway to the host's loopback — so nothing here is reachable
# from the network the machine is on, and the throwaway keys below protect
# nothing on purpose.
#
# What comes up:
#
#   Xray        VLESS REALITY Vision (18443), REALITY gRPC (18444), REALITY
#               XHTTP (18445), TLS XHTTP h2 (18446), Trojan TLS (18447),
#               Shadowsocks 2022 (18448), VMess WebSocket (18449)
#   core        Hysteria2 (18450/udp) and TUIC (18451/udp) — our pinned
#               sing-box (core/cmd/devbox), built here with the overlay
#   panel       http://10.0.2.2:18080/sub/<token> — a subscription the way
#               Remnawave serves one: base64 list, subscription-userinfo,
#               profile-title, announce. Tokens starting with "hwid" behave like
#               a panel with a device limit of one: no x-hwid header gets the
#               "App not supported" stub, a second device gets "device limit".
#               Every request is logged with its headers to panel.log.
#   blob        http://203.0.113.10/blob?mb=N inside the tunnel — a documentation
#               address the servers redirect to a local endpoint that answers
#               with N MiB (/digest gives their SHA-256). Throughput and
#               continuity checks without the internet: this address exists
#               only on the far side of a proxy, so a request that reaches it
#               went through the tunnel, and one that leaked goes nowhere.
#
# Servers are addressed by NAME (10.0.2.2.nip.io, a public wildcard DNS name
# that resolves to 10.0.2.2) unless STAND_HOST says otherwise: a node written
# as an IP never exercises the resolver that turns a node's host into an
# address, and that resolver was the reason the tunnel carried nothing until
# session 11 (docs/17-agent-handoff.md).
#
# The probe (`probe` above) is a static binary pushed to /data/local/tmp. It is
# what makes "did traffic get through, and when did it stop" a measurement
# rather than a look at the screen:
#
#   adb shell /data/local/tmp/probe get 'http://203.0.113.10/blob?mb=16'
#   adb shell /data/local/tmp/probe loop 'http://203.0.113.10/blob?mb=0' 250 60
#
# `get` prints bytes, time, speed and the SHA-256 (compare with
# http://127.0.0.1:18090/digest?mb=16 on the host); `loop` prints one line per
# request, so a network change or a crash in the middle shows up as a run of
# FAIL lines with timestamps. Run it as an ordinary app would be with
# `adb shell su 2000 …` on a rootable image: root is exempt from the always-on
# kill switch, uid 2000 is not.
#
# Where to look while testing:
#   $STAND_DIR/xray-access.log   every connection a client made through Xray,
#                                with its destination — the proof that traffic
#                                went through the tunnel and not beside it
#   $STAND_DIR/core.log          the same for Hysteria2 and TUIC
#   $STAND_DIR/panel.log         subscription requests and their headers
#
# Xray is NOT downloaded here: point XRAY_BIN at a release from
# https://github.com/XTLS/Xray-core/releases. Needs go, python3 and openssl.

set -uo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly CORE_DIR="${REPO_ROOT}/core"
readonly STAND_DIR="${STAND_DIR:-${TMPDIR:-/tmp}/commy-stand}"
readonly HOST="${STAND_HOST:-10.0.2.2.nip.io}"
readonly SNI="stand.test"

readonly UUID="4f6a3b2c-9d1e-4c5a-8b7f-0123456789ab"
readonly PASSWORD="commy-stand-password"
# 16 random bytes, base64 — the key size 2022-blake3-aes-128-gcm wants.
readonly SS_KEY="bIRlc3RhbmQta2V5LTE2Yg=="
# The same throwaway REALITY pair scripts/xhttp_interop.sh uses.
readonly REALITY_PRIVATE="OM6hs0J8f634S9InrMZ1IHVgiqRD4vtOM48EkKZFPW0"
readonly REALITY_PUBLIC="EDz_uy9HLU1rYpRN9VKIPOpFqCGbvs9oHlxZBwwwWSc"
readonly SHORT_ID="0123456789abcdef"
readonly DECOY_PORT=18440 PANEL_PORT=18080 BLOB_PORT=18090
readonly BLOB_IP="203.0.113.10"

die() { printf '\n\033[31merror:\033[0m %s\n\n' "$*" >&2; exit 1; }
say() { printf '\033[36m==>\033[0m %s\n' "$*"; }

links() {
  local vmess
  vmess="$(printf '{"v":"2","ps":"🇺🇸 VMess WS","add":"%s","port":"18449","id":"%s","aid":"0","scy":"auto","net":"ws","type":"none","host":"","path":"/vm","tls":""}' \
    "${HOST}" "${UUID}" | base64 -w0)"
  cat <<LINKS
vless://${UUID}@${HOST}:18443?security=reality&encryption=none&pbk=${REALITY_PUBLIC}&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${SNI}&sid=${SHORT_ID}#🇳🇱 REALITY Vision
vless://${UUID}@${HOST}:18444?security=reality&encryption=none&pbk=${REALITY_PUBLIC}&fp=chrome&type=grpc&serviceName=grpc&sni=${SNI}&sid=${SHORT_ID}#🇩🇪 REALITY gRPC
vless://${UUID}@${HOST}:18445?security=reality&encryption=none&pbk=${REALITY_PUBLIC}&fp=chrome&type=xhttp&path=%2Fxh&mode=auto&sni=${SNI}&sid=${SHORT_ID}#🇫🇮 REALITY XHTTP
vless://${UUID}@${HOST}:18446?security=tls&encryption=none&type=xhttp&path=%2Fxt&mode=auto&sni=${SNI}&alpn=h2&fp=chrome&allowInsecure=1#🇸🇪 TLS XHTTP
trojan://${PASSWORD}@${HOST}:18447?security=tls&sni=${SNI}&type=tcp&allowInsecure=1#🇫🇷 Trojan
ss://$(printf '2022-blake3-aes-128-gcm:%s' "${SS_KEY}" | base64 -w0)@${HOST}:18448#🇬🇧 Shadowsocks 2022
vmess://${vmess}
hysteria2://${PASSWORD}@${HOST}:18450?sni=${SNI}&insecure=1#🇯🇵 Hysteria2
tuic://${UUID}:${PASSWORD}@${HOST}:18451?sni=${SNI}&alpn=h3&congestion_control=bbr&allow_insecure=1#🇸🇬 TUIC
LINKS
}

xray_config() {
  local cert="${STAND_DIR}/cert.pem" key="${STAND_DIR}/key.pem"
  local reality="\"security\": \"reality\", \"realitySettings\": {\"target\": \"127.0.0.1:${DECOY_PORT}\", \"serverNames\": [\"${SNI}\"], \"privateKey\": \"${REALITY_PRIVATE}\", \"shortIds\": [\"${SHORT_ID}\"]}"
  local tls="\"security\": \"tls\", \"tlsSettings\": {\"certificates\": [{\"certificateFile\": \"${cert}\", \"keyFile\": \"${key}\"}]"
  cat <<JSON
{ "log": {"loglevel": "info", "access": "${STAND_DIR}/xray-access.log", "error": "${STAND_DIR}/xray.log"},
  "inbounds": [
    { "tag": "reality-vision", "listen": "127.0.0.1", "port": 18443, "protocol": "vless",
      "settings": {"clients": [{"id": "${UUID}", "flow": "xtls-rprx-vision"}], "decryption": "none"},
      "streamSettings": {"network": "tcp", ${reality}} },
    { "tag": "reality-grpc", "listen": "127.0.0.1", "port": 18444, "protocol": "vless",
      "settings": {"clients": [{"id": "${UUID}"}], "decryption": "none"},
      "streamSettings": {"network": "grpc", "grpcSettings": {"serviceName": "grpc"}, ${reality}} },
    { "tag": "reality-xhttp", "listen": "127.0.0.1", "port": 18445, "protocol": "vless",
      "settings": {"clients": [{"id": "${UUID}"}], "decryption": "none"},
      "streamSettings": {"network": "xhttp", "xhttpSettings": {"path": "/xh", "mode": "auto"}, ${reality}} },
    { "tag": "tls-xhttp", "listen": "127.0.0.1", "port": 18446, "protocol": "vless",
      "settings": {"clients": [{"id": "${UUID}"}], "decryption": "none"},
      "streamSettings": {"network": "xhttp", "xhttpSettings": {"path": "/xt", "mode": "auto"}, ${tls}, "alpn": ["h2"]}} },
    { "tag": "trojan", "listen": "127.0.0.1", "port": 18447, "protocol": "trojan",
      "settings": {"clients": [{"password": "${PASSWORD}"}]},
      "streamSettings": {"network": "tcp", ${tls}}} },
    { "tag": "ss2022", "listen": "127.0.0.1", "port": 18448, "protocol": "shadowsocks",
      "settings": {"method": "2022-blake3-aes-128-gcm", "password": "${SS_KEY}", "network": "tcp,udp"} },
    { "tag": "vmess-ws", "listen": "127.0.0.1", "port": 18449, "protocol": "vmess",
      "settings": {"clients": [{"id": "${UUID}"}]},
      "streamSettings": {"network": "ws", "wsSettings": {"path": "/vm"}} }
  ],
  "routing": {"rules": [{"type": "field", "ip": ["${BLOB_IP}"], "outboundTag": "blob"}]},
  "outbounds": [
    {"tag": "direct", "protocol": "freedom", "settings": {"finalRules": [{"action": "allow"}]}},
    {"tag": "blob", "protocol": "freedom",
     "settings": {"redirect": "127.0.0.1:${BLOB_PORT}", "finalRules": [{"action": "allow"}]}}
  ] }
JSON
}

core_config() {
  local tls="\"tls\": {\"enabled\": true, \"server_name\": \"${SNI}\", \"alpn\": [\"h3\"], \"certificate_path\": \"${STAND_DIR}/cert.pem\", \"key_path\": \"${STAND_DIR}/key.pem\"}"
  cat <<JSON
{ "log": {"level": "info", "timestamp": true, "output": "${STAND_DIR}/core.log"},
  "inbounds": [
    {"type": "hysteria2", "tag": "hysteria2", "listen": "127.0.0.1", "listen_port": 18450,
     "users": [{"password": "${PASSWORD}"}], ${tls}},
    {"type": "tuic", "tag": "tuic", "listen": "127.0.0.1", "listen_port": 18451,
     "users": [{"uuid": "${UUID}", "password": "${PASSWORD}"}], "congestion_control": "bbr", ${tls}}
  ],
  "route": {"rules": [{"ip_cidr": ["${BLOB_IP}/32"], "action": "route-options",
                       "override_address": "127.0.0.1", "override_port": ${BLOB_PORT}}],
            "final": "direct"},
  "outbounds": [{"type": "direct", "tag": "direct"}] }
JSON
}

panel_py() {
  cat <<'PY'
import base64, http.server, json, socketserver, sys, time

port, links_file, log_file = int(sys.argv[1]), sys.argv[2], sys.argv[3]
DEVICE_LIMIT = 1
devices = {}

def stub(remark):
    # What Remnawave sends instead of servers: one line at 0.0.0.0:1 whose
    # name is the message (hwidNotSupportedRemarks / hwidMaxDevicesRemarks).
    return ("vless://00000000-0000-0000-0000-000000000000@0.0.0.0:1"
            "?encryption=none&type=tcp#" + remark)

def b64(text):
    return "base64:" + base64.b64encode(text.encode()).decode()

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *args):
        pass
    def do_GET(self):
        headers = {k.lower(): v for k, v in self.headers.items()}
        parts = self.path.split("?")[0].strip("/").split("/")
        token = parts[1] if len(parts) >= 2 and parts[0] == "sub" else None
        verdict = "servers"
        if token is None:
            self.send_response(404); self.send_header("Content-Length", "0"); self.end_headers()
            verdict = "not found"
        else:
            body = open(links_file, encoding="utf-8").read().strip()
            if token.startswith("hwid"):
                hwid = headers.get("x-hwid")
                known = devices.setdefault(token, [])
                if not hwid:
                    body, verdict = stub("App not supported"), "stub: no x-hwid"
                elif hwid not in known and len(known) >= DEVICE_LIMIT:
                    body, verdict = stub("Device limit reached"), "stub: device limit"
                elif hwid not in known:
                    known.append(hwid)
            payload = base64.b64encode(body.encode()).decode().encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("profile-title", b64("🧪 Commy stand"))
            self.send_header("profile-update-interval", "12")
            self.send_header("subscription-userinfo",
                             "upload=1073741824; download=5368709120; "
                             "total=107374182400; expire=%d" % (time.time() + 30 * 86400))
            self.send_header("announce", b64("Test stand on the developer machine"))
            self.send_header("support-url", "https://github.com/Makhkets/commy")
            self.end_headers()
            self.wfile.write(payload)
        with open(log_file, "a", encoding="utf-8") as log:
            log.write(json.dumps({"time": time.strftime("%H:%M:%S"), "path": self.path,
                                  "verdict": verdict, "headers": headers},
                                 ensure_ascii=False) + "\n")

class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

Server(("127.0.0.1", port), Handler).serve_forever()
PY
}

decoy_py() {
  cat <<'PY'
import socket, socketserver, ssl, sys

port, cert, key = int(sys.argv[1]), sys.argv[2], sys.argv[3]
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.minimum_version = ssl.TLSVersion.TLSv1_3
context.load_cert_chain(cert, key)
BODY = b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"

class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(15)
        try:
            with context.wrap_socket(self.request, server_side=True) as tls:
                tls.recv(4096)
                tls.sendall(BODY)
        except (OSError, ssl.SSLError):
            pass

class Server(socketserver.ThreadingMixIn, socketserver.TCPServer):
    daemon_threads = True
    allow_reuse_address = True

Server(("127.0.0.1", port), Handler).serve_forever()
PY
}

blob_py() {
  cat <<'PY'
import hashlib, http.server, socketserver, sys, urllib.parse

CHUNK = bytes(range(256)) * 4096  # 1 MiB, the same every time

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *args):
        pass
    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        mb = int(urllib.parse.parse_qs(url.query).get("mb", ["1"])[0])
        if url.path == "/digest":
            body = hashlib.sha256(CHUNK * mb).hexdigest().encode() + b"\n"
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(CHUNK) * mb))
        self.end_headers()
        for _ in range(mb):
            self.wfile.write(CHUNK)

class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

Server(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
PY
}

probe_go() {
  cat <<'GO'
// probe runs inside the emulator and says whether traffic gets through, how
// fast, and when it stops and starts again. It never resolves names itself —
// Android has no /etc/resolv.conf — so URLs carry an IP.
package main

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"time"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Fprintln(os.Stderr, "usage: probe get <url> | probe body <url> [host] | probe loop <url> <every-ms> <seconds>")
		os.Exit(2)
	}
	switch os.Args[1] {
	case "get":
		os.Exit(get(os.Args[2]))
	case "body":
		host := ""
		if len(os.Args) > 3 {
			host = os.Args[3]
		}
		os.Exit(body(os.Args[2], host))
	case "loop":
		every, _ := strconv.Atoi(os.Args[3])
		seconds, _ := strconv.Atoi(os.Args[4])
		loop(os.Args[2], time.Duration(every)*time.Millisecond, time.Duration(seconds)*time.Second)
	}
}

func client(timeout time.Duration) *http.Client {
	return &http.Client{Timeout: timeout, Transport: &http.Transport{DisableKeepAlives: true}}
}

func get(url string) int {
	start := time.Now()
	resp, err := client(120 * time.Second).Get(url)
	if err != nil {
		fmt.Printf("FAIL %v after %s\n", err, time.Since(start).Round(time.Millisecond))
		return 1
	}
	defer resp.Body.Close()
	hash := sha256.New()
	n, err := io.Copy(hash, resp.Body)
	took := time.Since(start)
	if err != nil {
		fmt.Printf("FAIL after %d bytes: %v\n", n, err)
		return 1
	}
	fmt.Printf("OK %d bytes in %s, %.2f MB/s, sha256 %s\n", n, took.Round(time.Millisecond),
		float64(n)/took.Seconds()/1e6, hex.EncodeToString(hash.Sum(nil)))
	return 0
}

// body prints what one GET answers, with the Host header set by hand and no
// redirect followed — how a probe that resolves no names asks an address
// echo which server the traffic left through:
//
//	probe body 'http://208.95.112.1/line/?fields=query,country' ip-api.com
func body(url, host string) int {
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		fmt.Println("FAIL", err)
		return 1
	}
	if host != "" {
		req.Host = host
	}
	c := client(15 * time.Second)
	c.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	resp, err := c.Do(req)
	if err != nil {
		fmt.Println("FAIL", err)
		return 1
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(io.LimitReader(resp.Body, 600))
	fmt.Printf("HTTP %d\n%s\n", resp.StatusCode, data)
	return 0
}

func loop(url string, every, total time.Duration) {
	c := client(every*4 + time.Second)
	deadline := time.Now().Add(total)
	for time.Now().Before(deadline) {
		start := time.Now()
		resp, err := c.Get(url)
		stamp := start.Format("15:04:05.000")
		if err != nil {
			fmt.Printf("%s FAIL %v\n", stamp, err)
		} else {
			n, _ := io.Copy(io.Discard, resp.Body)
			resp.Body.Close()
			fmt.Printf("%s OK %d %s\n", stamp, n, time.Since(start).Round(time.Millisecond))
		}
		if rest := every - time.Since(start); rest > 0 {
			time.Sleep(rest)
		}
	}
}
GO
}

probe() {
  command -v adb >/dev/null 2>&1 || die "adb is not on PATH."
  local dir="${STAND_DIR}/probe"
  mkdir -p "${dir}"
  probe_go > "${dir}/main.go"
  printf 'module probe\n\ngo 1.24\n' > "${dir}/go.mod"
  # linux/amd64, static: the x86_64 emulator runs it as it is.
  ( cd "${dir}" && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath \
      -ldflags "-s -w" -o probe . ) || die "the probe did not build."
  adb push "${dir}/probe" /data/local/tmp/probe >/dev/null || die "adb push failed."
  adb shell chmod 755 /data/local/tmp/probe
  say "probe is at /data/local/tmp/probe"
}

start() {
  [[ -x "${XRAY_BIN:-}" ]] || die "XRAY_BIN must point at an xray binary.
   Get one from https://github.com/XTLS/Xray-core/releases — this script
   downloads nothing."
  for tool in go python3 openssl; do
    command -v "${tool}" >/dev/null 2>&1 || die "${tool} is not on PATH."
  done
  [[ -f "${STAND_DIR}/pids" ]] && die "already running — scripts/emulator_stand.sh stop"
  mkdir -p "${STAND_DIR}"

  say "building the pinned core with the overlay"
  local tags overlay
  tags="$(grep -oP '(?<=^readonly TAGS=")[^"]+' "${REPO_ROOT}/scripts/build_core.sh")"
  overlay="$(cd "${CORE_DIR}" && go run ./cmd/overlaygen)" || die "overlaygen failed."
  ( cd "${CORE_DIR}" && GODEBUG=goindex=0 go build -overlay="${overlay}" -tags "${tags}" \
      -ldflags "-checklinkname=0" -o "${STAND_DIR}/devbox" ./cmd/devbox ) || die "the core did not build."

  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
    -keyout "${STAND_DIR}/key.pem" -out "${STAND_DIR}/cert.pem" -days 30 -subj "/CN=${SNI}" \
    -addext "subjectAltName=DNS:${SNI},DNS:${HOST}" 2>/dev/null || die "openssl failed."
  links > "${STAND_DIR}/links.txt"
  xray_config > "${STAND_DIR}/xray.json"
  core_config > "${STAND_DIR}/core.json"
  panel_py > "${STAND_DIR}/panel.py"
  blob_py > "${STAND_DIR}/blob.py"
  decoy_py > "${STAND_DIR}/decoy.py"

  local pids=()
  # What REALITY borrows its handshake from: any TLS 1.3 server will do — as
  # long as it serves more than one connection at a time. `openssl s_server`
  # does not: a session cut off mid-handshake (a phone losing Wi-Fi) held it
  # until Xray timed out, and every REALITY handshake behind it waited ~75 s.
  # That looked exactly like a tunnel that does not survive a network change.
  setsid python3 "${STAND_DIR}/decoy.py" "${DECOY_PORT}" "${STAND_DIR}/cert.pem" \
    "${STAND_DIR}/key.pem" > "${STAND_DIR}/decoy.out" 2>&1 < /dev/null & pids+=($!)
  setsid "${XRAY_BIN}" run -c "${STAND_DIR}/xray.json" > "${STAND_DIR}/xray.out" 2>&1 < /dev/null & pids+=($!)
  setsid "${STAND_DIR}/devbox" "${STAND_DIR}/core.json" > "${STAND_DIR}/core.out" 2>&1 < /dev/null & pids+=($!)
  setsid python3 "${STAND_DIR}/panel.py" "${PANEL_PORT}" "${STAND_DIR}/links.txt" \
    "${STAND_DIR}/panel.log" > "${STAND_DIR}/panel.out" 2>&1 < /dev/null & pids+=($!)
  setsid python3 "${STAND_DIR}/blob.py" "${BLOB_PORT}" > "${STAND_DIR}/blob.out" 2>&1 < /dev/null & pids+=($!)
  printf '%s\n' "${pids[@]}" > "${STAND_DIR}/pids"
  sleep 2

  local pid dead=0
  for pid in "${pids[@]}"; do kill -0 "${pid}" 2>/dev/null || dead=1; done
  if [[ ${dead} -eq 1 ]]; then
    tail -n 5 "${STAND_DIR}"/*.out >&2
    stop
    die "a server did not stay up; the lines above say which."
  fi
  say "Xray: $("${XRAY_BIN}" version | head -1)"
  say "up. In the emulator:"
  echo "    subscription   http://10.0.2.2:${PANEL_PORT}/sub/stand"
  echo "    with HWID      http://10.0.2.2:${PANEL_PORT}/sub/hwid-stand"
  echo "    through it     http://${BLOB_IP}/blob?mb=8  (only reachable through a proxy)"
  echo "    logs           ${STAND_DIR}/{xray-access,core,panel}.log"
}

stop() {
  [[ -f "${STAND_DIR}/pids" ]] || { say "not running"; return 0; }
  local pid
  while read -r pid; do
    [[ -n "${pid}" ]] && kill -- "-${pid}" 2>/dev/null
  done < "${STAND_DIR}/pids"
  rm -f "${STAND_DIR}/pids"
  say "stopped"
}

case "${1:-}" in
  start) start ;;
  stop) stop ;;
  links) links ;;
  probe) probe ;;
  *) die "usage: scripts/emulator_stand.sh start | stop | links | probe" ;;
esac
