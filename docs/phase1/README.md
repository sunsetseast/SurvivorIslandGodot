# Phase 1 · Character laboratory

**Gate result: INCOMPLETE.** Maeve is an original adult character with a continuous body mesh, fitted garments, a weighted humanoid rig, facial morph, and seven motion clips. The lab validates the Blender-to-Godot route and browser controls. The close-up finish falls short of the stylized-realistic art target. Cast production should wait.

## Inspect the build

The **Godot Character Lab** workflow builds a single-threaded Web export and creates the `survivor-island-character-lab-web` artifact. The capture job uses Chromium software WebGL and publishes the images and raw metrics. The Phase 0 entry point and main-branch Pages workflow still target the feasibility beach. GitHub permits one Pages site per repository, so the draft uses a separate artifact. [GitHub Pages site limits](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages#types-of-github-pages-sites)

On a computer with Python, extract the Web artifact and run `python3 -m http.server 8000 --bind 0.0.0.0` from its directory. On an iPhone connected to the same network, open that computer’s LAN address with port 8000 in Safari. Disable portrait orientation lock and rotate sideways. **This draft has no hosted lab URL.** The Web ZIP is a set of website files and requires an HTTP host.

1. Open **Face** and cycle **Rotate** through the front, three-quarter, profile, and rear. Compare **Smile** and **Warm light**.
2. In **Body**, test **Walk**, **Jog**, **Talk**, **Sit**, then **Stand**. Check foot contact, hands, and the shirt at the shoulder bend.
3. In **Explore**, drag a left thumb over open space to move and a right thumb over open space to orbit. Tap **Run toggle** for the jog. With desktop input, use WASD and Shift.
4. Cycle **1 rig → 6 rigs → 18 rigs** in **Body**. These are copies of Maeve. Record startup time, displayed FPS and draw counts, and any hitching after two minutes. Test rotating the phone and switching away and back.

## Visual evidence

The first three sheets use captures from the Godot 4.7.2 Compatibility Web export. The pipeline comparison includes neutral Blender renders of both source bases. These images show what the actual geometry and lighting produced.

[Portraits and expression](maeve-portraits.jpg) · [Body angles and motion](maeve-body-motion.jpg) · [Gameplay and load presets](maeve-web-lab.jpg) · [Blender base comparison](pipeline-comparison.jpg)

| Area | Observation | Gate |
| --- | --- | --- |
| Face | The longer chin, convex bridge, asymmetrical cheek volume, and lower-lid shaping read in profile. The front still has a smooth, stock-looking orbital transition. Masked lashes break into dark pixels at the lower lid and the fringe crosses an eyebrow. | Below target |
| Anatomy | Compact adult proportions and a visibly articulated elbow, forearm, and hand improve on the rigid-piece prototype. The idle has a fairly wide stance and its shoulder posture repeats a donor pose. | Prototype |
| Hair | Copper variation and directional strands read at gameplay scale. The two big fringe shells look like a stiff wig in profile. The scalp transition, hairline edges, and wispy perimeter need authored grooming. | Below target |
| Clothing | The jersey and jeans use fitted geometry and the chest tab follows the garment under motion. Shortening the shoe cuffs removed the most visible sock-through-denim intersections. Sleeve hems and the collar still read too thin at close range. | Prototype |
| Skin | Baked color and matte PBR make the face readable in both light presets. The broad cheek highlight and uniform roughness flatten skin detail, and the model needs more local color and roughness authoring. | Below target |
| Motion | The seated pose reaches the block and the rig visibly articulates on walks and jogs. The clips blend and fingers curl with the donor. Terrain-aware foot locking, gait calibration at partial stick, lip sync, and sustained pose-intersection review are still open. | Prototype |

## Pipeline decision

Use **MPFB2 for base topology, proportion controls and fitted weights**, **Blender for identity sculpt, grooming, garments and corrective deformation**, and **Quaternius Standard as the initial motion donor**. Bake to each character’s actual rig. Better results require time on the face, groom and costume before testing a cast batch.

| Candidate | Evidence | Decision |
| --- | --- | --- |
| MakeHuman / MPFB2 | Local Blender 4.3.2 automation made a body with UVs, shaped phenotype and region targets. Maeve uses the game-engine rig and transferred garment weights. The comparison sheet shows a default MPFB face from the same body preset. | Repeatable foundation. Use corrective sculpting beyond the sliders. |
| Blender Studio Human Base Meshes 1.4.1 | Opened the CC0 bundle and rendered the female realistic base. The mesh has 10,582 base vertices, a sculptable profile and separate eyes. The examined collection has no armature, transferred garment weights or production material pass. | Keep as sculpt reference or a foundation for a manually retopologized specialist character. |
| Blender modeling | Fitted and shaped the mesh from independent cheek, bridge, orbital, chin and forehead targets. Fitted jersey, jeans and trail shoes, altered the groom, created a weighted chest tab, and preserved a smile shape. | Useful for controlled refinement. Use hand-sculpted planes, eyelid and lip cleanup, layered groom cards and garment thickness for the next art gate. |
| Quaternius Universal Animation Library 1 | Inspected the 46 animations actually present in the free Godot Standard GLB. Baked seven idle, walk, jog, talk, and seating clips onto Maeve. | Covers the current lab. |
| Quaternius Universal Animation Library 2 | Publisher’s free Standard listing complements locomotion with traversal and task motions. No Series 2 motion was baked into Maeve. | Evaluate when specific interaction animations are needed. |
| Mixamo | Adobe offers free access with an Adobe ID. The service requires sign-in and a hosted workflow. | Optional fallback for missing animations. The build has no dependency on it. |
| Old Three.js pipeline | Read both earlier repositories and the 3D art bible, Blender progress, cast pilot, and character rebuild. The old binder copied skin weights to modified geometry, and the runtime adjusted cadence and sampled toes. The audit documented generic orbital planes, uniform hair strips, flat skin and clothing, and deformation gaps. | Reuse the contact and cadence tests, matching studio views, and stable naming conventions. Rebuild runtime animation and import settings for Godot. |

[Blender Studio CC0 bundle](https://www.blender.org/download/demo-files/#assets) · [MPFB2 and MakeHuman overview](https://download.makehumancommunity.org/mpfb/faq/differences_between_mpfb2_and_makehuman.html) · [Quaternius 1 Standard](https://store.godotengine.org/asset/quaternius/universal-animation-library/) · [Quaternius 2](https://quaternius.itch.io/universal-animation-library-2) · [Mixamo FAQ](https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html) · [Previous model audit](https://github.com/sunsetseast/SurvivorIsland3Dprototype/blob/708a21c43b4b2969aa28bf2142005e4f5df0bcdf/docs/character-art-bible/MODEL_AUDIT.md)

## Measured scope

| Item | Value |
| --- | --- |
| Character GLB | 30,148 triangles, 10 material primitives, 53 joints, 9 images, 7 clips, 1 smile morph, approximately 2.0 MiB |
| Images | 256–1,024 px, including a 768 px masked groom. About 18.7 MiB if decoded to RGBA8 with a full mip chain, shared across instances where the driver permits |
| Animation cost | Per-actor skeleton and state tree. Approximate upper bound of 954 joint poses for 18 rigs per update. Separate animation CPU timing has not been measured |
| Web page files | WASM 39.5 MB, PCK about 3.63 MB, loader about 280 KB. ZIP transfer size is smaller |
| Phase 0 baseline | `191e5c6e8c636c892c6fee4dab7d203b744658a8`, Godot `4.7.2.stable.official.ed1daf0bf`, successful headless import, smoke and single-threaded export. [Phase 0 Actions run](https://github.com/sunsetseast/SurvivorIslandGodot/actions/runs/45284571005) · [Phase 0 Pages](https://sunsetseast.github.io/SurvivorIslandGodot/) |
| Physical iPhone Safari | Pending. Software-rendered Chromium measurements are useful for checking scene behavior and submissions. The 60 FPS target still requires device evidence |

A local HTTP startup took **2.96 s** in Chromium 149 with software WebGL 2. These are medians of six live HUD samples per preset in the 956 × 440 landscape viewport. Renderer totals include the stage. Frame-rate samples fluctuated on the software renderer and should not be used as a hardware scaling curve.

| Active rigs | FPS | Draws | Submitted primitives |
| ---: | ---: | ---: | ---: |
| 1 | 20 | 56 | 18,752 |
| 6 | 23 | 107 | 54,170 |
| 18 | 10.5 | 227 | 148,880 |

Chromium passed startup, the three touch-selected load presets, simultaneous move and orbit, and return to idle after touch release. The Godot headless test independently passed clean import, seven clip states, actual shin motion, sitting and standing transitions, smile, movement and camera follow. [Raw browser metrics](browser-metrics.json)

The older production meshes used roughly 9,000–23,000 triangles. Maeve exceeds that range. Test the current model on the phone before setting a shipping budget. If the group view requires reduction, start with overlapping hair cards and fully covered body geometry and preserve the face and hair silhouette.

[Rebuild and asset provenance](PIPELINE.md)
