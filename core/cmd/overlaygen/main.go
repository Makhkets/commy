// Command overlaygen writes the handful of edits Commy makes to the pinned
// sing-box and its TUN library into patched copies of those modules, applied
// at build time and nowhere else, and a go.mod that builds against them.
//
//	go test -modfile="$(go run ./cmd/overlaygen -out build/_overlay)" ...
//
// scripts/build_core.sh hands the same go.mod to gomobile inside a copy of
// core/ (a -modfile flag would follow gomobile into its own temporary module).
//
// There are five of them, and each is here because the alternative was worse.
//
// # XHTTP
//
// sing-box picks a V2Ray transport with a `switch` over a closed set of names,
// in two places: where the `transport` block is decoded, and where the client
// is built. There is no registry to add to. The transport itself is ordinary
// code in core/xhttp; two upstream files gain eleven lines so that the name
// "xhttp" reaches it. See docs/adr/0010-xhttp-transport.md.
//
// # The REALITY ClientHello
//
// sing-box removes the X25519MLKEM768 key share from the ClientHello of its
// REALITY client, because REALITY servers older than Xray v25.5 cannot finish
// a handshake that offers it. Since Xray v26.9.8 the server does the opposite:
// it refuses a ClientHello that does NOT offer it, as "outdated/strange" — no
// browser has sent such a hello for two years. No released sing-box copes with
// both, and the owner of a server is not the user of this app. The edit makes
// the client send the modern hello first and fall back to the stripped one
// when, and only when, the server has answered with somebody else's
// certificate. See docs/adr/0011-reality-client-hello.md.
//
// # The REALITY client version
//
// A REALITY client writes its version into the encrypted session ID, and the
// server may refuse versions outside a range. sing-box writes 1.8.1 — and
// Xray 26.7.28, when its owner sets no range, refuses everything below
// 26.3.27: "other clients may be refused to connect". Every node of a panel
// that updated to it answered this client with the cover site's certificate,
// while clients on current Xray connected. The edit writes 26.9.9, the Xray
// release whose REALITY client this one now matches — the hello above is
// that release's. The server uses the number for nothing but the range. See
// docs/adr/0013-reality-client-version.md.
//
// # The server the user picked
//
// With the cache file on, a selector starts on the outbound it last saw
// selected — stored whenever a server is switched inside a running core —
// and consults its configured default only when the cache holds nothing.
// Commy writes the user's choice into that default on every start, from its
// own settings. So a server picked while disconnected lost to the one last
// switched to inside the previous session: the chip named one server and the
// traffic went through another, or through one that was down. The edit
// consults the cache only for a selector with no default. See
// docs/adr/0014-selector-default.md.
//
// # The gVisor reader that outlives its stack
//
// sing-tun puts a filter in front of the gVisor link endpoint, and the
// filter's Attach wraps whatever it is handed — nil included. Closing the
// stack detaches the endpoint with Attach(nil); the wrapper turns that into a
// non-nil dispatcher, and fdbased, which stops its reader only on nil, stops
// nothing. Every stop or reload of the core then leaves a thread asleep in
// ppoll on the old descriptor number: the TUN interface outlives the tunnel,
// one more per reconnect, and a reader that wakes up reads whatever file now
// owns that number — a socket of the new core, or the new TUN. Seen on the
// emulator; upstream sing-tun has the same one-line fix on its main branch,
// but no tag sing-box pins does — v0.8.15, which v1.13.21 requires, carries
// the file unchanged. See docs/adr/0012-gvisor-reader-stop.md.
//
// # Why patched copies
//
// Reaching upstream code means changing upstream files, and there are three
// ways to do that:
//
//   - fork sing-box and point go.mod at the fork. Every downstream that does
//     this ends up maintaining a fork; go.mod stops saying which core we ship.
//   - vendor sing-box into the repository. A thousand files of somebody else's
//     code in every diff, for a change of a few dozen lines.
//   - leave the module exactly as published and patch it at build time. go.mod
//     keeps naming the real version, and the whole delta is the list of edits
//     below.
//
// This is the third. The edits are exact-string replacements: each anchor must
// appear exactly once in a file whose SHA-256 is the one recorded here, in a
// module whose version is the one recorded here. A sing-box bump that touches
// any of these files, or brings a different sing-tun, stops the build with a
// message saying so, instead of compiling a stale copy of upstream's code into
// the core (rule R8: a bump is its own change, and re-basing these edits — or
// dropping one upstream no longer needs — is part of it).
//
// Until session 22 the patched files were laid over the module cache with
// `go build -overlay`. Go 1.25 refuses an overlay under GOMODCACHE, which
// pinned the core to Go 1.24 and its expired security support; the copies
// outside the cache replace that (docs/adr/0018-core-module-copies.md), and
// with them the module-index workaround the overlay needed
// (GODEBUG=goindex=0) is gone as well.
package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// module is an upstream module the overlay edits, at the version the hashes
// below were taken from. The version is checked against go.mod by the module
// query, not assumed.
type module struct {
	path    string
	version string
}

