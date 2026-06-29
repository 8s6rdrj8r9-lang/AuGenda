# Font Files

These font files are bundled with AuGenda for accessibility:

- **Atkinson Hyperlegible** (Regular, Bold) — Braille Institute, SIL Open Font License
- **OpenDyslexic** (Regular) — OpenDyslexic, free to use

## Xcode Setup

After adding these files to the repo, you must also add them to the Xcode project:

1. Open `AuGenda.xcodeproj` in Xcode
2. Drag `Fonts/` folder into the Project Navigator
3. Select "Create groups" and check the "AuGenda" target
4. Verify `Info.plist` contains `UIAppFonts` with the correct filenames
5. Build and verify the fonts load correctly
