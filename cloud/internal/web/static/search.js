// Search over the documentation, in the browser: the index is one JSON
// file from this site, and what you type goes nowhere.
(function () {
  var input = document.getElementById("doc-search");
  if (!input) return;
  var box = document.getElementById("doc-results");
  var index = null;
  function load() {
    if (index) return Promise.resolve(index);
    return fetch(input.dataset.index).then(function (r) { return r.json(); }).then(function (d) { index = d; return d; });
  }
  function esc(s) { var d = document.createElement("div"); d.textContent = s; return d.innerHTML; }
  input.addEventListener("input", function () {
    var q = input.value.trim().toLowerCase();
    if (q.length < 2) { box.classList.add("hidden"); return; }
    load().then(function (pages) {
      var words = q.split(/\s+/);
      var hits = pages.map(function (p) {
        var t = p.Title.toLowerCase(), x = p.Text.toLowerCase(), score = 0;
        for (var i = 0; i < words.length; i++) {
          if (t.indexOf(words[i]) >= 0) score += 5;
          else if (x.indexOf(words[i]) >= 0) score += 1;
          else return null;
        }
        var at = x.indexOf(words[0]);
        return { p: p, score: score, snippet: p.Text.substr(Math.max(0, at - 40), 120) };
      }).filter(Boolean).sort(function (a, b) { return b.score - a.score; }).slice(0, 8);
      box.innerHTML = hits.map(function (h) {
        return '<a href="' + h.p.URL + '">' + esc(h.p.Title) + '<small>…' + esc(h.snippet) + '…</small></a>';
      }).join("") || '<a>—</a>';
      box.classList.remove("hidden");
    });
  });
  document.addEventListener("click", function (e) { if (!box.contains(e.target) && e.target !== input) box.classList.add("hidden"); });
})();
