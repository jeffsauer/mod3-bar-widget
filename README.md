<img width="1894" height="1218" alt="mod3-bar-widget" src="https://github.com/user-attachments/assets/082c51e3-0780-45a4-9471-a62fb46e8c19" />

# mod3-bar-widget
Omarchy plugin bar widget that drops down and toggles visibility of the [mod3 solitaire game](https://github.com/jeffsauer/mod3_solitaire) using a hyprland scratchpad workspace.

Assumes mod3-solitaire AppImage is located in ~/Applications and is named Mod3_Solitaire.AppImage

To install, use the following command:

```
omarchy plugin add https://github.com/jeffsauer/mod3-bar-widget --enable
```

Also add the following to your ~/.config/hypr/hyprland.lua file:

```
-- Mod3 Solitaire: park the game window on a special (scratchpad) workspace so
-- the bar plugin can show/hide it like a dropdown. Floated and
-- sized so it reads as a panel, not a tiled full screen window.
o.window({ title = "^Mod3 Solitaire$" }, {
  workspace = "special:mod3",
  float = true,
  size = { 1040, 900 },
  center = true,
})
```

To enable a keybinding shortcut to toggle the visibility (e.g. SUPER+ALT+M), simply add the following to .config/hypr/bindings.lua:

```
o.bind("SUPER + ALT + M", "Mod3 Solitaire", "omarchy-shell -q com.darkhorse-studios.mod3-bar-widget toggle")
```

Make sure you are not over-riding an existing key binding.
