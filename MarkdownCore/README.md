# MarkdownCore

The parts of dexEdit that are only text and ranges:

- `MarkdownScanner` — line-based scanner producing character ranges for live styling
- `MarkdownFormatter` — wrap/unwrap, headings, line prefixes, links, images
- `MarkdownContext` / `ActiveFormats` — what markdown surrounds the cursor
- `Note` — title, preview and filename slug derived from the text

Nothing here imports AppKit, so it builds unchanged for iOS. Anything that needs
a text view, a colour or a font lives in the app instead — see
`Sources/Editor/MarkdownStyler.swift` and `MarkdownFormatterApply.swift`.

```bash
swift test    # 55 tests, no app required
```
