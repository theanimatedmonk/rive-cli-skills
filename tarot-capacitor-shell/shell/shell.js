// Scales the demo's 360x780 phone screen to fill the device screen.
(() => {
  const fit = () => {
    const scale = Math.min(window.innerWidth / 360, window.innerHeight / 780);
    document.documentElement.style.setProperty("--shell-scale", String(scale));
  };
  fit();
  window.addEventListener("resize", fit);
})();
