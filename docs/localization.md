# Localization

Round 20 adds the first GUI localization layer for English and simplified
Chinese.

## Languages

Resource files live under `resources/i18n/`:

- `en-US.json`
- `zh-CN.json`

The GUI defaults from the Windows UI culture. Use `-Language` to override it:

```powershell
.\WinQStep.ps1 -Language en-US
.\WinQStep.ps1 -Language zh-CN
```

The lower-level GUI script accepts the same option:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start_gui.ps1 -Language zh-CN
```

## Scope

Localized text currently covers high-value GUI text:

- top action buttons;
- job input labels;
- main tab headers;
- artifact buttons;
- common status bar messages;
- common message box captions and close-window warning text.

The localization layer intentionally does not translate:

- CP2K input keywords;
- JSON keys or metadata schemas;
- file names and paths;
- CP2K stdout, stderr, or `.out` text;
- generated QuickStep input text.

Those values remain stable because they are part of CP2K or WinQStep's machine
interfaces, not user-facing prose.

## Implementation Notes

`scripts/gui/WinQStep.GuiHost.ps1` loads localization resources and provides
small lookup helpers such as `Get-WinQStepText` and `Format-WinQStepText`.
`scripts/start_gui.ps1` applies those resources to the loaded WPF controls after
`scripts/gui/WinQStep.xaml` is loaded.

Missing keys fall back to the key name, and non-English languages fall back to
`en-US` for any keys not present in the selected resource file.
