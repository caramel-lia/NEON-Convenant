# NEON//COVENANT — GEMINI//LINK (Violet TUI + Tactical Grid)

A self-hosted, **1–5 player cyberpunk tabletop RPG**, now with a shared grid and manual dice, written in Ruby/Sinatra, with Gemini as the AI Game Master (SWITCH//ZERO). The violet/cyan/black CRT terminal interface, dice mechanics, characters, and campaign-save format are preserved from the previous Groq and Qwen editions.

## What is inside

- Private 8-character campaign codes, host controls, lobby, crew chat and five archetypes (Netrunner, Solo, Ghost, Techie, Fixer).
- Server-generated 2d6 + attribute rolls (not chosen or edited by Gemini).
- Persistent world memory, narrative choices, gear, hit points, stress and credits, with bounded AI-generated effects.
- **NEW: Interactive 14×9 tactical grid** with numbered player tokens, live movement, map tiles and host terrain editing.
- **NEW: Manual D4/D6/D8/D10/D12/D20/D100 rolls**, broadcast to the crew without consuming an AI turn.
- Gemini REST `generateContent` integration with structured JSON output and server-only credentials; no Python/Node AI package needed.
- Default **`gemini-3.5-flash-lite`**, which Google lists with free-tier text input and output, subject to account, regional and rate limits. To try richer scenes, use `gemini-3.8-flash` if your account permits it. Availability and fees can change; check https://ai.google.dev/gemini-api/docs/pricing.
- `DEMO_MODE=true` for local scripted play with **zero AI API requests**.

## 1 — Install on Kali Linux

From the extracted `neon_covenant_gemini_final` directory:

```bash
sudo apt update
sudo apt install -y ruby ruby-dev build-essential bundler
bundle config set --local path 'vendor/bundle'
bundle install
cp .env.example .env
nano .env
bundle exec ruby app.rb
```

Open <http://127.0.0.1:4567>. Avoid `sudo bundle install`; your previous permission error came from Bundler writing to system gem folders. The `Gemfile` includes `rackup` and `puma` for Sinatra 4.

If your Kali `bundle` executable isn't found, install bundler in your user gem directory and ensure that directory is on `PATH`, or install the `bundler` Debian package as above.

## 2 — Configure your Gemini API key

Create an API key at <https://aistudio.google.com/apikey>. Place it **only in `.env` on the Sinatra server**:

```dotenv
GEMINI_API_KEY=your_gemini_api_key_here
GEMINI_MODEL=gemini-3.5-flash-lite
DEMO_MODE=false
APP_HOSTS=
PORT=4567
RACK_ENV=development
```

Restart Sinatra when updating `.env`. For potentially richer narration, try `GEMINI_MODEL=gemini-3.8-flash`, which may have different free-tier availability or limits. Do **not** add the API key to `public/app.js`, `public/index.html`, a Git commit or a chat message.

The GM uses Google's HTTPS REST endpoint `POST /v1beta/models/{model}:generateContent` with an `x-goog-api-key` header, `systemInstruction`, and `generationConfig.responseFormat.text` structured JSON schema. Campaign context is sent per request and stored locally between rounds (no Gemini conversation store required).

## 3 — Upgrade an existing NEON//COVENANT Groq/Qwen/Gemini install

1. Stop the running server and **back up both `.env` and `data/rooms/`**.
2. Extract this ZIP to a separate folder. Copy its **`app.rb`, `lib/`, `public/`, `Gemfile`, `config.ru`, `test/`** into `~/NEON-Convenant`, keeping the original `.env` and `data/rooms/` intact. Copy `.env.example` only for reference.
3. Edit `~/NEON-Convenant/.env`: set `GEMINI_API_KEY`, `GEMINI_MODEL=gemini-3.5-flash-lite`, and `DEMO_MODE=false`. Remove old `GROQ_*` or `QWEN_*` variables if convenient, but they are not read by this edition.
4. Reinstall to the local bundle and start:

   ```bash
   cd ~/NEON-Convenant
   bundle config set --local path vendor/bundle
   bundle install
   bundle exec ruby app.rb
   ```

5. Hard-refresh the UI with `Ctrl+Shift+R`. The project does not change the game-state schema; existing rooms **should remain compatible**. A backup is still important.

**Note:** A `.env` from Groq with only `GROQ_API_KEY` will not authorize Gemini. The server should report `"gm_mode":"gemini"` at `/health` when its Gemini key is configured, `"demo"` in demo mode, or `"unconfigured"` without credentials.

## 4 — How to play

Create a room as host and share its code with up to four friends. Select your class and campaign tone. The host starts the session, prompting Gemini to narrate the opener. Each player describes freeform actions using HACK, FORCE, STEALTH, TALK or INVESTIGATE. The server rolls 2d6, then Gemini narrates successes, failures, encounters and consequences. After everyone submits, the GM automatically advances, or the host can advance when some players are away.

Each campaign start and resolved round makes **one** Gemini API request; room browsing, chat, and entering actions do not. Quota errors produce a visible message and leave already submitted actions intact so the host can retry. Some free accounts can encounter daily or per-minute limits.

For offline demo play, set `DEMO_MODE=true` (no API key needed).

## 5 — Self-hosting / Cloudflare Tunnel

Docker is also supported:

```bash
cp .env.example .env
# Edit .env with GEMINI_API_KEY, APP_HOSTS=game.example.com, RACK_ENV=production
docker compose up --build -d
```

Docker binds the host port to `127.0.0.1:4567`; a Cloudflare Tunnel on the host can proxy to <http://127.0.0.1:4567>. This is a prototype for a trusted crew rather than a hardened public service. Protect the tunnel and add stronger abuse protections before opening it to strangers.

## 6 — Validation

```bash
ruby test/game_test.rb
ruby -c app.rb
ruby -c lib/gm.rb
node --check public/app.js  # optional
```

Automated tests cover character stats, PStore save/recovery, server rolls, secret handling, Gemini request shape and parsing, schema validation, missing keys, incomplete responses, and 429 retry information. **Mock tests cannot prove your API key has real working quota**; test a campaign start with your own key.

## Project layout

```text
neon_covenant_gemini_final/
├── app.rb                Sinatra routes & multiplayer game server
├── lib/game.rb           Rules, secure player tokens, PStore, server dice
├── lib/map.rb            Tactical grid, movement, terrain editing and map sync
├── lib/gm.rb             Gemini REST API + demo GM
├── public/index.html     Violet/cyan CRT interface
├── public/style.css      CRT, TUI panels & scanline theme
├── public/app.js         Multiplayer browser client
├── test/game_test.rb     Offline unit tests
├── Gemfile               Sinatra, Puma, Rackup, Dotenv
├── .env.example          Key/model template (no secrets)
├── Dockerfile
└── compose.yaml
```

Official docs: [Generate Content API](https://ai.google.dev/api/generate-content), [Structured Output](https://ai.google.dev/gemini-api/docs/generate-content/structured-output), [Pricing](https://ai.google.dev/gemini-api/docs/pricing).

---

## 7 — NEW: Tactical grid (14 × 9)

This edition adds a **shared, interactive tactical map** directly above the GM narration. It works in a browser; it is not a static image or third-party maps service.

- **Player tokens:** Each operative appears as a numbered violet/cyan/pink/amber/green token. The roster below the grid identifies the token owner.
- **Click-to-move:** Click a reachable tile to move **your own** token by up to **four orthogonal squares per click**. Walls and occupied cells block routes. Diagonal shortcuts are not allowed. Movement updates every crew member's map on the normal 2.6-second room polling interval, without using Gemini quota.
- **Terrain types:** Floor (`·`), wall (`▥`, impassable), cover (`▤`), objective (`◇`), and hazard (`⚠`). Cover/hazard/objective tiles are visual cues; the AI GM and the players still adjudicate any combat effects.
- **Host editor:** Click **HOST: EDIT**, select a tile type, and click grid cells to paint terrain. Non-host players cannot edit or reset terrain; the server checks authorization. The server also refuses to place walls underneath players. Click **MOVE** to return to movement mode.
- **Regenerate (`↻`):** The host can recreate the sector grid from the current location. Regenerating removes hand-painted changes and resets every operative's position.
- **Scene sync:** The grid automatically generates a new procedural sector when the GM reports a changed `location` in the scene. This will reset painted tiles and positions. The sector map is an **illustrative sketch**, not a detailed image of the location or a promise of precise line-of-sight rules.
- **Lobby & saves:** The map is prepared from room creation, becomes visible in the active story view, and is saved in the same PStore room as the campaign. Older campaign files without a `map` field are automatically given a grid without modifying the characters or story.

### Moving and editing

Each cell has a coordinate such as **B5** or **N9**, with letters across the top and numbers down the left. To avoid blocked cells, select a nearby walkable cell first; you can move again after the prior move is saved. Movement is a visual positioning aid and **does not consume an action or trigger an AI scene**. It also does not automatically grant combat advantage or bypass story obstacles.

### Dedicated map endpoints

All routes require the same player bearer token used by other room actions. **Only host** can call paint and reset. The server checks map coordinates and terrain values rather than trusting browser input:

```text
POST /api/rooms/:code/map/move   {"x": 5, "y": 4}
POST /api/rooms/:code/map/paint  {"x": 5, "y": 4, "terrain": "cover"}
POST /api/rooms/:code/map/reset  {}
```

## 8 — NEW: Manual dice console

Under **DATASTREAM**, there is a `DICE://MANUAL` panel. Set the number of dice **1–8**, sides **D4, D6, D8, D10, D12, D20 or D100**, and modifier **−20 to +20**, then optionally enter a reason (up to 80 characters). **ROLL TO DATASTREAM** rolls with Ruby's `SecureRandom` on the server and broadcasts the individual dice and total to the entire room.

Three shortcuts are provided: **2D6**, **D20** and **D100**. You can see the last manual result beneath the roll button, and every roll appears under the shared **ROLLS** event filter.

Manual dice **do not** trigger a Gemini request, don't consume an action, and don't automatically change character stats. The usual narrative action rolls (2D6 + class attribute vs difficulty) continue to run separately when a player commits an action.

```text
POST /api/rooms/:code/roll
Authorization: Bearer <your-player-token>
Content-Type: application/json

{"count":2,"sides":6,"modifier":1,"reason":"Check the lock"}
```

## 9 — Upgrade to this grid edition

**Recommended:** Extract the downloaded ZIP to a new directory first. From your existing `~/NEON-Convenant` installation, **back up `.env` and `data/rooms/` before copying files**. Copy `app.rb`, `lib/`, `public/`, `Gemfile`, and `test/` from the grid edition into your existing project. Leave the original `.env` and `data/rooms/` in place.

```bash
cd ~/NEON-Convenant
bundle config set --local path vendor/bundle
bundle install
bundle exec ruby app.rb
```

Hard-refresh the browser (`Ctrl+Shift+R`). Your Gemini settings remain `GEMINI_API_KEY=...`, `GEMINI_MODEL=...`, and `DEMO_MODE=false` (or `true` for an offline demonstration).

To run the expanded offline test suite:

```bash
ruby test/game_test.rb
ruby -c app.rb
ruby -c lib/game.rb
ruby -c lib/map.rb
ruby -c lib/gm.rb
node --check public/app.js
```

**Testing status:** 22 offline Ruby tests and 718 assertions passed before packaging. All syntax checks passed. The live Sinatra/Gemini integration and a visual browser walkthrough require verification on your Kali host; no real API key is included.
