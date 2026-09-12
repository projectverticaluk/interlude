#requires -Version 5.1
<#
Red ASCII cinema with a cap-wearing repair technician.
Movie artwork: Simon Jansen, https://www.asciimation.co.nz/
Default movie source: towel.blinkenlights.nl:23, received directly.
This script only draws an animation.
#>
[CmdletBinding()]
param(
    [ValidateRange(15,60)][int]$Fps = 30,
    [ValidateRange(0,86400)][double]$Duration = 0,
    [ValidateRange(-1,86400)][double]$At = -1,
    [string]$MoviePath,
    [int]$Seed = (Get-Random -Minimum 1 -Maximum 1000000),
    [switch]$NoMovie,
    [switch]$SelfTest
)
$ErrorActionPreference = 'Stop'
$W = 128
$H = 44
$Movie = New-Object 'System.Collections.Generic.List[object]'
$MovieEnds = New-Object 'System.Collections.Generic.List[double]'
$Live = -not ($NoMovie -or $MoviePath -or $SelfTest -or $At -ge 0)
$script:LiveLoading = $Live
$script:wire = ''
$script:openingArrival = -1.0
$script:streamClosed = $false
$script:connectionError = ''
$font = @{
    'A' = @(' # ', '# #', '###', '# #', '# #')
    'M' = @('#   #', '## ##', '# # #', '#   #', '#   #')
    'Z' = @('###', '  #', ' # ', '#  ', '###')
    'I' = @('###', ' # ', ' # ', ' # ', '###')
    'S' = @('###', '#  ', '###', '  #', '###')
    'F' = @('###', '#  ', '## ', '#  ', '#  ')
    'X' = @('# #', '# #', ' # ', '# #', '# #')
    'N' = @('#   #', '##  #', '# # #', '#  ##', '#   #')
    'G' = @('###', '#  ', '# #', '# #', '###')
    'Y' = @('# #', '# #', ' # ', ' # ', ' # ')
    'O' = @('###', '# #', '# #', '# #', '###')
    'U' = @('# #', '# #', '# #', '# #', '###')
    'R' = @('## ', '# #', '## ', '# #', '# #')
    'H' = @('# #', '# #', '###', '# #', '# #')
    'T' = @('###', ' # ', ' # ', ' # ', ' # ')
    'E' = @('###', '#  ', '## ', '#  ', '###')
    'P' = @('## ', '# #', '## ', '#  ', '#  ')
    'D' = @('## ', '# #', '# #', '# #', '## ')
    'W' = @('#   #', '#   #', '# # #', '## ##', '#   #')
    '4' = @('# #', '# #', '###', '  #', '  #')
    ':' = @('   ', ' # ', '   ', ' # ', '   ')
    ')' = @('#  ', ' # ', ' # ', ' # ', '#  ')
    '!' = @(' # ', ' # ', ' # ', '   ', ' # ')
    ' ' = @('   ', '   ', '   ', '   ', '   ')
}

# ponytail: fixed 128x44 stage preserves the source's 67x13 movie frames.
$steps = @(
    @{ Name='repair'; N=3; From=@(0,21); To=@(0,21); Face=1; Label='Tightening the bottom-left corner.' }
    @{ Name='walk'; N=1; From=@(0,21); To=@(0,28); Face=1; Label='Checking the other side.' }
    @{ Name='walk'; N=5; From=@(0,28); To=@(106,28); Face=1; Label='Nothing to see here. Enjoy the film.' }
    @{ Name='walk'; N=1; From=@(106,28); To=@(106,21); Face=-1; Label='Coming through...' }
    @{ Name='repair'; N=3; From=@(106,21); To=@(106,21); Face=-1; Label='Bottom-right corner: could use a turn.' }
    @{ Name='walk'; N=3; From=@(106,21); To=@(106,1); Face=-1; Label='Climbing up to the top corner.' }
    @{ Name='repair'; N=3; From=@(106,1); To=@(106,1); Face=-1; Label='Top-right corner. Just a little adjustment.' }
    @{ Name='hide'; N=2; From=@(106,1); To=@(80,13); Face=-1; Label='Going behind the screen for a minute...' }
    @{ Name='hidden'; N=8; From=@(80,13); To=@(80,13); Face=-1; Label='Do not worry about the spare parts.' }
    @{ Name='hide'; N=3; From=@(80,13); To=@(0,13); Face=-1; Label='Back. Those parts were probably optional.' }
    @{ Name='walk'; N=2; From=@(0,13); To=@(0,1); Face=1; Label='One more corner.' }
    @{ Name='repair'; N=3; From=@(0,1); To=@(0,1); Face=1; Label='Top-left corner: nearly perfect.' }
    @{ Name='walk'; N=3; From=@(0,1); To=@(0,21); Face=1; Label='Another inspection lap.' }
)
$cycleLength = [double](($steps | ForEach-Object { $_.N } | Measure-Object -Sum).Sum)
$script:partCycle = -1
$script:parts = @()

