# Speed Monitor Bugs

## Open

_No open bugs_

## Fixed

### BUG-001: Version comparison uses string instead of numeric
- **Journey**: UI-4
- **Severity**: High
- **Status**: ✅ FIXED (v3.1.05)
- **Description**: Update indicator not showing when 3.1.04 > 3.1.2
- **Root Cause**: String comparison "3.1.04" < "3.1.2" (lexicographic)
- **Fix Applied**: Added `isNewerVersion()` function with numeric comparison in SpeedMonitorMenuBar.swift:427-439
- **Verification**: Server 3.1.05 correctly shows update for app 3.1.2
