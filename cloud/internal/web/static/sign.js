// Commy Cloud — the operator's key never leaves this browser.
//
// A project's key is made here with WebCrypto Ed25519 and saved as a file;
// the server receives only the public half. A manifest is signed here with
// that file and only the signed string is posted. Format and rules:
// docs/adr/0019-subscription-domain-recovery.md. The same key file works
// with `commy-cloud sign` (PKCS#8, base64url).

const b64url = (bytes) =>
  btoa(String.fromCharCode(...new Uint8Array(bytes)))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const fromB64url = (text) => {
  const s = text.replace(/-/g, "+").replace(/_/g, "/");
  const bin = atob(s + "===".slice((s.length + 3) % 4));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
};

async function ed25519Supported() {
  try {
    await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
    return true;
  } catch {
    return false;
  }
}

function download(name, text) {
  const blob = new Blob([text], { type: "application/json" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = name;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 5000);
}

// ---- a new project: make the key, keep the private half on disk ----
const newProject = document.getElementById("new-project");
if (newProject) {
  const keyField = document.getElementById("pkey");
  const manual = document.getElementById("manual-key");
  const manualInput = document.getElementById("pkey-manual");
  ed25519Supported().then((ok) => {
    if (!ok) manual.classList.remove("hidden");
  });
  newProject.addEventListener("submit", async (event) => {
    if (keyField.value) return;
    event.preventDefault();
    if (!manual.classList.contains("hidden")) {
      keyField.value = manualInput.value.trim();
      newProject.submit();
      return;
    }
    const id = document.getElementById("pid").value.trim();
    const pair = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
    const pub = b64url(await crypto.subtle.exportKey("raw", pair.publicKey));
    const priv = b64url(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
    download(`commy-${id}-recovery-key.json`, JSON.stringify({
      v: 1, type: "commy-recovery-key", project: id,
      public_key: pub, private_key: priv,
      created: new Date().toISOString(),
      note: "Keep this file safe and offline. Without it you cannot move your clients to a new address.",
    }, null, 2));
    keyField.value = pub;
    newProject.submit();
  });
}

// ---- a new release: sign it with the key file ----
const signForm = document.getElementById("sign-form");
if (signForm) {
  const error = document.getElementById("sign-error");
  const fail = (text) => { error.textContent = text; error.classList.remove("hidden"); };
  const lines = (id) => document.getElementById(id).value
    .split(/\s+/).map((s) => s.trim()).filter(Boolean);
  signForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    error.classList.add("hidden");
    const file = document.getElementById("keyfile").files[0];
    if (!file) return fail("Key file? / Файл ключа?");
    let key;
    try {
      key = JSON.parse(await file.text());
    } catch {
      return fail("Not a key file / Это не файл ключа");
    }
    if (key.type !== "commy-recovery-key" || !key.private_key) {
      return fail("Not a key file / Это не файл ключа");
    }
    let privateKey;
    try {
      privateKey = await crypto.subtle.importKey("pkcs8", fromB64url(key.private_key), { name: "Ed25519" }, false, ["sign"]);
    } catch {
      return fail("This browser cannot sign Ed25519 — use `commy-cloud sign` / Браузер не умеет Ed25519 — используйте `commy-cloud sign`");
    }
    const payload = {
      v: 1,
      id: signForm.dataset.id,
      seq: Number(signForm.dataset.seq),
      iat: Math.floor(Date.now() / 1000),
      origin: document.getElementById("origin").value.trim().replace(/\/+$/, ""),
      mirrors: lines("mirrors").map((m) => m.replace(/\/+$/, "")),
      rendezvous: lines("points"),
      key: key.public_key,
    };
    const next = document.getElementById("nextkey").value.trim();
    if (next) payload.next_key = next;
    const name = document.getElementById("mname").value.trim();
    if (name) payload.name = name;
    if (key.public_key !== signForm.dataset.key) {
      // Allowed only along an announced rotation, which the server checks.
      if (!confirm("This key is not the project's current one. Sign anyway? / Ключ не текущий для проекта. Всё равно подписать?")) return;
    }
    const signed = "v1." + b64url(new TextEncoder().encode(JSON.stringify(payload)));
    const signature = await crypto.subtle.sign({ name: "Ed25519" }, privateKey, new TextEncoder().encode(signed));
    document.getElementById("manifest").value = signed + "." + b64url(signature);
    document.getElementById("publish-form").submit();
  });
}

// ---- copy buttons ----
for (const button of document.querySelectorAll("[data-copy]")) {
  button.addEventListener("click", async () => {
    const source = document.getElementById(button.dataset.copy);
    await navigator.clipboard.writeText(source.value ?? source.textContent);
    const label = button.textContent;
    button.textContent = "✓";
    setTimeout(() => { button.textContent = label; }, 1500);
  });
}
