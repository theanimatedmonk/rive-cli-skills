// Builds www/ from the web demo (../tarot-frontend-demo stays the single
// source): copies the demo, bundles the Rive runtime locally so the app
// works offline, and adds the app-only shell stylesheet and script.
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const root = new URL("..", import.meta.url).pathname;
const demo = join(root, "../tarot-frontend-demo");
const www = join(root, "www");

rmSync(www, { recursive: true, force: true });
mkdirSync(www, { recursive: true });
for (const name of ["index.html", "main.js", "style.css", "personas.js", "tarot-animation.riv", "assets"]) {
  cpSync(join(demo, name), join(www, name), { recursive: true });
}

const rive = join(root, "node_modules/@rive-app/webgl2");
mkdirSync(join(www, "vendor"), { recursive: true });
for (const name of ["rive.js", "rive.wasm", "rive_fallback.wasm"]) {
  cpSync(join(rive, name), join(www, "vendor", name));
}
cpSync(join(root, "shell/shell.css"), join(www, "shell.css"));
cpSync(join(root, "shell/shell.js"), join(www, "shell.js"));

const indexPath = join(www, "index.html");
let html = readFileSync(indexPath, "utf8");
const cdn = /<script src="https:\/\/unpkg\.com\/@rive-app\/webgl2@[^"]+"><\/script>/;
if (!cdn.test(html)) {
  throw new Error("Could not find the Rive runtime <script> in the demo's index.html");
}
html = html.replace(
  cdn,
  '<script src="vendor/rive.js"></script>\n    <script>rive.RuntimeLoader.setWasmUrl("vendor/rive.wasm");</script>',
);
html = html.replace(
  '<link rel="stylesheet" href="style.css" />',
  '<link rel="stylesheet" href="style.css" />\n    <link rel="stylesheet" href="shell.css" />',
);
html = html.replace("</body>", '  <script src="shell.js"></script>\n  </body>');
writeFileSync(indexPath, html);
console.log("www/ synced from tarot-frontend-demo");
