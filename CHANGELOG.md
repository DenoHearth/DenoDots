# Changelog

## v1.8.3 — 2026-11-23

- The party leader crown on your own player frame is back. It now sits on the top-left of the portrait ring instead of under the icon row (1.8.1 had hidden it).

## v1.8.2 — 2026-11-17

- Warlock: new default icon Demonic Brand (the Demonology talent's brand that Searing Pain puts on your target). Shows once you have the talent; existing warlock lists get it added once, at the end. Asked for on CurseForge.
- A learned passive talent now counts as known for an icon.

## v1.8.1 — 2026-11-11

- The tiny yellow line under the icon row is gone: it was the game's party leader icon on the player frame peeking out under the row. It is now kept invisible; the game still shows and hides it as before

## v1.8.0 — 2026-11-11

- "In combat only" icons now also show while you have a target you can attack (alive and hostile), before combat starts; they go away again when the target is gone or dead and you are out of combat

## v1.7.5 — 2026-11-10

- New: paladin starting list - Seal, Judgement on the target, Judgement ready, Consecration, Aura and Blessing reminders, and Holy Shield and Righteous Fury (off, for tanks). A paladin who logged in with an older version gets it once
- New: better glows - reminders get a red, animated proc glow while the buff is missing; cooldowns get a proc glow in combat when the spell is ready
- New: "Combat" switch per icon - DoTs, buffs and cooldowns show only in combat, reminders all the time
- New: "Row / Bar" button per icon - Bar shows no icon on the row and puts its glow on the action button with the spell; a switch at the bottom sets every icon at once
- Fixed: a buff cast before combat now shows when combat starts; the glows follow a target change; the cooldown swipe no longer leaves a dark square in action bar mode
- The Glow switch now also works for reminders and cooldowns

## v1.4.0 — 2026-11-07

- New: a Deno Dots page in the game's Options, AddOns, with an Open Editor button and a Show Minimap Button switch
- New: a minimap button (click opens the editor, drag moves it), picked up by minimap button collectors such as Button Drawer
- The pet health and mana bars above the player frame are off by default (they showed the pet twice next to a nameplate addon's pet frame); the editor still turns them on

## v1.3.0 — 2026-10-08

- Click an icon to cast its spell, also in combat; a new switch in the editor turns it off

## v1.2.0 — 2026-10-08

- New editor look with clearer labels and tooltips; the glow start is a setting (default 3 seconds, 1 to 10); the row no longer lands on the player frame in the default layout

## v1.1.0 — 2026-10-08

- Each icon now has a kind (DoT, Debuff, Buff, Reminder, Pet buff, Cooldown) and its own switches for the missing mark, the glow and the timer; reminders show only when the buff is missing; new editor look

## v1.0.0 — 2026-10-07

- First release: icons with timers for your effects on the target and your own buffs, a red-framed grey icon for a missing one, a proc glow in the last 3 seconds, pet health and mana bars, and an in-game editor (`/dots`)
