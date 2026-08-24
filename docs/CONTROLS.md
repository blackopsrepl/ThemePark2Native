# Controls

The host translates modern inputs into the PC version's original keyboard and
mouse actions. It does not patch save data or require the DOS setup program.

## Keyboard and mouse

| Modern input | Original action |
|---|---|
| W / S | Walk / halt |
| A / D | Rotate left / right |
| Q | Attack |
| E | Defend |
| Space | Throw projectile or cast selected combat spell |
| F | Push, operate or give |
| Left/right click | Original contextual move/defend and throw/attack behavior |

The physical pointer is mapped from the actual aspect-correct content rectangle
to the engine's absolute pointer range, so letterboxing and fullscreen do not
change its coordinates. Click inside the game to capture it. Raw deltas support
captured/controller motion without allowing the Windows and DOS pointers to
drift apart. Press `Ctrl+F10`, or switch away, to release it.

The Windows arrow is always hidden over the game client because Heimdall draws
its own cursor. The host selects a transparent Win32 client cursor without
changing Windows' global cursor counter or input routing. The arrow reappears
over the frame, outside the game, or in another application.

`Escape` is delivered to Heimdall normally, including for advancing its intro.
If the game later returns to DOS, the private DOS runtime sends a shutdown
condition and the native window closes; no emulator menu is shown. The host
confirms that `H2PC` remains absent across several engine ticks, so an intro
transition or one transient DOS bookkeeping frame cannot close the window.

In expanded gameplay, scene X coordinates include the wider camera origin and
are translated back to the engine's original 320-pixel hit-testing space. Over
the centered control bar, its 53-pixel native offset is removed instead. DOS
scripts therefore receive the same coordinates they did in the original view.

`Ctrl+F5` writes the quick state and `Ctrl+F9` restores it. `Alt+Enter` toggles
borderless fullscreen. Presentation has no scale-mode selector: expanded
gameplay always fills a 16:9 client area at the machine's native height (1080,
1440, 2160, or a resized-window height); original menus use full-height 4:3.

## Xbox controller

| Xbox input | Action |
|---|---|
| D-pad | Walk, halt and rotate |
| Right stick | Move game cursor, with precision near center |
| Left stick | Unassigned |
| A / B | Left / right mouse button |
| Right / left trigger | Attack / defend |
| X | Throw projectile or cast combat spell |
| Y | Push, operate or give |
| Menu | Pause (`P`) |
| View | Escape/back |

The right-stick pointer and face-button bindings remain active everywhere.
This is intentional: Theme Park's maps, inventory, spell preparation and control
bar are mouse-driven, while movement and combat have unambiguous bindings. No
unreliable screen-image heuristic is needed to guess whether a menu is open.
