#!/bin/bash
set -e
cd /workspace
rm -rf /workspace/node-v22.*-linux-x64
if [ ! -x /workspace/node/bin/node ]; then
  V=$(curl -s https://nodejs.org/dist/index.json | python3 -c 'import json,sys; print([r["version"] for r in json.load(sys.stdin) if r["version"].startswith("v22.")][0])')
  curl -fsSL https://nodejs.org/dist/$V/node-$V-linux-x64.tar.xz | tar --no-same-owner -xJ -C /workspace && mv /workspace/node-$V-linux-x64 /workspace/node
fi
/workspace/node/bin/node --version
mkdir -p /workspace/tools && cd /workspace/tools
[ -x crane ] || curl -fsSL https://github.com/google/go-containerregistry/releases/latest/download/go-containerregistry_Linux_x86_64.tar.gz | tar --no-same-owner -xz crane
./crane digest lebbi/open-game-master:latest
mkdir -p /workspace/ogm-image
./crane export --platform linux/amd64 lebbi/open-game-master:latest - | tar --no-same-owner -x -C /workspace/ogm-image app
ls /workspace/ogm-image/app
echo OGM_INSTALL_DONE
