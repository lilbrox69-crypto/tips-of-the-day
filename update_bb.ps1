# Kosarka preko API-Basketball (Pro plan, od 26.9.2026): tekuca sezona, sve lige, kvote.
# Pise bb.json (danasnje utakmice) i rezultate za pracenje pogodaka. NBA ide i dalje preko balldontlie (update_us.ps1).
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
function Get-Many([string[]]$paths) {
  $out = @{}; $paths = @($paths | Select-Object -Unique)
  for ($i = 0; $i -lt $paths.Count; $i += 10) {
    $batch = $paths[$i..([math]::Min($i + 9, $paths.Count - 1))]
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $tasks = @{}; foreach ($p in $batch) { $tasks[$p] = $client.GetStringAsync("https://v1.basketball.api-sports.io/$p") }
    foreach ($p in $batch) { $script:calls++; try { $out[$p] = $tasks[$p].Result | ConvertFrom-Json } catch { Write-Host "  greska: $p" } }
    $wait = 2300 - $sw.ElapsedMilliseconds; if ($wait -gt 0) { Start-Sleep -Milliseconds $wait }
  }
  return $out
}
function Get-One($path) { (Get-Many @($path))[$path] }
$FIN = @('FT', 'AOT')
function Compact($g) { [pscustomobject]@{ id = [string]$g.id; d = $g.date; hid = [string]$g.teams.home.id; aid = [string]$g.teams.away.id; hs = [int]$g.scores.home.total; as = [int]$g.scores.away.total } }
function PrevSeason($s) { $s = [string]$s; if ($s -match '^(\d{4})-(\d{4})$') { "$([int]$matches[1] - 1)-$([int]$matches[2] - 1)" } else { [string]([int]$s - 1) } }

# ---------- 1) danas + juce (rezultati za pracenje) ----------
$r0 = Get-One "games?date=$today&timezone=Europe/Sarajevo"
$ry = Get-One "games?date=$($todayD.AddDays(-1).ToString('yyyy-MM-dd'))&timezone=Europe/Sarajevo"
$res = @{}
foreach ($g in @($ry.response) + @($r0.response)) { if ($g.status.short -in $FIN) { $c = Compact $g; $res["basketball:bb$($c.id)"] = [ordered]@{ h = $c.hs; a = $c.as } } }
if ($res.Count) { Save-Results $root $res }
$skip = 'Women| W$|Wom|Femin|Fem\.|U1[5-9]|U2[0-3]|Youth|Junior|Reserve|NBA|WNBA|Summer League|Friendl'
$games = @($r0.response | Where-Object { $_.status.short -eq 'NS' -and $_.league.name -notmatch $skip -and $_.teams.home.name -notmatch ' W$| U\d\d$|Women' })
Write-Host "API-Basketball: $(@($r0.response).Count) utakmica danas, $($games.Count) u obzir"

# ---------- 2) istorija: tekuca sezona lige + prosla sezona (kes) ----------
$lp = @($games | ForEach-Object { "games?league=$($_.league.id)&season=$($_.league.season)" } | Select-Object -Unique)
$lres = Get-Many $lp
$hist = @{}; $seen = @{}
function Add-Hist($c) { if ($seen.ContainsKey($c.id)) { return }; $seen[$c.id] = 1; foreach ($t in $c.hid, $c.aid) { if (-not $hist.ContainsKey($t)) { $hist[$t] = New-Object System.Collections.ArrayList }; [void]$hist[$t].Add($c) } }
foreach ($r in $lres.Values) { foreach ($g in $r.response) { if ($g.status.short -in $FIN) { Add-Hist (Compact $g) } } }
# prosla sezona samo za lige gdje timovi imaju malo utakmica (pocetak sezone), kesirano zauvijek
$prevNeed = @($games | Where-Object { -not $hist.ContainsKey([string]$_.teams.home.id) -or $hist[[string]$_.teams.home.id].Count -lt 8 -or -not $hist.ContainsKey([string]$_.teams.away.id) -or $hist[[string]$_.teams.away.id].Count -lt 8 } |
  ForEach-Object { "$($_.league.id)|$(PrevSeason $_.league.season)" } | Select-Object -Unique)
$fetch = @()
foreach ($ls in $prevNeed) { $lid, $ps = $ls.Split('|'); $f = Join-Path $cacheDir "bb_${lid}_$ps.json"; if (Test-Path $f) { $carr = Get-Content -Raw -Encoding UTF8 $f | ConvertFrom-Json; foreach ($c in $carr) { if ($c -and $c.id) { Add-Hist $c } } } else { $fetch += "games?league=$lid&season=$ps" } }
if ($fetch.Count) {
  $pres = Get-Many $fetch
  foreach ($pth in $pres.Keys) {
    $list = @($pres[$pth].response | Where-Object { $_.status.short -in $FIN } | ForEach-Object { Compact $_ })
    $m = [regex]::Match($pth, 'league=(\d+)&season=(.+)$'); $f = Join-Path $cacheDir "bb_$($m.Groups[1].Value)_$($m.Groups[2].Value).json"
    [IO.File]::WriteAllText($f, ('[' + (($list | ForEach-Object { $_ | ConvertTo-Json -Compress }) -join ',') + ']'), $enc)
    foreach ($c in $list) { Add-Hist $c }
  }
}

