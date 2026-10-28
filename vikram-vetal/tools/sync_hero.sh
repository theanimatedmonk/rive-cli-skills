#!/bin/sh
# King Vikram lives in ../king and the Vetal in ../vetal (their own Rive
# files); the scene draws them too, and carries each as a component (their
# pages' scripts). Copies their modules, shaders and scripts into the
# scene's project, so every file ships the same characters. Run after
# changing any of them.
cd "$(dirname "$0")/.." || exit 1
cp king/Hero.luau rive/Hero.luau
cp king/king.wgsl rive/king.wgsl
cp vetal/Spirit.luau rive/Spirit.luau
cp vetal/vetal.wgsl rive/vetal.wgsl
cp king/King.luau rive/King.luau
cp vetal/Vetal.luau rive/Vetal.luau
echo "synced Hero.luau, king.wgsl, King.luau, Spirit.luau, vetal.wgsl and Vetal.luau into rive/"
