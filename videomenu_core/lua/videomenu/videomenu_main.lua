-- ============================================================
--  Video Main Menu Background  -  CORE  (addon 1)
--  Loaded in the menu state by lua/includes/videomenu_loader.lua
--
--  Videos live in a pack addon. Any addon that has the same folder name is merged into the list:
--      data_static/<PackFolder>/<file>.txt      (use .webm when testing locally)
--  The name shown in the list is the file name (without the extension).
--
--  NOTE: the game cannot read file names with non-ASCII characters (Japanese, Thai, ...).
--  Use ASCII file names. To show another name in the list, put it in a small text file next to the video:
--      <video name>.title.txt     (first line = the name to show, UTF-8)
--  Every video has its own title file, so several pack addons never clash (when two addons contain a
--  file with the same name the game can only read one of them). A shared titles*.txt
--  (one line per video:  file name | display name) is still read as a fallback.
--  make_pack.bat creates everything automatically.
--
--  Console commands:  videomenu_list   videomenu_play <number or name>   videomenu_reload
-- ============================================================
if not MENU_DLL then return end
if not VideoMenuLoader then return end

VideoMenu = VideoMenu or {}
local Loader = VideoMenuLoader

-- ---------------- settings ----------------
local C = {
	PackFolder = "videomenu_pack", -- folder data_static/<name>/ that holds the videos
	Volume     = 0.5,              -- initial volume 0-1 (afterwards the last value you set is remembered)
	Fit        = "cover",          -- initial video size: "cover" (fill, crop edges) | "contain" (fit, show all) | "fill" (stretch)
	MinSizeKB  = 200,              -- smaller files are not treated as videos (README.txt etc.)
	Debug      = false,            -- initial state of the debug box (can be toggled in the SETTINGS panel)
}
VideoMenu.Config = C

