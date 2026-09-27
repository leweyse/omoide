---
"omoide": patch
---

fix(ui): borders, focus marks and corners look inconsistent across cards, badges and buttons

- Library: card borders break at some screen resolutions
- Events and collections: a card loses its top border while the row is scrolled
- Cards: focus shows as corner marks everywhere, and badges and buttons follow the theme's corner rounding
