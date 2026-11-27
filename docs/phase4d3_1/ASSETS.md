# Supply artwork audit and provenance

All 15 categories are original metre-scale meshes authored in supply_visual.gd.
The source mesh and shader files are the provenance; no external generated model,
show artwork or paid asset is imported. Natural fabric/fibre/grain shaders are
original procedural materials, requiring no texture downloads. Geometry is cached
per category and merged by material; subsequent instances share mesh/materials.
Per-type dimensions replace universal 0.65m normalization. Ground pivots are local
floor level; carry grips use the existing hand_r bone attachment with per-type grip transforms. Before/after native
contact sheets at identical scale/camera are private evidence, distinct from gameplay.

Research leads inspected:

- Poly Haven wicker_basket_01: CC0 listing, woven geometry/material reference;
  source ~22k triangles. Public metadata/download API requests returned 403 here;
  no restriction was bypassed and no file imported.
- Poly Haven pot_enamel_01: CC0, ~11k triangles; decorative flame finish is a poor
  fit for the intended neutral cookware. Not imported.
- Poly Haven hessian_380: CC0 burlap reference; API returned 403. Not imported.
- Poly Haven wooden_crate_02: CC0, James Ray Cock/Jurita Burger, ~5k triangles;
  maritime wood reference, not a needed collectible category. Not imported.
- 3dassets.dev wipe-day-survival-island-machete-07664857: listing describes a .87m
  tool and advertises CC0. Provenance/geometry not independently downloaded and
  verified. Not imported; the replacement is original tapered, swept blade geometry.
- Sketchfab bamboo, fishing-net and coconut leads in the owner brief all returned
  403. Exact downloads/attribution not verified; none imported.
- ambientCG Bamboo001A: procedural 1.3m material, downloadable 1K JPG listed;
  original nodes/cut ends and shared procedural material better suit these bundles.
  Not imported.

Poly Haven license: https://polyhaven.com/license. Candidate URLs are retained in
the owner's implementation brief. No new attribution/redistribution obligations
arise from candidates that were not imported. Existing ship/character/environment
asset notices remain applicable and unchanged.

The six unused legacy supply GLBs were removed from runtime source. Their historical
license/provenance files are retained for the before/after audit. The replacement
steel blade and hollow vessel surfaces are explicitly indexed before mesh merging;
actual rendering caught missing non-indexed surfaces during development.

## Evaluated candidate URLs

- https://polyhaven.com/a/wicker_basket_01
- https://polyhaven.com/a/pot_enamel_01
- https://polyhaven.com/a/hessian_380
- https://3dassets.dev/assets/wipe-day-survival-island-machete-07664857
- https://sketchfab.com/3d-models/free-bamboo-set-e9f9fa5397814f81bf85ad06acf5bf30
- https://sketchfab.com/3d-models/fishing-net-cbb4bfc4e5654500a70dfe72ffc0ce0a
- https://sketchfab.com/3d-models/low-poly-coconut-1-442192db87e94268a69887540744a155
- https://ambientcg.com/view?id=Bamboo001A
- https://polyhaven.com/a/wooden_crate_02

## Final source and runtime geometry

- `marooning/supply_visual.gd` SHA-256: `6166b3ab1e0de357e96f6885dca784aed1ea0c1b016429eede8966a531cfc162`.
- `marooning/prop_surface.gdshader` SHA-256: `4ad6e20f55473ab9557263bd77e9190d60402be317355d662fa6307780cc6e9c`.
- `marooning/collection_station.gd` SHA-256: `7ba256ed1fc5bf17da46d8615d4763a3429fff21bc300cba4a122fda2738908b`.

| Category | Metre bounds XYZ | Triangles | Material surfaces |
| --- | --- | ---: | ---: |
| bamboo | (0.39857, 0.23312, 1.319) | 3816 | 4 |
| basket | (0.560785, 0.377, 0.556) | 6312 | 3 |
| blanket | (0.680785, 0.296, 0.296) | 1224 | 3 |
| coconut | (0.666506, 0.437, 0.340329) | 1872 | 3 |
| cup | (0.177928, 0.245588, 0.172) | 2520 | 1 |
| fishing | (0.61, 0.09, 0.42) | 2232 | 2 |
| fruit | (0.560785, 0.44, 0.556) | 8328 | 4 |
| machete | (0.135, 0.065, 0.9) | 240 | 2 |
| pot | (0.604249, 0.279, 0.536) | 1128 | 1 |
| rice | (0.393923, 0.54, 0.541644) | 864 | 2 |
| rope | (0.53, 0.115981, 0.38) | 1800 | 1 |
| tarp | (0.680785, 0.296, 0.296) | 1224 | 3 |
| tools | (0.359088, 0.185, 0.563481) | 864 | 3 |
| water | (0.344683, 0.53, 0.295442) | 648 | 3 |
| wood | (0.377606, 0.23312, 0.65686) | 996 | 3 |
