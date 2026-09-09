# Reicon local catalog

Local copy of the [Reicon](https://github.com/dqev/reicon) SVG icon library so we can search names and preview files without guessing. **Not shipped in the app.** Only the eight files under `Light Stats/Resources/Icons/` go into the bundle.

Source: `https://github.com/dqev/reicon` (MIT). Outline and Filled weights, 24×24.

## Browse

- Open `catalog.html` in a browser. Search by name or category; click a tile to copy the kebab-case name.
- `names.txt` — one name per line, for `rg` / Finder.
- `names-by-category.txt` — same names grouped by category.
- `outline/` and `filled/` — 2680 SVGs each.

```bash
rg -i 'cpu|fan|battery' design/reicon/names.txt
open design/reicon/catalog.html
```

## Copy into the app

1. Pick an Outline SVG (that is the weight already used in the product).
2. Copy it to `Light Stats/Resources/Icons/<app-name>.svg`.
3. Add the case to `AppSVGIcon` if needed, and keep `ATTRIBUTION.txt` in sync.

Current shipped mapping:

| App file | Reicon name |
|----------|-------------|
| cpu.svg | cpu |
| gpu.svg | microchip |
| memory.svg | ram2 |
| network.svg | station |
| proxy.svg | shield-network |
| disk.svg | ssd |
| temperature.svg | temperature |
| processes.svg | layers |

## Refresh

```bash
cd design/reicon
curl -fsSL -o reicon-icons.zip https://raw.githubusercontent.com/dqev/reicon/main/public/reicon-icons.zip
unzip -q -o reicon-icons.zip
```
