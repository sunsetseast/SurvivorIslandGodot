/** Build Godot's public-safe inputs from the exact version of the Three.js camp. */
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const sourceCommit = "708a21c43b4b2969aa28bf2142005e4f5df0bcdf";
const oldRoot = "artifacts/survivor-camp-prototype/src";
const lock = JSON.parse(await readFile(new URL("inputs.json", import.meta.url), "utf8"));
const output = resolve(dirname(fileURLToPath(import.meta.url)), "../../tonsai/generated");
const local = process.argv[2];
const temp = await mkdtemp(join(tmpdir(), "tonsai-data-"));
async function source(path) {
  const bytes = local
    ? await readFile(join(local, oldRoot, path))
    : execFileSync("curl", ["--fail", "--silent", "--show-error", "--location", "--retry", "2",
        "--max-time", "90", "https://raw.githubusercontent.com/sunsetseast/SurvivorIsland3Dprototype/" + sourceCommit + "/" + oldRoot + "/" + path],
      { maxBuffer: 16 * 1024 * 1024 });
  const hash = createHash("sha256").update(bytes).digest("hex");
  if (lock[path] !== hash) throw new Error("Source checksum mismatch: " + path);
  return bytes;
}

async function importLayout() {
  // The old data modules are pure when the browser-only profiler is stubbed.
  // Use the original generators wholesale offline, with Node's TS type erasure.
  const moduleFiles = [
    "world.ts", "environment/geography.ts", "environment/forest.ts",
    "environment/composition.ts", "environment/hidingSpots.ts",
    "environment/rockCollision.json", "environment/candidate-surfaces.json",
  ];
  await mkdir(join(temp, "environment"));
  await writeFile(join(temp, "environment/profile.ts"), "export function recordStage() {}");
  for (const path of moduleFiles) {
    let body = (await source("game/" + path)).toString();
    // Add explicit ESM suffixes and import attributes for the two JSON sources.
    if (path.endsWith(".ts")) body = body.replace(
      /from (["'])(\.{1,2}\/[^"']+)\1/g,
      (_match, _quote, specifier) => specifier.endsWith(".json")
        ? `from "${specifier}" with { type: "json" }`
        : `from "${specifier}.ts"`,
    );
    await writeFile(join(temp, path), body);
  }
  const load = path => import(pathToFileURL(join(temp, path)).href);
  const w = await load("world.ts");
  const g = await load("environment/geography.ts");
  const { FOREST_PLANTS } = await load("environment/forest.ts");
  const { CLIFF_MASSES, BACKDROP_TREES, PRIVATE_SPACES } = await load("environment/composition.ts");
  const { HIDING_CANDIDATES } = await load("environment/hidingSpots.ts");
  if (g.TRAILS.length !== 12 || HIDING_CANDIDATES.length !== 39) throw new Error("Unexpected source inventory");
  const extent = g.TERRAIN_EXTENT;
  const width = extent.maxX - extent.minX + 1;
  const depth = extent.maxZ - extent.minZ + 1;
  const raster = Buffer.alloc(width * depth * 9);
  const shadeGrid = new Map();
  for (const shade of w.SHADE) {
    for (let x = Math.floor((shade.x - shade.r) / 12); x <= Math.floor((shade.x + shade.r) / 12); x++) {
      for (let z = Math.floor((shade.z - shade.r) / 12); z <= Math.floor((shade.z + shade.r) / 12); z++) {
        const key = `${x},${z}`;
        if (!shadeGrid.has(key)) shadeGrid.set(key, []);
        shadeGrid.get(key).push(shade);
      }
    }
  }
  const shore = [];
  let i = 0;
  for (let z = extent.minZ; z <= extent.maxZ; z++) {
    const coast = w.shorelineX(z);
    shore.push(+coast.toFixed(4));
    for (let x = extent.minX; x <= extent.maxX; x++) {
      const distance = x - coast;
      const jungle = w.smoothstep(11, 25, distance + (w.noise2(x * .11, z * .11) - .5) * 12);
      const clearing = 1 - w.smoothstep(6, 13, Math.hypot(x + 9, z + 31));
      const shelter = 1 - w.smoothstep(0, 4, Math.hypot(Math.max(5 - x, 0, x - 19), Math.max(-50 - z, 0, z + 31)));
      raster.writeFloatLE(w.baseHeight(x, z), i);
      raster[i + 4] = Math.round(jungle * 255);
      raster[i + 5] = Math.round(Math.max(w.trailWear(x, z), clearing, shelter) * 255);
      raster[i + 6] = Math.round(w.smoothstep(.2, 4.4, distance) * 255);
      raster[i + 7] = distance >= .9 && g.territoryContains(x, z) && x >= w.BOUNDS.minX &&
        x <= w.BOUNDS.maxX && z >= w.BOUNDS.minZ && z <= w.BOUNDS.maxZ && !g.cliffSolid(x, z) ? 255 : 0;
      let light = 1 - w.smoothstep(28, 70, distance) * .16;
      for (const shade of shadeGrid.get(`${Math.floor(x / 12)},${Math.floor(z / 12)}`) ?? []) {
        const falloff = Math.max(0, 1 - Math.hypot(x - shade.x, z - shade.z) / shade.r);
        light -= shade.s * falloff * falloff * .32;
      }
      raster[i + 8] = Math.round(Math.max(.49, light) * 255);
      i += 9;
    }
  }
  function placement(p, multiplier, variant = p.variant) {
    return [p.x, p.y ?? w.baseHeight(p.x, p.z), p.z, p.scale * multiplier, p.rotation, variant ?? 0]
      .map(value => +value.toFixed(4));
  }
  const vegetation = {
    trees: [...w.BROADLEAF.map((p, i) => placement(p, 1, i % 3)),
      ...BACKDROP_TREES.map((p, i) => placement(p, .36, i % 3))],
    palms: w.PALMS.map(p => placement(p, .81)),
    understory: FOREST_PLANTS.filter((p, i) => i % (p.zone === "backdrop" ? 4 : 2) === 0).map(p => placement(p, 1)),
    ferns: w.FERNS.filter((_, i) => i % 3 === 0).map((p, i) =>
      placement(p, p.z >= 67 && p.z <= 101 && p.x >= -38 && p.x <= 6 ? 2.3 : 3.2, i % 4)),
    rocks: w.ROCKS.map(p => placement(p, .85)),
    springRim: Array.from({ length: 11 }, (_, i) => {
      const a = i * Math.PI * 2 / 11;
      return placement({ x: g.SPRING.x + Math.cos(a) * 1.65, z: g.SPRING.z + Math.sin(a) * 1.35,
        scale: .25 + (i % 3) * .055, rotation: i * 2.399 }, 1);
    }),
  };
  const layout = {
    locationId: "tonsai", sourceCommit, extent, bounds: w.BOUNDS, territory: g.TERRITORY, shore,
    spawn: w.SPAWN, landmarks: w.LANDMARKS, naturalLandmarks: g.NATURAL_LANDMARKS,
    trails: g.TRAILS, expandedPlaces: g.EXPANDED_PLACES, privateSpaces: PRIVATE_SPACES,
    hidingCandidates: HIDING_CANDIDATES, cave: g.CAVE, shelter: w.SHELTER, props: w.PROPS,
    logs: w.SEATING_LOGS, vegetation, headlands: CLIFF_MASSES,
    // Bamboo is represented by non-blocking understory in this port.
    colliders: w.COLLIDERS.filter(c => c.kind !== "bamboo"),
  };
  await writeFile(join(output, "layout.json"), JSON.stringify(layout));
  await writeFile(join(output, "heightfield.bin"), raster);
  console.log(`Tonsai ${width}×${depth} samples, ${g.TRAILS.length} trails, ${HIDING_CANDIDATES.length} candidates`);
}

await mkdir(output, {recursive: true});
try {
  await importLayout();
  for (const path of Object.keys(lock).filter(path => path.startsWith("assets/"))) {
    await writeFile(join(output, path.split("/").at(-1)), await source(path));
  }
} finally {
  await rm(temp, {recursive: true, force: true});
}
