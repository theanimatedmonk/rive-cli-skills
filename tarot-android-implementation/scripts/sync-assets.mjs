// Copies what the app shares with the other tarot projects:
//   - the signed vector .riv (./rive, the Rive CLI project, built with
//     `rive . --publish`), which renders on the native Rive runtime
//   - the card faces and images, and the personas as JSON, from the web demo
//     (../tarot-frontend-demo stays the source of the readings)
import { cpSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import vm from "node:vm";

const root = new URL("..", import.meta.url).pathname;
const demo = join(root, "../tarot-frontend-demo");
const riv = join(root, "rive/build/tarot-android-implementation.riv");
const assets = join(root, "app/src/main/assets");
const raw = join(root, "app/src/main/res/raw");

if (!existsSync(riv)) {
  throw new Error("Build the .riv first: `rive . --publish` in ./rive");
}
mkdirSync(raw, { recursive: true });
cpSync(riv, join(raw, "tarot_animation.riv"));

cpSync(join(demo, "assets/cards"), join(assets, "cards"), { recursive: true });
mkdirSync(join(assets, "images"), { recursive: true });
for (const name of ["promo-card.png", "promo-bg.png", "bg.png"]) {
  cpSync(join(demo, "assets", name), join(assets, "images", name));
}

// personas.js declares `const TAROT_PERSONAS = [...]`; evaluate it and keep
// just the card file name (cards/<file>) with the texts.
const context = {};
vm.runInNewContext(readFileSync(join(demo, "personas.js"), "utf8") + "\nthis.out = TAROT_PERSONAS;", context);
const personas = context.out.map((p) => ({
  image: p.image.replace(/^assets\/cards\//, ""),
  name: p.name,
  career: p.career,
  love: p.love,
  finance: p.finance,
}));
writeFileSync(join(assets, "personas.json"), JSON.stringify(personas, null, 2) + "\n");
console.log(`synced: .riv, ${personas.length} personas, cards, images`);
