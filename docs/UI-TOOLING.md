# UI measurement tools

These are local developer tools for native macOS windows. They do not add
telemetry, network calls or user-facing behaviour. Use them when a screenshot
alone is not precise enough for layout work.

## `scripts/ui_probe.swift`

Reads the Accessibility geometry of a running window and prints frames plus
gaps in screen points.

```bash
swift scripts/ui_probe.swift --app Cornetta --window Summary
swift scripts/ui_probe.swift --app Cornetta --window Summary --json /tmp/summary.json
```

Grant Accessibility permission to the terminal or the process that runs jcode
in **System Settings → Privacy & Security → Accessibility** for the full view
tree. Without it the tool falls back to `CGWindowList` and still reports the
outer window frame.

Output includes:

- window frame and estimated content frame;
- `AXScrollArea` frame and gaps to the content edges;
- `AXTextArea` height and free space below it;
- every button frame with its bottom and right gap;
- the visible content bottom and the empty space before the real content bottom;
- a JSON tree with role, description, frame and accessibility path for each node.

The last toolbar item is normally the content edge, so the button gap is the
space a footer has to close. For example, before 0.9.7 the Summary settings
window reported:

```text
Window frame: x=915 y=435 w=700 h=678
Content frame: x=915 y=463 w=700 h=650
Button Close: bottom gap 212.5, right gap 77.5
Button Save:  bottom gap 212.5, right gap 24.0
Visible content bottom: 900.5, empty bottom: 212.5
```

After the 0.9.7 layout fix the same probe reported:

```text
Button Close: bottom gap 24.0, right gap 77.5
Button Save:  bottom gap 24.0, right gap 24.0
Visible content bottom: 1089.0, empty bottom: 24.0
Scroll area (prompt editor): 652 x 281.5, left/right gap 24.0
```

The text editor grew from 210 points to 281.5 points at the default window
size. Resizing the now-resizable window grows it further while the footer stays
24 points from the bottom. `ui_grid.py` independently measured
`blank_bottom_points: 23.5`, matching the Accessibility result.

## `scripts/ui_grid.py`

Adds a point grid, a content box and an empty-area overlay to a window-only
screenshot. It also detects the last row and column that contain content.

```bash
screencapture -x -l 56066 shot.png
python3 scripts/ui_grid.py shot.png --scale 2 --content-top 28 \
  --out shot-grid.png --json shot-grid.json
```

`--content-top` is the point where the titlebar ends. On a Retina display the
PNG is twice the point size, so pass `--scale 2`. The tool trims the transparent
shadow produced by `screencapture -l` automatically. Pillow is required
(`python3 -m pip install pillow`); it is an optional developer dependency.

The JSON contains `content_bottom_points`, `blank_bottom_points` and
`blank_right_points`. Use these to prove that a footer is not at the window
edge or that a text box leaves a large unused region.

## Layout rules

- Make the content area flexible: `.frame(maxHeight: .infinity)`.
- Pin the footer at the bottom, not in the middle: let the content group fill
  the window, then place the footer after it.
- A text editor should use `.frame(minHeight: 210, maxHeight: .infinity)` and
  `.layoutPriority(1)` inside that flexible group.
- Make settings windows `.resizable` and set `contentMinSize`; otherwise the
  empty space cannot be reclaimed by the user.
- Keep outer scroll views at the window edge. Put padding inside the scroll
  content, not around the whole scroll view. A footer belongs in
  `safeAreaInset(edge: .bottom)` or below a flexible scroll view.
- Prefer the 8-point grid from the design rules. `ui_grid.py` draws 8-point
  minor lines and 50-point labelled major lines.

## Privacy

The probe reads role, description and frame only. It does not print text-field
or password values. The grid tool works on a local screenshot and writes local
artifacts. Neither tool contacts the network.
