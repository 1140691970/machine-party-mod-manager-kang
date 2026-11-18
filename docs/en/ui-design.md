# UI design specification

**English** · [简体中文](../zh-CN/ui-design.md) · [繁體中文](../zh-TW/ui-design.md)

This describes the current desktop UI and marks what is not implemented yet. See the [current screenshot](../images/screenshot-catalog.png); the original concept is [ui-reference.png](../images/ui-reference.png). Redesigns update this page directly instead of appending superseding sections.

## Visual style: Machine Party

Taken from the game's wine-red overalls and brass machinery: deep wine backgrounds, brass accents and cream text. Rounded corners and raised buttons add some game character without competing with mod covers, which stay the visual focus.

- **Brand**: the gear badge mark, a cream masked face inside a brass gear on a rounded wine plate. The UI uses `apps/desktop/ui/images/logo.svg`; the app icon source is `apps/desktop/artwork/app-icon.svg` (with macOS padding). Run `npx --yes --package @tauri-apps/cli@2.12.5 tauri icon ../artwork/app-icon.svg -o /tmp/icons` in `apps/desktop/src-tauri` and copy only the desktop sizes into `icons/`.
- **Design tokens**: colours, fonts, type scale, spacing, radii, shadows and motion are all defined in `apps/desktop/ui/tokens.css`. Components and layout reference variables only and add no new colour values.
  - Backgrounds from dark to light: sidebar `--wine-900`, main area `--wine-850`, cards `--wine-800`, hover `--wine-750`; the selected navigation item uses `--wine-600`.
  - The accent is brass `--brass-500`, used for primary buttons, links and the "Update available" tag; success is a pale green and warnings a warm orange.
  - Titles and the brand use a condensed bold face (Avenir Next Condensed / Bahnschrift Condensed), body text uses system UI fonts and version numbers use a monospaced font.
- **Shared components** (`components.css`, created by `dom.js` and `icons.js`):
  - Button `button(text, action, variant, icon)`: `primary` raised brass, `secondary` outlined, `ghost` without fill and `link` text link; card buttons add `btn-block` to fill the width.
  - Tag `tag(text, tone)`: a dark pill with `accent`, `success` and `warning` tones; version tags use the monospaced font.
  - Card `.card`, panel `.panel`, text field `.field`, select `.select`, dialog `.dialog`, progress bar `progress()` and skeleton `.skeleton`.
  - Buttons in a dialog are collected into its action row; text links stay in the body.
  - Icons are 24px line icons that follow the text colour, created by `icon(name)`; they replace the earlier character icons.
- **Motion**: cards rise and fade in one after another when a page opens (not while searching); on hover they lift with a brass outline and a slight cover zoom. Buttons press down 1px, dialogs scale in with a spring, covers shimmer as skeletons until loaded and the brand mark tilts on hover. All durations drop to zero when the system requests reduced motion.
- Every focusable element has a visible brass focus ring and works with the keyboard.

## Layout

- **Sidebar**: the mark with `MACHINE PARTY` and the "Mod Manager" subtitle at the top. Primary navigation "Mod catalog" and "Installed", each with an icon and at least 44px high; the selected item has a wine fill and a brass icon. "Settings" at the bottom.
- **Header**: a condensed page title and subtitle on the left; on the catalog page a pill search box on the right with the placeholder "Search mods, authors or keywords".
- **Content**: an equal-height card grid that fills the available width, with a minimum card width of about 280px. Settings is a vertical list of panels up to 720px wide.
- **Narrow windows (≤760px)**: the sidebar collapses to the mark and icons, the header stacks vertically and search takes the full width.

## Mod card

1. **Cover (16:9)**: the catalog version at top left ("Version unlisted" when absent) and the state tag at top right: "Update available" on brass, "Matches catalog" in green, "Local version is newer" and "Check versions" in warm orange, and the default dark tag otherwise. A skeleton shows until the image loads; without an image, or when it fails, a wine gradient title cover is shown. No text is overlaid on images.
2. **Title and summary**: the title is a link that opens details, followed by a one-line summary of its purpose and multiplayer requirements. When the manager has an install record, "Local · version" and "Catalog · version" follow.
3. **Footer**: one full-width button. The author page link lives in details, not on the card.

| Local vs catalog | State tag | Primary button |
| --- | --- | --- |
| No install record | "Unverified" (when the catalog version is unverified) | "Install" (explains it awaits physical verification) |
| Same version | "Matches catalog" | "Uninstall" |
| Local older, new version unverified | "Update pending verification", existing install kept | "Update" (explains it becomes available after verification) |
| Local older, new version verified | "Update available" | "Update" |
| Local newer | "Local version is newer", existing install kept | "Uninstall" |
| Either version unknown or not comparable, or records unreadable | "Check versions", never replaced automatically | "Check versions" (opens details) |

Until the install engine is connected, install, update and uninstall only show an explanation and never modify files.

## Details dialog

In order: the detailed description (multiplayer conditions, required loader, conflicts), catalog version, local version and state note when present, and the author page link with an external-link icon. Differences from the base game's multiplayer and upstream licence information will be added.

## Settings

Settings consists of three panels:

- Language: 简体中文, 繁體中文, English. The system language is used on first launch and the user's choice is remembered.
- Game folder: the current path in a monospaced font or "No game folder selected", with "Select game folder" and "Scan again".
- Manager version and "Check for app updates". When a new version exists, an update button slides in at the top of the main area; it confirms "Update and restart" and shows download progress as a bar and percentage.

## First launch

A single game copy loads directly; several copies open a dialog listing candidate paths; none prompts to choose a folder or browse first, with "Set up later".

## Planned

- A game status line at the bottom of the sidebar: a green dot with "Game version v2.1.2", switching to a warning colour that opens folder selection when no game is detected.
- A "Switch" button for mods that conflict with the active one. Its confirmation names the mod being replaced and prepares the new package before restoring the old mod.
- Confirmation dialogs for install, switch and update that check whether the game is running, version fingerprints and conflicts, stopping with a next step for incompatibility or unknown modifications; progress shows download, verify, apply and confirm, and the new record is written only on success.
