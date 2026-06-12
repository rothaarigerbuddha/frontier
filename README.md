# Frontier

A small publishing site for a social-science project: mostly **articles**, with an
admin dashboard for authoring them, users/roles/permissions, and image uploads.

This repository glues together two pieces that were originally built separately:

- **`frontend/`** — Next.js 16 (App Router, React 19, Tailwind v4). Renders the
  public site and the `/dashboard` admin UI. All API calls happen **server-side**
  via Server Actions.
- **`backend/`** — .NET 8 Web API (Clean Architecture: Domain / Application /
  Infrastructure / Api) with SQLite, JWT auth and static image hosting.

They are wired together and runnable with **one command** via Docker Compose, and
can be exposed to the internet through a **single tunnel URL** (Cloudflare or ngrok)
— no domain or hosting rental required.

---

## Architecture

Everything is fronted by a tiny **Caddy gateway** so the browser only ever talks to
one origin. That removes CORS entirely and means a single tunnel exposes the whole app.

```
                           ┌──────────────────────────────┐
  browser / tunnel  ─────▶ │   gateway (Caddy)  :8080      │
                           │   one public origin           │
                           └───────────────┬──────────────┘
            /auth /posts /uploads /users    │    everything else
            /roles /permissions /images     │    ( / , /articles, /dashboard … )
            /swagger                        │
                  ┌─────────────────────────┴─────────────────────┐
                  ▼                                                ▼
        ┌───────────────────┐                          ┌───────────────────┐
        │  backend (.NET 8) │   internal network       │ frontend (Next.js)│
        │      :8080        │ ◀───────────────────────  │      :3000        │
        │  SQLite + images  │   server-side API calls   │  SSR + dashboard  │
        └───────────────────┘                          └───────────────────┘
```

- The frontend's **server-side** code calls the backend directly at
  `http://backend:8080` (compose network).
- Article **images** are referenced with **relative** URLs (`/images/posts/<file>`),
  so they resolve against whatever origin served the page — `localhost`, a tunnel,
  or a real domain — and the gateway routes them to the backend.

---

## Prerequisites

- **Docker** + **Docker Compose v2** (`docker compose`).
- **cloudflared** *(optional)* — only for the public tunnel. `ngrok` works too.

<details>
<summary>Install Docker</summary>

**Arch / CachyOS**
```bash
sudo pacman -S docker docker-compose docker-buildx
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"   # then log out/in so the group applies
```

**Ubuntu / Debian**
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"
```

**macOS / Windows** — install [Docker Desktop](https://www.docker.com/products/docker-desktop/).
</details>

<details>
<summary>Install cloudflared (optional — for the public tunnel)</summary>

```bash
# Arch / CachyOS
sudo pacman -S cloudflared            # or: yay -S cloudflared-bin

# Debian/Ubuntu
curl -fsSL https://pkg.cloudflare.com/cloudflared.deb -o cloudflared.deb && sudo dpkg -i cloudflared.deb

# macOS
brew install cloudflared
```
</details>

---

## Quick start

```bash
cp .env.example .env        # optional — defaults are fine for local testing
./run.sh                    # build + start everything, then open a public tunnel
```

What `run.sh` does:

1. builds and starts the three containers (`docker compose up -d --build`),
2. waits until the app answers on `http://localhost:8080`,
3. if `cloudflared` is installed, opens a **Cloudflare quick tunnel** and prints a
   public `https://<random>.trycloudflare.com` URL you can share.

Variants:

```bash
./run.sh --no-tunnel    # local only, no tunnel
./run.sh --logs         # follow container logs
./run.sh --down         # stop & remove the stack
```

Prefer raw compose? `docker compose up --build` then open `http://localhost:8080`.

### What you get

| URL | What |
|-----|------|
| `http://localhost:8080` | Public site (article list + reader) |
| `http://localhost:8080/dashboard` | Admin dashboard — **login `admin` / `admin123`** |
| `http://localhost:8080/swagger` | Backend API explorer |

The database is auto-created and seeded on first start (admin user + a "Hello, world!" post).

---

## Public tunnel

The app is one origin on port `8080`, so any HTTP tunnel pointed at
`http://localhost:8080` exposes the whole thing — pages, API and images.

