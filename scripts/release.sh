#!/usr/bin/env bash
# Google Chat for macOS
# Copyright (C) 2026 Bas Peters
#
# This program is free software: you can redistribute it and/or modify it under the terms of the
# GNU General Public License as published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
# even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with this program. If not,
# see <https://www.gnu.org/licenses/>.
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Creates and pushes the tag v<version> from Support/Info.plist. GitHub Actions builds the app
# and publishes the ZIP as a release asset.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist)"
TAG="v$VERSION"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "There are uncommitted changes. Commit them first." >&2
    exit 1
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || git ls-remote --exit-code --tags origin "$TAG" >/dev/null 2>&1; then
    echo "Tag $TAG already exists. Increase CFBundleShortVersionString in Support/Info.plist." >&2
    exit 1
fi

git tag -a "$TAG" -m "Version $VERSION"
git push origin "$TAG"
echo "Pushed tag: $TAG"
echo "GitHub Actions will build the app and publish its ZIP to Releases."
