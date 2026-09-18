# ForeverDiff Collector

Help build the [ForeverDiff](https://foreverdiff.gg) database just by playing World of Warcraft: Forever. The addon records quests, creatures, vendors, loot and dungeon entrances. You choose when to share the file. **No coding or GitHub account needed to contribute game data.**

## Install in 3 steps

1. **[Download ForeverDiffCollector.zip](https://github.com/anombyte93/ForeverDiffCollector/releases/latest/download/ForeverDiffCollector.zip)** and unzip it.
2. Open the folder for the WoW version you actually play. Put the **ForeverDiffCollector** folder inside **Interface → AddOns**.
3. Start WoW, enable **ForeverDiff Collector** in the character screen's **AddOns** list, then enter the world and type **`/fdc`**. A collection count means it loaded.

The final layout must be `Interface/AddOns/ForeverDiffCollector/ForeverDiffCollector.toc` — no extra folder around it. If WoW was already open, try `/reload`; restart it if the addon doesn't appear. If it is marked out of date, enable **Load out of date AddOns**.

Targets Forever beta **1.60.1 / interface 16001** and Classic Era **1.15.9 / interface 11509**. Beta loading was reported working on build **69893** on 18 September 2026. Other builds may need testing; Retail and other Classic versions are not claimed compatible.

## Help by playing

1. Play normally: open quest windows, target creatures, visit vendors, loot and enter/leave dungeons.
2. Type **`/reload`** or log out when you're done, so WoW saves the data.
3. Open **[foreverdiff.gg/contribute](https://foreverdiff.gg/contribute)** and upload this file from the same WoW version's folder:

   `WTF/Account/<your account folder>/SavedVariables/ForeverDiffCollector.lua`

Choose the `.lua` file, not `.lua.bak`, and not the addon source from `Interface/AddOns`. Uploaded observations enter the site's review/import process; uploading does not mean they are already published. You can upload again after another session. Keep your collected data; there is no need to reset it after uploading.

Can't install it? The [contribution page](https://foreverdiff.gg/contribute#screenshot) also accepts screenshots. Crop out character names and chat first.

## Other ways to help

- **[Report a bug](https://github.com/anombyte93/ForeverDiffCollector/issues/new?template=bug_report.md)** — say what happened, what you expected and your game build.
- **[Suggest an improvement](https://github.com/anombyte93/ForeverDiffCollector/issues/new?template=feature_request.md)** — small ideas and clearer instructions welcome.
- **[Contribute code or docs](CONTRIBUTING.md)** — fork this repo and open a pull request. Tests run without WoW.

## Useful commands

| Command | What it does |
| --- | --- |
| `/fdc` | Show collection counts. |
| `/fd 123` | Open a copyable ForeverDiff link for item 123. You can also insert an item link. |
| `/fdc reset` | **Delete collected observations.** Save anything you need first. |

This GitHub package collects data and provides `/fd` links. It does not bundle a live list of missing items, so item-hint tooltip lines are absent by default. The [website's snapshot download](https://foreverdiff.gg/downloads/ForeverDiffCollector.zip) adds its current item-hint data to the collector version bundled with that website deployment.

## Privacy

The addon saves game facts, your realm and client build locally. It does not deliberately record account/character/player names, guilds, chat or mail, and it does not upload anything automatically. Quest text is copied as displayed by the game, so review the file before sharing if it contains personalised text. Upload only the collector file, never your entire WTF folder. Contributions become public game data under the website's data terms.

## Updating

Use the same **[latest download link](https://github.com/anombyte93/ForeverDiffCollector/releases/latest/download/ForeverDiffCollector.zip)** whenever a release is announced. Close WoW and replace the addon folder, then reopen it. Your observations live separately in `WTF`; leave that folder alone. Installed addons do not update themselves.

## Licence

Addon code and documentation: [MIT](LICENSE). The licence does not grant rights to Blizzard game assets or change the terms for data uploaded to ForeverDiff. This is an independent community project, not affiliated with Blizzard Entertainment.
