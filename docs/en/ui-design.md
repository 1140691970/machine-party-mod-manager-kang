# UI design specification

**English** · [简体中文](../zh-CN/ui-design.md) · [繁體中文](../zh-TW/ui-design.md)

This describes the current desktop UI and marks what is not implemented yet. The reference image is [ui-reference.png](../images/ui-reference.png). Redesigns update this page directly instead of appending superseding sections.

## Visual direction

- Dark industrial style matching Machine Party. Layered charcoal backgrounds: the sidebar is darker than the main area and cards are separated by thin borders.
- Primary buttons use a warm off-white fill (about `#E6E1CC`) with dark text; secondary actions are dark outlined buttons; errors use a warm orange.
- The brand uses an Impact-style condensed bold face; body text uses system UI fonts (Segoe UI, Microsoft YaHei, PingFang SC).
- Every focusable element has a visible focus ring and works with the keyboard.

## Layout

- **Sidebar**: the `MACHINE PARTY` brand and "Mod Manager" subtitle at the top. Primary navigation "Mod catalog" and "Installed", each at least 44px high with 6px spacing. "Settings" at the bottom.
- **Header**: page title and subtitle on the left; on the catalog page a search box on the right with the placeholder "Search mods, authors or keywords".
- **Content**: an equal-height card grid that fills the available width, with a minimum card width of about 282px.
- **Narrow windows (≤760px)**: the sidebar collapses to icons, the header stacks vertically and search takes the full width.

## Mod card

1. **Cover (16:9)**: the catalog version at top left ("Version unlisted" when absent) and the state tag at top right. When the image fails, a title cover with the mod name is shown; no text is overlaid on images.
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

In order: the detailed description (multiplayer conditions, required loader, conflicts), catalog version, local version and state note when present, and the author page link (`author ↗`). Differences from the base game's multiplayer and upstream licence information will be added.

## Settings

- Language: 简体中文, 繁體中文, English. The system language is used on first launch and the user's choice is remembered.
- Game folder: the current path or "No game folder selected", with "Select game folder" and "Scan again".
- Manager version and "Check for app updates". When a new version exists, an update button appears at the top of the main area; it confirms "Update and restart" and shows download progress.

## First launch

A single game copy loads directly; several copies open a dialog listing candidate paths; none prompts to choose a folder or browse first, with "Set up later".

## Planned

- A game status line at the bottom of the sidebar: a green dot with "Game version v2.1.2", switching to a warning colour that opens folder selection when no game is detected.
- A "Switch" button for mods that conflict with the active one. Its confirmation names the mod being replaced and prepares the new package before restoring the old mod.
- Confirmation dialogs for install, switch and update that check whether the game is running, version fingerprints and conflicts, stopping with a next step for incompatibility or unknown modifications; progress shows download, verify, apply and confirm, and the new record is written only on success.
- The next UI redesign: design tokens (colour, spacing, type scale, radius), component layers and a consistent icon set replacing the current character icons.