function Read-Movie([string]$Path) {
    $file = Get-Item -LiteralPath $Path
    if ($file.Length -gt 10MB -or $file.PSIsContainer) { throw 'Movie must be a frame text file smaller than 10 MB.' }
    if ($file.Extension -eq '.json') {
        $frames = @(Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json)
        $previous = 0.0
        foreach ($frame in $frames) {
            if ($frame.Lines.Count -ne 13 -or [double]::IsNaN($frame.End) -or [double]::IsInfinity($frame.End) -or $frame.End -le $previous) { throw 'Invalid recorded frame timing or height.' }
            foreach ($line in $frame.Lines) {
                if ($line.Length -gt 67 -or $line -match '[^\x20-\x7e]') { throw 'Invalid recorded ASCII frame.' }
            }
            $previous = [double]$frame.End
            [PSCustomObject]@{Lines=[string[]]$frame.Lines; End=$previous}
        }
        return
    }
    $lines = [IO.File]::ReadAllLines($file.FullName)
    if ($lines.Count -eq 0 -or $lines.Count % 14 -ne 0) { throw 'Invalid movie: expected a duration line followed by 13 image lines per frame.' }
    $foundOpening = $false
    $total = 0.0
    for ($i = 0; $i -lt $lines.Count; $i += 14) {
        $hold = 0
        if (-not [int]::TryParse($lines[$i], [ref]$hold) -or $hold -lt 1 -or $hold -gt 15000) { throw "Invalid frame duration at line $($i + 1)." }
        $picture = [string[]]$lines[($i + 1)..($i + 13)]
        foreach ($line in $picture) {
            if ($line.Length -gt 67 -or $line -match '[^\x20-\x7e]') { throw "Invalid ASCII artwork at frame $($i / 14)." }
        }
        if (($picture -join ' ') -match 'A long time ago') { $foundOpening = $true }
        if ($foundOpening) {
            $total += $hold / 15.0
            [PSCustomObject]@{ Lines=$picture; End=$total }
        }
    }
    if (-not $foundOpening) { throw 'Film opening not found; refusing to play the preamble as the movie.' }
}

function Draw([int]$X, [int]$Y, [string[]]$Lines) {
    for ($r=0; $r -lt $Lines.Count; $r++) {
        if ($Y+$r -lt 0 -or $Y+$r -ge $H) { continue }
        $left = [Math]::Max(0,$X)
        $right = [Math]::Min($W,$X+$Lines[$r].Length)
        if ($right -le $left) { continue }
        $row = $script:canvas[$Y+$r]
        $script:canvas[$Y+$r] = $row.Substring(0,$left) + $Lines[$r].Substring($left-$X,$right-$left) + $row.Substring($right)
    }
}
function Box([int]$X, [int]$Y, [int]$Width, [int]$Height) {
    Draw $X $Y @('+' + ('-' * ($Width-2)) + '+')
    for ($r=1; $r -lt $Height-1; $r++) { Draw $X ($Y+$r) @('|' + (' ' * ($Width-2)) + '|') }
    Draw $X ($Y+$Height-1) @('+' + ('-' * ($Width-2)) + '+')
}
function Center([string]$Text, [int]$Y) {
    Draw ([int][Math]::Floor(($W-$Text.Length)/2)) $Y @($Text)
}
function BigText([string]$Text, [int]$Y) {
    for ($r=0; $r -lt 5; $r++) { Center (($Text.ToCharArray() | ForEach-Object { $font[[string]$_][$r] }) -join ' ') ($Y+$r) }
}