### Option A — Cloudflare quick tunnel (zero config, instant)

Already automated by `./run.sh`. To do it manually:

```bash
cloudflared tunnel --url http://localhost:8080
```

Copy the printed `https://<something>.trycloudflare.com` URL. Good for demos; the
URL is random and changes every run.

### Option B — Cloudflare named tunnel (stable URL / your own domain)

For a persistent address (requires a free Cloudflare account + a domain on Cloudflare):

```bash
cloudflared login                              # authorize in the browser
cloudflared tunnel create frontier             # creates a tunnel + credentials
cloudflared tunnel route dns frontier app.example.com
cloudflared tunnel run --url http://localhost:8080 frontier
```

`app.example.com` now serves the app over HTTPS, stably.

### Option C — ngrok

```bash
# install: https://ngrok.com/download  (Arch: yay -S ngrok)
ngrok config add-authtoken <YOUR_TOKEN>        # one-time, free account
ngrok http 8080
```

Share the `https://<id>.ngrok-free.app` URL ngrok prints.

> **Already whitelisted:** Next.js Server Actions reject cross-origin requests by
> default. `*.trycloudflare.com`, `*.ngrok-free.app`, `*.ngrok.app` and `localhost`
> are pre-approved in `frontend/next.config.ts` (`serverActions.allowedOrigins`).
> If you use a **custom domain**, add it there.

---

## Running without Docker (local dev)

Two terminals, the original dev workflow:

```bash
# 1) backend  (needs the .NET 8 SDK)
cd backend/FrontierWeb
dotnet run                       # -> http://localhost:5160  (+ /swagger)

# 2) frontend (needs Node 20+)
cd frontend
cp .env.example .env             # API_INTERNAL_URL + NEXT_PUBLIC_IMAGE_BASE_URL=http://localhost:5160
npm install
npm run dev                      # -> http://localhost:3000
```

Here there is no gateway, so the frontend and backend are on different origins —
that is exactly why `NEXT_PUBLIC_IMAGE_BASE_URL` must point at the backend for
images to load.

---

## Configuration

Set in `.env` (consumed by `docker-compose.yml`):

| Variable | Default | Purpose |
|----------|---------|---------|
| `PORT` | `8080` | Host port for the gateway / whole app |
| `AUTH_KEY` | dev placeholder | JWT signing key — **change for real use** |
| `CORS_ALLOWED_ORIGINS` | empty (any) | Comma-separated backend CORS allowlist |

Service-level env (already set in compose, override only if you know why):

| Variable | Service | Purpose |
|----------|---------|---------|
| `API_INTERNAL_URL` | frontend | Server-side backend base URL (`http://backend:8080`) |
| `NEXT_PUBLIC_IMAGE_BASE_URL` | frontend | Empty → relative image URLs via the gateway |
| `ConnectionStrings__BlogDb` | backend | SQLite location (`/data/blog.db` on a volume) |

---

## Data & persistence

Two named Docker volumes keep state across restarts/rebuilds:

- `backend-db` → the SQLite database (`/data/blog.db`)
- `backend-uploads` → uploaded article images (`/app/wwwroot/images/posts`)

Wipe everything and start fresh (re-seeds admin + sample post):

```bash
docker compose down -v
```

---

## Layout

```
frontier/
├── docker-compose.yml      # gateway + frontend + backend, one command
├── run.sh                  # build/up + Cloudflare quick tunnel
├── .env.example
├── gateway/Caddyfile       # single-origin reverse proxy
├── frontend/               # Next.js app (+ Dockerfile)
└── backend/                # .NET 8 solution (+ Dockerfile, entrypoint)
```

---

## Notes / before going to production

This setup is tuned for **local testing and demos**. Tighten these before any real deployment:

- The seed admin (`admin` / `admin123`) is **for testing only** — change/remove it
  (`backend/.../DataSeeder.cs`) and set a strong `AUTH_KEY`.
- Posts/uploads write endpoints currently have `[Authorize(Policy = "AdminOnly")]`
  **commented out** in the backend controllers — they are open to anyone. Re-enable
  them for production.
- Restrict `CORS_ALLOWED_ORIGINS` to your real domain.
- Put real TLS in front (a named Cloudflare tunnel or a proper reverse proxy).
