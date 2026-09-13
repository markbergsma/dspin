#!/usr/bin/env bash
# Build DSPin against a local checkout of esphome-dspi.
#
# dspin.yaml refers to the component by its published github:// URL, which is
# what someone cloning this repo should get. While the component is unpublished,
# or while you are developing it alongside this config, that URL has to be
# rewritten to a local path. This wrapper does that against a scratch copy so
# dspin.yaml itself stays as users see it.
#
#   ./tools/build.sh config                    # validate
#   ./tools/build.sh compile                   # build
#   ./tools/build.sh run --device dspin.local  # build, upload, tail logs
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

# esphome resolves !secret relative to the config file, so the scratch copy
# needs the secrets alongside it.
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

sed "s|source: github://markbergsma/esphome-dspi@main|source: {type: local, path: $COMPONENTS}|" \
  dspin.yaml >"$scratch/dspin.yaml"
[ -f secrets.yaml ] && cp secrets.yaml "$scratch/secrets.yaml"

echo "building against $COMPONENTS"
exec esphome "$1" "$scratch/dspin.yaml" "${@:2}"