var (
	singBox = module{"github.com/sagernet/sing-box", "v1.13.21"}
	// singTun is whatever sing-box v1.13.21 requires. It moves only when
	// sing-box does, so a bump meets this check as well as the hashes.
	singTun = module{"github.com/sagernet/sing-tun", "v0.8.15"}
)

type edit struct {
	// anchor is upstream text that must occur exactly once.
	anchor string
	// replacement is what the anchor becomes.
	replacement string
}

type target struct {
	module module
	// path is relative to the module root.
	path   string
	sha256 string
	edits  []edit
}

var targets = []target{
	{
		module: singBox,
		path:   "option/v2ray_transport.go",
		sha256: "b21a197c27195d7b35ce746751905d2e054fdfc668ec66052f7efd4714538d0e",
		edits: []edit{
			{
				anchor: "import (\n",
				replacement: "import (\n" +
					"\txhttpconfig \"github.com/Makhkets/commy/core/xhttp/config\"\n",
			},
			{
				anchor: "\tHTTPUpgradeOptions V2RayHTTPUpgradeOptions `json:\"-\"`\n",
				replacement: "\tHTTPUpgradeOptions V2RayHTTPUpgradeOptions `json:\"-\"`\n" +
					"\tXHTTPOptions       xhttpconfig.Options     `json:\"-\"`\n",
			},
			{
				anchor: "\tcase C.V2RayTransportTypeHTTPUpgrade:\n\t\tv = o.HTTPUpgradeOptions\n",
				replacement: "\tcase C.V2RayTransportTypeHTTPUpgrade:\n\t\tv = o.HTTPUpgradeOptions\n" +
					"\tcase xhttpconfig.TransportType:\n\t\tv = o.XHTTPOptions\n",
			},
			{
				anchor: "\tcase C.V2RayTransportTypeHTTPUpgrade:\n\t\tv = &o.HTTPUpgradeOptions\n",
				replacement: "\tcase C.V2RayTransportTypeHTTPUpgrade:\n\t\tv = &o.HTTPUpgradeOptions\n" +
					"\tcase xhttpconfig.TransportType:\n\t\tv = &o.XHTTPOptions\n",
			},
		},
	},
	{
		module: singBox,
		path:   "common/tls/reality_client.go",
		sha256: "c4ac64433d5fce2c4f40ad0e49ed73f90259861c2553307fb394559c923f6b68",
		edits: []edit{
			{
				anchor:      "\t\"strings\"\n",
				replacement: "\t\"strings\"\n\t\"sync/atomic\"\n",
			},
			{
				anchor: "\tpublicKey []byte\n\tshortID   [8]byte\n}\n",
				replacement: "\tpublicKey []byte\n\tshortID   [8]byte\n" +
					"\t// [commy] See commyRealityHello below.\n" +
					"\tcommyHello *commyRealityHello\n}\n" + realityHelloType,
			},
			{
				anchor:      "&RealityClientConfig{ctx, uClient.(*UTLSClientConfig), publicKey, shortID}",
				replacement: "&RealityClientConfig{ctx, uClient.(*UTLSClientConfig), publicKey, shortID, &commyRealityHello{logger: logger}}",
			},
			{
				anchor:      realityStripBlock,
				replacement: realityStripBlockGuarded,
			},
			{
				anchor: "\terr = uConn.HandshakeContext(ctx)\n\tif err != nil {\n\t\treturn nil, err\n\t}\n",
				replacement: "\terr = uConn.HandshakeContext(ctx)\n\tif err != nil {\n" +
					"\t\t// [commy] Only a server that answered as somebody else counts. A\n" +
					"\t\t// timeout or a reset says nothing about which hello it wants.\n" +
					"\t\tif verifier.refused {\n\t\t\te.commyHello.refusedWith(legacyHello)\n\t\t}\n" +
					"\t\treturn nil, err\n\t}\n",
			},
			{
				anchor: "\tif !verifier.verified {\n",
				replacement: "\tif !verifier.verified {\n" +
					"\t\te.commyHello.refusedWith(legacyHello) // [commy]\n",
			},
			{
				anchor:      "\t\te.publicKey,\n\t\te.shortID,\n\t}\n",
				replacement: "\t\te.publicKey,\n\t\te.shortID,\n\t\te.commyHello, // [commy]\n\t}\n",
			},
			{
				anchor: "\tauthKey    []byte\n\tverified   bool\n}\n",
				replacement: "\tauthKey    []byte\n\tverified   bool\n" +
					"\t// [commy] The certificate was not REALITY's: the server treated this\n" +
					"\t// client as a stranger and showed it the target's own.\n" +
					"\trefused bool\n}\n",
			},
			{
				anchor:      "\topts := x509.VerifyOptions{\n\t\tDNSName:       c.serverName,\n",
				replacement: "\tc.refused = true // [commy]\n\topts := x509.VerifyOptions{\n\t\tDNSName:       c.serverName,\n",
			},
			{
				anchor: "\thello.SessionId[0] = 1\n\thello.SessionId[1] = 8\n\thello.SessionId[2] = 1\n",
				replacement: "\t// [commy] The client version a REALITY server reads. Upstream says\n" +
					"\t// 1.8.1, and Xray 26.7.28 refuses anything below 26.3.27 unless its\n" +
					"\t// owner opted out. See core/cmd/overlaygen.\n" +
					"\thello.SessionId[0] = 26\n\thello.SessionId[1] = 9\n\thello.SessionId[2] = 9\n",
			},
		},
	},
	{
		module: singBox,
		path:   "transport/v2ray/transport.go",
		sha256: "3ff90cfde30a7b25db84174f61715c54b1a6f1242ac823469e877c655a971189",
		edits: []edit{
			{
				anchor: "import (\n",
				replacement: "import (\n" +
					"\t\"github.com/Makhkets/commy/core/xhttp\"\n" +
					"\txhttpconfig \"github.com/Makhkets/commy/core/xhttp/config\"\n",
			},
			{
				anchor: "\t\treturn v2rayhttpupgrade.NewServer(ctx, logger, options.HTTPUpgradeOptions, tlsConfig, handler)\n",
				replacement: "\t\treturn v2rayhttpupgrade.NewServer(ctx, logger, options.HTTPUpgradeOptions, tlsConfig, handler)\n" +
					"\tcase xhttpconfig.TransportType:\n" +
					"\t\treturn nil, E.New(\"xhttp: this build carries the client only\")\n",
			},
			{
				anchor: "\t\treturn v2rayhttpupgrade.NewClient(ctx, dialer, serverAddr, options.HTTPUpgradeOptions, tlsConfig)\n",
				replacement: "\t\treturn v2rayhttpupgrade.NewClient(ctx, dialer, serverAddr, options.HTTPUpgradeOptions, tlsConfig)\n" +
					"\tcase xhttpconfig.TransportType:\n" +
					"\t\treturn xhttp.NewClient(ctx, dialer, serverAddr, options.XHTTPOptions, tlsConfig)\n",
			},
		},
	},
	{
		module: singBox,
		path:   "protocol/group/selector.go",
		sha256: "12ba424ed8a9ee3f560f008e5f2c0c116ae6b9538ea6b688240dd8d96a0eda52",
		edits: []edit{
			{
				anchor: "\tif s.Tag() != \"\" {\n\t\tcacheFile := service.FromContext[adapter.CacheFile](s.ctx)\n" +
					"\t\tif cacheFile != nil {\n\t\t\tselected := cacheFile.LoadSelected(s.Tag())\n",
				replacement: "\t// [commy] The configuration's default is the user's choice, made in\n" +
					"\t// the app while no core ran; the cache holds the last one made inside\n" +
					"\t// a running core. See core/cmd/overlaygen.\n" +
					"\tif s.Tag() != \"\" && s.defaultTag == \"\" {\n" +
					"\t\tcacheFile := service.FromContext[adapter.CacheFile](s.ctx)\n" +
					"\t\tif cacheFile != nil {\n\t\t\tselected := cacheFile.LoadSelected(s.Tag())\n",
			},
		},
	},
	{
		module: singTun,
		path:   "stack_gvisor_filter.go",
		sha256: "9fc5164671a89a8aec5c2d9929af360e774a2a74f38364ac512d268ad23ede4b",
		edits: []edit{
			{
				anchor: "func (w *LinkEndpointFilter) Attach(dispatcher stack.NetworkDispatcher) {\n",
				replacement: "func (w *LinkEndpointFilter) Attach(dispatcher stack.NetworkDispatcher) {\n" +
					"\t// [commy] nil is how the stack detaches, and fdbased stops its\n" +
					"\t// reader only on nil. Wrapped, it stopped nothing. See\n" +
					"\t// core/cmd/overlaygen.\n" +
					"\tif dispatcher == nil {\n\t\tw.LinkEndpoint.Attach(nil)\n\t\treturn\n\t}\n",
			},
		},
	},
}

