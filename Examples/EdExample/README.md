# EdExample

1. Run `make ios` from the repository root.
2. Install XcodeGen if needed (`brew install xcodegen`).
3. Run `xcodegen generate` in this directory.
4. Open `EdExample.xcodeproj` and run on an arm64 simulator or device.

The battery tool is read-only and runs automatically. The note tool is
mutating, so Ed pauses and asks the user before Swift executes it.
