# NEON//COVENANT

**A browser-based, 1–5 player cyberpunk tabletop RPG built with Ruby + Sinatra, with an AI Game Master and CRT/TUI interface.**

- **Multiplayer rooms:** 8-character invite code, up to five total players, each on their own device/browser. The host starts the story and can advance a round when somebody is absent.
- **Storyteller:** Google Gemini Interactions API, with JSON-schema scene results, scene memory, consequences, cinematic descriptions, suggested moves, and narrative continuity.
- **Tabletop rules:** Choose Netrunner, Solo, Ghost, Techie, or Fixer. Submit any action with an approach; the server rolls **2d6 + relevant stat** against a fixed difficulty. The GM must accept the rolled result.
- **Shared world:** Character HP, stress, credits, loadouts, chat, events, rounds, and scenes survive restarts using Ruby's built-in `PStore` (no database installation required).
- **Terminal aesthetic:** Green-on-black CRT interface, violet/amber highlights, mission HUD, crew health bars, in-world text, datastream, and responsive mobile layout.
- **Demo mode:** A scripted GM lets you explore the interface and mechanics without using paid API credits.

## Requirements

Ruby **3.2+** (3.3 recommended), Bundler, and internet access for `bundle install` and AI calls. `Gemfile` installs Sinatra, Puma, and Dotenv.