// The upstream block that strips the hybrid key share, word for word. The edit
// keeps it and puts a condition in front of it.
const realityStripBlock = "\tfor _, extension := range uConn.Extensions {\n" +
	"\t\tif ce, ok := extension.(*utls.SupportedCurvesExtension); ok {\n" +
	"\t\t\tce.Curves = common.Filter(ce.Curves, func(curveID utls.CurveID) bool {\n" +
	"\t\t\t\treturn curveID != utls.X25519MLKEM768\n" +
	"\t\t\t})\n" +
	"\t\t}\n" +
	"\t\tif ks, ok := extension.(*utls.KeyShareExtension); ok {\n" +
	"\t\t\tks.KeyShares = common.Filter(ks.KeyShares, func(share utls.KeyShare) bool {\n" +
	"\t\t\t\treturn share.Group != utls.X25519MLKEM768\n" +
	"\t\t\t})\n" +
	"\t\t}\n" +
	"\t}\n" +
	"\terr = uConn.BuildHandshakeState()\n" +
	"\tif err != nil {\n" +
	"\t\treturn nil, err\n" +
	"\t}\n"

const realityStripBlockGuarded = "\t// [commy] A hello as Chrome sends it first; the stripped one only once this\n" +
	"\t// server has refused that. See core/cmd/overlaygen.\n" +
	"\tlegacyHello := e.commyHello.legacy.Load()\n" +
	"\tif legacyHello {\n" +
	"\t\tfor _, extension := range uConn.Extensions {\n" +
	"\t\t\tif ce, ok := extension.(*utls.SupportedCurvesExtension); ok {\n" +
	"\t\t\t\tce.Curves = common.Filter(ce.Curves, func(curveID utls.CurveID) bool {\n" +
	"\t\t\t\t\treturn curveID != utls.X25519MLKEM768\n" +
	"\t\t\t\t})\n" +
	"\t\t\t}\n" +
	"\t\t\tif ks, ok := extension.(*utls.KeyShareExtension); ok {\n" +
	"\t\t\t\tks.KeyShares = common.Filter(ks.KeyShares, func(share utls.KeyShare) bool {\n" +
	"\t\t\t\t\treturn share.Group != utls.X25519MLKEM768\n" +
	"\t\t\t\t})\n" +
	"\t\t\t}\n" +
	"\t\t}\n" +
	"\t\terr = uConn.BuildHandshakeState()\n" +
	"\t\tif err != nil {\n" +
	"\t\t\treturn nil, err\n" +
	"\t\t}\n" +
	"\t}\n"

