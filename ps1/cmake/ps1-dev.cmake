# Initial cache for local PS1 development builds on Windows.
# Used by ps1/scripts/configure.ps1 via `cmake -C`.

set(CMAKE_BUILD_TYPE Release CACHE STRING "")
set(LLVM_ENABLE_ASSERTIONS ON CACHE BOOL "")

set(LLVM_ENABLE_PROJECTS "clang;lld" CACHE STRING "")
set(LLVM_TARGETS_TO_BUILD "Mips" CACHE STRING "")

# clang-cl + lld-link against the MSVC headers and libraries.
set(CMAKE_C_COMPILER clang-cl CACHE STRING "")
set(CMAKE_CXX_COMPILER clang-cl CACHE STRING "")
set(LLVM_USE_LINKER lld CACHE STRING "")
set(LLVM_PARALLEL_LINK_JOBS 6 CACHE STRING "")

# sccache. LLVM's own ccache hook stays off.
set(LLVM_CCACHE_BUILD OFF CACHE BOOL "")
set(CMAKE_C_COMPILER_LAUNCHER sccache CACHE STRING "")
set(CMAKE_CXX_COMPILER_LAUNCHER sccache CACHE STRING "")
# sccache cannot cache /Zi (shared PDB). Embed debug info (/Z7) if any is enabled.
set(CMAKE_MSVC_DEBUG_INFORMATION_FORMAT Embedded CACHE STRING "")
# Strip the checkout path from __FILE__ so worktrees produce identical objects.
set(LLVM_USE_RELATIVE_PATHS_IN_FILES ON CACHE BOOL "")

# Fewer host dependencies, faster configure.
set(LLVM_ENABLE_ZLIB OFF CACHE STRING "")
set(LLVM_ENABLE_ZSTD OFF CACHE STRING "")
set(LLVM_ENABLE_LIBXML2 OFF CACHE STRING "")
set(LLVM_INCLUDE_BENCHMARKS OFF CACHE BOOL "")
set(LLVM_INCLUDE_EXAMPLES OFF CACHE BOOL "")
set(LLVM_INCLUDE_DOCS OFF CACHE BOOL "")
