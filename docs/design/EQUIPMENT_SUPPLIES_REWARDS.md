# Equipment, supplies and rewards
## Confirmed direction
Every contestant has an invisible permanent personal canteen; no theft, equipment slot or requirement to secure it on ship. Every tribe gets one guaranteed machete and cooking pot, independent of competitive loot. Shared gear can be reserved/borrowed by one eligible tribe member at a time per unit. Resource baskets increase collection capacity; hand tools accelerate construction; rope is consumed for structural bonus, bamboo for frame/platform and palm fronds for roofing. Firewood is fuel. Additional cooking pots increase concurrent cooking capacity. Cooking spit is a portable kit/two forked posts and crossbar for roasting; assembled spit and possible improvised version are future construction/cooking objects. No handlines, rods or generic fishing kits in revised catalog. Net is basic, sling is advanced. Snorkeling mask, snorkel and fins are one wearable set, never split. No competitive water containers or metal cups; no beans; tarp, blankets and flint belong to reward pool. Do not implement all functions at once.

## Deferred 50-item competitive catalog (proposed counts)
| Type | Count | Purpose |
|---|---:|---|
| Rice sacks | 3 | Cooking |
| Cooking pots | 3 | Extra capacity |
| Cooking spit kits | 3 | Roasting |
| Cast nets | 2 | Shallow area fishing |
| Hand tool kits | 2 | Construction efficiency |
| Rope bundles | 6 | Structural bonus |
| Bamboo bundles | 6 | Shelter |
| Coconut bundles | 6 | Food and modest hydration |
| Fruit baskets | 4 | Food |
| Firewood bundles | 6 | Fuel |
| Resource baskets | 4 | Carrying capacity |
| Palm frond bundles | 5 | Roofing |
| Total | 50 | |

Exclusive offshore reward: one Hawaiian sling. Counts are proposed tuning, not authorized catalog replacement during 5B.1. Future reward options: flint, tarps, blankets, hammocks, snorkeling set, additional food and cookware, other luxuries. No automatic flint. Need friction firemaking fallback. Nets may catch nothing; sling needs actual aim/hit. No gear means no conventional fishing, but shore foraging remains possible.

## Compatibility and ownership
Old marooning uses 50 original instance IDs (including water, cups, fishing kit, tarp, blanket, machetes) and offshore_fishing_reward. Preserve immutable original records, definitions and all earned supplies. Do not reinterpret an old fishing kit/reward as a functional new item without a future explicit versioned migration. New starting gear is separate from earned supplies and granted once per tribe. Legacy stored water remains finite reserve, not a source of infinite water; see 5B.1. No future catalog edits in 5B.1. Personal canteens separate from stock/hydration. Shared reusable gear stays in canonical stock with unit-level reservation ownership; no consumption or duplication on borrow/return. A reservation is not proof of an item held or consumed; require valid action/site/actor. No arbitrary user-created inventory or cross-tribal transfer. Keep original opening provenance distinct from dynamic stock.

Future 4D.5 HUD: reward available, own/rival claimed (name), expired; persistent objective/distance and one-time clear event, physical removal after claim; internally claim/secure/deliver distinct. Current race.gd auto-targets platform until claim or 150 active seconds then routes to shore. Preserve automatic steering; existing paddle mechanic controls propulsion. No change now.
