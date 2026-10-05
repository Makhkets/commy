// The white-label subscription page. The subscription address arrives in
// the URL fragment (#https://…), which browsers never send to a server:
// it is read here, turned into each client's import link, and goes nowhere.
(function () {
  var root = document.getElementById("sub");
  var accent = root.dataset.accent;
  if (/^#[0-9a-fA-F]{6}$/.test(accent || "")) {
    document.documentElement.style.setProperty("--page-accent", accent);
  }
  var ru = root.dataset.lang === "ru";
  var raw = decodeURIComponent(location.hash.slice(1) || "");
  var sub = /^https?:\/\/[^\s]+$/i.test(raw) ? raw : "";
  if (!sub) return;
  document.getElementById("sub-missing").classList.add("hidden");

  var enc = encodeURIComponent(sub);
  var b64 = btoa(unescape(encodeURIComponent(sub)));
  // The same forms Commy's ForeignImportLink reads, from Remnawave's stock
  // subscription page and the clients' own documentation.
  var apps = {
    commy: ["Commy", "commy://import/" + sub, ru ? "открытый код, без телеметрии" : "open source, no telemetry"],
    happ: ["Happ", "happ://add/" + sub],
    incy: ["INCY", "incy://import/" + sub],
    v2raytun: ["v2RayTun", "v2raytun://import/" + sub],
    hiddify: ["Hiddify", "hiddify://import/" + sub],
    streisand: ["Streisand", "streisand://import/" + sub],
    shadowrocket: ["Shadowrocket", "sub://" + b64],
    v2rayng: ["v2rayNG", "v2rayng://install-config?url=" + enc],
    clashmeta: ["Clash Meta", "clashmeta://install-config?url=" + enc],
    singbox: ["sing-box", "sing-box://import-remote-profile?url=" + enc]
  };
  var list = (root.dataset.apps || "").split(",").filter(function (id) { return apps[id]; });
  var box = document.getElementById("apps");
  list.forEach(function (id, index) {
    var app = apps[id];
    var a = document.createElement("a");
    a.className = "app" + (index === 0 ? " primary" : "");
    a.href = app[1];
    var name = document.createElement("strong");
    name.textContent = (ru ? "Добавить в " : "Add to ") + app[0];
    var note = document.createElement("span");
    note.textContent = app[2] || "";
    a.appendChild(name);
    a.appendChild(note);
    box.appendChild(a);
  });

  if (typeof qrcode === "function") {
    qrcode.stringToBytes = qrcode.stringToBytesFuncs["UTF-8"];
    var qr = qrcode(0, "M");
    qr.addData(sub, "Byte");
    qr.make();
    var img = document.createElement("img");
    img.alt = ru ? "QR-код подписки" : "Subscription QR code";
    img.src = qr.createDataURL(6, 2);
    var holder = document.getElementById("qr");
    holder.appendChild(img);
    holder.classList.remove("hidden");
  }
  var row = document.getElementById("copy-row");
  row.classList.remove("hidden");
  document.getElementById("copy-sub").addEventListener("click", function (e) {
    navigator.clipboard.writeText(sub).then(function () { e.target.textContent = "✓"; });
  });
})();