const realityHelloType = `
// commyRealityHello remembers which ClientHello the server of one outbound
// authenticates. It is shared by every clone of the outbound's configuration:
// what one connection learns, the next one uses.
//
// [commy] Not upstream code. See core/cmd/overlaygen.
type commyRealityHello struct {
	// legacy is whether to strip X25519MLKEM768, which is what upstream always
	// does. False — the hello a browser sends — until a server refuses it.
	legacy atomic.Bool
	logger logger.ContextLogger
}

// refusedWith records that the server did not authenticate a hello of the
// given kind. It stores the opposite of what THAT handshake sent, not of the
// current value: two handshakes failing at once must not cancel each other.
func (h *commyRealityHello) refusedWith(legacy bool) {
	h.legacy.Store(!legacy)
	if h.logger == nil {
		return
	}
	sent, next := "with", "without"
	if legacy {
		sent, next = "without", "with"
	}
	h.logger.Warn("reality: the server did not authenticate a ClientHello ", sent,
		" X25519MLKEM768; the next handshake goes ", next, " it. If that fails too, ",
		"the public key, the short id or the server name is wrong")
}
`

func main() {
	// The underscore matters: the copies still say `package option` and
	// `package v2ray`, and without it `go vet ./...` would find them and try
	// to build them as ours.
	out := flag.String("out", filepath.Join("build", "_overlay"), "directory to write the patched modules into")
	flag.Parse()
	modfile, err := generate(*out)
	if err != nil {
		fmt.Fprintln(os.Stderr, "overlaygen:", err)
		os.Exit(1)
	}
	// The path is the program's whole output, so a script can capture it.
	fmt.Println(modfile)
}