function Draw-Hero([int]$X, [int]$Y, [int]$Face, [bool]$Repair, [double]$Seconds) {
    $pose = [int][Math]::Floor($Seconds*5) % 2
    # Sampled from the user's original photo; keep its cap, face, hands, and short feet.
    $hero = @(
        '   ..=*%#@%#@#=.      ',
        '  -#@%#@%#@%#@%#-     ',
        ' *%%#@%#@%#@%#@%+.... ',
        '+%-%++#-#@%#@%#@%#@%#+',
        '%+==============*#    ',
        '%.              -#    ',
        '%.     #     #  -#    ',
        '%.     #     #  -#    ',
        '%-             .=#    ',
        '-#*++++++++++++#*:    ',
        ' **:#%#@%#@%#*-*=     ',
        ' #++%@%#@%#@%%+*#     ',
        '    @%#    #%@        '
    )
    if ($Seconds % 5 -gt 4.9) {
        $hero[6]='%.     -     -  -#    '
        $hero[7]='%.              -#    '
    }
    if (-not $Repair) {
        $soles=$hero[12].ToCharArray()
        switch ([int][Math]::Floor($Seconds*8) % 4) {
            0 { 11..13 | ForEach-Object { $soles[$_]=' ' } }
            2 { 4..6 | ForEach-Object { $soles[$_]=' ' } }
        }
        $hero[12]=-join $soles
    }
    if ($Face -eq -1) {
        $hero = @(foreach ($line in $hero) {
            $chars=$line.ToCharArray(); [Array]::Reverse($chars); -join $chars
        })
    }
    Draw $X $Y $hero
    if ($Face -eq 1) {
        if ($Repair -and $pose) { Draw ($X+17) ($Y+10) @('      __','-----<__') }
        else { Draw ($X+21) ($Y+8) @('\ /',' | ',' | '); Draw ($X+17) ($Y+11) @('-----+') }
    } else {
        if ($Repair -and $pose) { Draw ($X-3) ($Y+10) @('__','__>-----') }
        else { Draw ($X-3) ($Y+8) @('\ /',' | ',' | '); Draw ($X-2) ($Y+11) @('+------') }
    }
}

function Get-Parts([double]$Seconds) {
    $cycle = [int][Math]::Floor($Seconds/$cycleLength)
    if ($cycle -ne $script:partCycle) {
        $rng = New-Object System.Random ([int](($Seed + [long]$cycle) % [int]::MaxValue))
        $script:parts = @(for ($i=0; $i -lt 12; $i++) {
            $side = if ($rng.Next(2)) { 1 } else { -1 }
            [PSCustomObject]@{
                Start=21.0 + $rng.NextDouble()*6
                X=64 + $side*(14 + $rng.NextDouble()*8)
                Y=18 + $rng.NextDouble()*3
                VX=$side*(10 + $rng.NextDouble()*5)
                VY=-(23 + $rng.NextDouble()*4)
                Kind=$rng.Next(3)
            }
        })
        $script:partCycle = $cycle
    }
    $local = $Seconds % $cycleLength
    foreach ($part in $script:parts) {
        $age = $local - $part.Start
        if ($age -lt 0 -or $age -gt 3) { continue }
        [PSCustomObject]@{
            X=[int][Math]::Round($part.X + $part.VX*$age)
            Y=[int][Math]::Round($part.Y + $part.VY*$age + 10*$age*$age)
            Age=$age
            Kind=$part.Kind
        }
    }
}

function Get-MovieIndex([double]$Seconds) {
    if (-not $MovieEnds.Count -or $Seconds -lt 0 -or $Seconds -ge $MovieEnds[-1]) { return -1 }
    $index = $MovieEnds.BinarySearch($Seconds)
    if ($index -ge 0) { return ($index + 1) }
    return (-$index - 1)
}

