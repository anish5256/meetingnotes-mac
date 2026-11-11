# MeetingNotes for Mac

## Share with a colleague (no setup needed)

Requires **Apple Silicon** and **macOS 14+** (14.2+ for recording calls). The app includes Python,
its transcription engine, ffmpeg and speaker models.

1. Unzip **MeetingNotes.zip** and drag **MeetingNotes.app** to **Applications**.
2. Try opening it, then allow the first launch via **System Settings ▸ Privacy & Security ▸ Open Anyway**.
   If needed, run this fallback in Terminal and open the app again:
   ```bash
   find /Applications/MeetingNotes.app -exec xattr -d -s com.apple.quarantine {} + 2>/dev/null
   ```
   (Removes the "downloaded from the internet" flag from every file in the app. `xattr -r` no longer
   exists on recent macOS, so use this form.)
3. Connect ChatGPT or Claude in **Settings ▸ Accounts**. For account sign-in, install the corresponding
   connection through Homebrew: `brew install --cask codex` or `brew install --cask claude-code`.
   Alternatively, enter a **Claude API key** in **Settings ▸ Advanced**, then select **Claude API key**
   in **Settings ▸ Models**; this needs nothing else installed.
4. Make your first recording. It downloads the **~3 GB speech model** once, so allow extra time and disk space.

To create the shareable zip from a developer checkout, run `bash scripts/package.sh`. It reads the pipeline
from `TRANSCRIBER_DIR` (default `~/voice-memo-transcriber`), which must contain `requirements-engine.txt`
and `scripts/download_models.sh`. Downloads are cached under `build/cache`. Use `SKIP_ENGINE=1` to reuse
an already prepared `build/engine`.

---

Record a meeting (or a call), and get a clean transcript and a summary in a few minutes. Works with
**Hindi, Hinglish and English**. Looks and feels like Apple's Voice Memos.

- **Record** from any microphone (built-in, AirPods, USB), with **pause/resume**
- **Calls too**: Google Meet, Zoom, Teams… are captured from your Mac's sound, even with AirPods
- **Transcribes while you talk**, so the notes are ready about a minute after you press Stop
- Knows **who spoke** (you are Speaker 1; others are Speaker 2, 3…)
- **ChatGPT or Claude** fixes misheard words and writes the summary (TL;DR, decisions, action items)
- **Google Calendar**: see your next meeting, record it in one click, notes are named after the meeting
- **Drop any audio file** (m4a, mp3, wav, ogg, …) to get notes for it

Transcription runs **on your Mac**. Only the text is sent to ChatGPT or Claude for the summary.

---

## What you need

| | |
|---|---|
| Mac | Apple Silicon (M1 or newer) |
| macOS | 14 Sonoma or newer (14.2+ for recording calls) |
| Disk | about 10 GB free |
| Account | ChatGPT **or** Claude (your normal subscription is enough) |

## Developer install (about 10 minutes, mostly downloads)

