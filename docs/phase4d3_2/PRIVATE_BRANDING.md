# Owner-private presentation validation

The hosted presentation regression was incomplete private staging, not a removed
theme. `SURVIVOR_PRIVATE_UI` and `SURVIVOR_PRIVATE_LOGO` were unset; the retained
stage contained only Survivant.ttf and one button texture. A probe of the actual
old export loaded those two resources but found nine required resources absent:
logo, alternate button, both parchment textures and five tribe banners. The
existing resource loader therefore displayed its intentional public fallbacks.

Restore using `tools/tonsai/stage_private_ui.py` and the existing approved private
asset directory. Preserve its original artwork and import/export behavior. The
complete approved set has eleven resources; no restricted bytes belong in Git or
public Actions artifacts. Native review confirmed the original logo, Survivant,
carved buttons, parchment and tribe artwork across home, settings, selection,
season and tribe setup at 956×440 and tribe review at 812×375. Long roster lists
retain their existing scrolling; primary setup controls remain accessible.

`ci/build-tonsai.sh` marks stages using `SURVIVOR_PRIVATE_UI` (or explicit
`SURVIVOR_REQUIRE_PRIVATE_BRAND=1`) as requiring the complete presentation. After
export, package the owner-private build with:

```sh
python3 tools/tonsai/package_preview.py BUILD DIST FULL_SOURCE_SHA --require-private-brand
```

The packager mounts the actual exported PCK in an empty working directory and
runs `verify_private_brand.gd` with Godot. The packed requirement also applies if
the switch is omitted. Every required texture must load with positive dimensions;
the font must contain data, measure text and identify as Survivant. A required
build fails packaging if resources or the source marker are wrong. The protected
`private-brand-validation.json` binds the result to the source and raw pack hash.
This is a resource-load guard, not visual or device certification. Public builds
without the private requirement retain the intentional fallback interface.

Validation: the previous partial export was rejected with nine missing resources;
the restored export passed all eleven loads. Focused menu captures and the final
hosted delivery record are available in the owner-private evidence Page linked
from VALIDATION.md. No artwork was regenerated or committed.
