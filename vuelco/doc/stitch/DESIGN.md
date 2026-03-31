```markdown
# Design System Strategy: Vuelco

## 1. Overview & Creative North Star
This design system moves away from the generic "SaaS-kit" aesthetic to embrace **The Digital Curator**. In the high-stakes world of legal and accounting, users aren't looking for a "tool"—they are looking for a definitive, authoritative environment. 

The Creative North Star is defined by **Institutional Elegance**. We achieve this through "Soft Layering" and high-contrast typography that feels more like a modern financial journal than a standard web app. We intentionally break the rigid, boxed-in layout seen in the reference images (Extractito) by using expansive breathing room and shifting background tones to define sections, rather than heavy lines and borders.

## 2. Colors: Tonal Depth & Sophistication
Our palette is anchored in deep authority and fresh precision.

### The "No-Line" Rule
**Explicit Instruction:** You are prohibited from using 1px solid borders for sectioning. Structural separation must be achieved through background color shifts. For example, a `surface-container-low` (#f3f4f5) section should sit on a `surface` (#f8f9fa) background. This creates a high-end, seamless feel that standard "boxed" layouts lack.

### Surface Hierarchy & Nesting
Treat the UI as a series of physical layers. 
- **The Base:** Use `surface` (#f8f9fa) for the overall application canvas.
- **The Workspace:** Use `surface-container-lowest` (#ffffff) for primary work areas (like a sheet of paper on a desk).
- **Nested Context:** Use `surface-container-highest` (#e1e3e4) for internal sidebars or metadata panels to create natural recession.

### Signature Textures
- **The CTA Gradient:** For primary buttons and high-level headers, do not use flat colors. Use a subtle linear gradient from `primary` (#031636) to `primary_container` (#1a2b4c) at a 135-degree angle.
- **Glassmorphism:** For floating modals or navigation bars, use semi-transparent `surface_container_low` with a 20px backdrop-blur to allow brand colors to bleed through, softening the interface.

## 3. Typography: Editorial Authority
We utilize a dual-font strategy to balance character with utility.

- **The Display/Headline Axis (Manrope):** Chosen for its geometric precision and modern professional edge. `display-lg` (3.5rem) should be used with tight letter-spacing (-0.02em) to command attention in dashboards.
- **The Utility Axis (Inter):** Used for all `body` and `label` styles. Inter provides maximum legibility for dense accounting data and legal text.
- **Hierarchy as Brand:** Use `headline-sm` (1.5rem, Manrope) for section titles instead of bold body text. The contrast between the editorial Manrope and the functional Inter communicates "Vuelco" as a premium service.

## 4. Elevation & Depth: Tonal Layering
Traditional shadows and borders create visual noise. In this system, depth is "felt" rather than "seen."

- **The Layering Principle:** Instead of a shadow, place a `surface-container-lowest` (#ffffff) card on a `surface-container-low` (#f3f4f5) background. The subtle 2% difference in luminosity provides all the separation required for a premium look.
- **Ambient Shadows:** For floating elements (like dropdowns), use an extra-diffused shadow: `box-shadow: 0 20px 40px rgba(7, 27, 59, 0.06)`. Note the use of a tinted shadow (using `on_primary_fixed`) rather than pure black.
- **The "Ghost Border" Fallback:** If a border is required for accessibility in forms, use `outline_variant` at 20% opacity. Never use 100% opaque borders.

## 5. Components: Precision Primitives

### Buttons
- **Primary:** Gradient fill (`primary` to `primary_container`), `lg` roundedness (0.5rem), and `title-sm` typography. 
- **Secondary:** Transparent background with a "Ghost Border" and `on_surface` text.

### Cards & Lists
- **The Forfeiture of Dividers:** Horizontal lines are banned. Separate list items using `spacing-4` (1rem) of vertical white space or by alternating background tones (`surface-container-low` vs `surface-container-lowest`).
- **Signature Cards:** Cards should have no border. Use the `lg` (0.5rem) roundedness scale and a soft ambient shadow on hover to signal interactivity.

### Form Fields
- **Sophisticated Inputs:** Use `surface_container_highest` for the input background with a bottom-only "Ghost Border". On focus, transition the background to `surface_container_lowest` and the border to `secondary` (Mint/Cyan #006b5c).

### Additional Components: The "Audit Tracker"
Given the legal/accounting focus, implement a "Progressive Disclosure Stepper" that uses `secondary_container` (#68fadd) to highlight active states, moving away from the heavy dark bars seen in the reference images to a lighter, more ethereal "mint" glow.

## 6. Do's and Don'ts

### Do
- **Do** use asymmetrical layouts. Let a column of text breathe with wide 16 (4rem) margins on one side.
- **Do** use `secondary_fixed_dim` (#44ddc1) for success states and accent icons to keep the "fresh" mint feeling.
- **Do** use `manrope` for any numbers or data points to give them a "designed" financial look.

### Don't
- **Don't** use the playfully rounded "red heart" or similar iconography. All icons must be thin-stroke (1.5pt) and professional.
- **Don't** use standard "Modal Overlays" (pure black 50%). Use a `primary` (#031636) color at 30% opacity with a heavy blur to maintain the deep navy brand presence.
- **Don't** cram data. If a table feels tight, increase the row height using `spacing-12` (3rem) and remove all vertical lines.