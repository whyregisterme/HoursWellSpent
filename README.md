# Hours Well Spent

Shared-time vignettes for SkyrimNet: NPC-proposed, LLM-written, remembered by everyone there, and
good for a skill.

NPCs propose spending time together. Confirm, skip ahead, and SkyrimNet writes how it went:
narrated, remembered, and practised. Go over the ledgers with your steward, spar in the yard, sit up
half the night over wine. The hours pass in a moment and you read how they went, written from who you
both are, where you are and what the NPC has been remembering lately.

## Requirements

- SkyrimNet **0.28.0 (beta 28) or newer**
- PapyrusUtil SE (SkyrimNet already needs it)
- powerofthree's Papyrus Extender

## Install

Download `HoursWellSpent-<version>.zip` from [Releases](../../releases) and install it with your mod
manager (Vortex or MO2). Enable `HoursWellSpent.esp`. It's ESL-flagged, so it takes no load-order slot.

Updating: replace the old version rather than installing alongside it.

**Game versions:** tested on 1.6.1170. There is no DLL, so the mod itself doesn't depend on the game
version; it runs wherever SkyrimNet, PapyrusUtil and Papyrus Extender do. The plugin uses header
version 1.70, so it loads on SE 1.5.97 as well as AE, without needing BEES.

## Playing

- **The proposal.** When you and an NPC agree to do something together right now, they can fire the
  `SpendTimeTogether` action with what you'll do and for how long (1 to 8 hours; 2 if they don't say).
  A notification names them and the activity, then a box asks:
  - **Spend the time** goes ahead.
  - **Not now** declines, and the NPC hears that you put it off.
  - **Not now (silently)** declines without telling the NPC.
- **The hours.** The screen fades out, the clock moves on, and it fades back in. It works across
  midnight, the date rolls over as it should.
- **How it went.** SkyrimNet writes a short account (two to four sentences) from both bios, the NPC's
  recent memories, the place, the hour, and any followers who were close by. It's ordinary life, not
  an adventure: no fights, deaths, quests or rewards, and nothing you'd have to undo. You read it in a
  box, and it's narrated, so the NPC and anyone present remember it and the NPC can react.
- **Practice.** The account names the one skill those hours practised for you, if any. You gain about
  5% of a level in it per hour, adjusted by your own bonuses (standing stones, perks, other mods), so
  three hours over the books might give Speech around 15%. The notification shows what you actually
  gained.
- **Cooldown.** After the time is spent or declined, the action rests for 90 seconds. It can't fire
  while you or the NPC are in combat, or while time is already being spent.
- If SkyrimNet doesn't answer within 45 seconds, you get a plain one-line account instead, so the hours
  are never blank. (This fallback hasn't come up in testing yet.)

## Console levers

- Stuck mid-skip (black screen, no controls): `stopquest HWS_Quest`, then `startquest HWS_Quest`.
  Loading a save should also recover, since a skip interrupted by a load is finished with the plain
  account, though that path hasn't been tested in game.

## How it works

| Path | What |
|---|---|
| `scripts/HWS_Main.psc` | The action, the confirm box, the time skip, the account, the practice |
| `scripts/HWS_PlayerAlias.psc` | Passes the load event on, so a skip interrupted by a reload is finished |
| `spriggit/HoursWellSpent/` | The plugin as Spriggit JSON: one quest with a partner alias, and the confirm box |
| `layer/whyregister.hours-well-spent/` | The SkyrimNet layer: the `SpendTimeTogether` action and the `hws_scene` prompt that writes the account |

- The account comes from `SendCustomPromptToLLM` with the layer's `hws_scene` prompt. It returns JSON
  (`summary`, `skill`); the summary goes out through `DirectNarration`, which is what makes it a shared
  memory.
- Nothing is coded to a particular character: names, bios, memories and places all come from
  SkyrimNet at run time.
- Time moves by adding hours to `GameHour`, as the vanilla wait does, behind a fade with controls off.
- Practice uses SKSE's `ActorValueInfo.AddSkillExperience`. That function takes skill *use*, not
  experience: the engine multiplies it by each skill's use rate (One-Handed 6.3, Alchemy 0.75, and so
  on). Measured in game, asking for 5% of a One-Handed level gave 35%. So the amount is divided by the
  skill's use rate first, and the gain is measured before and after; the `[HWS] practise` line in the
  Papyrus log records both.
- Only skills from the prompt's own list can be raised, so a stray reply can't touch anything else.
- The confirm box doesn't name anyone (name tags in message boxes showed up as "[...]" in game); the
  notification just before it says who and what.

## Building

`build.sh` (Git Bash on Windows) compiles the scripts with Caprica, builds the `.esp` from the
Spriggit source, round-trips it back to JSON to catch dropped fields, and zips the result into
`dist/`. It expects to sit two folders below a tools folder inside the game directory
(`<Skyrim>/Tools/projects/HoursWellSpent`), with Caprica and Spriggit in that tools folder, Python 3
on PATH, and the game's Papyrus sources (vanilla, SKSE, PapyrusUtil, Papyrus Extender, SkyrimNet)
installed. It only reads the game folder.

## Credits

- SkyrimNet by the SkyrimNet team
- PapyrusUtil by exiledviking; Papyrus Extender by powerofthree

## License

MIT. See [LICENSE](LICENSE).
