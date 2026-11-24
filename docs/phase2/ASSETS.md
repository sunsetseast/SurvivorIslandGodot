# Phase 2.2 asset sources

Runtime assets are in `world/assets`. The export starts from an allowlisted
staging directory and includes only the existing public character rig.

| Asset | License and reproducible inputs |
| --- | --- |
| Swim and tread motion | CC0. [Quaternius Universal Animation Library](https://quaternius.itch.io/universal-animation-library), [Godot Standard ZIP](https://store.godotengine.org/asset/quaternius/universal-animation-library/download/44/), SHA-256 `18ff1a7215f4852b320203e8aaf02a1578b5c8eef9027fbaedfcedc7b85a3ac2`. Verified the in-place `Swim_Fwd_Loop` and `Swim_Idle_Loop` in the Godot GLB. [KinemIQ stroke](https://kinemiq.app/animations/move-swimming/) and [tread](https://kinemiq.app/animations/idle-in-water/) list the same CC0 origin. |
| Ocean | CC0. [GodotLearning Stylized Water](https://godotlearning.com/shaders/stylized-water), [ZIP](https://godotlearning.com/library/stylized-water/stylized-water.zip), SHA-256 `3aa13862466a27624e64d9f10795410adf5d8f9adb366faa7deb61f8df8bffe7`. Extract `water_normal_a.png` as `water-ripple.png`. The adapted shader retains the Compatibility depth reconstruction and omits vertex waves and screen refraction. |
| Sky | CC0. [Sunflowers Pure Sky](https://polyhaven.com/a/sunflowers_puresky) [2K HDR](https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/2k/sunflowers_puresky_2k.hdr), SHA-256 `430861cb722951c1eeff3b3c5762e7e73a610fcffc4186b5d828c5e7557fe1b4`. Evaluated [Kloppenheim 05](https://polyhaven.com/a/kloppenheim_05_puresky) at the same resolution. Sunflowers gives the sea-facing view a more varied cloud field. |
| Campfire log and stump | CC0. [Dead Tree Trunk 02](https://polyhaven.com/a/dead_tree_trunk_02) and [Tree Stump 01](https://polyhaven.com/a/tree_stump_01). |
| Stones and bucket | CC0. [Coast Land Rocks 03](https://polyhaven.com/a/coast_land_rocks_03) and [Wooden Bucket 01](https://polyhaven.com/a/wooden_bucket_01) from [The Smuggler’s Cove](https://polyhaven.com/collections/smugglers_cove). |
| Well layout | The stone ring and covered rope-and-bucket silhouette follow the [SurvivorIsland2025 reference image](https://github.com/sunsetseast/SurvivorIsland2025/blob/main/Assets/Screens/water-well.png). The image is a reference only. |

For each prop, use `https://api.polyhaven.com/files/<slug>` and the
`gltf → 1k → gltf` entry. Verify the entry and companion BIN and diffuse JPEG
against their API MD5s. Save the glTF as `<slug>/<slug>.gltf` and keep the
companion paths specified by the API. Run Blender 4.3.2 with
`--python tools/tonsai/prepare_props.py -- <input-root> <output-directory>`.
The script normalizes placement, caps triangle counts, and uses a single
512 px diffuse texture per prop. The existing Island Tree 02 and ferns remain
in the camp. Island Tree 03 adds several texture sets and was left out.

For the panorama, run `convert sunflowers_puresky_2k.hdr -evaluate multiply 0.82
-colorspace sRGB -sampling-factor 4:2:0 -quality 86 sunflowers-sky.jpg`.
The sky is a 2K display image. Camp lighting is set independently.

To regenerate the motion, open the Phase 1 `Maeve.blend` in headless Blender
and run `character_lab/tools/bake_water_motion.py` with the source and output
GLB paths after `--`. Import the resulting GLB and the existing public
`maeve.glb` in a temporary Godot project. Run
`character_lab/tools/extract_water_motion.gd` with the two GLB resource
paths and the destination `surface-swimming.res`. Only the two retargeted
sets of animation tracks ship in the new resource.

The reference prototype and its checksums for the cliff shell, foliage,
terrain and landmark layout are in `tools/tonsai/inputs.json` and
`tools/tonsai/prepare.mjs`.
