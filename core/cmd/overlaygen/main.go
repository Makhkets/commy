// Command overlaygen writes the build overlay: the handful of edits Commy
// makes to the pinned sing-box, applied at build time and nowhere else.
//
//	go run ./cmd/overlaygen -out build/_overlay
//
// There are two of them, and each is here because the alternative was worse.
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
// # Why an overlay
//
// Reaching upstream code means changing upstream files, and there are three
// ways to do that:
//
//   - fork sing-box and point go.mod at the fork. Every downstream that does
//     this ends up maintaining a fork; go.mod stops saying which core we ship.
//   - vendor sing-box into the repository. A thousand files of somebody else's
//     code in every diff, for a change of a few dozen lines.
//   - leave the module exactly as published and overlay the files at build
//     time with `go build -overlay`. go.mod keeps naming the real version, and
//     the whole delta is the list of edits below.
//
// This is the third. The edits are exact-string replacements: each anchor must
// appear exactly once in a file whose SHA-256 is the one recorded here. A
// sing-box bump that touches any of these files stops the build with a message
// saying so, instead of compiling a stale copy of upstream's code into the core
// (rule R8: a bump is its own change, and re-basing this overlay — or dropping
// an edit upstream no longer needs — is part of it).
//
// One sharp edge, handled by scripts/build_core.sh: the go command reads the
// import list of a module-cache package from its module index and does not
// look at overlays when it does. An overlaid file that adds an import — ours
// do — fails to compile unless the index is off (GODEBUG=goindex=0).
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

const singBoxModule = "github.com/sagernet/sing-box"

// singBoxVersion is the release the hashes below were taken from. It is
// checked against go.mod by the module query, not assumed.
const singBoxVersion = "v1.13.16"

type edit struct {
	// anchor is upstream text that must occur exactly once.
	anchor string
	// replacement is what the anchor becomes.
	replacement string
}

type target struct {
	// path is relative to the sing-box module root.
	path   string
	sha256 string
	edits  []edit
}

var targets = []target{
	{
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
		},
	},
	{
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
	// The underscore matters when the directory is inside this module: the
	// patched files still say `package option` and `package v2ray`, and without
	// it `go vet ./...` would find them and try to build them as ours.
	out := flag.String("out", filepath.Join("build", "_overlay"), "directory to write the overlay into")
	flag.Parse()
	overlay, err := generate(*out)
	if err != nil {
		fmt.Fprintln(os.Stderr, "overlaygen:", err)
		os.Exit(1)
	}
	// The path is the program's whole output, so a script can capture it.
	fmt.Println(overlay)
}

// generate writes the patched files and overlay.json, and returns the
// absolute path of the latter.
func generate(out string) (string, error) {
	root, err := moduleRoot()
	if err != nil {
		return "", err
	}
	outAbs, err := filepath.Abs(out)
	if err != nil {
		return "", err
	}
	replace := make(map[string]string, len(targets))
	for _, t := range targets {
		upstream := filepath.Join(root, filepath.FromSlash(t.path))
		patched, err := patch(upstream, t)
		if err != nil {
			return "", err
		}
		destination := filepath.Join(outAbs, filepath.FromSlash(t.path))
		if err := os.MkdirAll(filepath.Dir(destination), 0o755); err != nil {
			return "", err
		}
		if err := os.WriteFile(destination, patched, 0o644); err != nil {
			return "", err
		}
		replace[upstream] = destination
	}
	document, err := json.MarshalIndent(map[string]any{"Replace": replace}, "", "  ")
	if err != nil {
		return "", err
	}
	overlay := filepath.Join(outAbs, "overlay.json")
	if err := os.WriteFile(overlay, append(document, '\n'), 0o644); err != nil {
		return "", err
	}
	return overlay, nil
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
				"(sha256 %s, expected %s from sing-box %s).\n"+
				"sing-box was bumped or the module cache is damaged. Re-base the edits in "+
				"core/cmd/overlaygen/main.go onto the new file, check the result by hand, "+
				"and record its hash",
			t.path, got, t.sha256, singBoxVersion)
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

// moduleRoot asks the go command where the pinned sing-box lives, and refuses
// to go on if go.mod pins something else or replaces the module.
func moduleRoot() (string, error) {
	command := exec.Command("go", "list", "-m", "-json", singBoxModule)
	// An inherited GOFLAGS may already name the overlay — a file this program
	// has not written yet — so the query runs with none. Emptied, not set to
	// -mod=mod: a program that only reads must not be able to rewrite go.mod.
	command.Env = append(os.Environ(), "GOFLAGS=")
	output, err := command.Output()
	if err != nil {
		return "", fmt.Errorf("go list -m %s: %w (run it from core/)", singBoxModule, err)
	}
	var module struct {
		Version string
		Dir     string
		Replace *struct{ Path string }
	}
	if err := json.Unmarshal(output, &module); err != nil {
		return "", err
	}
	if module.Replace != nil {
		return "", fmt.Errorf("%s is replaced by %s: the overlay is written against the published module",
			singBoxModule, module.Replace.Path)
	}
	if module.Version != singBoxVersion {
		return "", fmt.Errorf("go.mod pins %s %s, the overlay is written against %s",
			singBoxModule, module.Version, singBoxVersion)
	}
	if module.Dir == "" {
		return "", fmt.Errorf("%s is not in the module cache; run `go mod download`", singBoxModule)
	}
	return module.Dir, nil
}

func firstLine(text string) string {
	line, _, _ := strings.Cut(strings.TrimSpace(text), "\n")
	return line
}
