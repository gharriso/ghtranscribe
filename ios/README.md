# GHTranscribe (iOS)

An iOS app that transcribes and summarizes an audio file picked from the
Files app (e.g. a recording from Just Press Record's iCloud folder), with
no dependency on a desktop. Companion to the `ghtranscribe.py` desktop
script in the parent directory.

## Pipeline

1. Pick an audio file via the standard Files picker.
2. If it's an iCloud placeholder, wait for it to download.
3. Upload it to OpenAI's `gpt-4o-transcribe` for a transcript.
4. Send the transcript to `gpt-4o-mini`, which returns a summary as HTML
   (main topics/decisions, plus an "Observations" section).
5. Show the summary in-app; share it via the standard share sheet (e.g. to
   Apple Notes, which preserves the rich formatting).

Speaker diarization is intentionally not included -- OpenAI's transcription
API doesn't support it. Would need a second vendor (AssemblyAI/Deepgram) if
that becomes a requirement.

## Setup

Requires Xcode and [xcodegen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```
cd ios
xcodegen generate
open GHTranscribe.xcodeproj
```

Build and run on a simulator or device. On first launch, open Settings
(gear icon) and paste in an OpenAI API key -- it's stored in the Keychain
and used only for direct calls to `api.openai.com`.

The generated `.xcodeproj` is gitignored -- it's fully reproducible from
`project.yml`, so just re-run `xcodegen generate` after pulling changes.

### Running on a physical device

Simulator builds need no signing. For a real device, copy
`Local.xcconfig.example` to `Local.xcconfig` (gitignored) and set
`DEVELOPMENT_TEAM` to your Apple Developer team ID, then regenerate:

```
cp Local.xcconfig.example Local.xcconfig
# edit Local.xcconfig with your team ID
xcodegen generate
```

## Notes

- No microphone permission is needed -- the app only reads files you pick,
  it doesn't record.
- If building from the command line rather than Xcode's UI, make sure your
  shell's `PATH`/env vars don't have a conda (or similar) toolchain's `CC`,
  `LD`, `SDKROOT`, etc. exported -- those override Xcode's linker and break
  the build with cryptic `ld: unknown option` errors.
