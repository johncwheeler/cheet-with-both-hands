import Foundation

/// Starter cheets created on first launch (authored in Markdown and run through the importer).
public enum SampleCheets {
    public static func all() -> [Cheet] {
        [welcome, macOS, git, vim].compactMap { markdown in
            try? CheetImporter.importCheet(markdown, options: ImportOptions(format: .markdown)).cheet
        }
    }

    static let welcome = """
    # Cheet with Both Hands

    ## Open cheets
    | Shortcut | Action |
    |---|---|
    | ⌃⌥⌘1 … ⌃⌥⌘9, ⌃⌥⌘0 | Show cheet 1–10 (by position in the library) |
    | ⌃⌥⌘/ | Cheet picker — search every cheet |
    | ⌃⌥⌘` | Toggle the last cheet |
    | Tap the combo | Show / hide (sticky) |
    | Hold the combo | Peek — hides when you let go |

    ## Inside the overlay
    | Shortcut | Action |
    |---|---|
    | Type | Filter rows as you type |
    | ↑ / ↓ | Scroll |
    | ⌥↑ / ⌥↓ | Scroll a page (also PgUp / PgDn, Space) |
    | ⌘↑ / ⌘↓ | Jump to top / bottom |
    | ⌘F | Focus the filter field |
    | Esc | Clear the filter, then close |
    | ⌘[ / ⌘] | Previous / next cheet |
    | ⌘1 … ⌘9 | Jump to cheet by number |
    | ⌘+ / ⌘- / ⌘0 | Bigger / smaller / reset text |
    | ⌘P | Open the cheet picker |
    | ⌘E | Edit the layout (hide, delete, resize, style cards) |
    | ⌥⌘E | Edit the content |
    | ⌘W | Close the overlay |

    ## Editing the layout
    | Do this | To |
    |---|---|
    | Drag a card's title | Reorder — the others flow around it |
    | Drag the right / bottom edge | Resize (width snaps to columns) |
    | Hold ⌥ while dragging | Free-form width |
    | Double-click an edge | Back to automatic size |
    | Double-click a title | Rename the card |
    | 🖌 on a card | Text size, colors, background, glow |
    | H / ⌫ | Hide / delete the selected card |
    | ⌘Z / ⇧⌘Z | Undo / redo |
    | Esc or ⌘↩ | Done |

    ## Mouse
    - **Click a cell** — copies it to the clipboard
    - **Drag the header** — move the overlay (position is remembered)
    - **Drag the corner** — resize
    - **Click a section title** — collapse or expand it
    - **◐ button** — opacity, tint and text size on the fly

    ## Make your own
    - Menu bar icon → **New Cheet…** and paste Markdown, HTML, CSV/TSV or JSON
    - **New Cheet from Clipboard** grabs whatever you just copied (tables from web pages work great)
    - Drop `.md`, `.html`, `.csv`, `.tsv` or `.json` files onto the import window
    - **Import from URL…** picks the headings, tables, lists and code out of any page — tick the parts to keep
    - **Browse Cheatography…** searches thousands of community cheets; import one (choosing parts) or several at once
    - `##` headings become cards, tables stay tables, "`key` — description" lists become tables
    - Formulas (sup/sub, MathML, LaTeX) import as real math — x², Σ^[∞](script: 1)^[n=0](script: -1) — and images come along, cached for offline use

    ## Automation
    Prefix a path with `cheetwithbothhands://` and `open` it from scripts, Raycast, Alfred or Shortcuts.

    | Path | Does |
    |---|---|
    | `show/2` | Show cheet #2 (or by title: `show/git`) |
    | `toggle/vim` | Toggle a cheet |
    | `picker` | Open the cheet picker |
    | `hide` | Hide the overlay |
    | `ghost` | Toggle click-through ghost mode |
    | `import` | New cheet from the clipboard |
    | `import-url?url=…` | Import a web page (the browser bookmarklet uses this) |
    | `browse?q=vim` | Search Cheatography |
    """

