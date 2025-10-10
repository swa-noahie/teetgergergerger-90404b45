const fs = require("fs");
const path = require("path");

const srcDir = __dirname;
const distDir = path.join(srcDir, "dist");
const srcFile = path.join(srcDir, "index.html");
const destFile = path.join(distDir, "index.html");

if (!fs.existsSync(srcFile)) {
  console.error("Source index.html not found. Build aborted.");
  process.exit(1);
}

const providedApi = (process.env.API_BASE_URL || "").trim();
const apiBase = providedApi ? providedApi.replace(/\/+$/, "") : "__API_BASE__";

const html = fs.readFileSync(srcFile, "utf8").replace(/__API_BASE__/g, apiBase);

fs.rmSync(distDir, { recursive: true, force: true });
fs.mkdirSync(distDir, { recursive: true });
fs.writeFileSync(destFile, html, "utf8");

console.log(`API base injected as: ${apiBase || "[placeholder]"}`);
console.log(`Generated dist/index.html`);