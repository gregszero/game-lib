# Game Lib — an Omarchy shell plugin

One bar icon that opens your whole playable library: every Steam game you own,
plus cloud-gaming services and browser games that open the same way Omarchy
opens Hey or X.

```
        ┌──────────────────────────────┐
        │  Games        53 Steam · 38 web│
        │  ┌────────────────────────┐   │
        │  │ Search your library…   │   │
        │  └────────────────────────┘   │
        │  RECENTLY PLAYED              │
        │ ▸ Mistfall Hunter   36h · today│
        │   Counter-Strike 2  833h · 2d  │
        │  STEAM LIBRARY  53            │
        │   Arma 3      17h · not installed│
        │  WEB GAMES  38                │
        │   GeForce NOW   Cloud       󰖟 │
        └──────────────────────────────┘
```

## Why it needs no Steam account or API key

Steam already keeps everything this plugin needs on disk. The indexer reads it
directly:

| What | Where it comes from |
|------|--------------------|
| Game names | `appcache/appinfo.vdf` (Valve's binary KeyValues cache) |
| Owned apps | union of the artwork cache, playtime records, and install manifests |
| Installed + size | `steamapps/appmanifest_*.acf` |
| Playtime, last played | `userdata/<id>/config/localconfig.vdf` |
| Cover art | `appcache/librarycache/<appid>/` |

So the Steam half works offline, instantly, with Steam closed. DLC, Proton
builds and Steam runtimes are filtered out by app type.

The one thing local caches cannot know is a game you own but have *never*
installed or launched on this machine. If you want those listed too, put a
[Steam Web API key](https://steamcommunity.com/dev/apikey) in the plugin's
settings and the indexer will use `GetOwnedGames` as the authoritative list,
still falling back to local data if the call fails.

## Web games

Three sources, merged:

1. **A curated catalogue** (`catalog.json`) — itch.io, Xbox Cloud, GeForce NOW,
   Amazon Luna, Poki, CrazyGames, Lichess, the Internet Archive arcade, and more.
2. **Your own entries** in `~/.config/omarchy/extensions/game-lib.jsonc`.
3. **itch.io's browser-playable listings**, from their RSS feed, cached for six
   hours. If the feed is ever unavailable the indexer falls back to parsing the
   browse page, and to the last good cache after that.

Curated launchers open as chromeless web apps via `omarchy-launch-webapp`;
one-off scraped games open in a normal tab so history and the back button work.

### Adding your own

```jsonc
// ~/.config/omarchy/extensions/game-lib.jsonc
[
  {
    "name": "My Favourite Browser Game",
    "url": "https://example.com/game",
    "category": "Puzzle",
    "webapp": true   // true = chromeless window, false = normal tab
  }
]
```

## Install

```bash
omarchy plugin add https://github.com/gregszero/game-lib.git --enable --yes
```

Or from a local checkout:

```bash
ln -s ~/Developer/game-lib ~/.config/omarchy/plugins/greg.game-lib
omarchy-shell shell rescanPlugins
omarchy plugin enable greg.game-lib
```

## Using it

| Action | Result |
|--------|--------|
| Left click the icon | Open the panel |
| Type | Fuzzy filter — `agemp` finds *Age of Empires*, `cloud` finds every cloud service |
| ↑ / ↓ / Enter | Move and launch |
| Right click a row | Open its Steam store page |
| Right click the icon | Open the Steam client |
| Middle click the icon | Force a full re-index |
| Esc | Clear the search, then close |

## Settings

Every option lives on the widget's entry in `~/.config/omarchy/shell.json`:

| Key | Default | Meaning |
|-----|---------|---------|
| `refreshIntervalSec` | `300` | Background re-index interval |
| `recentCount` | `5` | Recently played games pinned at the top |
| `showWeb` | `true` | Include the web-games sections |
| `itchLimit` | `24` | itch.io games indexed; `0` disables the scrape |
| `showCovers` | `true` | Show Steam box art instead of a plain glyph |
| `includeTools` | `false` | Also list Proton builds and Steam runtimes |
| `steamApiKey` | `""` | Optional, for never-installed games |

## Scripts

Both are ordinary CLIs, so you can debug the plugin without the shell:

```bash
./bin/game-lib-index --section steam | jq '.steam.ownedCount'
./bin/game-lib-index --section web --refresh-itch | jq '.web.itchCount'
./bin/game-lib-launch steam 730
./bin/game-lib-launch web https://lichess.org
```

## License

MIT
