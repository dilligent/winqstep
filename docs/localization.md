# Localization

Round 20 added the first GUI localization layer for English and simplified
Chinese. Round 21 adds a persisted GUI language preference.

## Languages

Resource files live under `resources/i18n/`:

- `en-US.json`
- `zh-CN.json`

The GUI language is chosen in this order:

1. `-Language` on the launcher command line.
2. `ui_language` in the active WinQStep config file.
3. Windows UI culture.

Use `-Language` for a temporary launch override:

```powershell
.\WinQStep.ps1 -Language en-US
.\WinQStep.ps1 -Language zh-CN
```

The lower-level GUI script accepts the same option:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start_gui.ps1 -Language zh-CN
```

To persist a preference, set `ui_language` in the config to `en-US` or `zh-CN`,
or use the `UI Language` field on the GUI `Config` tab and then `Save Config`.
An empty value means system default.
The `Apply` button next to `UI Language` refreshes the current window
immediately without writing the config file.

## Scope

Localized text currently covers high-value GUI text:

- top action buttons;
- job input labels;
- main tab headers;
- artifact buttons;
- common status bar messages;
- common message box captions and close-window warning text.
- the GUI language selector.

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
`scripts/gui/WinQStep.xaml` is loaded. If no `-Language` override is supplied,
loading a config with `ui_language` refreshes the currently visible GUI labels.
The `Config` tab's language `Apply` button calls the same localization refresh
path directly from the selected language value.

Missing keys fall back to the key name, and non-English languages fall back to
`en-US` for any keys not present in the selected resource file.
