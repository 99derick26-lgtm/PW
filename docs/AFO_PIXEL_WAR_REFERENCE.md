# AFO to Pixel War Reference

Note: this file is reference material only.
It must not override `docs/PW locked rules.txt` or `docs/PW summary.txt`.
Current Pixel War pet scaling, guild rules, combat layout, and server ownership rules live in those two files.

This file preserves the AFO source mappings used for Pixel War combat tuning.

## Pet Counterparts

| AFO Pet | Pixel War Pet | Status |
| --- | --- | --- |
| Raccoon | Cat | Confirmed |
| Spider | Capybara | Confirmed |
| Dog | Dog | Confirmed |
| Angry Ostrich | Parrot | Confirmed |
| Cheetah | Cheetah | Confirmed |
| Panda | Panda | Confirmed |
| Brown Bear | Horse | Confirmed |
| Cat Boxer | Wasp | Confirmed |
| Triceratops | Turtle | Confirmed |
| Scorpion | Raccoon | Confirmed |
| Snake | Snake | Confirmed |
| Rhino | Rhino | Confirmed |
| Stegosaur | Guar | Confirmed |
| Green Dragon | Hippo | Confirmed |
| Red Dragon | Tiger | Confirmed |
| T. Rex / Dino Rex | Alligator | Confirmed |
| Werewolf | Polar Bear | Confirmed |
| Blue Dragon | Elephant | Confirmed |
| Hydra | Unmapped | AFO sheet includes Hydra; no Pixel War counterpart provided yet |

## AFO Pet Base Stats

| AFO Pet | Health | Strength | Agility | Speed | Level |
| --- | ---: | ---: | ---: | ---: | ---: |
| Raccoon | 30 | 20 | 40 | 80 | 3 |
| Spider | 80 | 100 | 60 | 100 | 7 |
| Dog | 50 | 40 | 60 | 60 | 8 |
| Angry Ostrich | 100 | 80 | 90 | 90 | 9 |
| Cheetah | 80 | 80 | 80 | 110 | 10 |
| Panda | 120 | 80 | 50 | 60 | 10 |
| Brown Bear | 100 | 100 | 90 | 60 | 12 |
| Cat Boxer | 70 | 60 | 80 | 250 | 13 |
| Triceratops | 120 | 120 | 70 | 70 | 14 |
| Scorpion | 90 | 120 | 70 | 100 | 14 |
| Snake | 100 | 150 | 70 | 100 | 14 |
| Rhino | 150 | 150 | 90 | 100 | 15 |
| Stegosaur | 200 | 200 | 70 | 60 | 16 |
| Green Dragon | 120 | 200 | 100 | 100 | 18 |
| Red Dragon | 100 | 150 | 100 | 150 | 24 |
| Dino Rex | 250 | 250 | 70 | 70 | 26 |
| Werewolf | 120 | 150 | 100 | 200 | 26 |
| Blue Dragon | 200 | 200 | 120 | 120 | 28 |
| Hydra | 150 | 130 | 110 | 130 | 30 |

## Weapon Counterparts

| AFO Weapon | Pixel War Weapon | Status |
| --- | --- | --- |
| Dagger | dagger | Confirmed |
| Short Sword | short_sword | Confirmed |
| Heavy Stick | crowbar | Confirmed |
| Sword | sword | Needs Pixel War item check |
| Spear | extending_spear | Confirmed |
| Machete | machette | Confirmed |
| Samurai Sword | katana_speed | Confirmed |
| Trident | scrap_trident | Confirmed |
| Bow | scrap_gun | Confirmed |
| Axe | heavy_axe / axe | Needs Pixel War item check |
| Stone Hammer | stone_hammer | Confirmed |
| Sickle | monosickle | Confirmed |
| Spike Club | pipecrusher | Confirmed |
| Heavy Sword | heavy_sword | Confirmed |
| Ice Burst Blade | Unmapped | AFO sheet includes this weapon; no Pixel War counterpart provided yet |
| Flame Thrower | multi-use torch | Confirmed |
| Rocket Launcher | scrap launcher | Confirmed |
| Dragon Slasher | executioner | Confirmed |
| Green Laser Sword | green_plasma_blade | Confirmed |

