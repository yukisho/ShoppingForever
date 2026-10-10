# Shopping Forever

Shopping Forever is an account-wide shopping-list addon built specifically for
World of Warcraft: Forever. It brings Auction House purchases, vendor items,
and profession materials together in one persistent set of lists without
automating purchases or crafting actions.

## Requirements

- World of Warcraft: Forever (`16001` interface)
- [ItemDB](https://www.curseforge.com/wow/addons/libitemdb)

ItemDB is a required dependency and is not bundled with Shopping Forever.

## Installation

1. Install and enable ItemDB.
2. Extract the `ShoppingForever` folder into your WoW `Interface/AddOns`
   directory.
3. Confirm that both ItemDB and Shopping Forever are enabled at character
   selection.
4. Enter the world and use `/sf` or the minimap button to open the addon.

When installing a release archive, preserve its included folder structure:

```text
Interface/
└── AddOns/
    └── ShoppingForever/
        ├── ShoppingForever.toc
        └── ...
```

## Quick start

1. Open Shopping Forever with `/sf` or its minimap button.
2. Type at least two characters of an item name.
3. Select an autocomplete result, choose a quantity, and select a goal mode.
4. Use the source action on the resulting row to search the Auction House,
   locate an observed vendor, or open a known profession recipe.

Item links and numeric item IDs can also be entered directly. Matching goals
with the same item and goal mode are merged automatically.

## Goal modes

### Own Total

Use **Own Total** when the desired number represents how many items you want to
own. Progress uses the live inventory counts exposed by the client, including
supported bag, bank, reagent-bank, and account-bank stores.

### Buy More

Use **Buy More** when the desired number represents how many additional items
you want to acquire. Progress can be adjusted manually and is also updated
when the client reports successful Auction House, vendor, or crafting results.

## Auction House and vendors

- Auction House actions fill a search for the selected item.
- Successful purchases are applied to matching Buy More goals when reported by
  the client.
- Visiting merchants teaches Shopping Forever which items those vendors sell.
- Known vendor locations are offered as acquisition alternatives.

Shopping Forever never confirms purchases on the player's behalf.

## Professions and crafting

Shopping Forever records known recipes for the current character and keeps an
account-wide cache of observed recipes for alternate characters.

When a recipe is selected in the profession window, **Add Reagents** adds the
missing direct reagents for the selected craft quantity to the active shopping
list. Materials already owned or already outstanding on the list are
subtracted first.

Shopping-list entries that can be crafted provide additional tools:

- Open a known recipe on the current character.
- Identify a known alternate-character crafter.
- Add missing recipe reagents.
- Expand fixed intermediate recipes into a multi-level crafting plan.
- Account for owned materials once across the expanded plan.
- Suggest crafting, observed vendors, or the Auction House for final inputs.

Recipes with unresolved selectable or optional reagent slots are not added
automatically, preventing Shopping Forever from choosing materials for the
player.

## Lists and organization

- Create multiple named, account-wide lists.
- Select lists directly from a paged list picker.
- Add notes and optional character assignments.
- Remember the selected list separately for each character.
- Duplicate a list while resetting its progress.
- Add many item links or item IDs transactionally with Bulk Add.
- Filter entries by All, Open, or Done.
- Sort by added order, name, remaining quantity, or source.
- Clear completed entries with one-step recovery.
- Reset progress for an entire list after confirmation.

## History, sharing, and backups

Acquisitions from the Auction House, vendors, crafting, and manual progress are
recorded in a bounded history. The latest compatible acquisition can be safely
undone from the selected list.

Shopping Forever supports two portable code formats:

- `SFL1` shares a single list and imports it with fresh progress and no
  character assignments.
- `SFB1` backs up all addon data. Restoring a backup first creates an automatic
  safety copy, and the three latest safety copies are retained.

Both formats include integrity checks to reject damaged codes.

## Minimap button

- Left-click opens or closes Shopping Forever.
- Right-click opens Manage List and Settings.
- Drag the button around the minimap to reposition it.
- Visibility and position are saved account-wide.
- Use `/sf minimap show` if the button has been hidden.

The button adapts to resized and custom-skinned minimaps.

## Commands

| Command | Action |
| --- | --- |
| `/sf` | Open or close Shopping Forever |
| `/sf add ITEM_LINK [QUANTITY]` | Add an item to the active list |
| `/sf new NAME` | Create and select a list |
| `/sf lists` | Open the list picker |
| `/sf own` | Set new entries to Own Total |
| `/sf buy` | Set new entries to Buy More |
| `/sf history` | Open acquisition history |
| `/sf undo` | Undo the latest compatible acquisition |
| `/sf manage` | Open list tools and settings |
| `/sf bulk` | Open transactional bulk entry |
| `/sf duplicate` | Duplicate the active list with fresh progress |
| `/sf share` | Open list sharing and full-backup tools |
| `/sf backup` | Open list sharing and full-backup tools |
| `/sf minimap` | Toggle the minimap button |
| `/sf minimap show` | Show the minimap button |
| `/sf minimap hide` | Hide the minimap button |
| `/sf minimap reset` | Show and reset the minimap button position |
| `/sf help` | Print command help |

## Saved data and behavior

Shopping Forever stores its account-wide data in `ShoppingForeverDB`. Lists,
settings, character recipe caches, vendor observations, history, and backup
safety copies persist through logout and reloads.

Some information is learned as the player encounters it:

- Vendor sources become available after visiting the relevant merchant.
- Alternate-character recipes become available after Shopping Forever has
  observed that character's profession data.
- Bank-related inventory counts depend on the stores and APIs exposed by the
  client.

## Troubleshooting

- If item autocomplete is unavailable, verify that ItemDB is installed and
  enabled.
- If the minimap button is missing, run `/sf minimap show` or
  `/sf minimap reset`.
- If a profession action is disabled, select a learned recipe and verify that
  it has a fixed item-reagent list.
- After replacing addon files, use `/reload` or restart the client.

When reporting a problem, include the action being performed, the selected
item or recipe, any Lua error, and a screenshot when layout is involved.