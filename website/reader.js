// Live Reader: the v0.9.0 reader's behaviour on a real audio file.
// - A click on a timestamp or a line seeks there and plays (LTR-44 contract).
// - The active line is the last one that has started, until its end + 1 s.
// - The transcript follows the active line while playing, only inside its own
//   scroll box, never the page. Scrolling it yourself stops that; Jump to
//   Playing (or a new play) turns it back on.
(function () {
  var root = document.querySelector("[data-reader]");
  if (!root) return;

  var HOLD = 1.0;
  var audio = root.querySelector("[data-audio]");
  var playBtn = root.querySelector("[data-play]");
  var seek = root.querySelector("[data-seek]");
  var now = root.querySelector("[data-now]");
  var list = root.querySelector("[data-lines]");
  var jump = root.querySelector("[data-jump]");
  var more = root.querySelector("[data-more]");
  var body = list.parentNode;
  var rows = Array.prototype.slice.call(list.children);
  var stamps = rows.map(function (li) { return li.querySelector(".lr-ts"); });
  var spans = rows.map(function (li) { return { start: +li.dataset.start, end: +li.dataset.end }; });
  var duration = +seek.max;
  var reduceMotion = matchMedia("(prefers-reduced-motion: reduce)");

  var pos = +seek.value;      // shown position; audio.currentTime once loaded
  var pending = pos;          // a seek waiting for metadata (iOS loads nothing up front)
  var active = -1;
  var following = true;
  var raf = 0;

  function clock(t) {
    t = Math.max(0, Math.floor(t));
    return Math.floor(t / 60) + ":" + String(t % 60).padStart(2, "0");
  }

  function lineAt(t) {
    var found = -1;
    for (var i = 0; i < spans.length && spans[i].start <= t; i++) found = i;
    return found >= 0 && t <= spans[found].end + HOLD ? found : -1;
  }

  function scrollable() { return list.scrollHeight > list.clientHeight + 1; }

  function lineVisible(i) {
    var r = rows[i].getBoundingClientRect(), box = list.getBoundingClientRect();
    return r.bottom > box.top + 4 && r.top < box.bottom - 4;
  }

  function centre(i) {
    if (!scrollable()) return;
    var li = rows[i];
    var top = li.offsetTop - (list.clientHeight - li.offsetHeight) / 2;
    list.scrollTo({ top: Math.max(0, top), behavior: reduceMotion.matches ? "auto" : "smooth" });
  }

  function updateJump() {
    jump.hidden = following || active < 0 || audio.paused || !scrollable() || lineVisible(active);
  }

  // Portrait phones show five lines and a row that opens the rest (CSS decides
  // whether the attribute has any effect). Playback past line five opens it too.
  var SHOWN = 5;
  function expand() {
    if (!body.hasAttribute("data-collapsed")) return;
    body.removeAttribute("data-collapsed");
    more.setAttribute("aria-expanded", "true");
  }

  function render(t) {
    pos = t;
    now.textContent = clock(t);
    seek.value = t;
    seek.style.setProperty("--p", (t / duration) * 100 + "%");
    seek.setAttribute("aria-valuetext", clock(t) + " of " + clock(duration));
    var line = lineAt(t);
    if (line !== active) {
      if (active >= 0) { rows[active].classList.remove("is-active"); rows[active].removeAttribute("aria-current"); }
      active = line;
      if (active >= SHOWN) expand();
      if (active >= 0) {
        rows[active].classList.add("is-active");
        rows[active].setAttribute("aria-current", "time");
        if (following && !audio.paused) centre(active);
      }
    }
    updateJump();
  }

  function setState() {
    var state = !audio.paused ? "playing" : (audio.ended || pos >= duration - 0.05 ? "ended" : "paused");
    root.dataset.state = state;
    playBtn.setAttribute("aria-label", state === "playing" ? "Pause" : state === "ended" ? "Play from start" : "Play");
  }

  function tick() {
    render(audio.currentTime);
    raf = audio.paused ? 0 : requestAnimationFrame(tick);
  }

  function seekTo(t) {
    t = Math.min(Math.max(t, 0), duration);
    if (audio.readyState >= 1) { audio.currentTime = t; pending = null; } else { pending = t; }
    render(t);
    setState();
  }

  // play() must run inside the click itself, or iOS refuses it.
  function play() {
    following = true;
    var p = audio.play();
    if (p && p.catch) p.catch(function () { setState(); });
  }

  function playFrom(i) {
    seekTo(spans[i].start);
    play();
    centre(i);
  }

  audio.addEventListener("loadedmetadata", function () {
    if (pending != null) { audio.currentTime = pending; pending = null; }
  });
  audio.addEventListener("play", function () { setState(); if (!raf) raf = requestAnimationFrame(tick); });
  audio.addEventListener("pause", function () { render(audio.currentTime || pos); setState(); });
  audio.addEventListener("ended", function () { render(duration); setState(); });
  audio.addEventListener("seeked", function () { if (audio.paused) render(audio.currentTime); });

  playBtn.addEventListener("click", function () {
    if (!audio.paused) { audio.pause(); return; }
    if (root.dataset.state === "ended") seekTo(0);
    play();
  });

  seek.addEventListener("input", function () { seekTo(+seek.value); });

  body.setAttribute("data-collapsed", "");
  more.addEventListener("click", function () {
    expand();
    stamps[SHOWN].focus({ preventScroll: true });
  });

  var stop = Math.max(0, lineAt(pos));   // the transcript's one tab stop: the active line
  stamps.forEach(function (b, i) {
    b.disabled = false;
    b.tabIndex = i === stop ? 0 : -1;
    b.addEventListener("click", function (e) { e.stopPropagation(); playFrom(i); });
  });

  // A click anywhere on a timed line plays it, unless the visitor was selecting text.
  rows.forEach(function (li, i) {
    li.addEventListener("click", function () {
      var sel = window.getSelection && String(window.getSelection());
      if (!sel) playFrom(i);
    });
  });

  // One tab stop for the transcript; arrows move between its timestamps.
  list.addEventListener("keydown", function (e) {
    var i = stamps.indexOf(document.activeElement);
    if (i < 0) return;
    var next = { ArrowDown: i + 1, ArrowUp: i - 1, Home: 0, End: stamps.length - 1 }[e.key];
    if (next == null) return;
    e.preventDefault();
    next = Math.min(Math.max(next, 0), stamps.length - 1);
    if (next >= SHOWN) expand();
    stamps[i].tabIndex = -1;
    stamps[next].tabIndex = 0;
    stamps[next].focus();
  });
  list.addEventListener("focusin", function (e) {
    var i = stamps.indexOf(e.target);
    if (i >= 0) stamps.forEach(function (b, j) { b.tabIndex = j === i ? 0 : -1; });
  });

  // The visitor's own scrolling (never ours) stops follow-along.
  ["wheel", "touchmove"].forEach(function (type) {
    list.addEventListener(type, function () { following = false; updateJump(); }, { passive: true });
  });
  list.addEventListener("scroll", updateJump, { passive: true });
  jump.addEventListener("click", function () {
    following = true;
    centre(active);
    // The button hides itself; hand keyboard focus to the playing line.
    if (active >= 0) stamps[active].focus({ preventScroll: true });
    updateJump();
  });

  // View switch (tabs). Showing the file pauses playback.
  var tabs = Array.prototype.slice.call(root.querySelectorAll('[role="tab"]'));
  function select(tab) {
    tabs.forEach(function (t) {
      var on = t === tab;
      t.setAttribute("aria-selected", on ? "true" : "false");
      t.tabIndex = on ? 0 : -1;
      document.getElementById(t.getAttribute("aria-controls")).hidden = !on;
    });
    if (tab.id !== "lr-tab-reader") audio.pause();
  }
  tabs.forEach(function (t, i) {
    t.addEventListener("click", function () { select(t); });
    t.addEventListener("keydown", function (e) {
      var d = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
      if (!d) return;
      e.preventDefault();
      var n = tabs[(i + d + tabs.length) % tabs.length];
      select(n);
      n.focus();
    });
  });

  render(pos);
  setState();
  // Open with the active line in view, as the reader does.
  if (active >= 0 && scrollable()) {
    list.scrollTop = Math.max(0, rows[active].offsetTop - (list.clientHeight - rows[active].offsetHeight) / 2);
  }
})();