function Get-Frame([double]$Seconds) {
    $script:canvas = @(for ($r=0; $r -lt $H; $r++) { ' ' * $W })
    $local = $Seconds % $cycleLength
    foreach ($step in $steps) { if ($local -lt $step.N) { break }; $local -= $step.N }
    $p = $local/$step.N
    $x = [int][Math]::Round($step.From[0] + ($step.To[0]-$step.From[0])*$p)
    $y = [int][Math]::Round($step.From[1] + ($step.To[1]-$step.From[1])*$p)
    $behind = $step.Name -in @('hide','hidden')

    Center 'M A Z  /  AFTER-HOURS CINEMA' 0
    Draw 59 32 @('|________|', '   |  |', ' __|__|__')
    Draw 39 36 @(' .------------------------------------------------.', ' /_[_][_][_][_][_][_][_][_][_][_][_][_][_][_][_][_]_\')
    Draw 0 41 @(('_' * $W))
    if ($behind -and $step.Name -ne 'hidden') { Draw-Hero $x $y $step.Face $false $Seconds }

    foreach ($part in @(Get-Parts $Seconds)) {
        $turn = [int][Math]::Floor($part.Age*7) % 2
        switch ($part.Kind) {
            0 { $art = if ($turn) { @(' \|/ ', '-(@)-', ' /|\ ') } else { @(' _|_ ', '-(O)-', '  |  ') } }
            1 { $art = if ($turn) { @(' /RAM/', '/###/', 'vvvv') } else { @('[RAM==]', 'vvvvvvv') } }
            2 { $art = if ($turn) { @('  /\', ' /CPU\', ' \##/', '  \/') } else { @('|||||', '[CPU]', '|||||') } }
        }
        Draw $part.X $part.Y $art
    }

    # The monitor is drawn over the technician and parts while they are behind it.
    Box 24 11 80 21
    Draw 27 11 @('[ MAZ OS / CINEMA ]')
    Draw 95 31 @('[o]')
    if (-not $script:LiveLoading -and $script:connectionError -and -not $Movie.Count) {
        Center 'COULD NOT RECEIVE THE MOVIE' 16
        Center $script:connectionError 20
        Center 'Q to quit; run again to reconnect.' 23
    } elseif ($script:LiveLoading -or $Seconds -lt 2) {
        BigText 'MAZ IS' 13
        BigText 'FIXING YOUR' 19
        BigText 'SHIT :)' 25
    } elseif ($Seconds -lt 7) {
        Center 'Meanwhile, sit back and watch the entirety of' 14
        BigText 'STAR WARS' 17
        BigText 'EPISODE 4!' 24
    } else {
        $index = Get-MovieIndex ($Seconds-7)
        if ($index -ge 0) { Draw 30 15 $Movie[$index].Lines }
        elseif ($Movie.Count) {
            Center 'END OF THE RECEIVED ANIMATION' 17
            Center $(if ($script:connectionError) { $script:connectionError } else { 'The available stream has ended.' }) 20
            Center 'R to replay / Q to quit' 23
        } else {
            Center 'MOVIE PREVIEW DISABLED' 17
            Center 'Run without -NoMovie to play the ASCIIMATION.' 20
        }
    }
    if (-not $behind) { Draw-Hero $x $y $step.Face ($step.Name -eq 'repair') $Seconds }
    Draw 2 42 @($step.Label)
    Draw 83 42 @('SPACE pause / R replay / Q quit')
    if ($script:LiveLoading -or $Seconds -lt 2) { Draw 2 43 @('Maz is fixing your shit :)') }
    elseif ($Seconds -lt 7) { Draw 2 43 @('Meanwhile, sit back and watch the entirety of Star Wars Episode 4!') }
    else { Draw 2 43 @('Maz is fixing your shit :)') }
    return ($script:canvas -join "`n")
}

function Convert-TowelChunk([string]$Data) {
    $frameMarker = [string][char]27 + '[H'
    $script:wire = ($script:wire + $Data).Replace(([string][char]27 + '[J'),'')
    while ($true) {
        $start = $script:wire.IndexOf($frameMarker,[StringComparison]::Ordinal)
        if ($start -lt 0) { break }
        $script:wire = $script:wire.Substring($start)
        if ($script:wire.StartsWith($frameMarker+$frameMarker)) { $script:wire=$script:wire.Substring(3); continue }
        if ($script:wire.Length -lt 988) { break }
        # Observed towel pages: six empty rows, then 13 rows of six spaces + 67 ASCII columns.
        $rows = $script:wire.Substring(3,985) -split "`r`n"
        if ($rows.Count -ne 19 -or ($rows[0..5] -join '') -ne '') { throw 'Unexpected towel frame layout.' }
        $picture = @(foreach ($row in $rows[6..18]) {
            if ($row.Length -ne 73 -or -not $row.StartsWith('      ') -or $row -match '[^\x20-\x7e]') { throw 'Unexpected towel frame data.' }
            $row.Substring(6,67)
        })
        [PSCustomObject]@{Lines=[string[]]$picture}
        $script:wire=$script:wire.Substring(988)
    }
    if ($script:wire.Length -gt 4096) { throw 'Unrecognised towel stream.' }
}

function Receive-Towel {
    if ($script:streamClosed) { return }
    try {
        if (-not $script:network) {
            if (-not $connect.IsCompleted) {
                if ($receiveClock.Elapsed.TotalSeconds -gt 12) { throw 'Connection timed out.' }
                return
            }
            $client.EndConnect($connect)
            $script:network=$client.GetStream()
        }
        while ($client.Available -gt 0) {
            $count=$script:network.Read($buffer,0,[Math]::Min($buffer.Length,$client.Available))
            $arrival=$receiveClock.Elapsed.TotalSeconds
            $script:lastData=$arrival
            foreach ($packet in @(Convert-TowelChunk ([Text.Encoding]::ASCII.GetString($buffer,0,$count)))) {
                if ($script:openingArrival -lt 0) {
                    if (($packet.Lines -join ' ') -notmatch 'A long time ago') { continue }
                    $script:openingArrival=$arrival
                    $script:LiveLoading=$false
                    $clock.Reset()
                }
                $start=$arrival-$script:openingArrival
                if ($Movie.Count) {
                    # Preserve ordering if the network delivers several frames in one read.
                    $previousStart=if ($Movie.Count -gt 1) { $MovieEnds[$Movie.Count-2] } else { 0.0 }
                    $start=[Math]::Max($start,$previousStart+0.001)
                    $Movie[$Movie.Count-1].End=$start
                    $MovieEnds[$Movie.Count-1]=$start
                }
                $Movie.Add([PSCustomObject]@{Lines=$packet.Lines; End=[double]::PositiveInfinity})
                $MovieEnds.Add([double]::PositiveInfinity)
            }
        }
        if ($client.Client.Poll(0,[Net.Sockets.SelectMode]::SelectRead) -and $client.Available -eq 0) {
            $script:streamClosed=$true
        } elseif ($receiveClock.Elapsed.TotalSeconds-$script:lastData -gt 45) { throw 'Server stopped sending data.' }
    } catch {
        $script:connectionError='Connection interrupted. Received frames remain playable.'
        $script:streamClosed=$true
    }
    if ($script:streamClosed) {
        $script:LiveLoading=$false
        if ($Movie.Count) {
            $end=$receiveClock.Elapsed.TotalSeconds-$script:openingArrival
            if ($Movie.Count -gt 1) { $end=[Math]::Max($end,$MovieEnds[$Movie.Count-2]+0.001) }
            $Movie[$Movie.Count-1].End=$end
            $MovieEnds[$Movie.Count-1]=$end
        } else { $script:connectionError='Towel is unavailable, or its stream format has changed.' }
        $client.Close()
    }
}

if ($MoviePath -and -not $NoMovie) {
    foreach ($frame in @(Read-Movie $MoviePath)) { $Movie.Add($frame); $MovieEnds.Add($frame.End) }
}

if ($SelfTest) {
    $title = (Get-Frame 0) -split "`n"
    $script:LiveLoading = $true
    foreach ($time in @(0,3,30,60)) {
        $loading = (Get-Frame $time) -split "`n"
        for ($r=13; $r -le 29; $r++) {
            if ($loading[$r].Substring(25,78) -cne $title[$r].Substring(25,78)) { throw 'Loading screen lost the Maz title.' }
        }
        if (($loading -join '') -match '(?i)towel|buffering|connecting|preparing the live') { throw 'Connection status leaked onto the title screen.' }
    }
    $script:LiveLoading = $false
    foreach ($time in @(0,1.999,2,6.999,7,28,35,39.999,40,79.9)) {
        $rows = (Get-Frame $time) -split "`n"
        if ($rows.Count -ne $H -or @($rows | Where-Object { $_.Length -ne $W }).Count) { throw "Frame bounds: $time" }
        if (($rows -join '') -match '[^\x20-\x7e]') { throw 'Unexpected terminal glyph' }
    }
    if ((Get-Frame 1.999) -notmatch 'Maz is fixing your shit' -or (Get-Frame 2) -notmatch 'Meanwhile, sit back') { throw 'Two-second title boundary failed' }
    if ((Get-Frame 6.999) -notmatch 'Meanwhile, sit back' -or (Get-Frame 7) -match 'Meanwhile, sit back') { throw 'Five-second invitation boundary failed' }
    for ($time=7; $time -lt 47; $time+=0.2) {
        $rows = (Get-Frame $time) -split "`n"
        $index = Get-MovieIndex ($time-7)
        if ($index -ge 0) {
            for ($r=0; $r -lt 13; $r++) {
                if ($rows[15+$r].Substring(30,67) -cne $Movie[$index].Lines[$r].PadRight(67)) { throw "Movie obscured: $time" }
            }
        }
    }
    [void](Get-Parts 24)
    $first = $script:parts[0]
    $positions = @(0,0.5,1 | ForEach-Object { $first.Y + $first.VY*$_ + 10*$_*$_ })
    if ([Math]::Abs(($positions[2]-2*$positions[1]+$positions[0])-5) -gt 0.0001) { throw 'Parts no longer follow a curved path' }
    $rows = (Get-Frame 24) -split "`n"
    if (($rows -join '') -match '%.     #     #  -#') { throw 'Hidden character is visible' }
    if ((Get-Frame 0) -notmatch '%.     #     #  -#') { throw 'Photo-derived face and eyes missing' }
    [void](Get-Frame 0)
    Draw-Hero 0 21 1 $false 0
    $rightLifted=$script:canvas[33].Substring(4,10)
    Draw-Hero 0 21 1 $false 0.25
    $leftLifted=$script:canvas[33].Substring(4,10)
    if ($rightLifted -cne '@%#       ' -or $leftLifted -cne '       #%@') { throw 'Feet are not lifting and planting alternately.' }
    if ($Movie.Count) {
        if (($Movie[0].Lines -join ' ') -notmatch 'A long time ago') { throw 'Opening credits were not skipped' }
        if ((Get-MovieIndex 0) -ne 0 -or (Get-MovieIndex $MovieEnds[0]) -ne 1 -or (Get-MovieIndex $MovieEnds[-1]) -ne -1) { throw 'Movie timeline boundary failed' }
    }
    $testRows=@(for ($r=0; $r -lt 13; $r++) { ('TEST FRAME ' + $r).PadRight(67) })
    $packet=([string][char]27+'[H') + ("`r`n"*6) + (($testRows | ForEach-Object { '      '+$_ }) -join "`r`n")
    $script:wire=''
    $decoded=@(for ($i=0; $i -lt $packet.Length; $i+=7) { Convert-TowelChunk $packet.Substring($i,[Math]::Min(7,$packet.Length-$i)) })
    if ($decoded.Count -ne 1 -or ($decoded[0].Lines -join "`n") -cne ($testRows -join "`n")) { throw 'Fragmented network frame was changed or lost.' }
    Write-Output "PASS: loading title, intro timing, bounds, unobscured movie, simple eyes, alternating foot lifts, hidden repair, curved parts, playback boundaries. Movie frames: $($Movie.Count)."
    return
}
if ($At -ge 0) { Get-Frame $At; return }
if ([Console]::IsOutputRedirected -or [Console]::IsInputRedirected) { throw 'Use an interactive terminal, or -At 30 to export a frame.' }

# Shared by direct PowerShell runs and the .command launcher. Only enlarge.
$targetWidth = [Math]::Max($W+1, [Console]::WindowWidth)
$targetHeight = [Math]::Max($H+1, [Console]::WindowHeight)
if ([Console]::WindowWidth -lt $targetWidth -or [Console]::WindowHeight -lt $targetHeight) {
    if ($env:OS -eq 'Windows_NT') {
        try {
            [Console]::SetBufferSize([Math]::Max($targetWidth,[Console]::BufferWidth), [Math]::Max($targetHeight,[Console]::BufferHeight))
            [Console]::SetWindowSize($targetWidth,$targetHeight)
        } catch { } # Hosts that reject native resizing can still support the escape below.
    }
    if ([Console]::WindowWidth -lt $targetWidth -or [Console]::WindowHeight -lt $targetHeight) {
        [Console]::Write(([string][char]27 + "[8;$targetHeight;${targetWidth}t"))
        # Give the terminal time to apply the request before checking dimensions.
        for ($attempt=0; $attempt -lt 10; $attempt++) {
            if ([Console]::WindowWidth -ge $targetWidth -and [Console]::WindowHeight -ge $targetHeight) { break }
            Start-Sleep -Milliseconds 50
        }
    }
}

$oldColor = [Console]::ForegroundColor
$oldBackground = [Console]::BackgroundColor
$oldCursor = $true
try { $oldCursor = [Console]::CursorVisible } catch { }
$lastSize = ''
$paused = $false
$clock = New-Object Diagnostics.Stopwatch
$client=$null
$script:network=$null
$script:lastData=0.0
try {
    [Console]::ForegroundColor = [ConsoleColor]::Red
    [Console]::BackgroundColor = [ConsoleColor]::Black
    [Console]::CursorVisible = $false
    if ($Live) {
        $client=New-Object Net.Sockets.TcpClient
        $connect=$client.BeginConnect('towel.blinkenlights.nl',23,$null,$null)
        $receiveClock=[Diagnostics.Stopwatch]::StartNew()
        $buffer=New-Object byte[] 16384
    }
    while ($Duration -eq 0 -or $clock.Elapsed.TotalSeconds -lt $Duration) {
        if ($Live) { Receive-Towel }
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true).Key
            if ($key -in @([ConsoleKey]::Q,[ConsoleKey]::Escape)) { break }
            if ($key -eq [ConsoleKey]::Spacebar) { $paused = -not $paused }
            if ($key -eq [ConsoleKey]::R) { $clock.Reset(); $script:partCycle=-1 }
        }
        $width = [Console]::WindowWidth
        $height = [Console]::WindowHeight
        $size = "$width,$height"
        if ($size -ne $lastSize) { [Console]::Clear(); $lastSize=$size }
        if ($width -le $W -or $height -le $H) {
            $clock.Stop()
            [Console]::SetCursorPosition(0,0)
            $notice = 'Enlarge terminal to 129 x 45 (or zoom out). Q to quit.'
            [Console]::Write($notice.Substring(0,[Math]::Min($notice.Length,[Math]::Max(0,$width-1))))
            Start-Sleep -Milliseconds 100
            continue
        }
        if ($paused -or $script:LiveLoading) { $clock.Stop() }
        $renderWatch = [Diagnostics.Stopwatch]::StartNew()
        $seconds=if ($script:LiveLoading) { $receiveClock.Elapsed.TotalSeconds } else { $clock.Elapsed.TotalSeconds }
        $render = (Get-Frame $seconds).Replace("`n","`r`n")
        [Console]::SetCursorPosition(0,0)
        [Console]::Write($render)
        if (-not $paused -and -not $script:LiveLoading) { $clock.Start() }
        Start-Sleep -Milliseconds ([int][Math]::Max(1,1000/$Fps-$renderWatch.ElapsedMilliseconds))
    }
} finally {
    if ($client) { $client.Dispose() }
    [Console]::ForegroundColor = $oldColor
    [Console]::BackgroundColor = $oldBackground
    [Console]::CursorVisible = $oldCursor
    [Console]::Clear()
}
