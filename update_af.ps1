# Fudbal preko API-Football (Pro plan): sve lige, statistika zadnjih 10 utakmica, korneri/kartoni i kvote (Bet365).
# Pise af.json (samo danasnje utakmice) i rezultate za pracenje pogodaka. Poziva se iz update.ps1.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$key = (Get-Content -Raw -Encoding UTF8 (Join-Path $root 'config.json') | ConvertFrom-Json).apiSportsKey
$tz = [System.TimeZoneInfo]::FindSystemTimeZoneById('Central European Standard Time')
$todayD = [System.TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $tz).Date
$today = $todayD.ToString('yyyy-MM-dd')
$enc = New-Object System.Text.UTF8Encoding($false)
$cacheDir = Join-Path $root 'cache'
. (Join-Path $root 'results_lib.ps1')

Add-Type -AssemblyName System.Net.Http
$client = New-Object System.Net.Http.HttpClient
$client.DefaultRequestHeaders.Add('x-apisports-key', $key)
$client.Timeout = [TimeSpan]::FromSeconds(60)
$script:calls = 0
# vise zahtjeva odjednom (10), ali ispod limita od 300/min
function Get-Many([string[]]$paths) {
  $out = @{}; $paths = @($paths | Select-Object -Unique)
  for ($i = 0; $i -lt $paths.Count; $i += 10) {
    $batch = $paths[$i..([math]::Min($i + 9, $paths.Count - 1))]
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $tasks = @{}; foreach ($p in $batch) { $tasks[$p] = $client.GetStringAsync("https://v3.football.api-sports.io/$p") }
    foreach ($p in $batch) {
      $script:calls++
      try { $out[$p] = $tasks[$p].Result | ConvertFrom-Json }
      catch { try { Start-Sleep -Seconds 2; $out[$p] = $client.GetStringAsync("https://v3.football.api-sports.io/$p").Result | ConvertFrom-Json; $script:calls++ } catch { Write-Host "  greska: $p" } }
    }
    $wait = 2300 - $sw.ElapsedMilliseconds; if ($wait -gt 0) { Start-Sleep -Milliseconds $wait }
  }
  return $out
}
function Get-One($path) { (Get-Many @($path))[$path] }
$FIN = @('FT','AET','PEN')
function Compact($f) {
  $hg = $f.score.fulltime.home; $ag = $f.score.fulltime.away
  if ($hg -eq $null) { $hg = $f.goals.home; $ag = $f.goals.away }
  [pscustomobject]@{ id = [string]$f.fixture.id; d = $f.fixture.date; hid = [string]$f.teams.home.id; aid = [string]$f.teams.away.id; hg = [int]$hg; ag = [int]$ag }
}

# ---------- 1) danasnje utakmice ----------
$fx = Get-One "fixtures?date=$today&timezone=Europe/Sarajevo"
$skip = 'Women|Femen|Femin|Frauen|Feminine|Damallsvenskan|Friendl|U1[5-9]|U2[0-3]|Youth|Junior|Reserve|Primavera|Premier League 2|Professional Development|Amateur|Regionalliga|Oberliga'
$teamSkip = '\sII$|\sIII$|\sB$|\sU\d\d$|\sReserves?$|\s2$'
$games = @($fx.response | Where-Object { $_.fixture.status.short -in 'NS','TBD' -and $_.league.name -notmatch $skip -and $_.teams.home.name -notmatch $teamSkip -and $_.teams.away.name -notmatch $teamSkip })
Write-Host "API-Football: $(@($fx.response).Count) utakmica danas, $($games.Count) u obzir"

