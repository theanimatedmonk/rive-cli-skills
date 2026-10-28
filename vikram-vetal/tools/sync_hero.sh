#!/bin/sh
# King Vikram lives in ../king and the Vetal in ../vetal (their own Rive
# files); the scene draws them too. Copies their modules and shaders into
# the scene's project, so every file ships the same characters. Run after
# changing king/Hero.luau, king/king.wgsl, vetal/Spirit.luau or
# vetal/vetal.wgsl.
cd "$(dirname "$0")/.." || exit 1
cp king/Hero.luau rive/Hero.luau
cp king/king.wgsl rive/king.wgsl
cp vetal/Spirit.luau rive/Spirit.luau
cp vetal/vetal.wgsl rive/vetal.wgsl
echo "synced Hero.luau, king.wgsl, Spirit.luau and vetal.wgsl into rive/"
