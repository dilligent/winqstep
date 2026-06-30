# Product Scope

WinQStep is a deterministic workflow tool for Windows users who run CP2K
QuickStep inside WSL2. It should reduce setup, input-file, path, and run-control
friction without pretending to make scientific decisions for the user.

## Goals

- Detect the user's real WSL2 and CP2K environment.
- Generate CP2K QuickStep inputs from explicit, typed GUI choices.
- Keep generated inputs readable and editable.
- Run an existing CP2K command through `wsl.exe`.
- Show logs and collect output files back into a Windows project folder.
- Integrate with external visualization or analysis tools instead of replacing
  them.

## Non-goals

- Do not use an LLM to generate CP2K input.
- Do not bundle CP2K source code, CP2K binaries, or CP2K data files.
- Do not implement broad post-processing or scientific interpretation.
- Do not try to expose the full CP2K input tree in the first versions.
- Do not hide CP2K errors behind generic GUI messages.

## First MVP

The first MVP is complete when a user can:

1. Select or confirm a WSL2 distro.
2. Detect `cp2k.psmp`, `cp2k`, or another configured CP2K command.
3. Detect `CP2K_DATA_DIR` and common basis/potential files.
4. Import a simple periodic structure.
5. Generate a QuickStep `ENERGY`, `ENERGY_FORCE`, `GEO_OPT`, or `CELL_OPT`
   input.
6. Run CP2K and save `.inp`, `.out`, and related outputs in a Windows folder.

## Product Rule

When the GUI cannot prove that an option maps to a supported CP2K keyword for
the user's environment, it should either hide that option or present it as an
advanced raw override. The default path should stay conservative and testable.
