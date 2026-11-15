# PS1 developer tooling

Scripts and CMake settings for building this fork locally on Windows.

## Requirements

* Visual Studio 2022 or later with the C++ x64 tools (headers and libraries).
* LLVM for Windows (`clang-cl`, `lld-link`) in `C:\Program Files\LLVM\bin`.
* CMake 3.20+, Python 3.
* Ninja and sccache: `winget install Ninja-build.Ninja Mozilla.sccache`.

## Layout

| Path | Purpose |
|---|---|
| `G:\git\llvm-project-ps1-mips` | main checkout (`ps1/main`), build dir `build\` |
| `G:\git\llvm-ps1-worktrees\MIC-<n>` | one worktree per ticket, build dir `build\` |
| `G:\git\ps1-tools\sccache` | shared sccache cache (60 GB cap) |

## Scripts

All scripts live in `ps1\scripts\` and work from any checkout.

| Script | What it does |
|---|---|
| `ps1-env.ps1` | Dot-source it. Enters the VS x64 dev shell, puts Ninja/sccache on PATH, configures sccache. |
| `configure.ps1 [-Fresh]` | Configures `build\` with `ps1\cmake\ps1-dev.cmake`. |
| `build.ps1 [targets...]` | Builds the default tool set, or the Ninja targets given. Prints the elapsed time. |
| `new-worktree.ps1 MIC-<n> <name>` | Creates `G:\git\llvm-ps1-worktrees\MIC-<n>` on branch `MIC-<n>-<name>` from `origin/ps1/main` and configures it. Refuses a fourth active worktree. |
| `remove-worktree.ps1 MIC-<n> [-Force]` | Deletes the worktree and its build dir. Keeps the branch. |

Typical ticket flow:

```powershell
ps1\scripts\new-worktree.ps1 MIC-14 r3000a-processor
cd G:\git\llvm-ps1-worktrees\MIC-14
ps1\scripts\build.ps1
ps1\scripts\build.ps1 check-llvm-codegen-mips check-llvm-mc-mips
```

## Build configuration

`ps1\cmake\ps1-dev.cmake`:

* Release with assertions, projects `clang;lld`, target `Mips` only.
* `clang-cl` + `lld-link` (MSVC ABI), sccache as the compiler launcher.
* `CMAKE_MSVC_DEBUG_INFORMATION_FORMAT=Embedded` (`/Z7`): sccache cannot cache
  `/Zi`, which writes a shared PDB.
* `LLVM_USE_RELATIVE_PATHS_IN_FILES=ON` and `SCCACHE_BASEDIRS` (set to every
  checkout by `ps1-env.ps1`) make objects independent of the checkout path, so
  a new worktree's build is served from the cache.

`ps1-env.ps1` restarts the sccache server when the set of checkouts changes,
because the server reads `SCCACHE_BASEDIRS` at start-up. Do not create or
remove a worktree while another checkout is building.

## Build times

Default tool set (3395 Ninja steps, 2770 compiles), measured on a 24-thread,
32 GB machine with clang-cl 23.1.5 and sccache 0.19.0.

| Build | Time | sccache |
|---|---|---|
| Base checkout, cold cache | 15:01 | 0.04% hits |
| New worktree, warm cache | 2:17 | 99.82% hits (2765 / 2770) |

The warm build is dominated by linking. The tests
`check-llvm-codegen-mips check-llvm-mc-mips check-lld` add about 3 minutes on a
fresh build dir (extra tools plus test run).
