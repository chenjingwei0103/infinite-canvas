#!/bin/sh
set -eu

repo_root=/opt/infinite-canvas
compose_file=$repo_root/docker-compose.server.yml
container_name=infinite-canvas
lock_file=/run/lock/infinite-canvas-update.lock
deployed_file=$repo_root/.deployed-revision

exec 9>"$lock_file"
flock -n 9 || exit 0

git -C "$repo_root" remote set-url origin https://github.com/chenjingwei0103/infinite-canvas.git
git -C "$repo_root" fetch --prune origin main

target_revision=$(git -C "$repo_root" rev-parse origin/main)
deployed_revision=$(cat "$deployed_file" 2>/dev/null || true)
if [ "$target_revision" = "$deployed_revision" ]; then
    printf '%s\n' "infinite_canvas_up_to_date=$target_revision"
    exit 0
fi

worktree_status=$(git -C "$repo_root" status --porcelain)
if [ -n "$worktree_status" ]; then
    unexpected_status=$(printf '%s\n' "$worktree_status" | grep -v -E '^\?\? (\.deploy-backups/|\.deployed-revision)$' || true)
    if [ -n "$unexpected_status" ]; then
        printf '%s\n' "$unexpected_status"
        exit 2
    fi
fi

git -C "$repo_root" switch main
git -C "$repo_root" pull --ff-only origin main
docker compose -f "$compose_file" config >/dev/null
docker compose -f "$compose_file" build --pull app
docker compose -f "$compose_file" up -d --no-build app

if [ "$(docker inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null || true)" != "true" ]; then
    docker compose -f "$compose_file" logs --tail 100 app || true
    exit 3
fi

docker exec "$container_name" node -e 'fetch("http://127.0.0.1:3000/").then((response) => { console.log("app_http=" + response.status); process.exit(response.ok ? 0 : 1); }).catch(() => process.exit(1))'
printf '%s\n' "$target_revision" > "$deployed_file.tmp"
mv "$deployed_file.tmp" "$deployed_file"
printf '%s\n' "infinite_canvas_updated=$target_revision"
