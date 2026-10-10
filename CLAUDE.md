# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Wayfinder is a World of Warcraft addon (Lua 5.1, no build step) that draws a compass banner at the top of the screen, plus a marker, distance and ETA for whatever the player is super-tracking. It targets three clients from one codebase (`## Interface:` in `Wayfinder.toc`): Retail (120100), WoW: Forever (16001, the primary target) and Classic Era (11509, experimental).

There is no test suite and no way to run the addon outside the game. Verification is `luacheck` plus in-game checking.

## Commands

```bash
luacheck --no-color -q          # lint; same invocation CI uses, config in .luacheckrc
```

- `luacheck` isn't installed by default (`brew install luacheck`).
- CI, the manual deprecated-API check and the third-party libraries are described in the DEVNOTES import below.
- `@project-version@` in the TOC is substituted by the packager on a tag push. `RELEASE.md` is the changelog, written by hand and published as-is. `README.md`, `DEVNOTES.md`, `HISTORY.md`, `CLAUDE.md` and `docs/` are excluded from the packaged addon by `.pkgmeta`.

## Conventions and known issues

@DEVNOTES.md

## Architecture

**Load order is the dependency order.** `Wayfinder.toc` loads `Libs\embeds.xml`, then `Wayfinder.lua`, `CompassBanner.lua`, `CardinalPoints.lua`, `SuperTracking.lua`, `Settings.lua`, `AddonCompartment.lua`, `Slash.lua`. Files share state only through the addon table (`local _, addon = ...`), so a module can use only what an earlier file has already published.

`Wayfinder.lua` creates the namespaces (`addon.API`, `addon.private`, `addon.Constants`; aliases are in the conventions above). It also provides `_p.getOrSetDefault`, `_p.bind` and a no-op `_p.refreshSettingsPanel` placeholder that `Settings.lua` later overwrites.

**The banner is a host for pluggable "elements".** `CompassBanner.lua` owns the frame and a single `OnUpdate`. Other modules register with `api.AddElementToBanner(name, angleFunction, createMarker, isSticky)`, which returns a handle used with `api.SetElementEnabled` and `api.SetElementRotateWhenSticky`. The banner reads `GetPlayerFacing()` each frame and positions every enabled element from the angle its callback returns. `CardinalPoints.lua` (N/E/S/W, intercardinals, pips) and `SuperTracking.lua` (the tracked-target marker) are both elements. A new thing on the banner should be a new element, not banner code.

**Facing can be unavailable.** Some places (most dungeons) return nil from `GetPlayerFacing()`, and in combat it can be a secret value. `onUpdate` then sets the banner's alpha to 0 but leaves it "shown" so the update keeps running and notices when facing returns. `api.CompassBanner.IsFacingAvailable()` feeds a notice in the settings page. The user's on/off choice (`showBanner`) is kept separate from this temporary hiding.

**Per-client gating happens at module level.** `SuperTracking.lua` checks for `C_SuperTrack`, `C_Navigation` and the `Enum.SuperTracking*` enums at the top. If any is missing (Classic Era), it publishes a do-nothing `api.SuperTracking` with `IsSupported() == false`, then `return`s. Settings and slash code must check `IsSupported` before offering the feature, and any new module needing client-specific APIs should follow the same stub pattern.

**Settings have three entry points that must stay in sync.** Every persisted setting is read once with `_p.getOrSetDefault(key, default)`, which writes the default back into the `WayfinderSettings` saved variable. It is changed by the settings panel (`Settings.lua`), by a `/wayfinder` subcommand (`Slash.lua`), and sometimes by the Addon Compartment click (`AddonCompartment.lua`). Setters in the owning module apply the change, write `WayfinderSettings`, then call `_p.refreshSettingsPanel()` so the panel reflects changes that didn't come from it. Follow that pattern for new settings and add a matching slash subcommand.

**The settings page uses Wayfinder's own controls, not Blizzard's shared Settings controls.** Building from the shared ones left Wayfinder's taint on frames Blizzard later reused, which caused Lua errors in unrelated options pages (see RELEASE.md 1.0.1). Don't switch back.

**Addon Compartment callbacks are plain globals.** `Wayfinder_OnAddonCompartment{Click,Enter,Leave}` are named in the TOC and called by Blizzard, so they can't live under `addon.*`. Any other new global must also be added to `globals` in `.luacheckrc`, which lists every WoW global used. Luacheck fails on an unlisted one.

## Things that bite

- **`Libs/embeds.xml` load order is deliberate** (LibStub, then CallbackHandler). The rest of the `Libs/` rules are in the DEVNOTES import above.
- **Interface numbers live in three places.** The TOC `## Interface:` line, the README Compatibility table and `RELEASE.md` must agree when a client is added or bumped.
