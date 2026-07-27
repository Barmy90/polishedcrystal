#!/bin/sh
# Convenience wrapper: this system's native `gcc` PATH lookup resolves to a
# broken/unrelated binary (missing cc1), so point CC at the real WinLibs
# mingw-w64 gcc explicitly. See conversation history for how it was diagnosed.
WLBIN="/c/Users/Work/AppData/Local/Microsoft/WinGet/Packages/BrechtSanders.WinLibs.POSIX.UCRT_Microsoft.Winget.Source_8wekyb3d8bbwe/mingw64/bin"
exec "$WLBIN/mingw32-make.exe" CC="$WLBIN/gcc.exe" "$@"