1. **Install Homebrew** if you don't have it: follow the one-line command on <https://brew.sh>.
2. **Install Apple's developer tools** (needed to build the app). Open **Terminal** and run:
   ```bash
   xcode-select --install
   ```
   Click **Install** in the window that appears. (If it says they're already installed, continue.)
3. **Download and install MeetingNotes.** In Terminal:
   ```bash
   git clone https://github.com/anish5256/meetingnotes-mac.git
   cd meetingnotes-mac
   bash install.sh
   ```
   The installer checks your Mac, installs what's missing (ffmpeg, Python), sets up the transcription engine
   ([voice-memo-transcriber](https://github.com/anish5256/voice-memo-transcriber)) in `~/voice-memo-transcriber`,
   builds the app into **~/Applications/MeetingNotes.app** and opens it.
4. **Install the AI connection you want to use** (one or both):
   ```bash
   brew install --cask codex         # ChatGPT
   brew install --cask claude-code   # Claude
   ```

## First launch (one-time)

1. Open **MeetingNotes** (from ~/Applications or Spotlight).
2. Open **Settings** (⌘,) ▸ **Accounts** ▸ **Connect ChatGPT** and/or **Connect Claude**. Your browser opens; sign in.
3. **Settings ▸ Models**: choose who **corrects the transcript** (recommended: ChatGPT or Claude; "Off" is fastest)
   and who **writes the summary**.
4. macOS will ask for permissions the first time you use each feature. Click **Allow**:

| When | Permission | Why |
|---|---|---|
| First recording | **Microphone** | to record you |
| First recording with "Include system audio (calls)" | **System Audio Recording** | to record the other people on a call |
| Click **Connect Calendar** (top of the sidebar) | **Calendars** | to show your next meeting |
| Turn on meeting reminders | **Notifications** | "Your meeting is starting. Record?" |

The **first** recording also downloads the speech model (~3 GB), so it takes a few extra minutes once.

### Google Calendar
MeetingNotes reads macOS Calendar. To see Google meetings: **System Settings ▸ Internet Accounts ▸ Add Account ▸
Google**, sign in and turn on **Calendars** (or click **Add Google Account…** in the app's calendar card).
The card shows your next meeting **with other attendees** within 12 hours.

## Everyday use

- **Record**: pick the microphone next to the red button, switch on **Include system audio (calls)** for online
  meetings, press the red button. Pause/resume any time. Press stop when done.
- **Record a calendar meeting**: click **Record** on the **Up next** card. The notes get the meeting's name and
  attendee names are spelled correctly.
- **Existing audio**: drag files onto the window, or click **+**.
- Each meeting shows a **Summary** and a **Transcript** tab and an audio player. Right-click a meeting to show it in
  Finder or move it to the Trash.

> Recording other people requires their consent. MeetingNotes never starts recording on its own.

## Where your files are

`~/Meetings/YYYY/MM/<date time> - <title>/` contains `summary.md`, the transcripts, the audio and `meta.json`.
`~/Meetings/INDEX.md` lists every meeting. **Settings ▸ General** changes the folder.

Optional: a personal glossary at `~/.voice-memo-glossary.txt` (names and terms the speech model mishears), for example
`- Rahul   (often heard as "Raul")`.

## Troubleshooting

| Problem | Fix |
|---|---|
| The window disappeared | Click MeetingNotes in the Dock, or Window ▸ MeetingNotes |
| "Connect ChatGPT/Claude first" | Settings ▸ Accounts ▸ Connect (install codex / claude-code first, see step 4) |
| No meetings in **Up next** | Click **Connect Calendar**; add Google in Internet Accounts; only meetings with attendees in the next 12 h show |
| Calls record only my voice | Turn on **Include system audio (calls)** before recording and allow System Audio Recording |
| A recording stopped half-way (crash, quit) | Just reopen the app: unfinished recordings are completed automatically |
| A job failed | Right-click it ▸ **Show Log** |
| "Microphone access was denied" | System Settings ▸ Privacy & Security ▸ Microphone ▸ enable MeetingNotes |

## Update

```bash
git -C ~/voice-memo-transcriber pull
cd meetingnotes-mac && git pull && bash install.sh
```

## Uninstall

```bash
rm -rf ~/Applications/MeetingNotes.app ~/voice-memo-transcriber
defaults delete com.anish.meetingnotes
```
Your meetings in `~/Meetings` are kept; delete that folder too if you want.

---

## For developers

- Build: `bash build_app.sh` → `build/MeetingNotes.app` · Tests: `swift test`
- The app prefers its built-in engine. To override it, enable **Settings ▸ General ▸ Use developer engine**
  and enter the **voice-memo-transcriber** path. Builds without an engine fall back to that checkout’s `venv`.
  `bash scripts/build_engine.sh` prepares the engine; `build_app.sh` embeds and signs it when present.
  The contract between the app and pipeline
  (session folders, segment files, CLI flags, JSON progress events) is in
  [voice-memo-transcriber/docs/meeting-app-plan.md](https://github.com/anish5256/voice-memo-transcriber/blob/main/docs/meeting-app-plan.md).
- App icon: `Resources/make_icon.swift` regenerates `Resources/AppIcon-source.png`.