# ---------- 2) istorija: liga-sezona (1 poziv po ligi), pa po timu gdje fali ----------
$lp = @($games | ForEach-Object { "fixtures?league=$($_.league.id)&season=$($_.league.season)&status=FT-AET-PEN" } | Select-Object -Unique)
$lres = Get-Many $lp
$hist = @{}   # team -> list of compact finished fixtures
$seen = @{}
function Add-Hist($f) {
  if ($seen.ContainsKey($f.id)) { return }; $seen[$f.id] = 1
  foreach ($t in $f.hid, $f.aid) { if (-not $hist.ContainsKey($t)) { $hist[$t] = New-Object System.Collections.ArrayList }; [void]$hist[$t].Add($f) }
}
foreach ($r in $lres.Values) { foreach ($f in $r.response) { if ($f.fixture.status.short -in $FIN) { Add-Hist (Compact $f) } } }
$teams = @($games | ForEach-Object { [string]$_.teams.home.id; [string]$_.teams.away.id } | Select-Object -Unique)
$need = @($teams | Where-Object { -not $hist.ContainsKey($_) -or $hist[$_].Count -lt 10 })
$tres = Get-Many @($need | ForEach-Object { "fixtures?team=$_&last=10" })
foreach ($r in $tres.Values) { foreach ($f in $r.response) { if ($f.fixture.status.short -in $FIN) { Add-Hist (Compact $f) } } }
$last = @{}
foreach ($t in $teams) { if ($hist.ContainsKey($t)) { $last[$t] = @($hist[$t] | Sort-Object { [datetime]$_.d } -Descending | Select-Object -First 10) } }

# ---------- 3) korneri/kartoni po utakmici (kes zauvijek, 20 utakmica po pozivu) ----------
$fxFile = Join-Path $cacheDir 'af_fx.json'
$fxStats = @{}
if (Test-Path $fxFile) { (Get-Content -Raw -Encoding UTF8 $fxFile | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $fxStats[$_.Name] = $_.Value } }
function StatOf($f, $teamId, $type) { $s = @($f.statistics | Where-Object { [string]$_.team.id -eq $teamId })[0]; if (-not $s) { return $null }; $v = @($s.statistics | Where-Object { $_.type -eq $type })[0].value; if ($v -eq $null) { return $null }; return [int]$v }
function Save-FxStats($resp) {
  $res = @{}
  foreach ($f in $resp) {
    $id = [string]$f.fixture.id; $h = [string]$f.teams.home.id; $a = [string]$f.teams.away.id
    $e = [ordered]@{ n = 0 }
    if (@($f.statistics).Count -ge 2) {
      $hc = StatOf $f $h 'Corner Kicks'; $ac = StatOf $f $a 'Corner Kicks'; $hy = StatOf $f $h 'Yellow Cards'; $ay = StatOf $f $a 'Yellow Cards'
      # nula kornera ukupno = liga ne salje statistiku, ne stvarna nula
      if ($hc -ne $null -and $ac -ne $null -and ($hc + $ac) -gt 0) { $e = [ordered]@{ hc = $hc; ac = $ac; hy = [int]$hy; ay = [int]$ay } }
    }
    $fxStats[$id] = [pscustomobject]$e
    if ($f.fixture.status.short -in $FIN) {
      $c = Compact $f; $r = [ordered]@{ h = $c.hg; a = $c.ag }
      if ($e.Contains('hc')) { $r.hc = $e.hc; $r.ac = $e.ac; $r.hy = $e.hy; $r.ay = $e.ay }
      $res["football:af$id"] = $r
    }
  }
  if ($res.Count) { Save-Results $root $res }
}
$ids = @($last.Values | ForEach-Object { $_ } | ForEach-Object { $_.id } | Select-Object -Unique | Where-Object { -not $fxStats.ContainsKey($_) })
# + jucerasnji i stariji nasi tipovi koji jos cekaju rezultat
$pf = Join-Path $cacheDir 'picks.json'
if (Test-Path $pf) { $ids += @(Get-Content -Raw -Encoding UTF8 $pf | ConvertFrom-Json | Where-Object { $_.hit -eq $null -and $_.date -lt $today -and $_.key -like 'football:af*' } | ForEach-Object { $_.key.Substring(11) }) }
$ids = @($ids | Select-Object -Unique)
$idPaths = @(); for ($i = 0; $i -lt $ids.Count; $i += 20) { $idPaths += 'fixtures?ids=' + (($ids[$i..([math]::Min($i + 19, $ids.Count - 1))]) -join '-') }
$sres = Get-Many $idPaths
foreach ($r in $sres.Values) { Save-FxStats $r.response }
[IO.File]::WriteAllText($fxFile, ($fxStats | ConvertTo-Json -Depth 3 -Compress), $enc)

