#!/usr/bin/env bash
#
# Frontier — one-command local launcher.
#
#   ./run.sh                 build + start the whole stack, then open a
#                            Cloudflare quick tunnel (public HTTPS URL).
#   ./run.sh --no-tunnel     just build + start locally (http://localhost:8080).
#   ./run.sh --down          stop and remove the stack.
#   ./run.sh --logs          follow container logs.
#
# Prerequisites: Docker + Docker Compose v2. cloudflared is optional (only
# needed for the public tunnel) — see README.md if it is missing.

set -euo pipefail

cd "$(dirname "$0")"

PORT="${PORT:-8080}"
LOCAL_URL="http://localhost:${PORT}"

# ---- pretty printing -------------------------------------------------------
c_green=$'\e[32m'; c_yellow=$'\e[33m'; c_red=$'\e[31m'; c_bold=$'\e[1m'; c_off=$'\e[0m'
info()  { printf '%s==>%s %s\n' "$c_green" "$c_off" "$*"; }
warn()  { printf '%s!! %s%s\n' "$c_yellow" "$*" "$c_off"; }
die()   { printf '%sxx %s%s\n' "$c_red" "$*" "$c_off" >&2; exit 1; }

# ---- docker compose detection ---------------------------------------------
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  die "Docker Compose not found. Install Docker Desktop or the docker + docker-compose-plugin packages (see README.md)."
fi

docker info >/dev/null 2>&1 || die "Docker daemon is not running. Start Docker and retry."

# ---- subcommands -----------------------------------------------------------
case "${1:-}" in
  --down)  info "Stopping stack..."; $DC down; exit 0 ;;
  --logs)  exec $DC logs -f ;;
esac

TUNNEL=1
TUNNEL_PROVIDER="${TUNNEL_PROVIDER:-cloudflared}"
case "${1:-}" in
  --no-tunnel) TUNNEL=0 ;;
  --tunnel)    TUNNEL_PROVIDER="${2:-cloudflared}" ;;
esac

# ---- build + start ---------------------------------------------------------
info "Building and starting containers (this can take a few minutes the first time)..."
$DC up -d --build

# ---- wait for the gateway to answer ---------------------------------------
info "Waiting for the app to become healthy at ${LOCAL_URL} ..."
ready=0
for _ in $(seq 1 60); do
  if curl -fsS -o /dev/null "${LOCAL_URL}" 2>/dev/null; then ready=1; break; fi
  sleep 2
done
if [ "$ready" = 1 ]; then
  info "${c_bold}App is up:${c_off} ${LOCAL_URL}"
else
  warn "Gateway did not answer yet. Check logs with: ./run.sh --logs"
fi

cat <<EOF

  ${c_bold}Frontier is running${c_off}
  ----------------------------------------------------------
  Site        ${LOCAL_URL}
  Dashboard   ${LOCAL_URL}/dashboard   (login: admin / admin123)
  API (Swagger) ${LOCAL_URL}/swagger
  ----------------------------------------------------------

EOF

# ---- public tunnel ---------------------------------------------------------
if [ "$TUNNEL" = 0 ]; then
  info "Started without a tunnel (--no-tunnel)."
  exit 0
fi

info "Opening public tunnel via: ${c_bold}${TUNNEL_PROVIDER}${c_off}"
info "Press Ctrl+C to close the tunnel (containers keep running; stop them with ./run.sh --down)."
echo

case "$TUNNEL_PROVIDER" in
  cloudflared)
    command -v cloudflared >/dev/null 2>&1 || {
      warn "cloudflared is not installed — skipping. Try: ./run.sh --tunnel localhost.run"
      warn "The app is still fully usable locally at ${LOCAL_URL}"; exit 0; }
    warn "If this stalls at 'Requesting new quick Tunnel', your ISP likely blocks trycloudflare.com."
    warn "Fallback that needs no account/install: ./run.sh --tunnel localhost.run"
    exec cloudflared tunnel --url "${LOCAL_URL}"
    ;;
  localhost.run|localhostrun|lhr)
    # SSH reverse tunnel — no account, no install (ssh is already present).
    # Prints a public https://*.lhr.life URL.
    exec ssh -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30 \
      -R 80:localhost:"${PORT}" localhost.run
    ;;
  serveo)
    exec ssh -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30 \
      -R 80:localhost:"${PORT}" serveo.net
    ;;
  ngrok)
    command -v ngrok >/dev/null 2>&1 || {
      warn "ngrok is not installed. Install from https://ngrok.com/download (AUR: paru -S ngrok),"
      warn "then authenticate once: ngrok config add-authtoken <YOUR_TOKEN>"; exit 0; }
    exec ngrok http "${PORT}"
    ;;
  *)
    die "Unknown tunnel provider '${TUNNEL_PROVIDER}'. Use: cloudflared | localhost.run | ngrok | serveo"
    ;;
esac
