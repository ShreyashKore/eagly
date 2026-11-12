# Framework logos

The marks drawn on the Logs pane's framework chips (`LogFramework.logoAsset`).

- **Source:** [Simple Icons](https://github.com/simple-icons/simple-icons)
  (branch `develop`), copied unchanged, for every file except `defold.svg`.
  Simple Icons publishes the files under CC0 1.0.
- **Defold:** `defold.svg` is the Defold Foundation's own colour logo,
  `images/logo/DefoldLogoColour.svg` from
  [defold/defold.github.io](https://github.com/defold/defold.github.io/blob/master/images/logo/DefoldLogoColour.svg)
  (branch `master`), copied byte-for-byte. Simple Icons has no Defold mark.
- **Trademarks:** each mark is a trademark of its owner (Google, Meta, Unity
  Technologies, Epic Games, the Godot Engine project, Microsoft / the .NET
  Foundation, Ionic, the Apache Software Foundation, Cocos, YoYo Games, the
  Defold Foundation). Eagly uses them only to identify the framework a log
  line comes from, and implies no endorsement.
- **Godot:** the Godot logo is by the Godot Engine project and licensed under
  CC BY 4.0 ([godotengine.org/press](https://godotengine.org/press)).

The Simple Icons SVGs are single-path 24×24 monochrome glyphs; the chips tint
them with the framework's accent (`EaglyTheme.frameworkColor`). The Defold logo
is full colour (gradients and a `<style>` block) and is drawn untinted
(`LogFramework.logoHasOwnColours`).

Solar2D and Kivy have no logo here: Simple Icons has no mark for either, and no
official SVG was found to copy. Their chips draw a Material glyph instead.
