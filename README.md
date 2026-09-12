# Interlude

A red terminal animation for the wait between jobs.

Run in an interactive PowerShell window:

```powershell
irm https://raw.githubusercontent.com/projectverticaluk/interlude/main/run.ps1 | iex
```

This downloads and runs the readable script in this repository. It draws the Maz repair character and streams the Star Wars ASCIIMATION from `towel.blinkenlights.nl:23`. It does not perform PC repairs, install software, require administrator access, or add anything to startup.

The Maz title stays visible while the movie connects, followed by the five-second invitation and the received film. The terminal requests at least 129 columns by 45 rows; enlarge it manually if the host blocks resizing. Outbound TCP port 23 must be available for the movie.

**Q / Escape / Ctrl+C** quits. **Space** pauses. **R** replays. Closing playback restores the console colours and cursor.

Requires Windows PowerShell 5.1 or PowerShell 7 in a terminal (not PowerShell ISE). For macOS, download the repository and double-click `Start.command`; PowerShell must already be installed.

Offline check or animation without the movie:

```powershell
.\run.ps1 -SelfTest
.\run.ps1 -NoMovie
```

`python3 Check-Terminal.py` checks both local launch methods in a simulated macOS terminal. The GitHub workflow checks the published script under Windows PowerShell 5.1 and PowerShell 7; it cannot verify physical window resizing.

Movie artwork: [Simon Jansen](https://www.asciimation.co.nz/). Telnet presentation: Sten Spans and Mike Edwards. Movie frames are received live, not included in this repository. Playback contains whatever the server supplies; this is not a claim that the adaptation covers the complete feature film.
