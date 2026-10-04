import { createHash, createHmac } from "node:crypto";
import { cpSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const [version, repository, ref, signingKey, outputArg = "dist/release"] = process.argv.slice(2);
if (!version || !repository || !ref || !signingKey) {
  throw new Error("Usage: node tools/build-release.mjs <version> <repository> <ref> <signing key> [output]");
}

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const output = resolve(root, outputArg);
const includeRoots = ["cookieos"];
const includeFiles = [
  "cookieos-update.lua", "install.lua", "pair-node.lua", "recovery.lua", "startup-v3.lua",
];

function walk(directory) {
  const result = [];
  for (const name of readdirSync(directory)) {
    const path = join(directory, name);
    if (statSync(path).isDirectory()) result.push(...walk(path));
    else result.push(path);
  }
  return result;
}

const sources = [
  ...includeRoots.flatMap((name) => walk(join(root, name))),
  ...includeFiles.map((name) => join(root, name)),
];

function luaType(value) {
  if (typeof value === "string") return "string";
  if (typeof value === "number") return "number";
  if (typeof value === "boolean") return "boolean";
  return "table";
}

function canonical(value, seen = new Set()) {
  if (value === null || value === undefined) return "n";
  if (typeof value === "boolean") return value ? "b1" : "b0";
  if (typeof value === "number") return `d${value.toPrecision(17).replace(/\.0+(?=e|$)/, "")};`;
  if (typeof value === "string") return `s${Buffer.byteLength(value)}:${value}`;
  if (seen.has(value)) throw new Error("Cyclic manifest value");
  seen.add(value);
  const entries = Array.isArray(value)
    ? value.map((child, index) => [index + 1, child])
    : Object.entries(value);
  entries.sort(([a], [b]) => `${luaType(a)}:${a}`.localeCompare(`${luaType(b)}:${b}`));
  const encoded = `t${entries.length}:` + entries.map(([key, child]) => canonical(key, seen) + canonical(child, seen)).join("");
  seen.delete(value);
  return encoded;
}

rmSync(output, { recursive: true, force: true });
mkdirSync(join(output, "packages"), { recursive: true });
const files = sources.map((source) => {
  const path = relative(root, source).split(sep).join("/");
  const contents = readFileSync(source);
  const destination = join(output, "packages", path);
  mkdirSync(dirname(destination), { recursive: true });
  cpSync(source, destination);
  return {
    path: `/${path}`,
    source: `release/packages/${path}`,
    sha256: createHash("sha256").update(contents).digest("hex"),
  };
}).sort((a, b) => a.path.localeCompare(b.path));

const manifest = { version, repository, ref, files };
manifest.signature = createHmac("sha256", signingKey).update(canonical(manifest)).digest("hex");
writeFileSync(join(output, "manifest.json"), JSON.stringify(manifest, null, 2));

const installer = readFileSync(join(root, "install.lua"), "utf8").replace(
  'local EMBEDDED_RELEASE_KEY = "COOKIEOS_RELEASE_KEY_NOT_CONFIGURED"',
  `local EMBEDDED_RELEASE_KEY = ${JSON.stringify(signingKey)}`,
);
writeFileSync(join(output, "install.lua"), installer);
console.log(`Built CookieOS ${version}: ${files.length} files in ${output}`);