// generate copies every module an edit touches out of the module cache,
// applies the edits to the copies, and writes a go.mod that replaces those
// modules with them. It returns the absolute path of that go.mod.
//
// Copies, not `go build -overlay` on the cached files, which is what this used
// to write. Go 1.25 refuses an overlay that replaces anything under
// GOMODCACHE ("Files beneath GOMODCACHE must not be replaced"), so the
// overlay held the core to Go 1.24 — a release line that no longer gets
// security fixes, for the code that carries every byte of the user's traffic.
// See docs/adr/0018-core-module-copies.md.
func generate(out string) (string, error) {
	outAbs, err := filepath.Abs(out)
	if err != nil {
		return "", err
	}
	mainModfile, err := goEnv("GOMOD")
	if err != nil {
		return "", err
	}
	if mainModfile == "" || mainModfile == os.DevNull {
		return "", fmt.Errorf("not inside a module; run it from core/")
	}
	// Fresh every time: a copy left behind by another version, or carrying an
	// edit since removed, must never be what the next build compiles.
	modules := filepath.Join(outAbs, "mod")
	if err := os.RemoveAll(modules); err != nil {
		return "", err
	}
	copies := make(map[module]string)
	var order []module
	for _, t := range targets {
		copyRoot, known := copies[t.module]
		if !known {
			root, err := moduleRoot(t.module)
			if err != nil {
				return "", err
			}
			copyRoot = filepath.Join(modules, filepath.FromSlash(t.module.path)+"@"+t.module.version)
			if err := copyTree(root, copyRoot); err != nil {
				return "", fmt.Errorf("copy %s: %w", t.module.path, err)
			}
			copies[t.module] = copyRoot
			order = append(order, t.module)
		}
		// The copy is the upstream file byte for byte until this point, so the
		// hash is checked on it: the published file, as the module cache holds it.
		destination := filepath.Join(copyRoot, filepath.FromSlash(t.path))
		patched, err := patch(destination, t)
		if err != nil {
			return "", err
		}
		if err := os.WriteFile(destination, patched, 0o644); err != nil {
			return "", err
		}
	}
	return writeModfile(outAbs, mainModfile, copies, order)
}

// writeModfile writes core's go.mod with a replace for each patched module,
// and core's go.sum beside it. It returns the absolute path of the go.mod.
//
// The replacements are absolute paths: a go.mod given with -modfile resolves
// relative ones against the module root, not against its own directory, and
// gomobile copies them into a go.mod of its own in a temporary directory.
func writeModfile(outAbs, mainModfile string, copies map[module]string, order []module) (string, error) {
	content, err := os.ReadFile(mainModfile)
	if err != nil {
		return "", err
	}
	var text strings.Builder
	text.Write(content)
	text.WriteString("\n// Written by core/cmd/overlaygen: the patched copies of upstream modules.\n")
	for _, m := range order {
		fmt.Fprintf(&text, "replace %s %s => %s\n", m.path, m.version, filepath.ToSlash(copies[m]))
	}
	modfile := filepath.Join(outAbs, "go.mod")
	if err := os.WriteFile(modfile, []byte(text.String()), 0o644); err != nil {
		return "", err
	}
	sum, err := os.ReadFile(strings.TrimSuffix(mainModfile, ".mod") + ".sum")
	if err != nil {
		return "", err
	}
	if err := os.WriteFile(filepath.Join(outAbs, "go.sum"), sum, 0o644); err != nil {
		return "", err
	}
	return modfile, nil
}

