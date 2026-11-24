# Maeve · source and export

The public study is an original character with short auburn hair, a green jersey, denim and trail shoes. The editable file contains original study choices and licensed source geometry and textures. A private likeness production gate remains separate.

[Download the editable Blender archive](Maeve-Blender-Source.zip) · [Runtime GLB](../../character_lab/assets/maeve.glb)

## Input records

| Input | Pin and license | Shipped use |
| --- | --- | --- |
| Blender | 4.3.2. [Blender downloads](https://www.blender.org/download/) | Headless fitting, animation bake and glTF export |
| MPFB2 | `2c6e38785e2e90b0d77ed8b988a4a41c4cdd6271` (`v2.0.14`). GPL tool, CC0 data. [MPFB license record](https://github.com/makehumancommunity/mpfb2/blob/2c6e38785e2e90b0d77ed8b988a4a41c4cdd6271/LICENSE.md) | Human base topology, face and body morph targets, game-engine rig and body weights |
| MakeHuman system assets | `makehuman_system_assets_cc0.zip`, SHA-256 `b542127a8e25547c7c29c19f2d1d2adb9a664c80396ecd694095dbc8028a0107`. CC0. [System asset pack](https://www.makehumancommunity.org/assets/assetpacks/makehuman_system_assets.html) | Fitted `bob01`, `eyebrow001`, `eyelashes01`, low-poly eyes, brown-light iris, middle-age light skin, `female_casualsuit01` and `shoes02`. Jersey re-dyed and unbranded. |
| Quaternius UAL 1 | Godot Store Standard release, SHA-256 `18ff1a7215f4852b320203e8aaf02a1578b5c8eef9027fbaedfcedc7b85a3ac2`. CC0. [Publisher and Godot download](https://store.godotengine.org/asset/quaternius/universal-animation-library/) | `Idle_Loop`, `Walk_Loop`, `Jog_Fwd_Loop`, `Idle_Talking_Loop`, `Sitting_Enter`, `Sitting_Idle_Loop`, `Sitting_Exit`. Only retargeted animation is included. |
| Blender Studio Human Base Meshes | 1.4.1, SHA-256 `811f43accbb31a88266d932f8f5563b2d13586fca0ba2693aad1f5fe582b3515`. CC0. [Blender Studio bundle](https://www.blender.org/download/demo-files/#assets) | Neutral comparison render only |
| Phase 1 authored work | Facial target recipe, hair and shoe edits, jersey dye and chest tab, retargeting and lab | Original work created for this project |

## Regenerate the asset

Install the pinned MPFB add-on in Blender’s **User Default** extension repository. For Linux Blender 4.3, a checkout’s `src/mpfb` directory can be symlinked to `~/.config/blender/4.3/extensions/user_default/mpfb`. Use **Edit → Preferences → Get Extensions** to find the active User Default path on another desktop. Extract the CC0 system pack and the Godot Standard library. Then run:

```bash
blender -b --factory-startup --python-exit-code 1 \
  --python character_lab/tools/build_maeve.py -- \
  --system-assets /path/to/extracted-system-pack \
  --motions /path/to/AnimationLibrary_Godot_Standard.glb \
  --glb build/maeve-raw.glb --blend build/Maeve.blend
python3 -m pip install Pillow
python3 character_lab/tools/pack_glb.py build/maeve-raw.glb character_lab/assets/maeve.glb
python3 character_lab/tools/validate_glb.py character_lab/assets/maeve.glb
```

The checked-in GLB has SHA-256 `2718195be83289f434c209a1373b0a3ae2e4ea114f16b741919262a1ed8964d8`. The script rebuilds the asset structure and the editable source. Blender and image encoder builds may differ in binary serialization.

The rig uses meters and the fitted MakeHuman game-engine A rest pose. In Blender it faces −Y with Z up. The GLB arrives in Godot facing +Z with Y up, rooted at the floor. The Blender bake matches Quaternius’s T-rest anatomical axes to the fitted arms, legs and fingers. It copies pose rotations into the corresponding target bone bases and scales pelvis translation. The donor’s rig and mesh are removed after baking. Godot loads this one authored skeleton and uses the imported AnimationPlayer library through an AnimationTree. Locomotion is in place and a CharacterBody3D supplies translation. The Smile morph is driven independently of the skeletal blend.

Keep the anatomical naming, orientation, artist-facing Blender source, material slots and clip API across the cast. Per character, sculpt primary shape and asymmetry, author skin and groom, fit garment construction, transfer and correct weights, and retest hand, shoulder, hip and knee poses. Run a close-up and gameplay-scale visual review before profiling a group. Clip compatibility can be shared. Achieving a recognizable identity still requires individual art direction and geometry.

## Rebuild the lab

```bash
bash ci/install-godot-web.sh
bash ci/build-character-lab.sh
python3 -m pip install playwright==1.62.0
python3 -m playwright install --with-deps chromium --only-shell
python3 character_lab/tools/review_web.py build/character-lab build/character-lab-captures
```

Open `character_lab/lab.tscn` as the current scene in Godot for native inspection. Use `?review` on the exported scene to enable deterministic screenshot controls for the browser harness.
