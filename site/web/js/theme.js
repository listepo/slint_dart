/*! slint_dart site — theme toggle + copy buttons.
   Theme cycles system → light → dark. The boot snippet in main.server.dart
   applies the theme before first paint (FOUC-safe).
   Persist key: localStorage["slint-dart-theme"] = "system" | "light" | "dark"
*/
(function () {
  const KEY = "slint-dart-theme";
  const ORDER = ["system", "light", "dark"];

  function stored() {
    try {
      return localStorage.getItem(KEY);
    } catch {
      return null;
    }
  }

  function resolve(preference) {
    if (preference === "light" || preference === "dark") return preference;
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }

  function apply(preference) {
    const pref = ORDER.includes(preference) ? preference : "system";
    const resolved = resolve(pref);
    const root = document.documentElement;
    root.setAttribute("data-theme", pref);
    root.setAttribute("data-theme-resolved", resolved);
    root.style.colorScheme = resolved;
    const btn = document.getElementById("theme-toggle");
    if (!btn) return;
    const labels = {
      system: "Theme: system (follows OS). Switch to light",
      light: "Theme: light. Switch to dark",
      dark: "Theme: dark. Switch to system",
    };
    btn.setAttribute("aria-label", labels[pref]);
    btn.setAttribute("title", labels[pref]);
    btn.dataset.theme = pref;
  }

  function cycle() {
    const current = stored() || "system";
    const next = ORDER[(ORDER.indexOf(current) + 1) % ORDER.length];
    try {
      localStorage.setItem(KEY, next);
    } catch {
      /* private mode */
    }
    apply(next);
  }

  async function copyText(text) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch {
      const ta = document.createElement("textarea");
      ta.value = text;
      ta.setAttribute("readonly", "");
      ta.style.position = "fixed";
      ta.style.opacity = "0";
      document.body.appendChild(ta);
      ta.select();
      let ok = false;
      try {
        ok = document.execCommand("copy");
      } catch {
        ok = false;
      }
      ta.remove();
      return ok;
    }
  }

  function wireCopy(btn, getText) {
    const label = btn.querySelector(".copy-btn-text") || btn;
    btn.addEventListener("click", async () => {
      const ok = await copyText(getText());
      label.textContent = ok ? "Copied" : "Press ⌘C";
      btn.classList.toggle("is-copied", ok);
      clearTimeout(btn._t);
      btn._t = setTimeout(() => {
        label.textContent = "Copy";
        btn.classList.remove("is-copied");
      }, 1600);
    });
  }

  function initCopy() {
    document.querySelectorAll("[data-copy-target]").forEach((btn) => {
      const target = document.getElementById(btn.dataset.copyTarget);
      if (target) wireCopy(btn, () => target.innerText);
    });
    document.querySelectorAll(".prose pre").forEach((pre) => {
      const wrap = document.createElement("div");
      wrap.className = "code-wrap";
      pre.parentNode.insertBefore(wrap, pre);
      wrap.appendChild(pre);
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "copy-btn";
      btn.setAttribute("aria-label", "Copy code");
      btn.innerHTML = '<span class="copy-btn-text">Copy</span>';
      wrap.appendChild(btn);
      wireCopy(btn, () => (pre.querySelector("code") || pre).innerText);
    });
  }

  window.__slintDartTheme = { apply, cycle, resolve, KEY };

  document.addEventListener("DOMContentLoaded", () => {
    apply(stored() || "system");
    const btn = document.getElementById("theme-toggle");
    if (btn) btn.addEventListener("click", cycle);
    initCopy();
  });

  try {
    window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
      if ((stored() || "system") === "system") apply("system");
    });
  } catch {
    /* older Safari */
  }
})();
