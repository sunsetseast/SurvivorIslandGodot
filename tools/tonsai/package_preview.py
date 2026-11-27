"""Package a staged Tonsai export for a static host with a per-file size limit."""
import argparse
import gzip
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("build", type=Path)
parser.add_argument("dist", type=Path)
parser.add_argument("source_commit")
parser.add_argument("--require-private-brand", action="store_true",
                    default=os.environ.get("SURVIVOR_REQUIRE_PRIVATE_BRAND") == "1")
args = parser.parse_args()
if not re.fullmatch(r"[0-9a-f]{40}", args.source_commit):
    parser.error("source_commit must be the full source Git SHA")

# Mount the actual export in an empty working directory, so loose private files
# cannot conceal missing imports or pack inclusion. The packed build's marker
# also requires validation when the command-line switch was omitted.
godot = os.environ.get("GODOT_BIN") or shutil.which("godot") or str(
    Path(os.environ.get("XDG_BIN_HOME", Path.home() / ".local/bin")) / "godot-4.7.2")
report_path = (args.build / "private-brand-validation.json").resolve()
pack_path = (args.build / "index.pck").resolve()
command = [godot, "--headless", "--main-pack", str(pack_path), "--script",
           str(Path(__file__).with_name("verify_private_brand.gd").resolve()), "--",
           "--pack", str(pack_path), "--report", str(report_path)]
if args.require_private_brand:
    command.append("--required")
with tempfile.TemporaryDirectory(prefix="survivor-brand-probe-") as isolated:
    subprocess.run(command[:2] + ["--log-file", str(Path(isolated) / "probe.log")] + command[2:],
                   cwd=isolated, check=True)
brand_report = json.loads(report_path.read_text())
if brand_report["required"]:
    assert brand_report["source"] == args.source_commit and brand_report["passed"]

files = (
    "private-brand-validation.json",
    "index.js", "index.audio.worklet.js", "index.audio.position.worklet.js",
    "index.icon.png", "index.apple-touch-icon.png", "index.png",
    "third-party-notices.txt",
)
args.dist.mkdir(parents=True, exist_ok=True)
for name in files:
    path = args.build / name
    if path.is_file():
        shutil.copyfile(path, args.dist / name)

# Worklet module loads do not inherit the document's authenticated request
# headers. Fetch the unchanged module through the normal same-origin session,
# then instantiate those authorized bytes locally. The host ACL still protects
# every source request; no credentials or restricted bytes enter a public URL.
engine_path = args.dist / "index.js"
engine_script = engine_path.read_text()
for receiver in ("GodotAudio.ctx", "ctx"):
    original = f"{receiver}.audioWorklet.addModule(path)"
    assert engine_script.count(original) == 1, "Pinned Godot worklet loader changed"
    engine_script = engine_script.replace(
        original, f"window.survivorLoadAudioWorklet({receiver}.audioWorklet,path)")
engine_path.write_text(engine_script)

bootstrap = """<script>
    // Serve the original engine and pack through a gzip stream on static hosts.
    const originalFetch = window.fetch.bind(window);
    window.survivorLoadAudioWorklet = async (worklet, path) => {
        const url = new URL(path, document.baseURI);
        if (url.origin !== location.origin) throw new Error("Unexpected worklet origin");
        const response = await originalFetch(url, {credentials: "same-origin"});
        if (!response.ok) throw new Error("Audio module download failed: " + response.status);
        const module = URL.createObjectURL(new Blob([await response.arrayBuffer()], {
            type: "application/javascript",
        }));
        try { await worklet.addModule(module); }
        finally { URL.revokeObjectURL(module); }
    };
    const packed = new Map([
        [new URL("index.wasm", document.baseURI).href, ["application/wasm", WASM_SIZE, WASM_PARTS]],
        [new URL("index.pck", document.baseURI).href, ["application/octet-stream", PACK_SIZE, PACK_PARTS]],
    ]);
    window.fetch = async (resource, options) => {
        const url = new URL(resource instanceof Request ? resource.url : resource, document.baseURI);
        const entry = packed.get(url.href);
        if (!entry) return originalFetch(resource, options);
        // Stream consecutive bounded parts; never buffer the complete pack twice.
        let part = 0;
        let reader = null;
        const compressed = new ReadableStream({
            async pull(controller) {
                while (part < entry[2].length) {
                    if (!reader) {
                        const response = await originalFetch(new URL(entry[2][part], document.baseURI), options);
                        if (!response.ok) throw new Error("Preview download failed: " + response.status);
                        reader = response.body.getReader();
                    }
                    const chunk = await reader.read();
                    if (!chunk.done) { controller.enqueue(chunk.value); return; }
                    reader.releaseLock();
                    reader = null;
                    part++;
                }
                controller.close();
            },
            async cancel(reason) { if (reader) await reader.cancel(reason); },
        });
        return new Response(compressed.pipeThrough(new DecompressionStream("gzip")), {
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
    part_size = 20 * 1024 * 1024
    parts = []
    for offset in range(0, len(compressed), part_size):
        name = f"index.{suffix}.gz" if len(compressed) <= part_size else f"index.{suffix}.gz.{len(parts):03d}"
        (args.dist / name).write_bytes(compressed[offset:offset + part_size])
        parts.append(name)
    assert gzip.decompress(b"".join((args.dist / name).read_bytes() for name in parts)) == payload
    bootstrap = bootstrap.replace(placeholder, str(len(payload)))
    bootstrap = bootstrap.replace(placeholder.replace("SIZE", "PARTS"), json.dumps(parts))
    print(f"{suffix}: {len(payload):,} bytes, {len(parts)} compressed part(s), exact reconstruction verified")

html = (args.build / "index.html").read_text()
assert re.search(r"GODOT_THREADS_ENABLED\s*=\s*false", html)
engine_script = '<script src="index.js"></script>'
assert html.count(engine_script) == 1
(args.dist / "index.html").write_text(html.replace(engine_script, bootstrap + engine_script))
(args.dist / "source-commit.txt").write_text(args.source_commit + "\n")
