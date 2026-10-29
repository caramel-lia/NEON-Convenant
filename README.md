# NEON//COVENANT — Meridian-9 Website Edition

A complete **Ruby + Sinatra cyberpunk tabletop RPG website** with a proper public homepage and a separate playable multiplayer client. Designed in a dark violet/cyan cyberpunk TUI style.

## What's new

| Page | Route | Function |
|---|---|---|
| Home | `/` | Responsive landing page with live tactical-grid illustration, product information, class selector, FAQ, Start/Join buttons, resume link |
| Play | `/play` | Full existing RPG client — character creation, room lobby, Gemini GM, synchronized tactical grid, manual dice, crew chat and campaign state |
| Field manual | `/guide` | Play instructions, mechanics, character stats, map controls, dice, saves |
| World | `/world` | Meridian-9 city lore, districts and campaign themes |
| Error page | Other non-API paths | Custom 404 page and home link |
| Health check | `/health` | JSON server/GM configuration status |

Campaigns remain compatible with the **Gemini Grid Fixed** version. Server code and game mechanics are preserved.

## Install (Kali Linux)

```bash
sudo apt update
sudo apt install -y ruby ruby-dev build-essential

cd ~/NEON-Convenant
bundle config set --local path vendor/bundle
bundle install
```

If it's your first time installing the project:

```bash
cp .env.example .env
nano .env
```

Configure the **server-side** environment file:

```dotenv
GEMINI_API_KEY=your_api_key_here
GEMINI_MODEL=gemini-3.5-flash-lite
DEMO_MODE=false
PORT=4567
BIND=127.0.0.1
RACK_ENV=development
```

The `GEMINI_API_KEY` must never be stored in frontend JavaScript or committed to Git. Get a key from https://aistudio.google.com/apikey. Availability and free-tier quotas depend on your account and region.

For a local test with no API requests:

```dotenv
DEMO_MODE=true
```

Start the website:

```bash
bundle exec ruby app.rb
```

Open **http://localhost:4567/** for the homepage; the playable console is at **http://localhost:4567/play**.

### Upgrade from a previous NEON//COVENANT release

1. Stop Sinatra and **back up `.env` plus `data/rooms/`**.
2. Extract the new ZIP into a temporary directory.
3. Copy `app.rb`, `Gemfile`, `config.ru`, `lib/`, `public/`, `scripts/` and `test/` into your existing app directory. **Do not replace** your `.env` or `data/rooms/`.
4. Run `bundle config set --local path vendor/bundle && bundle install`.
5. Run `ruby scripts/doctor.rb`, then `bundle exec ruby app.rb`.
6. Open `/` and use Ctrl+Shift+R to refresh cached styles.

Old invite URLs of the form `/?room=ABCDEFGH` redirect to `/play?room=ABCDEFGH`.

### Deploy through Cloudflare Tunnel

The application binds to `127.0.0.1:4567` by default so Cloudflare Tunnel can forward locally to it. When serving a custom hostname, add the hostname (not the URL) to `APP_HOSTS`:

```dotenv
APP_HOSTS=rpg.example.com
```

Production exposure requires additional protections. This is a **self-hosted multiplayer MVP**, not a hardened public SaaS: consider Cloudflare Access, request limiting, backups, monitoring, HTTPS, and a controlled invite audience. Room creation is intentionally not tied to user accounts. Do not publicly expose the app without considering abuse and API costs.

## Gameplay overview

- Up to **five** operatives per room (including host)
- Roles: Netrunner, Solo, Ghost, Techie, Fixer
- Three campaign themes: Noir, Rebellion, Ghost Signal
- Gemini game master creates scenes and consequences; Ruby controls dice and validated effects
- 2D6 + stat versus DC 10 for committed actions; manual D4/D6/D8/D10/D12/D20/D100 for ad hoc rolls
- Shared **14 × 9** grid with moveable player tokens, walls, cover, objectives, and hazards; host terrain editor
- Room and progress persistence in `data/rooms/` with browser-local bearer session tokens
- Shared event feed, crew chat, invite links and host-initiated round resolution

## File structure

```text
neon_covenant_full_site/
├── app.rb                      # Sinatra game API, website routes, custom 404
├── Gemfile                     # Sinatra, Rackup, Puma, dotenv
├── .env.example                # Environment variable template
├── lib/                        # Existing campaign, tactical map, Gemini GM
├── public/
│   ├── index.html              # New homepage /
│   ├── world.html              # /world
│   ├── guide.html              # /guide
│   ├── 404.html                # Custom missing page
│   ├── site.css / site.js      # Public website styles and interactions
│   ├── play.html               # Existing playable client /play
│   ├── style.css / app.js      # In-game styling and mechanics
│   └── favicon.svg
├── scripts/doctor.rb
├── test/game_test.rb
└── data/rooms/                # Persistent saved campaigns
```

## Validation

```bash
ruby -c app.rb
node --check public/site.js
node --check public/app.js
ruby test/game_test.rb
ruby test/site_test.rb
```

Both the existing game tests and new website structure tests run without a live API key. A real Gemini narration turn needs a configured API key, and a live deployment still needs end-to-end testing on your server.

## Limitations

- The homepage tactical map is an **illustrative CSS grid**. The actual interactive multiplayer map is inside `/play`.
- Browser sessions are stored locally, not in cross-device login accounts.
- Multiplayer updates poll the server roughly every 2.6 seconds instead of using WebSockets.
- There is no account system, public campaign directory, moderation panel, payments, or matchmaking service.
- The Gemini free tier has usage quotas. Demo mode is available for a local test.
