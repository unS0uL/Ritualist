# Ritualist (v1.1.5)

**Ritualist** is a minimalist, high-performance Warlock assistant for World of Warcraft 1.12.1, specifically crafted for the **Turtle WoW** community. It streamlines summoning logistics, ritual coordination, and shard management with an interface inspired by the clean aesthetics of pfUI.

<table border="0">
  <tr>
    <td valign="top">
      <img src="https://github.com/unS0uL/Ritualist/raw/media/mainWindow.jpg" width="200" alt="Ritualist Main Window" />
    </td>
    <td valign="top">
      <img src="https://github.com/unS0uL/Ritualist/raw/media/configWindow.jpg" width="450" alt="Ritualist Options" />
    </td>
  </tr>
</table>

---

## Changelog
### v1.1.5 (Latest)
- **Global Communication**: Automated chat messages (click requests, reports, expiration alerts) are now strictly in English to ensure compatibility in multilingual raids.
- **Improved AFK Protection**: Expired summon messages now explicitly instruct players to type "123" when they return.
- **Bugfixes**: Removed redundant localization keys and optimized internal string handling.

### v1.1.4
- **Batch Synchronization**: Entire summon queue is now packed into a single network message, reducing addon traffic by 95%.
- **Performance Engine**: Implemented O(1) UnitID lookups and lazy UI rendering. FPS remains stable even in 40-man raids with rapid queue changes.
- **Smart Auto-Summon**: Rewritten "Next" logic. Prioritizes players in the queue, then raid members. Includes distance-based scoring (Furthest First) and smart instance detection.
- **Global Detection**: Automatically detects and tracks summons from other Warlocks, even if they don't have the addon.
- **UI Polish**: Improved column width calculations (fixes truncated names in History) and added instant status feedback when switching targets.

### v1.1.3
- **UI Logic**: Improved auto-hide behavior. The window now respects manual opening and won't close while the mouse is over it.
- **Sync**: Added automatic version synchronization and queue request on joining a group/raid.
- **Optimization**: Reduced memory usage for Shard HUD updates.
- **Maintenance**: Internal code audit and cleanup.

### v1.1.2
- **Bugfixes**: Minor stability improvements in clicker alerts.

### v1.0.1
- **Enhanced Clicker Helper**: Added 30s raid chat alerts with Hive Mind Anti-Spam protection.
- **Smart Notifications**: "Next" button now reports specific reasons why players cannot be summoned (Dead, Offline, etc.).
- **Visual Polish**: Improved "Magical Spark" animation for active summons.
- **Bugfixes**: Resolved initialization errors and fixed missing status icons.

### v1.0.0
- Initial Release. Complete UI overhaul with dynamic resizing and Nampower optimization.

> **Disclaimer:** This project is an independent community-driven modification for World of Warcraft 1.12.1. It is not affiliated with, endorsed by, or connected to Blizzard Entertainment, Turtle WoW administration, or any other private server entity. The code is provided "as is" for educational and interface enhancement purposes only.

---

## ⚠️ IMPORTANT REQUIREMENT

**Ritualist REQUIRES [Nampower](https://gitea.com/avitasia/nampower/) to function.**  
The addon utilizes Nampower's advanced API for precise GUID tracking, distance calculations, and fast inventory scanning.

---

## Key Features

- **Smart Auto-Summon (Next Button)**: The core automation engine that finds the best target for you.
    - **Priority First**: Always processes players who requested a summon ("123") first.
    - **Distance Scoring**: Among valid targets, it always chooses the **Furthest First** to maximize the utility of the summon.
    - **Intelligent Filtering**: Automatically skips players who are already being summoned by others, dead, in combat, or already nearby.
    - **Instance Awareness**: Smart detection allows pulling players *into* your current dungeon/raid (if they are at the entrance) but prevents wasting shards on cross-instance attempts.
- **Dynamic "Rubber" UI**: The window automatically adjusts its width and height based on the names in the queue.
- **Unified Anchor**: A single master-control icon to move (Shift-drag) or toggle (Click) the interface.
- **Shared Shard HUD**: Tracks the total Soul Shard pool available among all Warlocks in the raid.
- **Soulwell Tool**: Announces ritual placement with calculated healing values based on your talents.

## Usage

### Commands
- `/rit` — Toggle the main window.
- `/rit options` — Open the configuration menu.
- `/rit debug` — Toggle debug mode (enables the **T**est button in the header).

### Interface
- **Left-Click** a name: Targets the player and starts the summon.
- **Next Button**: Attempts to summon the best available target or reports why others are blocked.
- **Anchor**: Click to hide/show. **Shift + Left Click** to move.

## Summon Statuses

- **Waiting**: Received "123", player is in the queue.
- **Nearby**: Player is within 40 yards but hasn't arrived yet.
- **Targeted**: A warlock in the raid has selected this player as their target.
- **Summoning**: Ritual is in progress (animated sparks) or the request is pending acceptance (static icon).
- **Interrupted**: The last summon attempt was cancelled or failed (shown for 5 seconds).
- **Timeout**: The 2-minute window to accept the summon has expired.
- **Offline / Dead / Combat**: Player is currently unavailable for summoning.
- **Wrong Zone**: Player is inside a dungeon or a different world zone.
- **Arrived**: Player successfully arrived (automatically moved to History).

## Installation

1. Download the latest release.
2. Ensure the folder is named `Ritualist`.
3. Place it in `World of Warcraft/Interface/AddOns/`.
4. Ensure **Nampower** is active.

## Supported Languages
- English (enUS)
- Ukrainian (ukUA)
- German (deDE)
- French (frFR)
- Spanish (esES)
- Chinese (zhCN)

## Credits & Acknowledgments

- **Shagu**: For the inspiration set by **pfUI**.
- **Luise**: For the original development of **RaidSummonPlus**.
- **RaidSummon Authors**: For the original automation concepts.

---

*Developed by **Unsoul**. Repository: [GitHub](https://github.com/unS0uL/Ritualist.git)*