// copyTree copies the module at [from] to [to]. The module cache hands out
// read-only files; the copies are writable, so the edits can land and the
// next run can remove them.
func copyTree(from, to string) error {
	return filepath.WalkDir(from, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		relative, err := filepath.Rel(from, path)
		if err != nil {
			return err
		}
		destination := filepath.Join(to, relative)
		if entry.IsDir() {
			return os.MkdirAll(destination, 0o755)
		}
		if !entry.Type().IsRegular() {
			return nil
		}
		content, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		return os.WriteFile(destination, content, 0o644)
	})
}

// goEnv asks the go command for one of its settings, with no GOFLAGS: an
// inherited one may already name a go.mod this program has not written yet.
func goEnv(name string) (string, error) {
	command := exec.Command("go", "env", name)
	command.Env = append(os.Environ(), "GOFLAGS=")
	output, err := command.Output()
	if err != nil {
		return "", fmt.Errorf("go env %s: %w", name, err)
	}
	return strings.TrimSpace(string(output)), nil
}

// patch applies the edits of [t] to the upstream file and returns the result.
func patch(upstream string, t target) ([]byte, error) {
	content, err := os.ReadFile(upstream)
	if err != nil {
		return nil, fmt.Errorf("read upstream %s: %w", t.path, err)
	}
	sum := sha256.Sum256(content)
	if got := hex.EncodeToString(sum[:]); got != t.sha256 {
		return nil, fmt.Errorf(
			"%s is not the file this overlay was written against "+
				"(sha256 %s, expected %s from %s %s).\n"+
				"sing-box was bumped or the module cache is damaged. Re-base the edits in "+
				"core/cmd/overlaygen/main.go onto the new file, check the result by hand, "+
				"and record its hash",
			t.path, got, t.sha256, t.module.path, t.module.version)
	}
	text := string(content)
	for _, e := range t.edits {
		if count := strings.Count(text, e.anchor); count != 1 {
			return nil, fmt.Errorf("%s: anchor %q occurs %d times, expected exactly one",
				t.path, firstLine(e.anchor), count)
		}
		text = strings.Replace(text, e.anchor, e.replacement, 1)
	}
	return []byte(text), nil
}

// moduleRoot asks the go command where the pinned module lives, and refuses to
// go on if the build selects another version or replaces the module.
func moduleRoot(m module) (string, error) {
	command := exec.Command("go", "list", "-m", "-json", m.path)
	// An inherited GOFLAGS may already name the go.mod this program writes —
	// which replaces the very module asked about — so the query runs with
	// none. Emptied, not set to -mod=mod: a program that only reads must not
	// be able to rewrite go.mod.
	command.Env = append(os.Environ(), "GOFLAGS=")
	output, err := command.Output()
	if err != nil {
		return "", fmt.Errorf("go list -m %s: %w (run it from core/)", m.path, err)
	}
	var listed struct {
		Version string
		Dir     string
		Replace *struct{ Path string }
	}
	if err := json.Unmarshal(output, &listed); err != nil {
		return "", err
	}
	if listed.Replace != nil {
		return "", fmt.Errorf("%s is replaced by %s: the edits are written against the published module",
			m.path, listed.Replace.Path)
	}
	if listed.Version != m.version {
		return "", fmt.Errorf("the build selects %s %s, the edits are written against %s",
			m.path, listed.Version, m.version)
	}
	if listed.Dir == "" {
		return "", fmt.Errorf("%s is not in the module cache; run `go mod download`", m.path)
	}
	return listed.Dir, nil
}

func firstLine(text string) string {
	line, _, _ := strings.Cut(strings.TrimSpace(text), "\n")
	return line
}
