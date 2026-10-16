# Reference trace

The supplied still is 1775 × 3840; coordinates below use a 947 × 2048 reference canvas. The supplied screen recording is 1170 × 2532 at 60 fps, 6.703 seconds long. Neither original media file is included in this public repository.

## Home geometry

- Icon size: 156 reference pixels; horizontal centers: 145.5, 364.5, 583, 801.
- Row top edges: 163, 401, 639, 877, 1115, 1353.
- Label: 29 pixel system font in a 34 pixel line box, separated from the icon by 13 pixels. The line box includes the font's ascender/descender space.
- Search capsule: 146 × 73, center at (473.5, 1706.5).
- All layout measurements use the full screen rather than safe-area origin. The real OS status bar remains visible and manages its own hardware-dependent placement. The user-approved resting placement includes the previous page host’s vertical offset, (top safe inset − bottom safe inset) / 2; the lighter pager preserves that offset explicitly.
- The white Photos icon contour measured near the top edge follows a fourth-order superellipse: roughly 17 pixels inset at 8 pixels below the top of a 156 pixel icon. This contour is used for both the glass and the icon's paint/border.

## Motion

Frames were inspected at 10 fps across the full clip and 30 fps across opening transitions. Folder opening starts around 0.78 seconds and is essentially settled around 1.1–1.2 seconds. App opening starts around 3.39 seconds and reaches the screen edge around 3.65–3.75 seconds.

Folder target: x = 12.1% screen width, y = 29.55% screen height, width = 75.8% screen width, height = 41.0% screen height. Title center: (50%, 23%). Interior icons retain home icon size, with centers at 26.9%, 50%, 73.1% screen width.

The folder surface and each preview icon interpolate from their source rectangles to the measured destination rectangles. Labels/title fade in during expansion. Background icons enlarge and blur. Closing reverses the same geometry. Numbered pages grow from the tapped icon, crossfade from icon art into content, then return to that same source rectangle. Gestures can interactively reduce expansion progress.

SpringBoard is an OS-private implementation; this app recreates its observed motion with public SwiftUI APIs. It does not call private APIs or replace the iPhone launcher. The clock widget in the new still is not added: the existing 32 numbered destinations and editable folders are preserved. The earlier instruction to omit the Dock is retained.

## Performance and editing update

The resting geometry is retained. Numbered icon art and the default wallpaper are cached images; live Liquid Glass remains on folders and controls. Interactive glass highlights and platform copy-drag previews have been removed. A sequenced long press and direct drag move only the icon. Folder rename operations require a folder with multiple slots, and saved single-slot names are repaired on load. UI verification covers normal navigation, moving 13 to 17’s former cell, dissolving a folder, and keeping the final numbered name after relaunch.
