"""Package a staged Tonsai export for a static host with a per-file size limit."""
import argparse
import gzip
import re
import shutil
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("build", type=Path)
parser.add_argument("dist", type=Path)
parser.add_argument("source_commit")
args = parser.parse_args()
if not re.fullmatch(r"[0-9a-f]{40}", args.source_commit):
    parser.error("source_commit must be the full source Git SHA")

files = (
    "index.js", "index.audio.worklet.js", "index.audio.position.worklet.js",
    "index.icon.png", "index.apple-touch-icon.png", "index.png",
)
args.dist.mkdir(parents=True, exist_ok=True)
for name in files:
    path = args.build / name
    if path.is_file():
        shutil.copyfile(path, args.dist / name)

bootstrap = """<script>
    // Serve the original engine and pack through a gzip stream on static hosts.
    const originalFetch = window.fetch.bind(window);
    const packed = new Map([
        [new URL("index.wasm", document.baseURI).href, ["application/wasm", WASM_SIZE]],
        [new URL("index.pck", document.baseURI).href, ["application/octet-stream", PACK_SIZE]],
    ]);
    window.fetch = async (resource, options) => {
        const url = new URL(resource instanceof Request ? resource.url : resource, document.baseURI);
        const entry = packed.get(url.href);
        if (!entry) return originalFetch(resource, options);
        const response = await originalFetch(url.href + ".gz", options);
        if (!response.ok) return response;
        return new Response(response.body.pipeThrough(new DecompressionStream("gzip")), {
            headers: {"Content-Type": entry[0], "Content-Length": entry[1]},
        });
    };
</script>
"""
for suffix, magic, placeholder in (
    ("wasm", b"\x00asm", "WASM_SIZE"),
    ("pck", b"GDPC", "PACK_SIZE"),
):
    payload = (args.build / f"index.{suffix}").read_bytes()
    assert payload.startswith(magic)
    compressed = gzip.compress(payload, compresslevel=6, mtime=0)
    assert len(compressed) < 25 * 1024 * 1024, suffix
    (args.dist / f"index.{suffix}.gz").write_bytes(compressed)
    bootstrap = bootstrap.replace(placeholder, str(len(payload)))

html = (args.build / "index.html").read_text()
assert re.search(r"GODOT_THREADS_ENABLED\s*=\s*false", html)
engine_script = '<script src="index.js"></script>'
assert html.count(engine_script) == 1
(args.dist / "index.html").write_text(html.replace(engine_script, bootstrap + engine_script))
(args.dist / "source-commit.txt").write_text(args.source_commit + "\n")