# ---------- 4) kvote (Bet365), stranica po stranica ----------
$odds = @{}
$o1 = Get-One "odds?date=$today&bookmaker=8&timezone=Europe/Sarajevo&page=1"
$oPages = @($o1)
if ($o1 -and $o1.paging.total -gt 1) { $more = Get-Many @(2..$o1.paging.total | ForEach-Object { "odds?date=$today&bookmaker=8&timezone=Europe/Sarajevo&page=$_" }); $oPages += @($more.Values) }
function OddOf($bets, $betId, $val) { $b = @($bets | Where-Object { $_.id -eq $betId })[0]; if (-not $b) { return $null }; $v = @($b.values | Where-Object { [string]$_.value -eq $val })[0]; if ($v) { [math]::Round([double]$v.odd, 2) } }
foreach ($pg in $oPages) {
  foreach ($r in $pg.response) {
    $bets = $r.bookmakers[0].bets; if (-not $bets) { continue }
    $o = [ordered]@{}
    $map = @(@('w1',1,'Home'), @('x',1,'Draw'), @('w2',1,'Away'), @('o15',5,'Over 1.5'), @('o25',5,'Over 2.5'), @('u25',5,'Under 2.5'),
      @('gg',8,'Yes'), @('hs',28,'No'), @('as',27,'No'), @('c8',45,'Over 7.5'), @('y3',80,'Over 2.5'))
    foreach ($m in $map) { $v = OddOf $bets $m[1] $m[2]; if ($v) { $o[$m[0]] = $v } }
    if ($o.Count) { $odds[[string]$r.fixture.id] = $o }
  }
}

# ---------- 5) procenti (isti model kao ranije) ----------
function Get-Stats($t) {
  $g = $last[$t]; if (-not $g -or $g.Count -lt 8) { return $null }
  $rows = @($g | ForEach-Object { $h = $_.hid -eq $t; $gf = if ($h) { $_.hg } else { $_.ag }; $ga = if ($h) { $_.ag } else { $_.hg }
    [pscustomobject]@{ gf = $gf; ga = $ga; res = $(if ($gf -gt $ga) { 'P' } elseif ($gf -eq $ga) { 'N' } else { 'I' }) } })
  $n = $rows.Count
  [pscustomobject]@{ n = $n; gf = [math]::Round((($rows | Measure-Object gf -Sum).Sum / $n), 2); ga = [math]::Round((($rows | Measure-Object ga -Sum).Sum / $n), 2)
    scored = @($rows | Where-Object { $_.gf -gt 0 }).Count; conceded = @($rows | Where-Object { $_.ga -gt 0 }).Count
    btts = @($rows | Where-Object { $_.gf -gt 0 -and $_.ga -gt 0 }).Count; o15 = @($rows | Where-Object { ($_.gf + $_.ga) -ge 2 }).Count
    o25 = @($rows | Where-Object { ($_.gf + $_.ga) -ge 3 }).Count; o35 = @($rows | Where-Object { ($_.gf + $_.ga) -ge 4 }).Count
    form = (($rows | Select-Object -First 5 | ForEach-Object { $_.res }) -join '') }
}
function Get-CStats($t) {
  $rows = @($last[$t] | ForEach-Object { $s = $fxStats[$_.id]; if ($s -and $s.hc -ne $null -and ([int]$s.hc + [int]$s.ac) -gt 0) { $h = $_.hid -eq $t
    [pscustomobject]@{ cf = $(if ($h) { $s.hc } else { $s.ac }); ca = $(if ($h) { $s.ac } else { $s.hc }); ct = $s.hc + $s.ac; yt = $s.hy + $s.ay } } })
  if ($rows.Count -lt 6) { return $null }
  $n = $rows.Count
  [pscustomobject]@{ n = $n; cf = [math]::Round((($rows | Measure-Object cf -Sum).Sum / $n), 1); ca = [math]::Round((($rows | Measure-Object ca -Sum).Sum / $n), 1)
    ct = [math]::Round((($rows | Measure-Object ct -Sum).Sum / $n), 1); c8 = @($rows | Where-Object { $_.ct -ge 8 }).Count
    yt = [math]::Round((($rows | Measure-Object yt -Sum).Sum / $n), 1); y3 = @($rows | Where-Object { $_.yt -ge 3 }).Count }
}
function PoissonP($l, $k) { $f = 1.0; for ($i = 2; $i -le $k; $i++) { $f *= $i }; [math]::Exp(-$l) * [math]::Pow($l, $k) / $f }
function PoissonOver($l, $line) { $b = 0.0; for ($k = 0; $k -le [math]::Floor($line); $k++) { $b += PoissonP $l $k }; 1 - $b }
function Pct([double]$x) { [int][math]::Round([math]::Max([double]0.0, [math]::Min([double]1.0, $x)) * 100) }