# ---------- 3) kvote (po ligi), medijan svih kladionica ----------
$opaths = @($games | ForEach-Object { "odds?league=$($_.league.id)&season=$($_.league.season)" } | Select-Object -Unique)
$ores = Get-Many $opaths
function Median($xs) { $s = @($xs | Sort-Object); if ($s.Count -eq 0) { return $null }; $m = [int][math]::Floor($s.Count / 2); if ($s.Count % 2) { $s[$m] } else { ($s[$m - 1] + $s[$m]) / 2 } }
$omap = @(@('w1', 2, 'Home'), @('w2', 2, 'Away'), @('o160', 4, 'Over 160.5'), @('u160', 4, 'Under 160.5'), @('o220', 4, 'Over 220.5'), @('u220', 4, 'Under 220.5'))
$odds = @{}
foreach ($r in $ores.Values) {
  foreach ($x in $r.response) {
    $vals = @{}
    foreach ($bk in $x.bookmakers) { foreach ($m in $omap) {
      $b = @($bk.bets | Where-Object { $_.id -eq $m[1] })[0]; if (-not $b) { continue }
      $v = @($b.values | Where-Object { [string]$_.value -eq $m[2] })[0]; if (-not $v) { continue }
      if (-not $vals.ContainsKey($m[0])) { $vals[$m[0]] = New-Object System.Collections.ArrayList }; [void]$vals[$m[0]].Add([double]$v.odd) } }
    $o = [ordered]@{}; foreach ($k in $vals.Keys) { $o[$k] = [math]::Round((Median $vals[$k]), 2) }
    if ($o.Count) { $odds[[string]$x.game.id] = $o }
  }
}

# ---------- 4) procenti ----------
function Erf([double]$x) { $s = [math]::Sign($x); $x = [math]::Abs($x); $t = 1 / (1 + 0.3275911 * $x)
  $y = 1 - (((((1.061405429 * $t - 1.453152027) * $t) + 1.421413741) * $t - 0.284496736) * $t + 0.254829592) * $t * [math]::Exp(-$x * $x); return $s * $y }
