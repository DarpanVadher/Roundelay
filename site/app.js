// Fills the download section from the latest GitHub release. Without JavaScript, or if every source fails, the
// static "Open the latest release on GitHub" button in index.html still works.
(function () {
  "use strict";
  var REPO = "DarpanVadher/Roundelay";
  var RELEASES = "https://github.com/" + REPO + "/releases";
  var list = document.getElementById("dl-list");
  var sub = document.getElementById("dl-sub");
  var heroBtn = document.getElementById("hero-download");
  var heroNote = document.getElementById("hero-note");
  if (!list) return;

  var PLATFORMS = [
    { id: "windows", name: "Windows", note: "Windows 10 or 11, 64-bit. Unzip and run multiphone_player.exe.", test: /windows-x64\.zip$/i, exp: false },
    { id: "android", name: "Android", note: "Android 5.0 or newer. Most phones need the arm64 file.", test: /android-arm64\.apk$/i, exp: false,
      extra: [{ label: "32-bit ARM", test: /android-armv7\.apk$/i }, { label: "x86_64", test: /android-x86_64\.apk$/i }, { label: "App bundle", test: /android\.aab$/i }] },
    { id: "linux", name: "Linux", note: "64-bit. Guest only, little tested.", test: /linux-x64\.tar\.gz$/i, exp: true },
    { id: "macos", name: "macOS", note: "Apple silicon and Intel. Guest only, not notarized: right-click, then Open.", test: /macos-universal\.zip$/i, exp: true }
  ];

  function detectOS() {
    var ua = (navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || "";
    var full = navigator.userAgent || "";
    if (/android/i.test(full)) return "android";
    if (/iphone|ipad|ipod/i.test(full)) return "ios";
    if (/win/i.test(ua) || /windows/i.test(full)) return "windows";
    if (/mac/i.test(ua)) return "macos";
    if (/linux|x11/i.test(ua + full)) return "linux";
    return "";
  }

  function size(bytes) {
    return bytes >= 1048576 ? (bytes / 1048576).toFixed(1) + " MB" : Math.round(bytes / 1024) + " KB";
  }
  function fmtDate(iso) {
    try { return new Date(iso).toLocaleDateString(undefined, { year: "numeric", month: "long", day: "numeric" }); } catch (e) { return ""; }
  }
  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }
  function link(href, text, cls) {
    var a = el("a", cls, text);
    a.href = href;
    return a;
  }
  function find(assets, re) {
    for (var i = 0; i < assets.length; i++) if (re.test(assets[i].name)) return assets[i];
    return null;
  }

  function showNone() {
    list.textContent = "";
    var p = el("p", "dl-state");
    p.appendChild(el("strong", null, "The first release is on its way. "));
    p.appendChild(document.createTextNode("Until then you can build Roundelay from source, or follow the project on "));
    p.appendChild(link("https://github.com/" + REPO, "GitHub"));
    p.appendChild(document.createTextNode("."));
    list.appendChild(p);
    if (heroBtn) { heroBtn.textContent = "Get Roundelay"; heroBtn.href = "#download"; }
  }

  function render(rel) {
    var assets = rel.assets || [];
    if (!assets.length) return showNone();
    var os = detectOS();
    list.textContent = "";

    var ver = (rel.tag_name || rel.tag || "").replace(/^v/, "");
    var head = el("p", "dl-ver", "Version " + ver + (rel.published_at ? " · " + fmtDate(rel.published_at) : ""));
    list.appendChild(head);
    if (sub) sub.textContent = "The latest release, straight from GitHub.";

    var shown = 0, mine = null;
    PLATFORMS.forEach(function (p) {
      var main = find(assets, p.test);
      if (!main) return;
      shown++;
      var row = el("div", "dl-row" + (p.id === os ? " mine" : ""));
      var info = el("div");
      var name = el("div", "dl-name", p.name);
      if (p.exp) name.appendChild(el("small", null, "Experimental"));
      if (p.id === os) name.appendChild(el("small", null, "Your device"));
      info.appendChild(name);
      info.appendChild(el("div", "dl-meta", p.note + " " + size(main.size)));
      row.appendChild(info);
      var btns = el("div", "dl-btns");
      btns.appendChild(link(main.browser_download_url, p.id === "android" ? "Download APK" : "Download", "btn"));
      (p.extra || []).forEach(function (x) {
        var a = find(assets, x.test);
        if (a) btns.appendChild(link(a.browser_download_url, x.label, "btn alt"));
      });
      row.appendChild(btns);
      list.appendChild(row);
      if (p.id === os) mine = { p: p, a: main };
    });

    var sums = find(assets, /^SHA256SUMS\.txt$/i);
    var more = el("p", "fine");
    if (sums) { more.appendChild(link(sums.browser_download_url, "SHA256SUMS.txt")); more.appendChild(document.createTextNode(" lists the checksum of every file. ")); }
    more.appendChild(link(rel.html_url || RELEASES, "Release notes and all files"));
    more.appendChild(document.createTextNode("."));
    list.appendChild(more);

    if (!shown) return showNone();
    if (heroBtn) {
      if (mine) {
        heroBtn.textContent = "Download for " + mine.p.name;
        heroBtn.href = mine.a.browser_download_url;
        if (heroNote) heroNote.textContent = "Version " + ver + ". Free and open source. No account, no cloud.";
      } else {
        heroBtn.textContent = "Download Roundelay";
        heroBtn.href = "#download";
        if (heroNote) heroNote.textContent = "Version " + ver + ". Free and open source. No account, no cloud.";
      }
    }
  }

  // release.json is written by the Pages workflow (same origin, no rate limit); the API is the fallback.
  function get(url) { return fetch(url, { headers: { Accept: "application/json" } }).then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); }); }

  get("release.json")
    .catch(function () { return get("https://api.github.com/repos/" + REPO + "/releases/latest"); })
    .then(render)
    .catch(showNone);
})();
