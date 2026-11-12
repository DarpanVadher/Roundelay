# Roundelay design system

Direction: one cobalt brand colour, a sun-yellow accent used sparingly (the dot at the centre of the mark, tertiary containers), and blue-tinted neutrals. The app (Flutter, Material 3) and the site (`site/style.css`) share these tokens. The app is an Operate surface (calm, native, scannable); the site is Persuade.

Source of truth in code: `app/lib/theme.dart` (`roundelayLight`, `roundelayDark`) and the `:root` variables in `site/style.css`.

## Brand mark
Two concentric rings and a centre dot (a roundelay: devices in a ring, in sync). White rings and a sun dot on a cobalt tile. Masters: `app/assets/icon/roundelay-icon.svg` (tile) and `roundelay-foreground.svg` (adaptive layer). Outputs are regenerated with `app/assets/icon/generate_icons.py`.

## Palette
| Token | Light | Dark | Role |
|---|---|---|---|
| primary | `#2433FF` | `#9FB0FF` | actions, links, brand |
| onPrimary | `#FFFFFF` | `#0B0F2B` | text on primary |
| primaryContainer | `#DFE3FF` | `#1722C9` | selected/pending surfaces |
| onPrimaryContainer | `#0D1233` | `#E4E8FF` | |
| secondary | `#424A73` | `#A9B1D9` | secondary text/controls |
| secondaryContainer | `#E6EAF9` | `#2A3270` | |
| tertiary | `#6B5200` | `#FFD84A` | accent |
| tertiaryContainer | `#FFD84A` | `#5C4800` | highlight chips, hero icon tile |
| surface | `#F3F5FC` | `#0B0F2B` | page background |
| surfaceContainerLowest..Highest | `#FFFFFF` to `#DDE2F5` | `#070A20` to `#20285F` | cards, sheets |
| onSurface | `#0D1233` | `#EEF0FF` | body text |
| onSurfaceVariant | `#424A73` | `#A9B1D9` | supporting text |
| outline / outlineVariant | `#666E96` / `#CCD3EE` | `#7F89BD` / `#2A3270` | borders, dividers |
| error / errorContainer | `#BA1A1A` / `#FFDAD6` | `#FFB4AB` / `#93000A` | errors |
| inverseSurface | `#1B2150` | `#EEF0FF` | scan-screen caption bar (88% opacity over camera) |

Rules: the QR code keeps a white quiet zone in both themes. Never place text on the sun accent except `#0D1233`. Neutrals are tinted toward the brand hue; no pure black or white surfaces except the QR and `surfaceContainerLowest` in light.

## Contrast (WCAG AA)
Computed from `theme.dart`: every text pair (on-colour over its container, onSurface and onSurfaceVariant over surfaces, primary over surface) is at least 6.4:1 in light and 7.2:1 in dark; `outline` over `surface` is 4.55:1 (light) and 5.56:1 (dark), above the 3:1 non-text requirement.

## Typography
App uses the platform default (Roboto / Segoe UI) with Material 3 type scale. Site: Bricolage Grotesque for display, Figtree for body (self-hosted in `site/fonts`).

## Glass and motion
Neutral cards (home choices, connected devices, guest status) are frosted glass: `GlassCard` in `app/lib/widgets/glass.dart` (18 px backdrop blur, white fill at 62% light / 7% dark, hairline white border) over `GlassBackdrop` (surface plus a cobalt glow top-left and a sun glow bottom-right). Alert cards (errors, join requests, demo banner) stay solid so they never lose contrast.

Illustration and motion: `RoundelayArt` (`app/lib/widgets/roundelay_art.dart`) is the mark as a living illustration: ripples pulse out from the sun dot, and device dots orbit while the host waits for guests. `Reveal` fades and slides content in (staggered 120 ms on the home screen). All of it stops under the OS reduced-motion setting, and the illustration is hidden in windows under 700 px tall.