function Phi([double]$z) { 0.5 * (1 + (Erf ($z / [math]::Sqrt(2)))) }
function Pct([double]$x) { [int][math]::Round([math]::Max([double]0.0, [math]::Min([double]1.0, $x)) * 100) }
function Esc([string]$s) { [Net.WebUtility]::HtmlEncode($s) }
function TS($t) {
  $g = @($hist[$t] | Sort-Object { [datetime]$_.d } -Descending | Select-Object -First 10); if ($g.Count -lt 6) { return $null }
  $rows = @($g | ForEach-Object { $h = $_.hid -eq $t; [pscustomobject]@{ pf = [double]$(if ($h) { $_.hs } else { $_.as }); pa = [double]$(if ($h) { $_.as } else { $_.hs }) } })
  $n = $rows.Count
  [pscustomobject]@{ n = $n; pf = [math]::Round((($rows | Measure-Object pf -Sum).Sum / $n), 1); pa = [math]::Round((($rows | Measure-Object pa -Sum).Sum / $n), 1)
    w = @($rows | Where-Object { $_.pf -gt $_.pa }).Count; o160 = @($rows | Where-Object { ($_.pf + $_.pa) -gt 160.5 }).Count; o220 = @($rows | Where-Object { ($_.pf + $_.pa) -gt 220.5 }).Count }
}
$list = New-Object System.Collections.ArrayList
foreach ($g in $games) {
  $ht = [string]$g.teams.home.id; $at = [string]$g.teams.away.id
  $h = TS $ht; $a = TS $at; if (-not $h -or -not $a) { continue }
  $eh = ($h.pf + $a.pa) / 2 + 2; $ea = ($a.pf + $h.pa) / 2 - 2; $m = $eh - $ea; $tot = $eh + $ea
  $sd = [math]::Max(10, 0.075 * $tot)
  $w1 = Phi ($m / $sd)
  $o160 = 0.5 * (1 - (Phi ((160.5 - $tot) / 15))) + 0.5 * ((($h.o160 / $h.n) + ($a.o160 / $a.n)) / 2)
  $o220 = 0.5 * (1 - (Phi ((220.5 - $tot) / 17))) + 0.5 * ((($h.o220 / $h.n) + ($a.o220 / $a.n)) / 2)
  $p = [ordered]@{ w1 = Pct $w1; w2 = Pct (1 - $w1); m10 = Pct ((1 - (Phi ((9.5 - $m) / $sd))) + (Phi ((-9.5 - $m) / $sd))); h80 = Pct (1 - (Phi ((79.5 - $eh) / 9))); o160 = Pct $o160; u160 = Pct (1 - $o160) }
  if ($tot -gt 190) { $p.o220 = Pct $o220; $p.u220 = Pct (1 - $o220); $p.h110 = Pct (1 - (Phi ((109.5 - $eh) / 11))) }
  $pm = [ordered]@{}; foreach ($k in @($p.Keys)) { $pm[$k] = $p[$k] }
  # mijesanje sa trzistem (kvote), kao u fudbalu: 65% nasa statistika, 35% kvote
  $o = $odds[[string]$g.id]
  if ($o) {
    if ($o.Contains('w1') -and $o.Contains('w2')) { $i1 = 1 / $o.w1; $i2 = 1 / $o.w2; $p.w1 = [int][math]::Round(0.65 * $p.w1 + 0.35 * 100 * $i1 / ($i1 + $i2)); $p.w2 = 100 - $p.w1 }
    foreach ($pair in @(@('o160', 'u160'), @('o220', 'u220'))) { if ($o.Contains($pair[0]) -and $o.Contains($pair[1]) -and $p.Contains($pair[0])) {
      $io = 1 / $o[$pair[0]]; $iu = 1 / $o[$pair[1]]; $p[$pair[0]] = [int][math]::Round(0.65 * $p[$pair[0]] + 0.35 * 100 * $io / ($io + $iu)); $p[$pair[1]] = 100 - $p[$pair[0]] } }
  }
  $HN = Esc $g.teams.home.name; $AN = Esc $g.teams.away.name
  $recTxt = "Zadnjih $($h.n): $HN $($h.w)-$($h.n - $h.w), prosjek $($h.pf):$($h.pa) &middot; $AN $($a.w)-$($a.n - $a.w), $($a.pf):$($a.pa)"
  $ov = "161+ poena: $HN $($h.o160)/$($h.n), $AN $($a.o160)/$($a.n)<br>Ocekivano oko $([math]::Round($tot)) poena"
  $ov2 = "Preko 220.5 bilo: $HN $($h.o220)/$($h.n), $AN $($a.o220)/$($a.n)<br>Ocekivano oko $([math]::Round($tot)) poena"
  $why = [ordered]@{ w1 = $recTxt; w2 = $recTxt; o160 = $ov; u160 = $ov; o220 = $ov2; u220 = $ov2; m10 = "Ocekivana razlika oko $([math]::Round([math]::Abs($m),1))<br>$recTxt"
    h80 = "$HN daje prosjecno $($h.pf), $AN prima $($a.pa)"; h110 = "$HN daje prosjecno $($h.pf), $AN prima $($a.pa)" }
  $utc = [datetime]::Parse($g.date, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
  $local = [System.TimeZoneInfo]::ConvertTimeFromUtc($utc, $tz)
  $mm = [ordered]@{ id = "bb$($g.id)"; league = "$($g.league.name) ($($g.country.name))"; time = $local.ToString('HH:mm'); home = $g.teams.home.name; away = $g.teams.away.name
    hl = $g.teams.home.logo; al = $g.teams.away.logo; p = $p; why = $why }
  if ($o) { $mm.o = $o }
  $mm.pm = $pm
  [void]$list.Add($mm)
}
# sjena: top 3 samo po statistici (bez kvota), iz svih utakmica
$sh = New-Object System.Collections.ArrayList
foreach ($mk in 'w1','w2','o160','u160','o220','u220','m10','h80','h110') {
  foreach ($m in @($list | Where-Object { $_.pm[$mk] -ne $null } | Sort-Object { - [int]$_.pm[$mk] } | Select-Object -First 3)) {
    [void]$sh.Add([ordered]@{ sport = 'basketball'; mk = $mk; key = "basketball:$($m.id)"; home = $m.home; away = $m.away; p = [int]$m.pm[$mk] }) } }
[IO.File]::WriteAllText((Join-Path $root 'shadow_bb.json'), (([ordered]@{ date = $today; picks = @($sh) }) | ConvertTo-Json -Depth 4 -Compress), $enc)
foreach ($m in $list) { $m.Remove('pm') }
$withOdds = @($list | Where-Object { $_.o })
if ($withOdds.Count -ge 10) { $list = $withOdds }
$out = [ordered]@{ basketball = [ordered]@{ days = @([ordered]@{ date = $today; matches = @($list | Sort-Object { $_.time }) }) } }
[IO.File]::WriteAllText((Join-Path $root 'bb.json'), ($out | ConvertTo-Json -Depth 8), $enc)
Write-Host "API-Basketball gotovo: $(@($list).Count) utakmica, $(@($list | Where-Object { $_.o }).Count) sa kvotama, $($script:calls) poziva"
