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

## Integration changes (frontend ↔ backend)

> **For the frontend & backend developers.** The two repos were built
> independently and disagreed on a few contracts. This section lists **every**
> change made to wire them together, file by file. Upstream business logic was
> otherwise left untouched — the edits are deliberately minimal.

### The one contract that mattered: the post `image` field

- A post's `image` holds **only a filename** (e.g. `abc123.jpg`). The backend
  saves uploads under `wwwroot/images/posts/` and serves them at
  `/images/posts/<filename>`. The **frontend builds the display URL at render
  time**. The frontend previously stored the *full* URL in `image`, which broke
  portability (the host got baked into the DB) and the article page.

### Frontend (`frontend/`)

| File | Change | Why |
|------|--------|-----|
| `src/lib/axios/httpClient.ts` | API base URL now from server-only `API_INTERNAL_URL` (→ `http://backend:8080` in Docker), falling back to `NEXT_PUBLIC_API_BASE_URL` then `http://localhost:5160` | This client runs **only server-side** (reads cookies via `next/headers`); it must reach the backend over the internal network, not a browser URL |
| `src/lib/utils.ts` (`getImageUrlFromPath`) | Returns a **relative** `/images/posts/<file>` URL by default (override with `NEXT_PUBLIC_IMAGE_BASE_URL`); tolerates already-absolute URLs and already-rooted paths | Images are fetched by the browser; a relative URL resolves against the page origin (gateway / tunnel / domain) and never hard-codes a host |
| `src/components/dashboard/CreateArticleForm.tsx` | Store only the uploaded **filename** in `image`; no longer crashes when submitting without a cover (`imageUpRes?.url ?? "placeholder.png"`); empty `notes` defaults to `"—"` | Match the backend contract; backend requires non-empty `Notes` |
| `src/components/dashboard/UpdateArticleForm.tsx` | Same filename-only contract; keep the existing image when no new file is uploaded; initial preview built via `getImageUrlFromPath`; empty `notes` defaults | Same as above |
| `src/app/(commonLayout)/articles/[slug]/page.tsx` | Cover rendered via `getImageUrlFromPath(article.image)` | Was `src={article.image}` (a bare filename) — the image never displayed |
| `next.config.ts` | `output: "standalone"`; `serverActions.allowedOrigins` (localhost + tunnel domains); `serverActions.bodySizeLimit: "15mb"`; trimmed `images.remotePatterns` to Unsplash | Slim Docker image; Server Actions must accept the gateway/tunnel origin (CSRF check) or login/create return 403; cover uploads go through a Server Action and the default 1 MB cap is too small |
| `.env.example`, `Dockerfile`, `.dockerignore` | **New** | Standalone Next.js image + local-dev env template |

### Backend (`backend/`)

| File | Change | Why |
|------|--------|-----|
| `FrontierWeb/Program.cs` | CORS is now configurable via `Cors:AllowedOrigins` (comma-separated); default = allow any origin (demo). Was hard-coded to `http://localhost:5173` | That was the old Vite dev port; it blocked the real frontend. Behind the gateway everything is same-origin anyway |
| `FrontierWeb/blog.db` | **Removed from the repo** | It was a **stale** SQLite file: its `Users` table had a flat `Role` column and **no** `Roles`/`Permissions`/`UserRoles` tables, so the current code (`AuthService` does `.Include(u => u.UserRoles)`) throws *"no such table"*. The DB is now created & seeded fresh on first run (`EnsureCreatedAsync` + `DataSeeder` → `admin`/`admin123` + a sample post) |
| `Dockerfile`, `.dockerignore`, `docker-entrypoint.sh` | **New** | Multi-stage .NET build; entrypoint re-seeds the uploads volume with bundled images and keeps the DB on a volume |

> No backend C# *business logic* was changed beyond CORS and dropping the stale DB file.

### New orchestration files (repo root)

`docker-compose.yml` · `gateway/Caddyfile` · `run.sh` · `.env.example` · `.gitignore`
— these are additive and don't touch either app's source.

---

## Изменения для согласования фронта и бэка *(RU)*

> **Для разработчиков фронта и бэка.** Репозитории делались независимо и
> расходились в нескольких контрактах. Ниже — **все** правки для их связки,
> по файлам. Бизнес-логику в остальном не трогали — изменения намеренно минимальны.