## AFO Weapon Stats

| AFO Weapon | AFO Stats | Level |
| --- | --- | ---: |
| Dagger | STR +5-10% | 1 |
| Short Sword | STR +10-15% | 4 |
| Heavy Stick | STR +10-30%, SPD -10% | 5 |
| Sword | STR +15-20% | 5 |
| Spear | STR +20-30% | 6 |
| Machete | STR +20-30%, SPD -10% | 6 |
| Samurai Sword | STR +15-30%, AGL +10% | 7 |
| Trident | STR +30-40%, SPD -10% | 10 |
| Bow | STR +20-30% | 10 |
| Axe | STR +10-60%, AGL -10%, SPD -20% | 12 |
| Stone Hammer | STR +10-80%, AGL -10%, SPD -30% | 13 |
| Sickle | STR +20-70% | 13 |
| Spike Club | STR +10-90%, SPD -30% | 14 |
| Heavy Sword | STR +40-50%, AGL +10%, SPD -10% | 15 |
| Ice Burst Blade | STR +60-70%, AGL +10% | 18 |
| Dragon Slasher | STR +80-120%, AGL +10% | 19 |
| Green Laser Sword | STR +70-80%, SPD +20% | 20 |
| Flame Thrower | STR +30-50%, AGL -10% | 25 |
| Rocket Launcher | STR +40-70% | 32 |

## Current Video Context

Observed fight context supplied by Pure:

| Side | Level | ATK | DEF | SPD | HP |
| --- | ---: | ---: | ---: | ---: | ---: |
| Player, left side | 14 | 161 | 184 | 191 | 246 |
| Opponent, right side | 19 | 192 | 207 | 182 | 342 |

Use this reference when extracting frames from `Screen_Recording_20260427_225819_YouTube.mp4`, identifying visible weapons/pets, and comparing observed damage against Pixel War formulas.

## Video OCR Notes: 2026-04-27 Screen Recording

Frame extraction:

- Source: `c:\Users\purec\Videos\Screen_Recording_20260427_225819_YouTube.mp4`
- Duration: about 32.54 seconds
- Extracted: 163 frames, one every 0.2 seconds

Readable damage numbers from enlarged frame crops:

| Time | OCR Damage | Visual Target |
| ---: | ---: | --- |
| 7.6s | -58 | Player / left side |
| 9.0s-9.2s | -5 | Player / left side |
| 13.2s | -52 | Player / left side |
| 18.0s | -55 | Player / left side |
| 22.0s | -53 | Player / left side |
| 29.4s-29.6s | -64 | Player / left side |
| 31.2s | -52 | Player / left side |

Current Pixel War comparison using supplied visible stats:

- Player: level 14, 161 ATK, 184 DEF, 191 SPD, 246 HP
- Opponent: level 19, 192 ATK, 207 DEF, 182 SPD, 342 HP
- Current formula: `damage = ATK - DEF * random(0.65, 0.75)`, minimum 1, crit 1.5x

Expected opponent hit into player before visible weapon multiplier:

- `192 - 184 * 0.75 = 54`
- `192 - 184 * 0.65 = 72`
- Expected normal range: 54-72

The observed opponent hits `52, 53, 55, 58, 64` are very close to the current Pixel War normal-hit range. The `-5` event is likely a pet or low-damage secondary source rather than the opponent leader's normal weapon hit.

Expected player hit into opponent before visible weapon multiplier:

- `161 - 207 * 0.75 = 5`
- `161 - 207 * 0.65 = 26`
- Expected normal range: 5-26

The recording did not yield clear right-side damage numbers from the extracted 0.2s frames, likely due timing/position/crop visibility.
