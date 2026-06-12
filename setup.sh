#!/usr/bin/env bash
#
# Frontier — ONE-TIME host setup (run once per machine).
#
# This is intentionally SEPARATE from run.sh: it performs privileged, system-wide
# changes (installing packages, enabling the Docker daemon, adding you to the
# `docker` group) and therefore uses `sudo` and will ask for your password.
# run.sh does NOT do any of this — it just builds and launches the app as your
# normal user.
#
#   ./setup.sh             install everything + enable Docker + add you to the group
#   ./setup.sh --yes       don't ask for confirmation
#   ./setup.sh --no-ngrok  skip installing ngrok (default tunnel provider)
#
# After it finishes you must LOG OUT and back in once so the `docker` group
# applies, then: ./run.sh

set -euo pipefail
cd "$(dirname "$0")"

c_green=$'\e[32m'; c_yellow=$'\e[33m'; c_red=$'\e[31m'; c_bold=$'\e[1m'; c_off=$'\e[0m'
info() { printf '%s==>%s %s\n' "$c_green" "$c_off" "$*"; }
warn() { printf '%s!!%s %s\n' "$c_yellow" "$c_off" "$*"; }
die()  { printf '%sxx%s %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }

ASSUME_YES=0
WITH_NGROK=1
for a in "$@"; do
  case "$a" in
    --yes|-y)   ASSUME_YES=1 ;;
    --no-ngrok) WITH_NGROK=0 ;;
    *) die "Unknown option: $a (use --yes, --no-ngrok)" ;;
  esac
done

[ "$(id -u)" -eq 0 ] && die "Run this as your normal user (NOT root/sudo) — it calls sudo itself only where needed."
command -v sudo >/dev/null 2>&1 || die "sudo is required but not found."

# ---- detect package manager ------------------------------------------------
PM=""
for c in pacman apt-get dnf zypper brew; do command -v "$c" >/dev/null 2>&1 && { PM="$c"; break; }; done
[ -n "$PM" ] || die "No supported package manager found. Install Docker manually (see README.md)."

info "Detected package manager: ${c_bold}${PM}${c_off}"
NGROK_LABEL=""; [ "$WITH_NGROK" = 1 ] && NGROK_LABEL=" + ngrok"
cat <<EOF

This will:
  • install Docker + Docker Compose + buildx + cloudflared${NGROK_LABEL}
  • enable & start the Docker service
  • add user '${USER}' to the 'docker' group
It uses ${c_bold}sudo${c_off} and may prompt for your password.

EOF
if [ "$ASSUME_YES" = 0 ]; then
  printf 'Proceed? [y/N] '; read -r ans
  case "$ans" in y|Y|yes|YES) ;; *) die "Aborted." ;; esac
fi

# ---- install Docker + tools ------------------------------------------------
install_pacman() {
  sudo pacman -S --needed --noconfirm docker docker-compose docker-buildx cloudflared
}
install_apt() {
  sudo apt-get update
  # Docker via the official convenience script (adds Docker's repo + compose plugin)
  if ! command -v docker >/dev/null 2>&1; then curl -fsSL https://get.docker.com | sudo sh; fi
  sudo apt-get install -y docker-compose-plugin docker-buildx-plugin || true
  if ! command -v cloudflared >/dev/null 2>&1; then
    curl -fsSL https://pkg.cloudflare.com/cloudflared.deb -o /tmp/cloudflared.deb && sudo dpkg -i /tmp/cloudflared.deb || \
      warn "cloudflared not installed automatically — see https://github.com/cloudflare/cloudflared"
  fi
}
install_dnf()    { sudo dnf install -y docker docker-compose || sudo dnf install -y moby-engine docker-compose; }
install_zypper() { sudo zypper install -y docker docker-compose; }
install_brew()   { brew install docker docker-compose colima cloudflared; warn "On macOS use Docker Desktop or Colima to run the daemon."; }

info "Installing Docker and tooling..."
case "$PM" in
  pacman) install_pacman ;;
  apt-get) install_apt ;;
  dnf) install_dnf ;;
  zypper) install_zypper ;;
  brew) install_brew ;;
esac

# ---- ngrok (default tunnel) ------------------------------------------------
install_ngrok() {
  command -v ngrok >/dev/null 2>&1 && { info "ngrok already installed."; return; }
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64)          url="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz" ;;
    Linux-aarch64|Linux-arm64) url="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz" ;;
    Darwin-*)              brew install ngrok/ngrok/ngrok 2>/dev/null || warn "Install ngrok from https://ngrok.com/download"; return ;;
    *) warn "Unknown platform — install ngrok manually from https://ngrok.com/download"; return ;;
  esac
  info "Installing ngrok..."
  tmp="$(mktemp -d)"
  curl -fsSL "$url" | tar -xz -C "$tmp" ngrok
  sudo install -m 0755 "$tmp/ngrok" /usr/local/bin/ngrok
  rm -rf "$tmp"
}
[ "$WITH_NGROK" = 1 ] && install_ngrok

# ---- enable & start the daemon (systemd) -----------------------------------
if command -v systemctl >/dev/null 2>&1; then
  info "Enabling & starting the Docker service..."
  sudo systemctl enable --now docker.service || warn "Could not start docker.service — check: systemctl status docker.service"
fi

# ---- docker group ----------------------------------------------------------
NEED_RELOGIN=0
if id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
  info "User '${USER}' is already in the 'docker' group."
else
  info "Adding '${USER}' to the 'docker' group..."
  sudo usermod -aG docker "$USER"
  NEED_RELOGIN=1
fi

# ---- summary ---------------------------------------------------------------
echo
info "${c_bold}Setup complete.${c_off}"
command -v docker      >/dev/null 2>&1 && echo "  docker:      $(docker --version 2>/dev/null)"
docker compose version >/dev/null 2>&1 && echo "  compose:     $(docker compose version --short 2>/dev/null)"
command -v ngrok       >/dev/null 2>&1 && echo "  ngrok:       $(ngrok --version 2>/dev/null)"
command -v cloudflared >/dev/null 2>&1 && echo "  cloudflared: $(cloudflared --version 2>/dev/null | head -1)"
echo

if [ "$NEED_RELOGIN" = 1 ]; then
  warn "${c_bold}Log out and back in${c_off} (or reboot) so the 'docker' group applies, then run: ./run.sh"
  warn "To use it immediately in THIS terminal without relogin: 'newgrp docker' then ./run.sh"
else
  info "You're ready. Start the app with: ${c_bold}./run.sh${c_off}"
fi

if command -v ngrok >/dev/null 2>&1; then
  echo
  info "ngrok is the default tunnel. Authenticate once (free account):"
  echo "  ngrok config add-authtoken <YOUR_TOKEN>   # from https://dashboard.ngrok.com/get-started/your-authtoken"
fi