    static let macOS = """
    # macOS Essentials

    ## System
    | Shortcut | Action |
    |---|---|
    | ⌘Space | Spotlight |
    | ⌘Tab | Switch apps |
    | ⌘` | Switch windows of the current app |
    | ⌃↑ | Mission Control |
    | ⌃↓ | App windows (App Exposé) |
    | ⌃← / ⌃→ | Previous / next Space |
    | ⌃⌘Q | Lock screen |
    | ⌥⌘Esc | Force Quit dialog |
    | ⌃⌘F | Toggle full screen |
    | fn E | Emoji & Symbols |

    ## Screenshots
    | Shortcut | Action |
    |---|---|
    | ⇧⌘3 | Capture the whole screen |
    | ⇧⌘4 | Capture a selection |
    | ⇧⌘4 then Space | Capture a window |
    | ⇧⌘5 | Screenshot & recording toolbar |
    | Add ⌃ | …copy to the clipboard instead |

    ## Text editing
    | Shortcut | Action |
    |---|---|
    | ⌥← / ⌥→ | Move by word |
    | ⌘← / ⌘→ | Start / end of line |
    | ⌘↑ / ⌘↓ | Start / end of document |
    | ⌥⌫ | Delete previous word |
    | ⌘⌫ | Delete to start of line |
    | fn ⌫ | Forward delete |
    | ⌃K | Kill to end of line |
    | ⌃Y | Yank killed text |
    | ⌃T | Transpose characters |
    | ⌥⇧⌘V | Paste and match style |

    ## Finder
    | Shortcut | Action |
    |---|---|
    | ⇧⌘G | Go to folder |
    | ⌘↑ | Enclosing folder |
    | ⌘↓ | Open selection |
    | Space | Quick Look |
    | ⌘⌫ | Move to Trash |
    | ⇧⌘. | Show hidden files |
    | ⌥⌘C | Copy path of selection |
    | ⌘1 … ⌘4 | Icon / list / column / gallery view |
    | ⌃⌘N | New folder with selection |

    ## Windows
    | Shortcut | Action |
    |---|---|
    | ⌘M | Minimise |
    | ⌘H | Hide app |
    | ⌥⌘H | Hide others |
    | ⌘W | Close window |
    | ⌥⌘W | Close all windows |
    | ⌘, | Settings |
    """

    static let git = """
    # Git Everyday

    ## Status & history
    - `git status -sb` — short status with branch
    - `git log --oneline --graph --all` — compact history graph
    - `git diff` — unstaged changes
    - `git diff --staged` — staged changes
    - `git show HEAD~1` — inspect a previous commit
    - `git blame -w file` — who changed each line

    ## Branches
    - `git switch -c name` — create and switch
    - `git switch -` — back to the previous branch
    - `git branch -d name` — delete a merged branch
    - `git branch -vv` — branches with upstream info
    - `git rebase -i main` — rewrite your branch onto main

    ## Commit
    - `git add -p` — stage hunks interactively
    - `git commit --amend --no-edit` — fold changes into the last commit
    - `git commit --fixup=SHA` — mark a fix for autosquash
    - `git restore --staged file` — unstage a file
    - `git restore file` — discard working-tree changes

    ## Remote
    - `git fetch --prune` — update and drop deleted remote branches
    - `git pull --rebase` — rebase local work on top of upstream
    - `git push -u origin HEAD` — push and set upstream
    - `git push --force-with-lease` — safer force push

    ## Rescue
    - `git stash push -m "msg"` — shelve changes
    - `git stash pop` — re-apply the latest stash
    - `git reflog` — find "lost" commits
    - `git reset --soft HEAD~1` — undo last commit, keep changes staged
    - `git cherry-pick SHA` — apply a single commit here
    """

    static let vim = """
    # Vim Motions

    ## Move
    | Keys | Motion |
    |---|---|
    | `h` `j` `k` `l` | Left, down, up, right |
    | `w` / `b` / `e` | Next word / back a word / end of word |
    | `0` / `^` / `$` | Line start / first non-blank / line end |
    | `gg` / `G` | First line / last line |
    | `{` / `}` | Previous / next paragraph |
    | `%` | Matching bracket |
    | `f`x / `t`x | Jump to / before character x |
    | Ctrl+D / Ctrl+U | Half page down / up |

    ## Edit
    | Keys | Action |
    |---|---|
    | `i` / `a` | Insert before / after cursor |
    | `o` / `O` | Open line below / above |
    | `ciw` | Change inner word |
    | `ci"` | Change inside quotes |
    | `dd` / `yy` / `p` | Delete / yank / put line |
    | `.` | Repeat last change |
    | `u` / Ctrl+R | Undo / redo |
    | `>>` / `<<` | Indent / outdent |

    ## Search & replace
    | Keys | Action |
    |---|---|
    | `/pattern` | Search forward |
    | `n` / `N` | Next / previous match |
    | `*` | Search word under cursor |
    | `:%s/old/new/g` | Replace in whole file |

    ## Windows
    | Keys | Action |
    |---|---|
    | Ctrl+W s | Split horizontally |
    | Ctrl+W v | Split vertically |
    | Ctrl+W w | Cycle windows |
    | `:q` / `:wq` | Quit / write and quit |
    """
}
