# NEON BAY CITY

Open-world first-person city game (Vice-City-inspired), built 100% free:
Godot 4.7.2 + Kenney/KayKit CC0 assets + free internet LLM for AI orders.

## Play it now

**[Play in your browser](https://vedant251002.github.io/open-world-game/)** — no install needed
(builds automatically from `main` via GitHub Actions, see below).

Prefer a native build? Grab the latest zip for your OS from the
[Releases page](https://github.com/Vedant251002/open-world-game/releases) — Windows, Linux and
macOS builds are attached to every tagged release. Unzip and run the executable
(macOS/Linux: `chmod +x` may be required; macOS build is unsigned, so right-click → Open the
first time to bypass Gatekeeper).

## Run it (from source)

    godot4 --path .

Or open the folder in the Godot editor and press F5.

## Play

- WASD move, SHIFT sprint, SPACE jump, ESC free/capture mouse
- T = command console. Type plain English, e.g.:
  "build a cafeteria here" / "build a hotel near the beach"
- A free AI model (OpenRouter -> OpenCode fallback) parses your order,
  a worker walks to the site and constructs it autonomously.

## Verify (automated screenshots + pixel analysis)

    godot4 --path . --resolution 1280x720 -- --autocap
    python tools/png_stats.py

Screenshots land in %APPDATA%/Godot/app_userdata/Neon Bay City/autocap.

## AI chain (scripts/ai_command.gd)

1. OpenRouter free models (nemotron-3-nano-omni / 3.5-lightning / 3-super, :free)
2. OpenCode Zen gateway glm-5.3-flash (fallback)
3. Built-in offline keyword parser (last resort — game always works)

Note: the API keys are read from local dev-machine `.env` files, never committed. Exported
builds (web/downloads) have no keys available, so they always run on the offline parser — the
build console still works, just without live LLM parsing.

## CI/CD (.github/workflows/build.yml)

Every push to `main` runs [`barichello/godot-ci`](https://hub.docker.com/r/barichello/godot-ci)
(Godot 4.7.2 + export templates preinstalled) to export the game for **Web, Windows, Linux and
macOS** in parallel, then:

- the **Web** build auto-deploys to GitHub Pages (see "Play it now" above)
- all four builds are uploaded as workflow artifacts (Actions tab → a run → Artifacts)
- pushing a tag like `v1.0.0` additionally zips every platform build and attaches it to a new
  GitHub Release

Pull requests only build (sanity check), they never deploy or release.

**One-time setup required in the GitHub repo settings:** Settings → Pages → Source →
select "GitHub Actions" (can't be scripted from here — needs a repo-admin click once).
Until that's set, the Windows/Linux/macOS/Web build jobs still run and produce artifacts, only
the Pages deploy step will be skipped/fail.

To cut a versioned release with downloadable builds:

    git tag v1.0.0
    git push origin v1.0.0

## Layout

- scenes/Main.tscn        entry point
- scripts/main.gd         boot: environment, city, player, life, HUD, console
- scripts/city_generator.gd  procedural city: roads, sidewalks, 36 blocks,
  pastel-tinted buildings, grow-in transitions, pulsing neon signs,
  shops with furnished interiors, park, beach + parasols + ocean
- scripts/player_fpp.gd   first-person controller
- scripts/car_agent.gd    lane-following traffic (colored cars)
- scripts/pedestrian.gd   sidewalk pedestrians (animated KayKit chars)
- scripts/worker_agent.gd autonomous builder (status text + progress)
- scripts/command_ui.gd   T-key order console
- tools/                  asset curation + screenshot analysis (python)

## Assets

CC0: Kenney (car/city/roads/furniture/nature kits), KayKit characters.
Full 1,583-model library kept at ../kingdom-city-rawstore/assets_raw.
