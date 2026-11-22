# Kinemium custom themes

In **Settings → Themes**, select a source preset, edit its tokens, then
**Save & Apply**. Export a saved theme to JSON, or import someone else's JSON.
Built-in themes remain read-only.

## Window background tokens

Each theme can define the following `tokens.window` settings:

```json
{
  "backgroundImage": "/home/user/Pictures/wallpaper.png",
  "backgroundImageTransparency": 0.18,
  "backgroundImageScaleType": "Crop",
  "contentTransparency": 0.78
}
```

An empty `backgroundImage` disables the background. The supported image
types are PNG, JPG/JPEG, WebP, GIF and SVG. Scaling is `Crop`, `Fit` or
`Stretch`. Transparency values are between 0 and 1: a higher
`contentTransparency` shows more of the image behind window content.

**Settings → Themes → Window Background** provides a native image picker,
preview, scaling selector and opacity controls. The theme-wide background
applies to editor windows that do not specify their own background image;
per-window `UI.window` options and window component overrides take precedence.

## Sharing image backgrounds

**Export JSON** bundles an image selected from a local filesystem path into
the JSON as a version-1 `windowImage` payload containing the image extension
and Base64 bytes (maximum 8 MiB before encoding). The exported JSON remains
a single shareable file.

**Import JSON** validates the embedded image and writes a uniquely named
image file alongside the imported theme JSON, then stores its new local path.
The original theme author's absolute path is not needed on the recipient's
computer. A writable folder is required for importing bundled images.

Builtin images and project URIs are saved as references rather than bundled.
A project URI still requires the matching project asset. Older v1 theme JSON
files without `tokens.window` continue to import.

The JSON file uses the schema keys `format: "kinemium-theme"`, `version: 1`,
`name`, and `tokens`. Colors are `#RRGGBB`; font fields include a builtin
family URI, weight, and style. Numeric token ranges are validated on import.
