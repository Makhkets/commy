#!/usr/bin/env bash
# Deploys Commy Cloud to the owner's server: source to /opt/commy-cloud/src,
# build and (re)start the container. Does not touch Caddy or DNS — those are
# one-time steps described in docs/19-commy-cloud.md, «Инфраструктура».
#
#   SSHPASS=... ./deploy.sh            (or with an SSH key: SSH="ssh" ./deploy.sh)
set -euo pipefail
HOST="${HOST:-root@31.76.100.71}"
SSH="${SSH:-sshpass -e ssh -o ConnectTimeout=20}"
here="$(cd "$(dirname "$0")" && pwd)"
tar -C "$here/.." --exclude=./data --exclude=./deploy -czf - . \
  | $SSH "$HOST" 'set -e; mkdir -p /opt/commy-cloud/src /opt/commy-cloud/data; rm -rf /opt/commy-cloud/src.new; mkdir /opt/commy-cloud/src.new; tar -C /opt/commy-cloud/src.new -xzf -; rm -rf /opt/commy-cloud/src; mv /opt/commy-cloud/src.new /opt/commy-cloud/src; chown 10001:10001 /opt/commy-cloud/data'
$SSH "$HOST" 'cat > /opt/commy-cloud/docker-compose.yml' < "$here/docker-compose.yml"
$SSH "$HOST" 'cd /opt/commy-cloud && docker compose up -d --build && sleep 3 && curl -fsS http://127.0.0.1:8097/healthz'
