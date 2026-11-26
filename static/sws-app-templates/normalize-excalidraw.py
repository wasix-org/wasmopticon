import json
import re
import sys
from pathlib import Path


def configure_build():
    recipe = Path("scripts/build.mjs")
    text = recipe.read_text()
    anchor = "// Direct Vite invocation avoids upstream's script forcing tracking back on."
    if text.count(anchor) != 1:
        raise ValueError("Expected one Vite build in the Excalidraw template")
    patch = """
// Pass through the ESNext TypeScript class-field default explicitly to Vite.
const viteConfig = join(source, 'excalidraw-app/vite.config.mts');
const viteSource = await readFile(viteConfig, 'utf8');
await writeFile(viteConfig, replaceOnce(viteSource, '    build: {',
  '    esbuild: { tsconfigRaw: { compilerOptions: { useDefineForClassFields: true } } },\\n    build: {'));
"""
    recipe.write_text(text.replace(anchor, patch + anchor))


def normalize_export(site):
    sitemap = site / "sitemap.xml"
    normalized, count = re.subn(
        r"<lastmod>[^<]+</lastmod>",
        "<lastmod>2000-01-01T00:00:00.000Z</lastmod>",
        sitemap.read_text(),
    )
    if count != 1:
        raise ValueError("Expected one generated Excalidraw sitemap timestamp")
    sitemap.write_text(normalized)

    source_map = site / "sw.js.map"
    metadata = json.loads(source_map.read_text())
    sources = metadata["sources"]
    if len(sources) != 1 or not re.search(r"(?:^|/)[0-9a-f]{32}/sw\.js$", sources[0]):
        raise ValueError("Expected a Workbox temporary path in the service-worker source map")
    metadata["sources"] = ["sw.js"]
    source_map.write_text(json.dumps(metadata, separators=(",", ":"), ensure_ascii=False) + "\n")


if sys.argv[1] == "--configure-build":
    configure_build()
else:
    normalize_export(Path(sys.argv[1]))
