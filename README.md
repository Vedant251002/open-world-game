# DELEGATE

> You cannot touch anything. You can only talk to three people.

A first-person village game in Godot 4.7. The world is voxels, streamed in
around you and generated from a seed — there are no meshes on disk. You have no
build key, no placement cursor and no inventory: if you want something to exist,
somebody else has to make it, and the only way to ask is language.

## Play it

**[Play in your browser](https://vedant251002.github.io/open-world-game/)** —
nothing to install, rebuilt from `main` on every push.

It works on a phone. On iPhone or Android, open that link and use **Share → Add
to Home Screen**; it installs as a standalone app and launches without the
browser chrome. Touch controls appear automatically: drag your left thumb
anywhere on the left of the screen to walk (push to the rim to run), drag on the
right to look, and use the on-screen TALK / JUMP / MAP buttons.

If the page hangs on a black screen, your browser has refused
`SharedArrayBuffer` — try the
**[no-threads build](https://vedant251002.github.io/open-world-game/lite/)**
instead. It runs everywhere but generates chunks on the main thread, so expect
it to stutter while the world streams in.

Desktop builds for Windows, Linux and macOS are attached to every tagged
[release](https://github.com/Vedant251002/open-world-game/releases).

## Controls

|            | Desktop           | Touch                          |
| ---------- | ----------------- | ------------------------------ |
| Move       | WASD              | left thumb stick               |
| Run        | Shift             | push the stick to the rim      |
| Jump       | Space             | JUMP                           |
| Look       | mouse             | drag on the right of the screen |
| Talk       | E                 | TALK                           |
| Map        | M                 | MAP                            |
| Menu       | Esc               | ESC                            |
| Frame stats| F3                | —                              |

## Run from source

    godot4 --path .

The AI reads its key from the environment or from a `.env` file in the project
root — copy `.env.example` and fill in one key. Without one the game runs
offline on the built-in plan library, which still answers every order, just
less well.

Two gateways are supported, chosen by whichever key is present:

| | Groq (default) | OpenCode Zen |
| --- | --- | --- |
| key | `GROQ_API_KEY` | `OPENCODE_API_KEY` |
| free | yes, no card | yes |
| speed | a second or two | ~45 s |
| JSON | held to a schema, always parses | best effort, truncates |

Groq is worth the two minutes it takes to get a key: it accepts a
`response_format` of `json_schema`, so the model physically cannot return a
plan that does not parse. That was the single most expensive failure in the
old setup — a reply cut off mid-string costs the whole wait and yields nothing.
The schema is generated from the same tables as the prompt and the validator,
in `scripts/ai/plan_schema.gd`, so the three cannot drift apart.

The free tier caps tokens per minute rather than just requests, so sustained
play is roughly an order a minute; repeated orders are served from the
archetype cache and never leave the machine.

Browser builds have no environment to read, so the deployed version goes
through `proxy/worker.js`, which holds the key on Cloudflare. It speaks to
either gateway — `wrangler secret put GROQ_API_KEY` is all that is needed to
move it across.

## Debug flags

Pass these after `--`, e.g. `godot4 --path . -- --seed=7 --nofar`:

| Flag           | Effect                                              |
| -------------- | --------------------------------------------------- |
| `--seed=N`     | fix the world seed                                   |
| `--provider=X` | force `groq` or `opencode` for one run               |
| `--nofar`      | skip the far-terrain horizon mesh                    |
| `--nostream`   | freeze chunk streaming                               |
| `--buildtest`  | drop the acceptance buildings onto real plots        |
| `--gentest`    | run generator assertions and exit                    |
| `--streamtest` | run streaming assertions and exit                    |
| `--bench`      | walk a fixed route and report frame times            |
| `--shot`       | capture the showcase views                           |
| `--mapshot`    | capture the map and exit                             |

## Builds

`.github/workflows/build.yml` exports Web, Windows, Linux and macOS on every
push to `main`, deploys the web build to GitHub Pages, and attaches the desktop
builds to any `v*.*.*` tag. The web job exports twice: the threaded PWA at the
site root and the no-threads fallback under `/lite/`.

GitHub Pages cannot set the `Cross-Origin-Opener-Policy` and
`Cross-Origin-Embedder-Policy` headers that `SharedArrayBuffer` requires, so the
main build enables Godot's PWA service worker, which supplies them itself. That
is why the root build is a PWA and not a plain page.