> **Gemini API key ≠ a Google account password or Gemini app subscription.** Obtain a key in [Google AI Studio](https://aistudio.google.com/apikey). Gemini API usage has its own quotas and billing. **Never enter your API key in the browser or share it with players.** It stays in the server's environment.

## Run locally

```bash
cd neon_covenant
gem install bundler
bundle install
cp .env.example .env
# Edit .env: add GEMINI_API_KEY=your_key (or DEMO_MODE=true for an offline demo)
bundle exec ruby app.rb
```

On Windows PowerShell, replace `cp` with `Copy-Item .env.example .env`, then edit `.env` in Notepad. Install Ruby through RubyInstaller first if it isn't available.

Open **http://127.0.0.1:4567**. The server listens only on localhost by default. For a LAN/public deployment, configure the bind address and reverse proxy appropriately.

### Minimal `.env`

```dotenv
GEMINI_API_KEY=your_gemini_api_key_here
GEMINI_MODEL=gemini-3.8-flash
DEMO_MODE=false
PORT=4567
```

Use a model your account has access to. The default model is Gemini 3.8 Flash; adjust it to a model available to your key. The GM relies on structured JSON output.

**To test without an API key:** set `DEMO_MODE=true`, then restart the server. The demo story is scripted, not Gemini-driven, but it honors your actions and dice.

**Upgrading from the OpenAI edition:** replace `OPENAI_API_KEY`/`OPENAI_MODEL` in your `.env` with `GEMINI_API_KEY`/`GEMINI_MODEL`, then restart Sinatra (or `docker compose up --build -d`). Existing room saves in `data/rooms/` use the same format. There is no OpenAI dependency in this edition.

**Model option:** If you want to try a lower-cost model, change `GEMINI_MODEL` to `gemini-3.5-flash-lite` (subject to your account's availability). Google AI Studio controls API usage and quotas; a Gemini app subscription does not supply an API key.

## Docker / local-home-server deployment

```bash
cp .env.example .env
# Edit .env with your key and desired settings
docker compose up --build -d
```

The Docker Compose configuration exposes port 4567 **only to the host's loopback interface** and persists games in `./data/rooms`. A Cloudflare Tunnel on the same home server can point to `http://127.0.0.1:4567`.

If you put the game behind a custom hostname, add that hostname (without `https://`) to `APP_HOSTS` in `.env`, for example `APP_HOSTS=game.example.com`, and restart the service. Sinatra's host authorization intentionally restricts unlisted domains. Configure HTTPS and access protection at your reverse proxy.

## Play the game

1. A player chooses an archetype and creates a campaign, selecting **Noir**, **Rebellion**, or **Ghost Signal**.
2. They click **INVITE** and send the generated URL to up to four others. Each player enters a unique handle and role.
3. The **host** clicks **BOOT THE CAMPAIGN** to create the opening AI-driven scene.
4. Each player writes a freeform action and chooses HACK, FORCE, STEALTH, TALK, or INVESTIGATE. They can also click a suggested path to insert it into the action editor.
5. The server rolls and locks the action. Once every current player has acted, the GM resolves the round automatically, describes outcomes, updates stats, and produces the next scene.
6. If a player is absent, the host may choose **ADVANCE WITH SUBMITTED ACTIONS** to skip those who have not submitted that round.

The GM call runs on the server. All connected browsers update by polling the room every ~2.6 seconds. The last person to act may see a generation delay as the GM prepares the next scene. In a one-person campaign, each submitted action immediately triggers the GM.

### Dice and stats

| Approach | Stat | Difficulty |
|---|---|---:|
| FORCE | EDGE | 9 |
| STEALTH | GHOST | 9 |
| HACK | TECH | 10 |
| TALK | GHOST | 9 |
| INVESTIGATE | TECH | 8 |

Roll **2d6 + stat**. A result at least as high as the DC succeeds; otherwise the GM describes a cost, complication, or setback. A failed roll never automatically prevents the story from moving forward. The GM can award modest HP, stress, credit, or item changes, but the server caps each change and validates which player acted. These are deliberately lightweight, original game rules rather than a licensed TTRPG ruleset.

## Project structure

```text
neon_covenant/
├── app.rb               # Sinatra routes, player authentication, room state machine
├── lib/
│   ├── game.rb          # Characters, persistent room store, dice, bounded effects
│   └── gm.rb            # Gemini Interactions API + structured GM + demo mode
├── public/
│   ├── index.html       # TUI / CRT interface
│   ├── style.css        # Responsive visual system
│   └── app.js           # API client, polling, browser UI
├── test/game_test.rb    # Core-game tests (can run without installing gems)
├── data/rooms/          # Auto-created PStore save files (gitignored)
├── .env.example
├── Dockerfile
├── compose.yaml
└── Gemfile
```

## Test

```bash
ruby test/game_test.rb
ruby -c app.rb
ruby -c lib/game.rb
ruby -c lib/gm.rb
node --check public/app.js   # optional if Node.js is installed
```

These tests validate character creation, secret filtering, dice, effect caps, the offline GM, PStore persistence, and stalled GM recovery. **Live Gemini calls require a valid API key and are not exercised by these unit tests.**

## Security / operational notes

- Player bearer tokens are random and only their SHA-256 digests are stored server-side. Browsers keep their tokens in `localStorage` for reconnecting on refresh. **Protect the site with HTTPS**, because player sessions and room access matter.
- The eight-character room code is an invite secret; it is **not** a substitute for user accounts. Anyone with the link may join before the campaign starts if a slot is free. There is no account recovery after disconnecting from a running game.
- Persistent room files may include campaign content and player-submitted text. They are stored under `data/rooms/`; protect this directory and avoid exposing it as static content. `public/` is the only public static directory.
- Never commit `.env`, API keys, room data, or logs. The supplied `.gitignore` and `.dockerignore` omit them.
- For exposure to strangers on the internet, add **reverse-proxy rate limiting, user accounts/access controls, abuse moderation, backups, and resource quotas** before making it generally available. The supplied project is a playable self-hosted MVP, not a hardened public MMO service.
- If the API times out or fails, the current submitted actions remain available so the host can retry the round. After a process crash, stale GM locks are cleared automatically after three minutes of subsequent room access.
- `GEMINI_MODEL` is configurable. The assistant's narrative is treated as untrusted input: the server owns rolls, validates player IDs, caps effects, and never evaluates generated code.

## API

`POST /api/rooms` create; `POST /api/rooms/:code/join` join; `GET /api/rooms/:code` snapshot; `POST /api/rooms/:code/start` boot; `POST /api/rooms/:code/action` submit move; `POST /api/rooms/:code/resolve` host advance; `POST /api/rooms/:code/chat` message; `POST /api/rooms/:code/leave` disconnect; `GET /health` readiness. Authenticated routes use `Authorization: Bearer <player_token>`. JSON POST requests use `Content-Type: application/json`.

## Official API reference

- [Gemini Interactions API](https://ai.google.dev/gemini-api/docs/interactions-overview)
- [Gemini structured outputs](https://ai.google.dev/gemini-api/docs/structured-output)
- [Gemini API keys](https://ai.google.dev/gemini-api/docs/api-key)

Original concept and assets created as an independent cyberpunk-inspired project.
