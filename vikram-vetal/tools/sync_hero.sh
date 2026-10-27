#!/bin/sh
# King Vikram lives in ../king (his own Rive file); the scene draws him too.
# Copies his module and shader into the scene's project, so both files ship
# the same hero. Run after changing king/Hero.luau or king/king.wgsl.
cd "$(dirname "$0")/.." || exit 1
cp king/Hero.luau rive/Hero.luau
cp king/king.wgsl rive/king.wgsl
echo "synced Hero.luau and king.wgsl into rive/"