### Главный контракт — поле `image` у поста

- В `image` хранится **только имя файла** (например `abc123.jpg`). Бэк сохраняет
  загрузки в `wwwroot/images/posts/` и отдаёт по `/images/posts/<имя>`. **URL для
  показа строит фронт при рендере.** Раньше фронт записывал в `image` *полный*
  URL — из-за этого адрес хоста «вшивался» в БД и ломалась страница статьи.

### Фронтенд (`frontend/`)

| Файл | Изменение | Зачем |
|------|-----------|-------|
| `src/lib/axios/httpClient.ts` | Базовый URL API берётся из серверной `API_INTERNAL_URL` (→ `http://backend:8080` в Docker), фолбэк на `NEXT_PUBLIC_API_BASE_URL`, затем `http://localhost:5160` | Клиент работает **только на сервере** (читает куки через `next/headers`) и должен ходить в бэк по внутренней сети, а не по браузерному адресу |
| `src/lib/utils.ts` (`getImageUrlFromPath`) | По умолчанию возвращает **относительный** `/images/posts/<файл>` (можно переопределить `NEXT_PUBLIC_IMAGE_BASE_URL`); понимает уже-абсолютные URL и уже-корневые пути | Картинки грузит браузер; относительный URL резолвится против origin страницы (шлюз/туннель/домен) и не «зашивает» хост |
| `src/components/dashboard/CreateArticleForm.tsx` | В `image` пишется только **имя файла**; больше не падает без обложки (`imageUpRes?.url ?? "placeholder.png"`); пустые `notes` → `"—"` | Соответствие контракту бэка; бэк требует непустое `Notes` |
| `src/components/dashboard/UpdateArticleForm.tsx` | Тот же контракт «только имя файла»; без новой загрузки сохраняется прежняя картинка; превью строится через `getImageUrlFromPath`; пустые `notes` по умолчанию | То же |
| `src/app/(commonLayout)/articles/[slug]/page.tsx` | Обложка рендерится через `getImageUrlFromPath(article.image)` | Было `src={article.image}` (голое имя файла) — картинка не показывалась |
| `next.config.ts` | `output: "standalone"`; `serverActions.allowedOrigins` (localhost + домены туннелей); `serverActions.bodySizeLimit: "15mb"`; в `images.remotePatterns` оставлен только Unsplash | Компактный Docker-образ; Server Actions должны принимать origin шлюза/туннеля (защита от CSRF), иначе логин/создание дают 403; загрузка обложки идёт через Server Action, а лимит 1 МБ по умолчанию мал |
| `.env.example`, `Dockerfile`, `.dockerignore` | **Новые** | Standalone-образ Next.js + шаблон env для локалки |

### Бэкенд (`backend/`)

| Файл | Изменение | Зачем |
|------|-----------|-------|
| `FrontierWeb/Program.cs` | CORS настраивается через `Cors:AllowedOrigins` (через запятую); по умолчанию — любой origin (демо). Было жёстко `http://localhost:5173` | Это старый порт Vite; он блокировал реальный фронт. За шлюзом всё равно один origin |
| `FrontierWeb/blog.db` | **Удалён из репозитория** | Это **устаревшая** БД: в её `Users` была плоская колонка `Role` и **не было** таблиц `Roles`/`Permissions`/`UserRoles`, поэтому текущий код (`AuthService` делает `.Include(u => u.UserRoles)`) падал с *"no such table"*. Теперь БД создаётся и засеивается заново при старте (`EnsureCreatedAsync` + `DataSeeder` → `admin`/`admin123` + пример поста) |
| `Dockerfile`, `.dockerignore`, `docker-entrypoint.sh` | **Новые** | Многостадийная сборка .NET; entrypoint досеивает том загрузок встроенными картинками и держит БД на томе |

