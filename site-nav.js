// A small floating nav between the demos, pinned to the bottom left of the
// viewport. Each demo page includes it with a relative <script src> to this
// file; the links are worked out from this script's own URL, so they hold on
// GitHub Pages (under the repo's path) and on a local server alike.
(function () {
  const script = document.currentScript;
  if (!script) {
    return;
  }
  const root = new URL(".", script.src);
  const PAGES = [
    { label: "Bow", path: "pinaka-bow/web/" },
    { label: "Tarot flow", path: "tarot-frontend-demo/" },
    { label: "10 Rings", path: "ten-rings/web/" },
  ];

  const style = document.createElement("style");
  style.textContent = `
    .site-nav {
      position: fixed;
      left: max(16px, env(safe-area-inset-left));
      bottom: max(16px, env(safe-area-inset-bottom));
      z-index: 1000;
      display: flex;
      gap: 2px;
      padding: 3px;
      border-radius: 999px;
      background: rgba(28, 28, 32, 0.78);
      box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.08), 0 8px 24px rgba(0, 0, 0, 0.35);
      backdrop-filter: blur(10px);
      -webkit-backdrop-filter: blur(10px);
      font: 500 12px/1 "DM Sans", system-ui, -apple-system, sans-serif;
    }
    .site-nav a {
      padding: 8px 12px;
      border-radius: 999px;
      color: rgba(255, 255, 255, 0.68);
      text-decoration: none;
      white-space: nowrap;
      transition: background-color 0.15s ease, color 0.15s ease;
    }
    .site-nav a:hover {
      color: #fff;
      background: rgba(255, 255, 255, 0.08);
    }
    .site-nav a:focus-visible {
      outline: 2px solid rgba(255, 255, 255, 0.6);
      outline-offset: 1px;
    }
    .site-nav a[aria-current="page"] {
      color: #16161a;
      background: #f2ecdf;
    }
  `;
  document.head.appendChild(style);

  const nav = document.createElement("nav");
  nav.className = "site-nav";
  nav.setAttribute("aria-label", "Demos");
  const here = location.pathname;
  for (const page of PAGES) {
    const url = new URL(page.path, root);
    const link = document.createElement("a");
    link.href = url.href;
    link.textContent = page.label;
    if (here.startsWith(url.pathname)) {
      link.setAttribute("aria-current", "page");
    }
    nav.appendChild(link);
  }
  document.body.appendChild(nav);
})();