-- ---------------- JavaScript injected into the menu page ----------------
local JS_TEMPLATE = [==[
(function () {
  var LIST = __LIST__, SEL = __SEL__, VER = __VER__, VOL = __VOL__, MUTED = __MUTED__,
      DEBUG = __DEBUG__, FIT = __FIT__, INGAME = __INGAME__;
  var doc = document;
  if (!doc.body) return;

  // Already created: just feed it the latest data from Lua
  var old = window.__vm;
  if (old && old.ver2 && doc.getElementById('vm_video')) {
    old.update(LIST, SEL, VER, INGAME);
    return;
  }
  if (old && old.remove) old.remove();

  var W = { ver2: true, list: [], sig: '', ver: undefined, cur: -1, curUrl: null, ig: null,
            open: false, sOpen: false, shown: false, userMuted: !!MUTED, timer: null, objUrl: null,
            tok: 0, xhr: null, stripH: 50, debug: !!DEBUG,
            fit: (FIT === 'contain' || FIT === 'fill') ? FIT : 'cover' };
  var lastEvent = 'start', loadInfo = '-', fmt = '?', clickArmed = false, retries = 0, volTimer = null;
  var dbgEl = null;

  function el(tag, css) { var e = doc.createElement(tag); if (css) e.style.cssText = css; return e; }
  // Send a message to Lua: Lua intercepts the menu's console messages and only accepts the
  // ones that start with VIDEOMENU:
  function toLua(msg) { try { console.log('VIDEOMENU:' + msg); } catch (e) {} }

  // ---------- video (sits behind the menu UI; hidden until it is really playing) ----------
  var v = el('video', 'position:fixed;left:0;top:0;width:100vw;height:100vh;object-fit:cover;' +
    'z-index:-1;pointer-events:none;background:#000;display:none;');
  v.id = 'vm_video';
  v.preload = 'auto';
  v.setAttribute('playsinline', '');
  doc.body.insertBefore(v, doc.body.firstChild);
  doc.documentElement.style.background = 'transparent';
  doc.body.style.background = 'transparent';
  v.volume = Math.min(1, Math.max(0, VOL));
  v.muted = W.userMuted;

  function cp(t) { try { return v.canPlayType(t) || 'no'; } catch (e) { return 'err'; } }
  var canPlay = 'canPlay webm vp8=' + cp('video/webm; codecs="vp8, vorbis"') +
    ' vp9=' + cp('video/webm; codecs="vp9, opus"') +
    ' | mp4 h264=' + cp('video/mp4; codecs="avc1.42E01E, mp4a.40.2"');

  // ---------- control bar (inside the dark strip at the bottom of the menu) ----------
  // [VIDEOS] [SOUND] [volume slider] [SETTINGS] [status]
  var ctl = el('div', 'position:fixed;left:0;bottom:0;height:50px;z-index:2147483000;display:none;' +
    'align-items:center;gap:6px;padding:0 14px;box-sizing:border-box;color:#fff;font:13px sans-serif;');
  ctl.id = 'vm_ctl';
  var BTN = 'cursor:pointer;user-select:none;padding:5px 10px;border-radius:8px;';
  var listBtn = el('span', BTN);
  var sndBtn = el('span', BTN + 'min-width:52px;text-align:center;');
  var rng = el('input', 'width:90px;margin:0 6px;');
  rng.type = 'range'; rng.min = 0; rng.max = 100;
  var setBtn = el('span', BTN);
  setBtn.textContent = 'SETTINGS';
  var status = el('span', 'font-size:11px;opacity:.85;max-width:160px;overflow:hidden;' +
    'text-overflow:ellipsis;white-space:nowrap;');
  ctl.appendChild(listBtn);
  ctl.appendChild(sndBtn);
  ctl.appendChild(rng);
  ctl.appendChild(setBtn);
  ctl.appendChild(status);
  doc.body.appendChild(ctl);

  function paintBtns() {
    listBtn.style.background = W.open ? 'rgba(255,255,255,.28)' : 'transparent';
    setBtn.style.background = W.sOpen ? 'rgba(255,255,255,.28)' : 'transparent';
    sndBtn.style.background = 'transparent';
  }
  [listBtn, sndBtn, setBtn].forEach(function (b) {
    b.onmouseenter = function () { b.style.background = 'rgba(255,255,255,.18)'; };
    b.onmouseleave = paintBtns;
  });

  // ---------- video list (opens above the control bar) ----------
  var PANEL = 'position:fixed;left:14px;bottom:58px;z-index:2147483000;display:none;box-sizing:border-box;' +
    'background:rgba(0,0,0,.78);color:#fff;border-radius:12px;';
  var panel = el('div', PANEL + 'width:460px;max-width:70vw;max-height:50vh;overflow-y:auto;padding:6px;font:14px sans-serif;');
  panel.id = 'vm_list';
  doc.body.appendChild(panel);

  // ---------- settings panel ----------
  var sPanel = el('div', PANEL + 'width:320px;max-width:80vw;padding:6px 14px 12px;font:13px sans-serif;');
  sPanel.id = 'vm_settings';
  doc.body.appendChild(sPanel);

  var CHIP = 'display:inline-block;margin:6px 6px 0 0;padding:5px 10px;border-radius:8px;cursor:pointer;user-select:none;';
  function heading(text) {
    var d = el('div', 'margin-top:10px;opacity:.7;font-size:11px;letter-spacing:.5px;text-transform:uppercase;');
    d.textContent = text;
    return d;
  }
  function chip(text, fn) {
    var c = el('span', CHIP);
    c.textContent = text;
    c.onclick = function (e) { if (e && e.stopPropagation) e.stopPropagation(); fn(); };
    return c;
  }

  // object-fit values: cover = fill the screen and crop the edges, contain = show the whole video, fill = stretch
  var FITS = [['cover', 'Fill (crop edges)'], ['contain', 'Fit (show all)'], ['fill', 'Stretch']];
  var fitChips = {};
  sPanel.appendChild(heading('Video size'));
  FITS.forEach(function (f) {
    var c = chip(f[1], function () { setFit(f[0], true); });
    fitChips[f[0]] = c;
    sPanel.appendChild(c);
  });
  sPanel.appendChild(heading('Debug'));
  var dbgChip = chip('', function () { setDebug(!W.debug, true); });
  sPanel.appendChild(dbgChip);

  function paintSettings() {
    FITS.forEach(function (f) {
      var on = (W.fit === f[0]);
      fitChips[f[0]].style.background = on ? 'rgba(255,255,255,.35)' : 'rgba(255,255,255,.12)';
      fitChips[f[0]].style.fontWeight = on ? 'bold' : 'normal';
    });
    dbgChip.textContent = W.debug ? 'Debug box: ON' : 'Debug box: OFF';
    dbgChip.style.background = W.debug ? 'rgba(255,255,255,.35)' : 'rgba(255,255,255,.12)';
    dbgChip.style.fontWeight = W.debug ? 'bold' : 'normal';
  }

  function setFit(mode, notify) {
    W.fit = mode;
    v.style.objectFit = mode;
    paintSettings();
    if (notify) toLua('fit:' + mode);
  }

  // ---------- debug box ----------
  function dbg(msg) {
    if (!dbgEl) {
      dbgEl = el('div', 'position:fixed;left:8px;top:8px;z-index:2147483000;' +
        'background:rgba(0,0,0,.65);color:#9f9;font:11px monospace;padding:4px 8px;' +
        'white-space:pre;pointer-events:none;');
      dbgEl.id = 'vm_dbg';
      doc.body.appendChild(dbgEl);
    }
    dbgEl.textContent = msg;
  }

  function updateDebug() {
    var er = v.error ? ('code=' + v.error.code + ' ' + (v.error.message || '')) : 'none';
    var now = W.list[W.cur] ? W.list[W.cur][0] : '-';
    dbg('[VideoMenu] ' + lastEvent + '\n' +
      'now: ' + now + '  (' + (W.cur + 1) + '/' + W.list.length + ')  route=' + (window.location.hash || '(none)') +
      '  strip=' + W.stripH + 'px  fit=' + W.fit + '\n' +
      'load: ' + loadInfo + '\n' +
      'fmt:  ' + fmt + '\n' +
      canPlay + '\n' +
      'rs=' + v.readyState + ' ns=' + v.networkState + ' paused=' + v.paused +
      ' t=' + (v.currentTime || 0).toFixed(1) + '/' + (isFinite(v.duration) ? v.duration.toFixed(1) : '?') +
      ' ' + v.videoWidth + 'x' + v.videoHeight + ' muted=' + v.muted + '\n' +
      'error: ' + er);
  }

  function setDebug(on, notify) {
    W.debug = !!on;
    if (W.debug) {
      if (!W.timer) W.timer = setInterval(updateDebug, 1000);
      updateDebug();
    } else if (W.timer) {
      clearInterval(W.timer);
      W.timer = null;
    }
    if (dbgEl) dbgEl.style.display = (W.debug && !W.ig) ? 'block' : 'none';
    paintSettings();
    if (notify) toLua('dbg:' + (W.debug ? '1' : '0'));
  }

  // ---------- open / close panels ----------
  function setOpen(b) {
    W.open = b;
    panel.style.display = b ? 'block' : 'none';
    if (b && W.sOpen) setSOpen(false);
    paintBtns();
  }

  function setSOpen(b) {
    W.sOpen = b;
    sPanel.style.display = b ? 'block' : 'none';
    if (b && W.open) setOpen(false);
    if (b) layoutBar();
    paintBtns();
  }

  function setStatus(t) { status.textContent = t || ''; }

  function sync() {
    sndBtn.textContent = (v.muted || v.volume === 0) ? 'MUTED' : 'SOUND';
    rng.value = Math.round(v.volume * 100);
  }

  // The bar is only shown on the main menu page ('#/' or no hash), not on other pages
  // such as Addons, which have their own "Back to Main Menu" button
  function isMainRoute() { return /^(#!?\/?)?$/.test(window.location.hash || ''); }

  // Make the bar as tall as the dark strip at the bottom of the menu: find a full-width element touching
  // the bottom edge of the screen (24px up to 20% of the screen height). Falls back to 50px.
  function layoutBar() {
    var h = 50;
    try {
      var W_ = window.innerWidth, H_ = window.innerHeight;
      var els = doc.elementsFromPoint ? doc.elementsFromPoint(Math.round(W_ / 2), H_ - 3) : [];
      var best = null;
      for (var i = 0; i < els.length; i++) {
        var e = els[i];
        if (e === ctl || e === panel || e === sPanel || e === v || e === dbgEl) continue;
        var r = e.getBoundingClientRect();
        if (r.width >= W_ * 0.95 && r.bottom >= H_ - 2 && r.height >= 24 && r.height <= H_ * 0.2) {
          if (!best || r.height < best) best = r.height;
        }
      }
      if (best) h = Math.round(best);
    } catch (e) {}
    W.stripH = h;
    ctl.style.height = h + 'px';
    panel.style.bottom = (h + 8) + 'px';
    sPanel.style.bottom = (h + 8) + 'px';
    try {
      // line the settings panel up with its button
      if (W.sOpen) sPanel.style.left = Math.max(8, Math.round(setBtn.getBoundingClientRect().left)) + 'px';
    } catch (e) {}
  }

  function applyDisplay() {
    var hide = !!W.ig;
    var showBar = !hide && W.list.length > 0 && isMainRoute();
    v.style.display = (!hide && W.shown) ? 'block' : 'none';
    ctl.style.display = showBar ? 'flex' : 'none';
    if (!showBar) { setOpen(false); setSOpen(false); }
    if (dbgEl) dbgEl.style.display = (!hide && W.debug) ? 'block' : 'none';
    layoutBar();
  }

  function markActive() {
    var rows = panel.children;
    for (var i = 0; i < rows.length; i++) {
      var on = (i === W.cur);
      rows[i].style.background = on ? 'rgba(255,255,255,.28)' : 'transparent';
      rows[i].style.fontWeight = on ? 'bold' : 'normal';
    }
  }

  function renderList() {
    while (panel.firstChild) panel.removeChild(panel.firstChild);
    var L = W.list;
    listBtn.textContent = 'VIDEOS (' + L.length + ')';
    if (!L.length) {
      var none = el('div', 'padding:8px 10px;opacity:.8;');
      none.textContent = 'No videos found';
      panel.appendChild(none);
      return;
    }
    L.forEach(function (it, i) {
      var row = el('div', 'padding:7px 10px;border-radius:8px;cursor:pointer;white-space:nowrap;' +
        'overflow:hidden;text-overflow:ellipsis;');
      row.textContent = it[0];
      row.title = it[0];
      row.onmouseenter = function () { row.style.background = 'rgba(255,255,255,.18)'; };
      row.onmouseleave = function () { markActive(); };
      row.onclick = function (e) { if (e && e.stopPropagation) e.stopPropagation(); pick(i); };
      panel.appendChild(row);
    });
    markActive();
  }

  listBtn.onclick = function (e) { if (e && e.stopPropagation) e.stopPropagation(); setOpen(!W.open); };
  setBtn.onclick = function (e) { if (e && e.stopPropagation) e.stopPropagation(); setSOpen(!W.sOpen); };
  var onDocClick = function (e) {
    if (!e || e.target === listBtn || e.target === setBtn) return;
    if (W.open && !panel.contains(e.target)) setOpen(false);
    if (W.sOpen && !sPanel.contains(e.target)) setSOpen(false);
  };
  doc.addEventListener('click', onDocClick, true);
  var onRoute = function () { applyDisplay(); };
  window.addEventListener('hashchange', onRoute, false);
  window.addEventListener('resize', onRoute, false);

  // ---------- playback ----------
  function rawPlay() {
    try { var p = v.play(); if (p && p.catch) p.catch(function () {}); } catch (e) {}
  }

  function armClick() {
    if (clickArmed) return;
    clickArmed = true;
    var f = function () {
      doc.removeEventListener('click', f, true);
      clickArmed = false;
      v.muted = W.userMuted;
      play();
      sync();
    };
    doc.addEventListener('click', f, true);
  }

  function play() {
    if (W.ig || !v.src) return;
    var p;
    try { p = v.play(); } catch (e) { lastEvent = 'play() threw'; return; }
    if (p && p.catch) {
      p.catch(function (e) {
        if (e && e.name === 'AbortError') return;
        lastEvent = 'play rejected: ' + (e && e.name);
        // Autoplay with sound was blocked: play muted, then restore the user's setting on the next click
        if (e && e.name === 'NotAllowedError') {
          if (!v.muted) { v.muted = true; rawPlay(); }
          armClick();
          sync();
        }
      });
    }
  }

  function saveVol() {
    if (volTimer) clearTimeout(volTimer);
    volTimer = setTimeout(function () {
      toLua('vol:' + v.volume.toFixed(2) + ',' + (W.userMuted ? '1' : '0'));
    }, 400);
  }

  sndBtn.onclick = function () {
    W.userMuted = !W.userMuted;
    v.muted = W.userMuted;
    if (!W.userMuted) play();
    sync();
    saveVol();
  };
  rng.oninput = function () {
    v.volume = rng.value / 100;
    if (W.userMuted && v.volume > 0) { W.userMuted = false; v.muted = false; }
    sync();
    saveVol();
  };

  v.addEventListener('playing', function () {
    lastEvent = 'playing'; retries = 0; W.shown = true; setStatus(''); applyDisplay();
  });
  v.addEventListener('ended', function () {
    lastEvent = 'ended -> restart';
    try { v.currentTime = 0; } catch (e) {}
    play();
  });
  v.addEventListener('error', function () {
    lastEvent = 'error event';
    setStatus('load failed');
    if (retries++ < 10) {
      setTimeout(function () {
        if (window.__vm === W && !W.ig) { v.src = W.objUrl || W.curUrl; play(); }
      }, 2000);
    }
  });

  // ---------- loading ----------
  // Download the whole file from asset:// into a Blob and play it through a blob: URL
  // (avoids problems with the .txt extension, MIME type and seeking) and detect the real
  // file type from its first bytes.
  function sniff(b) {
    if (b[0] === 0x1A && b[1] === 0x45 && b[2] === 0xDF && b[3] === 0xA3) return 'video/webm';
    if (b[4] === 0x66 && b[5] === 0x74 && b[6] === 0x79 && b[7] === 0x70) return 'video/mp4';
    if (b[0] === 0x4F && b[1] === 0x67 && b[2] === 0x67 && b[3] === 0x53) return 'video/ogg';
    return '';
  }

  function useSource(url, tok, isBlob) {
    if (tok !== W.tok) {
      if (isBlob) { try { URL.revokeObjectURL(url); } catch (e) {} }
      return;
    }
    var prev = W.objUrl;
    W.objUrl = isBlob ? url : null;
    v.src = url;
    if (prev && prev !== url) { try { URL.revokeObjectURL(prev); } catch (e) {} }
    if (!W.ig) play();
  }

  function loadVideo(url, size) {
    var tok = ++W.tok;
    if (W.xhr) { try { W.xhr.abort(); } catch (e) {} W.xhr = null; }
    setStatus('loading...');
    loadInfo = 'downloading...';
    fmt = '?';
    retries = 0;
    if (size > 314572800) {
      loadInfo = 'file > 300MB -> direct src';
      useSource(url, tok, false);
      return;
    }
    var x = new XMLHttpRequest();
    W.xhr = x;
    x.open('GET', url, true);
    x.responseType = 'blob';
    x.onprogress = function (e) {
      if (tok !== W.tok) return;
      loadInfo = e.lengthComputable ? ('downloading ' + Math.round(e.loaded * 100 / e.total) + '%')
                                    : ('downloading ' + Math.round(e.loaded / 1048576) + 'MB');
    };
    x.onerror = function () {
      if (tok !== W.tok) return;
      loadInfo = 'xhr failed (status ' + x.status + ') -> direct src';
      useSource(url, tok, false);
    };
    x.onload = function () {
      if (tok !== W.tok) return;
      var blob = x.response;
      if (!blob || !blob.size) {
        loadInfo = 'xhr empty (status ' + x.status + ') -> direct src';
        useSource(url, tok, false);
        return;
      }
      var fr = new FileReader();
      fr.onload = function () {
        if (tok !== W.tok) return;
        var b = new Uint8Array(fr.result), hex = [], i;
        for (i = 0; i < 12 && i < b.length; i++) hex.push(('0' + b[i].toString(16)).slice(-2));
        var mime = sniff(b);
        fmt = (mime || 'unknown') + '  [' + hex.join(' ') + ']';
        loadInfo = 'xhr ok ' + blob.size + ' bytes (status ' + x.status + ')';
        useSource(URL.createObjectURL(mime ? blob.slice(0, blob.size, mime) : blob), tok, true);
      };
      fr.readAsArrayBuffer(blob.slice(0, 16));
    };
    try { x.send(); } catch (e) { loadInfo = 'xhr threw: ' + e; useSource(url, tok, false); }
  }

  function switchTo(i) {
    var it = W.list[i];
    if (!it) return;
    W.cur = i;
    W.curUrl = it[1];
    markActive();
    loadVideo(it[1], it[2]);
  }

  // The user picked a video from the list: switch right away, then tell Lua so it is remembered
  function pick(i) {
    switchTo(i);
    toLua('sel:' + (i + 1));
    setOpen(false);
  }

  // ---------- data from Lua (sent every second) ----------
  W.setInGame = function (b) {
    if (W.ig === b) return;
    W.ig = b;
    applyDisplay();
    if (b) { v.pause(); } else { play(); }
  };

  W.update = function (list, sel, ver, ig) {
    W.setInGame(ig);

    var sig = JSON.stringify(list);
    if (sig !== W.sig) {
      W.sig = sig;
      W.list = list;
      var idx = -1;
      for (var i = 0; i < list.length; i++) { if (list[i][1] === W.curUrl) { idx = i; break; } }
      W.cur = idx;
      renderList();
    }

    // Switch video when Lua asks for it (ver changed) or when nothing has been loaded yet
    var need = false;
    if (ver !== W.ver) { W.ver = ver; need = true; }
    if (W.cur === -1 && list.length) need = true;
    if (need && list.length) {
      var s = Math.min(Math.max(sel, 0), list.length - 1);
      if (W.cur === -1 || list[s][1] !== W.curUrl) switchTo(s);
    }

    applyDisplay();
  };

  W.remove = function () {
    if (W.timer) clearInterval(W.timer);
    if (volTimer) clearTimeout(volTimer);
    if (W.xhr) { try { W.xhr.abort(); } catch (e) {} }
    doc.removeEventListener('click', onDocClick, true);
    window.removeEventListener('hashchange', onRoute, false);
    window.removeEventListener('resize', onRoute, false);
    [v, ctl, panel, sPanel, dbgEl].forEach(function (e) { if (e && e.parentNode) e.parentNode.removeChild(e); });
    try { v.pause(); v.removeAttribute('src'); v.load(); } catch (e) {}
    if (W.objUrl) { try { URL.revokeObjectURL(W.objUrl); } catch (e) {} W.objUrl = null; }
    if (window.__vm === W) window.__vm = null;
  };

  window.__vm = W;
  sync();
  renderList();
  setFit(W.fit, false);
  setDebug(W.debug, false);
  W.update(LIST, SEL, VER, INGAME);
})();
]==]

local EXTS = { txt = true, webm = true }
local SKIP = { ["readme.txt"] = true }

local state = {
	list = {}, sig = "",
	sel = 0, selPath = nil, pick = nil, wantPath = nil, ver = 1,
	vol = C.Volume, muted = false, fit = "cover", debug = false,
	tick = 0, lastMsg = nil, injected = false, fail = 0,
	diag = {}, diagSig = nil,
}

local function Log(...)
	local t = {}
	for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
	print("[VideoMenu] " .. table.concat(t, " "))
end

-- Print a message only when it changes (avoids flooding the console)
local function Say(msg)
	if state.lastMsg ~= msg then
		state.lastMsg = msg
		Log(msg)
	end
end

local function Trim(s)
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

-- ---------------- remembered settings (menu-state cookies, stored in mn.db) ----------------
local function CookieGet(key, default)
	if cookie and cookie.GetString then
		local ok, v = pcall(cookie.GetString, key, default)
		if ok and v ~= nil then return v end
	end
	return default
end

local function CookieSet(key, value)
	if cookie and cookie.Set then pcall(cookie.Set, key, tostring(value)) end
end

local function ValidFit(f)
	return f == "cover" or f == "contain" or f == "fill"
end

state.wantPath = CookieGet("videomenu_selected", nil)
state.vol = math.min(1, math.max(0, tonumber(CookieGet("videomenu_volume", nil)) or C.Volume))
state.muted = CookieGet("videomenu_muted", "0") == "1"

state.fit = CookieGet("videomenu_fit", nil)
if not ValidFit(state.fit) then state.fit = ValidFit(C.Fit) and C.Fit or "cover" end

local dbgCookie = CookieGet("videomenu_debug", nil)
if dbgCookie ~= nil then
	state.debug = (dbgCookie == "1")
else
	state.debug = C.Debug and true or false
end

-- ---------------- video list: every file in data_static/<PackFolder>/ ----------------
-- titles*.txt (optional):  file name | display name   (extension optional, # = comment)
-- Every file whose name starts with "titles" is merged. With several pack addons each one should
-- use its own titles_<packname>.txt, because when two addons contain a file with the same name
-- the game can only read one of them.
local function ReadTitles()
	local map = {}
	local dir = "data_static/" .. C.PackFolder .. "/"

	for _, fname in ipairs(file.Find(dir .. "titles*.txt", "GAME") or {}) do
		local text = file.Read(dir .. fname, "GAME")
		if text and text ~= "" then
			if string.sub(text, 1, 3) == "\239\187\191" then text = string.sub(text, 4) end -- UTF-8 BOM

			for line in string.gmatch(text, "[^\r\n]+") do
				line = Trim(line)
				if line ~= "" and string.sub(line, 1, 1) ~= "#" then
					local k, t = string.match(line, "^([^|\t]+)[|\t](.*)$")
					if k then
						k = string.lower(Trim(k))
						t = Trim(t)
						if t ~= "" then
							if map[k] == nil then map[k] = t end
							local bare = string.gsub(k, "%.[^.]+$", "")
							if map[bare] == nil then map[bare] = t end
						end
					end
				end
			end
		end
	end
	return map
end

-- Cut a string to at most n bytes without splitting a UTF-8 character
local function CutUtf8(s, n)
	if #s <= n then return s end
	local i = n
	while i > 0 do
		local b = string.byte(s, i + 1)
		if b and b >= 0x80 and b < 0xC0 then i = i - 1 else break end
	end
	return string.sub(s, 1, i)
end

-- First line of a small text file (UTF-8), or nil. Used for <video>.title.txt
local function ReadFirstLine(path)
	local text = file.Read(path, "GAME")
	if not text or text == "" then return nil end
	if string.sub(text, 1, 3) == "\239\187\191" then text = string.sub(text, 4) end -- UTF-8 BOM
	local line = string.match(text, "[^\r\n]+")
	if not line then return nil end
	line = Trim(line)
	if line == "" then return nil end
	return CutUtf8(line, 300)
end

-- Scan data_static/<PackFolder>/. Returns the video list and records, in state.diag, why every
-- file returned by file.Find was accepted or skipped.
local function Scan()
	local dir = "data_static/" .. C.PackFolder .. "/"
	local titles = ReadTitles()
	local out, seen, diag = {}, {}, {}
	local counts = { ["title file"] = 0, ["titles.txt"] = 0, ["file name"] = 0 }

	-- "GAME" merges files from garrysmod/addons/ and from mounted Workshop addons
	local names = file.Find(dir .. "*", "GAME")
	for _, name in ipairs(names or {}) do
		local lname = string.lower(name)
		local base, ext = string.match(lname, "^(.*)%.([^.]+)$")
		local why = "ok"

		if not (base and EXTS[ext]) then
			why = "skipped: not a .txt/.webm file"
		elseif string.find(lname, "%.title%.txt$") then
			why = "ok: title file"
		elseif SKIP[lname] or string.find(lname, "^titles.*%.txt$") then
			why = "skipped: README/titles file"
		elseif seen[base] then
			why = "skipped: duplicate name"
		else
			local path = dir .. name
			local size = file.Size(path, "GAME")
			if size and size >= C.MinSizeKB * 1024 then
				seen[base] = true
				local shown = string.match(name, "^(.*)%.[^.]+$") or name

				-- display name: <video>.title.txt  >  titles*.txt  >  the file name
				local title = ReadFirstLine(dir .. shown .. ".title.txt")
				local from = "title file"
				if not title then
					title = titles[lname] or titles[base]
					from = "titles.txt"
				end
				if not title then
					title = shown
					from = "file name"
				end
				counts[from] = counts[from] + 1

				out[#out + 1] = {
					title = title,
					from = from,
					path = path,
					size = size,
					url = "asset://garrysmod/" .. path,
				}
			else
				why = "skipped: size=" .. tostring(size) .. " (unreadable, or smaller than " .. C.MinSizeKB .. "KB)"
			end
		end

		diag[#diag + 1] = { name = name, why = why, ok = (why == "ok") }
	end
	state.diag = diag
	state.counts = counts

	table.sort(out, function(a, b)
		local x, y = string.lower(a.title), string.lower(b.title)
		if x == y then return a.path < b.path end
		return x < y
	end)
	return out
end

-- Show what file.Find returned and why files were skipped (printed only when the result changes)
local function DumpDiag(force)
	local d = state.diag or {}
	local parts = {}
	for i, e in ipairs(d) do parts[i] = e.name .. "=" .. e.why end
	local sig = #d .. "|" .. table.concat(parts, "\n")
	if sig == state.diagSig and not force then return end
	state.diagSig = sig

	Log("file.Find returned " .. #d .. " entries in data_static/" .. C.PackFolder .. "/")
	for i, e in ipairs(d) do
		if i > 12 then
			Log("... (only the first 12 entries are shown)")
			break
		end
		Log("  [" .. i .. "] " .. e.name .. "  ->  " .. e.why)
	end
end

local function FindPath(path)
	if not path then return nil end
	for i, e in ipairs(state.list) do
		if e.path == path then return i end
	end
	return nil
end

-- Choose the current video: the one the user picked > the one remembered from last time >
-- the one already playing > the first one
local function ApplySelection()
	local list = state.list
	if #list == 0 then
		state.sel = 0
		return
	end

	local wanted = FindPath(state.pick or state.wantPath)
	local idx = wanted or FindPath(state.selPath) or 1
	local path = list[idx].path
	if path ~= state.selPath then
		state.selPath = path
		state.ver = state.ver + 1 -- tells the menu page to switch video
		Log("now playing: " .. list[idx].title .. (wanted and "  (remembered)" or "  (default)"))
	end
	state.sel = idx
end

local function Rescan()
	local list = Scan()

	local parts = {}
	for i, e in ipairs(list) do parts[i] = e.path .. "|" .. e.size .. "|" .. e.title end
	local sig = table.concat(parts, "\n")
	if sig == state.sig then return end

	state.sig = sig
	state.list = list
	local c = state.counts or {}
	Say("found " .. #list .. " video(s) in data_static/" .. C.PackFolder .. "/  (names from: " ..
		(c["title file"] or 0) .. " .title.txt file(s), " .. (c["titles.txt"] or 0) .. " titles*.txt, " ..
		(c["file name"] or 0) .. " file name(s))")
	ApplySelection()
end

-- Select video number idx (bump = true when the menu page does not know yet and must be told to switch)
local function Pick(idx, bump)
	local e = state.list[idx]
	if not e then return false end

	state.pick, state.selPath, state.sel = e.path, e.path, idx
	CookieSet("videomenu_selected", e.path)
	if bump then state.ver = state.ver + 1 end
	return true
end

-- Called from the menu page (message "VIDEOMENU:sel:<number>") when the user picks a video from the list
function VideoMenu.OnSelect(i)
	i = tonumber(i)
	if i and Pick(math.floor(i), false) then
		Log("selected: " .. state.list[state.sel].title)
	end
end

-- Called from the menu page when the user changes the volume or mutes
function VideoMenu.OnVolume(vol, muted)
	state.vol = math.min(1, math.max(0, tonumber(vol) or state.vol))
	state.muted = (muted == true)
	CookieSet("videomenu_volume", string.format("%.2f", state.vol))
	CookieSet("videomenu_muted", state.muted and "1" or "0")
	Log(string.format("volume saved: %.2f%s", state.vol, state.muted and " (muted)" or ""))
end

-- Called from the menu page when the user changes the video size in SETTINGS
function VideoMenu.OnFit(mode)
	if ValidFit(mode) then
		state.fit = mode
		CookieSet("videomenu_fit", mode)
		Log("video size saved: " .. mode)
	end
end

-- Called from the menu page when the user toggles the debug box in SETTINGS
function VideoMenu.OnDebug(on)
	state.debug = (on == true)
	CookieSet("videomenu_debug", state.debug and "1" or "0")
	Log("debug box: " .. (state.debug and "on" or "off"))
end

-- Select by number or by name (exact name first, then "contains")
function VideoMenu.Play(query)
	query = Trim(tostring(query or ""))
	if query == "" then return false end

	local idx = nil
	local n = tonumber(query)
	if n and state.list[math.floor(n)] then
		idx = math.floor(n)
	else
		local q = string.lower(query)
		for i, e in ipairs(state.list) do
			if string.lower(e.title) == q then
				idx = i
				break
			end
		end
		if not idx then
			for i, e in ipairs(state.list) do
				if string.find(string.lower(e.title), q, 1, true) or string.find(string.lower(e.path), q, 1, true) then
					idx = i
					break
				end
			end
		end
	end

	if not idx then
		Log("video not found: " .. query .. "  (use videomenu_list to see the list)")
		return false
	end

	Pick(idx, true)
	Log("playing: " .. state.list[idx].title)
	return true
end

local function PrintList()
	if #state.list == 0 then
		Log("no videos found in data_static/" .. C.PackFolder .. "/")
	end
	for i, e in ipairs(state.list) do
		Log(string.format("%s%d. %s  (%.1f MB)  [name from: %s]  %s", (i == state.sel) and "> " or "  ", i,
			e.title, e.size / 1048576, e.from or "?", e.path))
	end

	local shown = 0
	for _, d in ipairs(state.diag or {}) do
		if not d.ok then
			shown = shown + 1
			if shown <= 10 then Log("  (skipped) " .. d.name .. "  ->  " .. d.why) end
		end
	end
end

-- ---------------- sending data to the menu page ----------------
-- Turn text into a JavaScript string literal (escapes control characters, ' " \ and U+2028/2029)
local function JsStr(s)
	s = tostring(s)
	s = string.gsub(s, "[\1-\31\127\"\\']", function(c) return string.format("\\u%04x", string.byte(c)) end)
	s = string.gsub(s, "\226\128[\168\169]", function(c)
		return (c == "\226\128\168") and "\\u2028" or "\\u2029"
	end)
	return '"' .. s .. '"'
end

local function ListJS()
	local parts = {}
	for i, e in ipairs(state.list) do
		parts[i] = "[" .. JsStr(e.title) .. "," .. JsStr(e.url) .. "," .. string.format("%d", e.size) .. "]"
	end
	return "[" .. table.concat(parts, ",") .. "]"
end

local function Replace(s, key, value)
	return (string.gsub(s, key, function() return value end))
end

local function BuildJS()
	local ok, ingame = pcall(IsInGame)

	local js = JS_TEMPLATE
	js = Replace(js, "__SEL__", tostring(math.max(0, state.sel - 1)))
	js = Replace(js, "__VER__", tostring(state.ver))
	js = Replace(js, "__VOL__", string.format("%.2f", state.vol))
	js = Replace(js, "__MUTED__", state.muted and "true" or "false")
	js = Replace(js, "__DEBUG__", state.debug and "true" or "false")
	js = Replace(js, "__FIT__", JsStr(state.fit))
	js = Replace(js, "__INGAME__", (ok and ingame) and "true" or "false")
	js = Replace(js, "__LIST__", ListJS()) -- last, so video titles can never collide with the other placeholders
	return js
end

-- Messages from the menu page: JS calls console.log("VIDEOMENU:<command>").
-- The main menu does not accept RUNLUA (SetAllowLua), so we intercept the ConsoleMessage of the
-- menu's DHTML panel instead.
--   sel:<number>        the user picked a video
--   vol:<0-1>,<0|1>     volume, and whether it is muted
--   fit:<mode>          video size (cover | contain | fill)
--   dbg:<0|1>           debug box off / on
local function HandleMsg(str)
	local i = string.match(str, "^sel:(%d+)$")
	if i then
		VideoMenu.OnSelect(tonumber(i))
		return
	end

	local v, m = string.match(str, "^vol:([%d%.]+),([01])$")
	if v then
		VideoMenu.OnVolume(tonumber(v), m == "1")
		return
	end

	local f = string.match(str, "^fit:(%a+)$")
	if f then
		VideoMenu.OnFit(f)
		return
	end

	local d = string.match(str, "^dbg:([01])$")
	if d then VideoMenu.OnDebug(d == "1") end
end

local function HookConsole(html)
	if html.__vmHooked then return end
	html.__vmHooked = true

	local orig = html.ConsoleMessage
	html.ConsoleMessage = function(self, msg, ...)
		if type(msg) == "string" and string.sub(msg, 1, 10) == "VIDEOMENU:" then
			local ok, err = pcall(HandleMsg, string.sub(msg, 11))
			if not ok then Log("error: " .. tostring(err)) end
			return
		end
		if orig then return orig(self, msg, ...) end
	end
end

-- Send JavaScript to the main menu page (pnlMainMenu.HTML is the DHTML that shows menu.html)
local function RunJS(js)
	local menu = pnlMainMenu
	if not IsValid(menu) then return false end

	local html = menu.HTML
	if IsValid(html) then
		HookConsole(html)
		html:QueueJavascript(js) -- DHTML queues it and runs it once the page has loaded
		return true
	end

	-- In case the menu is built differently than expected: pnlMainMenu is a DHTML itself, or has a Call method
	if menu.QueueJavascript then
		menu:QueueJavascript(js)
		return true
	end
	if menu.Call then
		menu:Call(js)
		return true
	end
	return false
end

local function Tick()
	state.tick = state.tick + 1
	if state.tick % 5 == 1 then Rescan() end

	if #state.list == 0 then
		Say("no videos found in data_static/" .. C.PackFolder .. "/ (pack addon not mounted yet, wrong folder name, or the file names cannot be read)")
		DumpDiag(false)
		return
	end

	if not IsValid(pnlMainMenu) then
		Say("waiting for the main menu panel (pnlMainMenu)...")
		return
	end

	-- Sent every second: the JS side checks by itself whether it has already been created
	-- (covers the menu page being reloaded)
	local sent = RunJS(BuildJS())
	if sent then
		state.fail = 0
		if not state.injected then
			state.injected = true
			Say("video script sent to the menu")
		end
	else
		state.fail = state.fail + 1
		if state.fail == 5 then
			Say("cannot send JS to the menu: pnlMainMenu.HTML = " .. tostring(pnlMainMenu.HTML) ..
				", pnlMainMenu.Call = " .. tostring(pnlMainMenu.Call))
		end
	end
end

timer.Create("VideoMenu_Tick", 1, 0, function()
	local ok, err = pcall(Tick)
	if not ok then Say("error: " .. tostring(err)) end
end)

-- New content got mounted (e.g. Workshop) -> rescan on the next tick
pcall(hook.Add, "GameContentChanged", "VideoMenu_Rescan", function() state.tick = 0 end)

-- ---------------- console commands ----------------
local function AutoComplete(cmd, args)
	local out = {}
	local q = string.lower(Trim(args or ""))
	for _, e in ipairs(state.list) do
		if q == "" or string.find(string.lower(e.title), q, 1, true) then
			out[#out + 1] = cmd .. " " .. e.title
			if #out >= 30 then break end
		end
	end
	return out
end

local cmdOk = false
if concommand and concommand.Add then
	cmdOk = pcall(concommand.Add, "videomenu_reload", function()
		state.sig = ""
		state.diagSig = nil
		state.injected = false
		state.lastMsg = nil
		RunJS("if(window.__vm&&window.__vm.remove)window.__vm.remove();")
		Rescan()
		Log("reload")
	end)

	pcall(concommand.Add, "videomenu_list", function() PrintList() end)

	pcall(concommand.Add, "videomenu_play", function(ply, cmd, args, argStr)
		local q = argStr
		if not q or q == "" then q = table.concat(args or {}, " ") end
		if Trim(q) == "" then
			Log("usage: videomenu_play <number or name>")
			PrintList()
			return
		end
		VideoMenu.Play(q)
	end, AutoComplete)
end

Log("core started (path ID: " .. tostring(Loader.CoreId) .. ") - looking for videos in data_static/" ..
	C.PackFolder .. "/ | videomenu_* commands: " .. (cmdOk and "ready" or "unavailable in the menu"))
