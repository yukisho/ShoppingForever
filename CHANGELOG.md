# Changelog

## 1.0.2

- Fixed overlapping minimap visibility and position-reset text in the Manage
  and Settings window.

## 1.0.1

- Fixed the minimap button radius so it sits on the edge of resized and
  custom-skinned minimaps instead of appearing inside them.
- Repositions the button when the minimap changes size and again at login.

## 1.0.0

- Added an original Shopping Forever addon icon.
- Added a native draggable minimap button with saved position and visibility.
- Added left-click list toggling, right-click settings access, and a usage
  tooltip to the minimap button.
- Added minimap visibility and position reset controls to Manage and Settings.
- Added `/sf minimap`, including explicit show, hide, and reset actions so a
  hidden button can always be restored.

## 0.9.0 - Development

- Added main-list column headings and alternating row shading.
- Added visible item ranges and clearer Previous/Next paging controls.
- Added distinct guidance for empty lists and filters with no matches.
- Dimmed completed rows while preserving their item links and controls.
- Added contextual tooltips for completion, progress, source, edit, and remove
  controls.

## 0.8.0 - Development

- Made the current list name a direct, paged list selector while preserving the
  previous/next list buttons.
- Added `/sf lists` as a shortcut to the list selector.
- Added persisted auto-open toggles for the Auction House, vendors, and
  profession windows to Manage List and Settings.
- Added strict normalization and tested accessors for auto-open preferences.

## 0.7.0 - Development

- Added item-name autocomplete to the main item field using the required
  LibItemDB-1.0 library supplied by the ItemDB addon.
- Added exact, prefix-first, and substring result ranking with punctuation-
  tolerant matching.
- Added mouse selection plus arrow-key, Tab, Enter, and Escape controls.
- Fixed mouse selection on clients where losing edit-box focus could close the
  autocomplete dropdown before its clicked row received the selection.
- Declared ItemDB as a hard addon dependency; it remains a separate install and
  is not bundled in the Shopping Forever release archive.

## 0.6.0 - Development

- Added multi-level crafting plans for fixed-reagent recipes.
- Added owned-material allocation across the plan so shared inputs are not
  counted twice.
- Added bounded recursion and dependency-cycle protection for cached recipes.
- Added acquisition suggestions for final materials from the current
  character, alternate crafters, observed vendors, or the Auction House.
- Added a Crafting Plan window with craft steps and transactional base-material
  expansion.

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