$list = New-Object System.Collections.ArrayList
foreach ($g in $games) {
  $ht = [string]$g.teams.home.id; $at = [string]$g.teams.away.id
  $hs = Get-Stats $ht; $as = Get-Stats $at; if (-not $hs -or -not $as) { continue }
  $lh = [math]::Max(0.2, (($hs.gf + $as.ga) / 2) * 1.08); $la = [math]::Max(0.2, (($as.gf + $hs.ga) / 2) * 0.94)
  $pH = 0.5 * (1 - [math]::Exp(-$lh)) + 0.5 * ((($hs.scored / $hs.n) + ($as.conceded / $as.n)) / 2)
  $pA = 0.5 * (1 - [math]::Exp(-$la)) + 0.5 * ((($as.scored / $as.n) + ($hs.conceded / $hs.n)) / 2)
  $bt = (($hs.btts / $hs.n) + ($as.btts / $as.n)) / 2; $tot = $lh + $la
  $o15 = 0.5 * (PoissonOver $tot 1.5) + 0.5 * ((($hs.o15 / $hs.n) + ($as.o15 / $as.n)) / 2)
  $o25 = 0.5 * (PoissonOver $tot 2.5) + 0.5 * ((($hs.o25 / $hs.n) + ($as.o25 / $as.n)) / 2)
  $w1 = 0.0; $dr = 0.0; $w2 = 0.0
  for ($i = 0; $i -le 8; $i++) { for ($j = 0; $j -le 8; $j++) { $p = (PoissonP $lh $i) * (PoissonP $la $j); if ($i -gt $j) { $w1 += $p } elseif ($i -eq $j) { $dr += $p } else { $w2 += $p } } }
  $s = $w1 + $dr + $w2
  $hc = Get-CStats $ht; $ac = Get-CStats $at; $pc8 = $null; $py3 = $null
  if ($hc -and $ac) {
    $lc = ($hc.cf + $ac.ca) / 2 + ($ac.cf + $hc.ca) / 2
    $pc8 = Pct (0.5 * (PoissonOver $lc 7.5) + 0.5 * ((($hc.c8 / $hc.n) + ($ac.c8 / $ac.n)) / 2))
    $py3 = Pct (0.5 * (PoissonOver (($hc.yt + $ac.yt) / 2) 2.5) + 0.5 * ((($hc.y3 / $hc.n) + ($ac.y3 / $ac.n)) / 2))
  }
  $utc = [datetime]::Parse($g.fixture.date, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
  $local = [System.TimeZoneInfo]::ConvertTimeFromUtc($utc, $tz)
  $m = [ordered]@{ id = "af$($g.fixture.id)"; league = "$($g.league.name) ($($g.league.country))"; time = $local.ToString('HH:mm')
    home = $g.teams.home.name; away = $g.teams.away.name; hl = $g.teams.home.logo; al = $g.teams.away.logo
    xg = @([math]::Round($lh, 2), [math]::Round($la, 2))
    p = [ordered]@{ gg = Pct (0.5 * $pH * $pA + 0.5 * $bt); o15 = Pct $o15; o25 = Pct $o25; u25 = Pct (1 - $o25); hs = Pct $pH; as = Pct $pA
      w1 = Pct ($w1 / $s); x = Pct ($dr / $s); w2 = Pct ($w2 / $s); c8 = $pc8; y3 = $py3 }
    hs = $hs; as = $as; hc = $hc; ac = $ac }
  $oo = $odds[[string]$g.fixture.id]; if ($oo) { $m.o = $oo }
  [void]$list.Add($m)
}
$out = [ordered]@{ date = $today; days = @([ordered]@{ date = $today; matches = @($list | Sort-Object { $_.time }) }) }
[IO.File]::WriteAllText((Join-Path $root 'af.json'), ($out | ConvertTo-Json -Depth 8), $enc)
Write-Host "API-Football gotovo: $($list.Count) utakmica sa statistikom, $(@($list | Where-Object { $_.o }).Count) sa kvotama, $($script:calls) poziva"
