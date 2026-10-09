# Release Notes

## [1.1.0] - 2026-10-08
### Added
- Experimental support for WoW Classic Era (1.15). The compass banner, its background, the center line, the compass detail levels and the settings page all work there. SuperTracking (the marker, distance and ETA) doesn't, because Classic Era doesn't have the game features it relies on. See the new Compatibility table in the README for how well each client is supported.
- Banner background: an optional dark fade behind the compass banner (Off, Subtle, Medium or Strong), so the directions stay readable over bright scenery. It's off by default. Set it in the options page or with `/wayfinder background <0-3>`. Thanks to mcbgamerguy on CurseForge for the suggestion.
- Show center line: an option to hide the line at the middle of the banner. Set it in the options page or with `/wayfinder centerline enable|disable`. Thanks to CyberzerkerGaming and mcbgamerguy on CurseForge for asking for it.
- `/wayfinder debug eta` records ten seconds of ETA data for troubleshooting.

### Changed
- The options page now looks like Blizzard's own settings pages: a label on the left and its control on the right, a highlight and tooltip as you hover a row, and a scroll bar when the window is short. Compass detail and Banner background are now steppers (arrows around the current value). Settings that only affect the banner are greyed out while it's turned off, and "Reset position" is now a "Banner position" row.
- Whether the banner is turned on is now remembered between sessions. It used to always come back on at login.
- The banner no longer hides itself in every instance. It now hides only where the game doesn't report which way you're facing (inside most dungeons, for example), and comes back on its own when it does. That also fixes the compass freezing in place in a few dungeons, which was the reason for hiding it in all of them. In places like your garrison it now stays visible. When the banner is hidden for this reason, a message near the top of the options page says why.
- The ETA is now worked out from how quickly you're closing in on the target, and shown as a steady countdown. It appears about a second after you start moving, ticks down smoothly, and shows `--` as soon as you stop or move away. Before, the seconds could flicker up and down, especially at long distances.

### Fixed
- The ETA always showed `--` while flying, because the game reports a current speed of zero in the air. It now works the same on foot, on a mount, flying or Skyriding, and on a taxi.

## [1.0.1] - 2026-09-26
### Fixed
- Changing Nameplate Style (Options > Nameplates) could throw a Lua error every frame while the preview cast bar animated. Wayfinder's options page was built from Blizzard's shared Settings controls, and that left Wayfinder's "taint" on control frames Blizzard later reused for its own settings. Thanks to u/xJayoftheDeadx on Reddit for the detailed report and suggested fix.

### Changed
- The options page is now a single page built from Wayfinder's own controls. The About info (icon, version, author) is at the top, and there's no separate About page anymore.
- Compass detail is now a set of radio buttons instead of a dropdown.

## [1.0.0] - 2026-09-24
### Changed
- Promoted from beta to a stable release. No functional changes since 1.0.0-beta.2 - the only blocker was the WoW: Forever beta's SavedVariables-not-read-back bug (see 1.0.0-beta.1's "Known issues" below). Blizzard has since fixed it upstream (Forever beta build 70009), it's been verified in-game against Wayfinder's own settings, and 1.0.0-beta.2 confirmed the automated release pipeline (CurseForge, Wago, and WoWInterface) publishes cleanly.

## [1.0.0-beta.2] - 2026-09-24
### Changed
- Docs/comment cleanup: removed the SavedVariables-bug notes from code comments, `Wayfinder.toc`, and DEVNOTES.md now that it's fixed upstream (Forever beta build 70009) - see 1.0.0-beta.1's "Known issues" below for the original context.
- Packaging: verifies the WoWInterface publish target added after 1.0.0-beta.1 (`X-WoWI-ID`) publishes correctly via the automated packager, ahead of the next stable release.

## [1.0.0-beta.1] - 2026-09-20
### Added
- Interface support for World of Warcraft: Forever (1.60.1, interface 16001), alongside current retail (12.1.0, interface 120100).
- SuperTracking: a marker, distance, and ETA readout on the compass banner for whatever you're currently super-tracking - quests, user-placed waypoints, area POIs, taxi nodes, and your own corpse.
- Configurable compass detail levels (0-3: none, cardinals, intercardinals, or a full ring of pips).
- A draggable, lockable compass banner (`/wayfinder unlock`/`lock`/`resetposition`), with its position remembered.
- A native in-game Settings panel (Escape > Options > AddOns, or `/wayfinder settings`), including an About page with the addon's icon and info.
- A minimap Addon Compartment entry for quick access, plus a proper addon icon shown there and in the addon list.

### Fixed
- SuperTracking marker never appearing (was using the wrong texture API for its atlas-based icon).
- SuperTracking failing to resolve a destination for older, pre-modern-navigation-system quest content.
- Updated the embedded HereBeDragons-2.0 library, whose vendored copy only indexed map IDs up to 2500 and would silently fail to resolve coordinates (breaking SuperTracking) in any zone added since then.
- A crash in the ETA readout when reading player speed while in combat, under WoW 12.0+'s "secret values" addon-disarmament system.

### Changed
- General code cleanup for idiomatic Lua/WoW addon conventions.

### Known issues
- WoW: Forever beta does not reliably read SavedVariables back on reload/restart (a confirmed upstream client bug, not a Wayfinder issue - see DEVNOTES.md). Compass detail, tracking toggles, and banner position may silently revert to their defaults until Blizzard fixes this.

## [1.0.0-alpha.1] - 2024-09-28
### Added
- Initial (alpha) release of Wayfinder.
- The main compass banner
- Cardinal waypoints

### Fixed
- N/A

### Changed
- N/A