> Бизнес-логику бэка (C#) кроме CORS и удаления устаревшей БД не меняли.

### Новые файлы оркестрации (корень репозитория)

`docker-compose.yml` · `gateway/Caddyfile` · `run.sh` · `.env.example` · `.gitignore`
— только добавлены, исходники приложений не затрагивают.

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

`./run.sh` opens a tunnel for you; pick the provider with `--tunnel`:

```bash
./run.sh --tunnel cloudflared     # default
./run.sh --tunnel localhost.run   # no account, no install (just ssh)
./run.sh --tunnel ngrok           # needs a free ngrok account
```

> **If the Cloudflare quick tunnel stalls** at `Requesting new quick Tunnel…`
> (`context deadline exceeded`), your ISP is blocking `trycloudflare.com`
> (common SNI filtering). Use `./run.sh --tunnel localhost.run` instead — it goes
> over SSH and is not affected. Named Cloudflare tunnels (Option B) also work,
> since they don't use `trycloudflare.com`.

### Option A — Cloudflare quick tunnel (zero config, instant)

Already automated by `./run.sh`. To do it manually:

```bash
cloudflared tunnel --url http://localhost:8080
```

Copy the printed `https://<something>.trycloudflare.com` URL. Good for demos; the
URL is random and changes every run.

### Option A2 — localhost.run (no account, no install)

```bash
ssh -R 80:localhost:8080 localhost.run
```

Prints a public `https://<random>.lhr.life` URL. SSH-based, so it works even where
`trycloudflare.com` is blocked.

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

## Поднять сервер самому — требования и шаги *(RU)*

### Требования

**Способ 1 — Docker (рекомендуется, всё одной командой):**
- **Docker** + **Docker Compose v2** (`docker compose`);
- ~несколько ГБ свободного места на диске и интернет (для первой сборки/скачивания образов);
- свободный порт **8080** на хосте (меняется через `PORT` в `.env`);
- *(опционально)* для публичной ссылки — `cloudflared`, `ngrok` или просто `ssh` (для localhost.run).

**Способ 2 — без Docker (как в исходных репозиториях):**
- **.NET 8 SDK** (бэкенд), **Node.js 20+** и npm (фронтенд).

### Установка инструментов

```bash
# Arch / CachyOS
sudo pacman -S docker docker-compose docker-buildx cloudflared
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"      # затем перелогиниться, чтобы группа применилась

# Ubuntu / Debian
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"

# macOS / Windows — Docker Desktop: https://www.docker.com/products/docker-desktop/
```

> ⚠️ Если после установки `docker` служба не стартует с ошибкой про `iptables`/`PREROUTING`
> — почти всегда помогает **перезагрузка** (так бывает, когда ядро обновлялось без ребута,
> и netfilter-модули для текущего ядра не загружаются).

### Запуск (Docker)

```bash
cd frontier
cp .env.example .env          # необязательно — значения по умолчанию подходят для локалки
./run.sh                      # сборка + старт всего стека, затем публичный туннель
```

Что делает `run.sh`: собирает и поднимает 3 контейнера (`docker compose up -d --build`),
ждёт ответа на `http://localhost:8080`, затем открывает туннель.

Варианты:
```bash
./run.sh --no-tunnel              # только локально, без туннеля
./run.sh --tunnel localhost.run   # публичная ссылка без аккаунта/установки (через ssh)
./run.sh --tunnel ngrok           # нужен бесплатный аккаунт ngrok
./run.sh --logs                   # смотреть логи контейнеров
./run.sh --down                   # остановить и удалить стек
```

Без скрипта: `docker compose up --build`, затем открыть `http://localhost:8080`.

### Что получаем

| URL | Что |
|-----|-----|
| `http://localhost:8080` | Публичный сайт (список статей + чтение) |
| `http://localhost:8080/dashboard` | Админка — вход **`admin` / `admin123`** |
| `http://localhost:8080/swagger` | Обзор API бэкенда |

БД создаётся и засеивается при первом старте (пользователь `admin` + пост «Hello, world!»).

### Данные и сброс

Состояние живёт в Docker-томах (`backend-db` — БД, `backend-uploads` — загруженные картинки)
и переживает перезапуск. Полный сброс к чистому состоянию:
```bash
docker compose down -v
```

### Запуск без Docker

См. англоязычный раздел **“Running without Docker (local dev)”** выше: бэк — `dotnet run`
в `backend/FrontierWeb` (→ `:5160`), фронт — `npm install && npm run dev` в `frontend`
(→ `:3000`), при этом в `frontend/.env` укажи `NEXT_PUBLIC_IMAGE_BASE_URL=http://localhost:5160`.

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
