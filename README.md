# NEON BAY CITY

Open-world first-person city game (Vice-City-inspired), built 100% free:
Godot 4.7.2 + Kenney/KayKit CC0 assets + free internet LLM for AI orders.

## Run it

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
