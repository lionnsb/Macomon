# Contributing to Macomon

Thanks for helping this tiny pixel world grow.

## Before opening a pull request

1. Keep changes focused and preserve the native AppKit architecture.
2. Build the project with `swift build`.
3. Build the app with `./scripts/build-app.sh`.
4. Run `dist/Macomon.app/Contents/MacOS/Macomon --self-test`.
5. Verify animated assets at every supported display size.

## Companion assets

- Use a transparent 64 × 64 GIF canvas.
- Keep binary alpha and nearest-neighbor pixel edges.
- Use `default_<behavior>_8fps.gif` filenames.
- Use `default_walk_left_8fps.gif` for a dedicated left-facing walk.
- Prefix contextual rain behaviors with `rain_`.
- Keep the character's size, baseline, outline, and palette consistent.
- Only submit artwork you created or have permission to redistribute.

## Code style

- Prefer small, explicit AppKit components.
- Preserve existing user settings and migration behavior.
- Add or update self-test coverage for new resources and behavior rules.
- Do not commit `.build`, app bundles, or DMG files.

## Issues

Please include the macOS version, Mac model, selected pet, display location, and reproduction steps for visual or behavioral bugs.
