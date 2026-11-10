# STL Support Viewer — complete Codespaces restore

This project contains the Julia HTTP backend, Three.js browser frontend, dependency manifest specification, and Codespaces configuration.

## Install into a blank Codespaces project

1. Upload `STL_Support_Viewer_COMPLETE_RESTORE.zip` into `/workspaces/STL-Support-Viewer/` using the VS Code Explorer (right-click folder > Upload Files).
2. Open a Codespaces terminal and run:

```bash
cd /workspaces/STL-Support-Viewer
unzip -o STL_Support_Viewer_COMPLETE_RESTORE.zip
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. server.jl
```

3. Leave the Julia server running. Open port 8080 using the **Ports** tab.
4. Load aligned original and supported STLs, click **Identify supports**, then use the CSV or RoboDK ZIP export buttons.

If port 8080 is already in use, stop the old Julia server first. Do not run two servers simultaneously.

## Project structure

- `server.jl` — Julia backend and approximate contact detection
- `web/index.html` — browser viewer and export tools
- `Project.toml` — required Julia packages
- `.devcontainer/` — Codespaces setup

## Important limitations

The classifier uses vertex proximity, not exact mesh subtraction. Contact regions are approximate and are NOT validated cutting targets. The assembly STL is not Boolean-unioned or verified watertight for printing. The RoboDK package provides geometry and coordinate references, NOT tool paths, cutter angles, collision checks, or robot executable code. Inspect all exported geometry before printing and validate robot motion independently.
