# Pracenje pogodaka: svaki dan zapise nase top 3 po opciji (cache\picks.json), a kad stigne rezultat provjeri da li je proslo.
# U data.json upise "track": pogoci zadnjih 30 dana, ukupno i po sportu.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$enc = New-Object System.Text.UTF8Encoding($false)
$dataFile = Join-Path $root 'data.json'
$picksFile = Join-Path $root 'cache\picks.json'
$resFile = Join-Path $root 'cache\results.json'
$data = Get-Content -Raw -Encoding UTF8 $dataFile | ConvertFrom-Json
$today = $data.today

$picks = New-Object System.Collections.ArrayList
if (Test-Path $picksFile) { foreach ($p in @(Get-Content -Raw -Encoding UTF8 $picksFile | ConvertFrom-Json)) { if ($p -and $p.date -ne $today) { [void]$picks.Add($p) } } }
$results = @{}
if (Test-Path $resFile) { (Get-Content -Raw -Encoding UTF8 $resFile | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $results[$_.Name] = $_.Value } }

# 1) danasnje top 3 po opciji (isto kao na stranici)
$lists = @{ football = @(($data.days | Where-Object { $_.date -eq $today }).matches) }
foreach ($p in $data.sports.PSObject.Properties) { $lists[$p.Name] = @(($p.Value.days | Where-Object { $_.date -eq $today }).matches) }
foreach ($sport in $lists.Keys) {
  $ms = @($lists[$sport] | Where-Object { $_ })
  if (-not $ms.Count) { continue }
  $markets = @($ms | ForEach-Object { $_.p.PSObject.Properties.Name } | Sort-Object -Unique)
  foreach ($mk in $markets) {
    $top = @($ms | Where-Object { $_.p.$mk -ne $null } | Sort-Object { - [int]$_.p.$mk } | Select-Object -First 3)
    foreach ($m in $top) {
      [void]$picks.Add([pscustomobject]@{ date = $today; sport = $sport; mk = $mk; key = "${sport}:$($m.id)"; home = $m.home; away = $m.away; p = [int]$m.p.$mk; hit = $null })
    }
  }
}

# 2) provjera rezultata
function Judge($sport, $mk, $r) {
  $h = [int]$r.h; $a = [int]$r.a; $t = $h + $a
  switch ("$sport|$mk") {
    { $_ -in 'football|gg', 'hockey|gg' } { return ($h -gt 0 -and $a -gt 0) }
    'football|o15' { return $t -ge 2 }  'football|o25' { return $t -ge 3 }  'football|o35' { return $t -ge 4 }  'football|u25' { return $t -le 2 }
    'football|hs' { return $h -gt 0 }   'football|as' { return $a -gt 0 }   'football|x' { return $h -eq $a }
    'football|c8' { if ($r.hc -eq $null) { return $null }; return ([int]$r.hc + [int]$r.ac) -ge 8 }
    'football|y3' { if ($r.hy -eq $null) { return $null }; return ([int]$r.hy + [int]$r.ay) -ge 3 }
    'basketball|o220' { return $t -ge 221 }  'basketball|u220' { return $t -le 220 }  'basketball|m10' { return [math]::Abs($h - $a) -ge 10 }
    'basketball|h110' { return $h -ge 110 }  'basketball|o160' { return $t -ge 161 }  'basketball|u160' { return $t -le 160 }  'basketball|h80' { return $h -ge 80 }
    'hockey|o55' { return $t -ge 6 }  'hockey|o45' { return $t -ge 5 }  'hockey|u55' { return $t -le 5 }
    'handball|o55' { return $t -ge 56 }  'handball|u55' { return $t -le 55 }
    'volleyball|s4' { return $t -ge 4 }  'volleyball|s5' { return $t -eq 5 }
    'nfl|o45' { return $t -ge 46 }  'nfl|u45' { return $t -le 45 }
    'mlb|o85' { return $t -ge 9 }  'mlb|u85' { return $t -le 8 }
  }
  if ($mk -eq 'w1') { return $h -gt $a }
  if ($mk -eq 'w2') { return $a -gt $h }
  return $null
}
$todayD = [datetime]::ParseExact($today, 'yyyy-MM-dd', $null)
foreach ($p in $picks) {
  if ($p.hit -ne $null -or $p.date -ge $today) { continue }
  $r = $results[$p.key]
  $v = if ($r) { Judge $p.sport $p.mk $r } else { $null }
  if ($v -ne $null) { $p.hit = [bool]$v }
  elseif (([datetime]::ParseExact($p.date, 'yyyy-MM-dd', $null)) -lt $todayD.AddDays(-10)) { $p.hit = 'void' }   # rezultat nikad nije stigao (odgodjeno i sl.)
}

# 3) cuvanje (zadnjih 60 dana) i statistika zadnjih 30 dana
$keep = @($picks | Where-Object { ([datetime]::ParseExact($_.date, 'yyyy-MM-dd', $null)) -ge $todayD.AddDays(-60) })
[IO.File]::WriteAllText($picksFile, (ConvertTo-Json @($keep) -Depth 3 -Compress), $enc)
$win = @($keep | Where-Object { $_.hit -is [bool] -and ([datetime]::ParseExact($_.date, 'yyyy-MM-dd', $null)) -ge $todayD.AddDays(-30) })
$bySport = [ordered]@{}
foreach ($g in ($win | Group-Object sport)) { $bySport[$g.Name] = [ordered]@{ n = $g.Count; hit = @($g.Group | Where-Object { $_.hit }).Count } }
$track = [ordered]@{ days = 30; n = $win.Count; hit = @($win | Where-Object { $_.hit }).Count; sports = $bySport }
$data | Add-Member -NotePropertyName track -NotePropertyValue $track -Force
[IO.File]::WriteAllText($dataFile, ($data | ConvertTo-Json -Depth 12), $enc)
Write-Host "Pracenje: danas zapisano $(@($keep | Where-Object { $_.date -eq $today }).Count) tipova; zadnjih 30 dana $($track.hit)/$($track.n)"
