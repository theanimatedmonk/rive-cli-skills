// A small floating nav between the demos, pinned to the bottom left of the
// viewport. Collapsed it is a pill naming the current demo; clicking it opens
// a menu above it with all three. Each demo page includes it with a relative
// <script src> to this file; the links are worked out from this script's own
// URL, so they hold on GitHub Pages (under the repo's path) and on a local
// server alike.
(function () {
  const script = document.currentScript;
  if (!script) {
    return;
  }
  const root = new URL(".", script.src);
  const PAGES = [
    { label: "Bow", path: "pinaka-bow/web/" },
    { label: "Ruins", path: "sheesupalgarh/web/" },
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
      font: 500 12px/1 "DM Sans", system-ui, -apple-system, sans-serif;
    }
    .site-nav__toggle,
    .site-nav__menu {
      border-radius: 999px;
      background: rgba(28, 28, 32, 0.78);
      box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.08), 0 8px 24px rgba(0, 0, 0, 0.35);
      backdrop-filter: blur(10px);
      -webkit-backdrop-filter: blur(10px);
    }
    .site-nav__toggle {
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 9px 12px 9px 14px;
      border: 0;
      color: rgba(255, 255, 255, 0.85);
      font: inherit;
      cursor: pointer;
      transition: color 0.15s ease;
    }
    .site-nav__toggle:hover {
      color: #fff;
    }
    .site-nav__chevron {
      width: 10px;
      height: 10px;
      transition: transform 0.2s ease;
    }
    .site-nav.is-open .site-nav__chevron {
      transform: rotate(180deg);
    }
    .site-nav__menu {
      position: absolute;
      left: 0;
      bottom: calc(100% + 8px);
      display: flex;
      flex-direction: column;
      gap: 2px;
      min-width: 100%;
      padding: 4px;
      border-radius: 14px;
      opacity: 0;
      transform: translateY(6px) scale(0.97);
      transform-origin: bottom left;
      pointer-events: none;
      visibility: hidden;
      transition: opacity 0.16s ease, transform 0.16s ease, visibility 0s linear 0.16s;
    }
    .site-nav.is-open .site-nav__menu {
      opacity: 1;
      transform: none;
      pointer-events: auto;
      visibility: visible;
      transition: opacity 0.16s ease, transform 0.16s ease;
    }
    .site-nav__menu a {
      padding: 9px 12px;
      border-radius: 10px;
      color: rgba(255, 255, 255, 0.72);
      text-decoration: none;
      white-space: nowrap;
      transition: background-color 0.15s ease, color 0.15s ease;
    }
    .site-nav__menu a:hover {
      color: #fff;
      background: rgba(255, 255, 255, 0.08);
    }
    .site-nav__menu a[aria-current="page"] {
      color: #16161a;
      background: #f2ecdf;
    }
    .site-nav__toggle:focus-visible,
    .site-nav__menu a:focus-visible {
      outline: 2px solid rgba(255, 255, 255, 0.6);
      outline-offset: 1px;
    }
    @media (prefers-reduced-motion: reduce) {
      .site-nav__menu,
      .site-nav__chevron {
        transition: none;
      }
    }
  `;
  document.head.appendChild(style);

  const nav = document.createElement("nav");
  nav.className = "site-nav";
  nav.setAttribute("aria-label", "Demos");

  const menu = document.createElement("div");
  menu.className = "site-nav__menu";
  menu.id = "site-nav-menu";
  const here = location.pathname;
  let current = "Demos";
  for (const page of PAGES) {
    const url = new URL(page.path, root);
    const link = document.createElement("a");
    link.href = url.href;
    link.textContent = page.label;
    if (here.startsWith(url.pathname)) {
      link.setAttribute("aria-current", "page");
      current = page.label;
    }
    menu.appendChild(link);
  }

  const toggle = document.createElement("button");
  toggle.type = "button";
  toggle.className = "site-nav__toggle";
  toggle.setAttribute("aria-expanded", "false");
  toggle.setAttribute("aria-controls", menu.id);
  toggle.innerHTML =
    '<span class="site-nav__label"></span>' +
    '<svg class="site-nav__chevron" viewBox="0 0 10 10" aria-hidden="true">' +
    '<path d="M2 6.5 5 3.5 8 6.5" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  toggle.querySelector(".site-nav__label").textContent = current;

  function setOpen(open) {
    nav.classList.toggle("is-open", open);
    toggle.setAttribute("aria-expanded", String(open));
  }
  toggle.addEventListener("click", (event) => {
    const open = !nav.classList.contains("is-open");
    setOpen(open);
    // Opened from the keyboard (Enter or Space: no pointer, detail 0), move
    // focus into the menu; a mouse click leaves it on the toggle.
    if (open && event.detail === 0) {
      const first = menu.querySelector('a[aria-current="page"]') || menu.querySelector("a");
      if (first) {
        first.focus({ preventScroll: true });
      }
    }
  });
  document.addEventListener("click", (event) => {
    if (!nav.contains(event.target)) {
      setOpen(false);
    }
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && nav.classList.contains("is-open")) {
      setOpen(false);
      toggle.focus();
    }
  });

  nav.append(menu, toggle);
  document.body.appendChild(nav);
})();
