#!/bin/sh
set -e

# SQLite database lives on a persistent volume (see docker-compose.yml ->
# ConnectionStrings__BlogDb=Data Source=/data/blog.db).
mkdir -p /data

# Uploaded images live on a persistent volume mounted at this path. On a fresh
# volume it is empty, so repopulate it with the images bundled in the build
# (without ever overwriting real uploads — `cp -n`).
mkdir -p /app/wwwroot/images/posts
if [ -d /seed/posts ]; then
  cp -rn /seed/posts/. /app/wwwroot/images/posts/ 2>/dev/null || true
fi

exec dotnet FrontierWeb.Api.dll
