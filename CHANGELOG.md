# Changelog

## 0.5.0 - Development

- Added transactional bulk entry with duplicate-line grouping and preflight
  validation.
- Added list duplication that preserves setup while resetting progress and
  character assignments.
- Added confirmed completed-item cleanup with recovery of the latest cleanup.
- Added whole-list progress reset and a consolidated Manage List window.
- Added `/sf manage`, `/sf bulk`, and `/sf duplicate` commands.

## 0.4.0 - Development

- Added checksummed SFL1 codes for exporting and importing individual lists.
- Added checksummed SFB1 full-data backup and restore codes.
- Added strict import validation, unique imported-list names, and reset progress
  for imported goals.
- Added automatic pre-restore safety copies with the three latest copies kept.
- Added the Share and Backup window plus `/sf share` and `/sf backup` commands.
- Added confirmed per-list acquisition-history clearing.

## 0.3.0 - Development

- Added bounded account-wide acquisition history with list-specific views.
- Added safe undo tied to the exact Buy More entry originally updated.
- Added history and undo controls plus `/sf history` and `/sf undo` commands.
- Added persistent All, Open, and Done filters.
- Added sorting by added order, item name, remaining need, and source.

## 0.2.0 - Development

- Added one-level recipe material planning with duplicate-safe missing-reagent
  expansion.
- Added item editing for quantities, goal modes, and preferred acquisition
  sources.
- Added list notes and account-wide character assignments with per-character
  list selection memory.

## 0.1.0 - Development

- Added the WoW Forever `16001` addon manifest and bootstrap lifecycle.
- Added versioned account-wide SavedVariables.
- Added named list creation, selection, renaming, and deletion.
- Added linked-item validation, duplicate merging, and asynchronous item-data
  refresh.
- Added Own Total and Buy More progress modes.
- Added live inventory counting across bags and supported bank stores.
- Added a movable initial list window and slash commands.
- Added Auction House search and successful-purchase event handling.
- Added merchant observation and inventory-confirmed vendor purchase handling.
- Added current-character profession recipe discovery with account-wide alt
  recipe caching.
- Added source suggestions and automatic crafted-output progress.
