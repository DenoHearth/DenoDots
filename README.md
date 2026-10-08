# Deno Dots

Small icons with timers for your damage-over-time effects on the target and for your own buffs, a red mark on the ones that are missing, and pet health and mana bars. The list is edited in game.

[![Latest release](https://img.shields.io/github/v/release/DenoHearth/DenoDots?label=download&style=for-the-badge)](https://github.com/DenoHearth/DenoDots/releases/latest)

A World of Warcraft: Forever addon (interface 16001).

## What it does

A small row of icons above your player frame for the things you have to keep up: your
damage-over-time effects on the target and your own buffs. Written from scratch for
World of Warcraft: Forever and its addon rules.

- **Up:** the spell's icon with the seconds left.
- **Missing:** the icon in grey with a red frame, so a gap is seen at a glance.
- **Last seconds:** the number turns red and the icon gets the action bar proc glow. 3 seconds
  by default; set it from 1 to 10 in the editor.
- **Pet bars:** health and mana of your pet under the row, with numbers.
- **Edited in game:** add any spell by name or id as "on target" or "my buff", switch
  icons on and off, change their order, remove them. A name covers every rank of the
  spell. Several spells in one icon mean "any of these" (one bane, one curse, one armor).
- **Click to cast:** a click on an icon casts its spell, also in combat. Handy for a buff
  that is missing.
- **Per class:** each class keeps its own list. Warlocks start with Corruption, Immolate,
  Bane, Curse and Armor; other classes start empty.
- An icon from the starting list shows once you have learned one of its spells.
- Size, position (drag with the mouse), the glow seconds and the pet bars are set in the same
  window.
- The row sits above your player frame. If the frame is against the top of the screen (the
  game's default layout) it sits under it instead.

## Install

- **CurseForge:** search for Deno Dots in the CurseForge app under WoW: Forever.
- **By hand:** download the zip from the
  [latest release](https://github.com/DenoHearth/DenoDots/releases/latest) and extract
  the `DenoDots` folder into `World of Warcraft\<Forever folder>\Interface\AddOns\`.
  Restart the game.

## Options

`/dots` or `/denodots` opens the editor. It opens out of combat only: the row is rebuilt
on every change.

## How it works

Forever hides combat data from addons: auras, health and time left come back as opaque
"secret" values that code may pass on but not read. This addon never reads them.

- Each icon is a slot of Blizzard's aura container. The game shows the slot while the aura
  is up and hides it when it is not; the grey "missing" picture simply lies underneath.
- The time left is written by the game's own duration text, with a colour curve the game
  evaluates.
- The glow is a second, empty slot whose "time text" is one frame of the proc glow per
  1/30 second, chosen by the game from the time left, and blank above 3 seconds. No script
  runs for it.
- Pet health and mana go straight from the API into the bars and the text.

## Limits

- It shows; it does not decide. No "refresh now" advice from enemy health, no damage numbers.
- A buff whose aura has a different spell id than the spell that casts it has to be added
  by the aura's id.
- Built and tested before the game's launch against the beta's interface files and an
  offline simulator. Report anything that looks wrong in the live game.

## Files

- `Data.lua` - generated: every class spell name and the ids of all its ranks
- `Core.lua` - saved settings, class defaults, events, slash commands
- `Tracks.lua` - the icon row, the aura slots and the glow
- `PetBars.lua` - pet health and mana
- `Editor.lua` - the in-game editor


## Compatibility

- World of Warcraft: Forever, interface version **16001**.
- Forever only. It uses that client's API and will not load on retail or the Classic clients.

## Changelog

What changed in each version: [CHANGELOG.md](CHANGELOG.md).

## License

MIT — see [LICENSE](LICENSE).  Current version: 1.3.0.
