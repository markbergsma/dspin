#!/usr/bin/env bash
# Build DSPin against a local checkout of esphome-dspi.
#
# The configs refer to the component by its published github:// URL, which is
# what someone cloning this repo should get. While the component is unpublished,
# or while you are developing it alongside this config, that URL has to be
# rewritten to a local path. This wrapper does that against a scratch copy so
# the configs themselves stay as users see it.
#
#   ./tools/build.sh config                    # validate
#   ./tools/build.sh compile                   # build
#   ./tools/build.sh run --device dspin.local  # build, upload, tail logs
#
# Builds dspin.yaml (the full UI build) by default. Set DSPIN_CONFIG to build
# the headless one instead:
#   DSPIN_CONFIG=dspin-basic.yaml ./tools/build.sh compile
#
# Override the component location with DSPI_COMPONENTS if it is not a sibling:
#   DSPI_COMPONENTS=~/src/esphome-dspi/components ./tools/build.sh compile
set -euo pipefail

cd "$(dirname "$0")/.."

COMPONENTS="${DSPI_COMPONENTS:-$PWD/../esphome-dspi/components}"

if [ ! -d "$COMPONENTS/dspi" ]; then
  echo "error: no dspi component at $COMPONENTS" >&2
  echo "Clone it as a sibling directory:" >&2
  echo "  git clone https://github.com/markbergsma/esphome-dspi ../esphome-dspi" >&2
  echo "or point DSPI_COMPONENTS at an existing checkout." >&2
  exit 1
fi

if [ $# -eq 0 ]; then
  echo "usage: $0 <esphome-command> [args...]   e.g. $0 run --device dspin.local" >&2
  exit 2
fi

CONFIG="${DSPIN_CONFIG:-dspin.yaml}"

if [ ! -f "$CONFIG" ]; then
  echo "error: no config at $CONFIG" >&2
  exit 1
fi

# esphome resolves !secret and !include relative to the config file, so the
# scratch copy needs the secrets and every config alongside it -- dspin.yaml
# includes dspin-basic.yaml as a package, and that is also the file carrying
# the external_components URL the sed below rewrites.
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

# The second rewrite covers any local component path: relative to the config file it resolves
# fine for a plain `esphome run` from the repo root, but the scratch copy moves the config away
# from it, so it has to become absolute here.
for f in dspin*.yaml; do
  sed -e "s|source: github://markbergsma/esphome-dspi@main|source: {type: local, path: $COMPONENTS}|" \
      -e "s|source: {type: local, path: components}|source: {type: local, path: $PWD/components}|" \
    "$f" >"$scratch/$f"
done
[ -f secrets.yaml ] && cp secrets.yaml "$scratch/secrets.yaml"

echo "building $CONFIG against $COMPONENTS"
exec esphome "$1" "$scratch/$CONFIG" "${@:2}"
