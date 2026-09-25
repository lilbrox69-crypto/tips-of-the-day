# NHL preko zvanicnog, besplatnog NHL API-ja (api-web.nhle.com, bez kljuca)
# Statistika = zadnjih 10 utakmica regularnog dijela/playoffa (tekuca + prosla sezona). Pise nhl.json
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$tz = [System.TimeZoneInfo]::FindSystemTimeZoneById('Central European Standard Time')
$today = [System.TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $tz).Date
$enc = New-Object System.Text.UTF8Encoding($false)
$y = if ($today.Month -ge 9) { $today.Year } else { $today.Year - 1 }
$seasons = @("$y$($y + 1)", "$($y - 1)$y")

function Get-NHL($path) {
  for ($t = 0; $t -lt 3; $t++) {
    try { return Invoke-RestMethod ("https://api-web.nhle.com/v1/" + $path) -TimeoutSec 30 } catch { Start-Sleep -Seconds 5 }
  }
  return $null
}
function Pct([double]$x) { [int][math]::Round([math]::Max([double]0.0, [math]::Min([double]1.0, $x)) * 100) }
function PoisP([double]$l, [int]$k) { $f = 1.0; for ($i = 2; $i -le $k; $i++) { $f *= $i }; [math]::Exp(-$l) * [math]::Pow($l, $k) / $f }
function Esc([string]$s) { [Net.WebUtility]::HtmlEncode($s) }
function TName($t) { if ($t.commonName) { "$($t.placeName.default) $($t.commonName.default)" } else { $t.name.default } }

# utakmice za danas (i sutra, zbog vremenske zone)
$upcoming = @()
$sch = Get-NHL ("schedule/" + $today.ToString('yyyy-MM-dd'))
foreach ($day in @($sch.gameWeek | Select-Object -First 2)) {
  foreach ($g in $day.games) { if ($g.gameType -in 2, 3 -and $g.gameState -in 'FUT', 'PRE') { $upcoming += $g } }
}

# jucerasnji rezultati za pracenje pogodaka
. (Join-Path $root 'results_lib.ps1')
$res = @{}; $yd = Get-NHL ("schedule/" + $today.AddDays(-1).ToString('yyyy-MM-dd'))
foreach ($day in @($yd.gameWeek | Select-Object -First 2)) {
  foreach ($g in $day.games) { if ($g.gameState -in 'OFF', 'FINAL' -and $g.homeTeam.score -ne $null) { $res["hockey:nhl$($g.id)"] = [ordered]@{ h = [int]$g.homeTeam.score; a = [int]$g.awayTeam.score } } }
}
Save-Results $root $res

# zadnjih 10 za svaki tim koji igra
$cache = @{}
function TeamStats($abbrev) {
  if ($cache.ContainsKey($abbrev)) { return $cache[$abbrev] }
  $list = @()
  foreach ($s in $seasons) {
    $r = Get-NHL "club-schedule-season/$abbrev/$s"
    if ($r) { $list += @($r.games | Where-Object { $_.gameType -in 2, 3 -and $_.gameState -in 'OFF', 'FINAL' }) }
  }
  $games = @($list | Sort-Object { [datetime]$_.startTimeUTC } -Descending | Select-Object -First 10 | ForEach-Object {
    $isH = $_.homeTeam.abbrev -eq $abbrev
    [pscustomobject]@{ pf = [double]$(if ($isH) { $_.homeTeam.score } else { $_.awayTeam.score }); pa = [double]$(if ($isH) { $_.awayTeam.score } else { $_.homeTeam.score }) } })
  $st = $null
  if ($games.Count -ge 5) {
    $n = $games.Count
    $st = [pscustomobject]@{ n = $n; pf = [math]::Round((($games | Measure-Object pf -Sum).Sum / $n), 1); pa = [math]::Round((($games | Measure-Object pa -Sum).Sum / $n), 1)
      w = @($games | Where-Object { $_.pf -gt $_.pa }).Count; games = $games }
  }
  $cache[$abbrev] = $st
  return $st
}
function Rate($s, $cond) { @($s.games | Where-Object -FilterScript $cond).Count }
function RateOf($s, $cond) { [double](Rate $s $cond) / [double]$s.n }

$days = @{}
foreach ($g in $upcoming) {
  $h = TeamStats $g.homeTeam.abbrev; $a = TeamStats $g.awayTeam.abbrev; if (-not $h -or -not $a) { continue }
  $HN = Esc (TName $g.homeTeam); $AN = Esc (TName $g.awayTeam)
  $lh = [math]::Max(0.5, ($h.pf + $a.pa) / 2 * 1.05); $la = [math]::Max(0.5, ($a.pf + $h.pa) / 2 * 0.97)
  $ph = 0.0; $pt = 0.0; $pa2 = 0.0; $o55 = 0.0; $o45 = 0.0
  for ($i = 0; $i -le 12; $i++) { $pi = PoisP $lh $i; for ($j = 0; $j -le 12; $j++) { $pp = $pi * (PoisP $la $j)
    if ($i -gt $j) { $ph += $pp } elseif ($i -eq $j) { $pt += $pp } else { $pa2 += $pp }
    if (($i + $j) -ge 6) { $o55 += $pp }; if (($i + $j) -ge 5) { $o45 += $pp } } }
  $w1 = $ph + $pt * ($ph / ($ph + $pa2))
  $bt = { $_.pf -gt 0 -and $_.pa -gt 0 }; $s6 = { ($_.pf + $_.pa) -ge 6 }; $s5 = { ($_.pf + $_.pa) -ge 5 }
  $gg = 0.5 * ((1 - [math]::Exp(-$lh)) * (1 - [math]::Exp(-$la))) + 0.5 * (((RateOf $h $bt) + (RateOf $a $bt)) / 2)
  $o55 = 0.5 * $o55 + 0.5 * (((RateOf $h $s6) + (RateOf $a $s6)) / 2)
  $o45 = 0.5 * $o45 + 0.5 * (((RateOf $h $s5) + (RateOf $a $s5)) / 2)
  $gl = "Ocekivani golovi $([math]::Round($lh,1)) - $([math]::Round($la,1))"
  $recTxt = "Zadnjih $($h.n): $HN $($h.w)-$($h.n - $h.w), prosjek $($h.pf):$($h.pa) &middot; $AN $($a.w)-$($a.n - $a.w), $($a.pf):$($a.pa)"
  $p = [ordered]@{ gg = Pct $gg; o55 = Pct $o55; o45 = Pct $o45; u55 = Pct (1 - $o55); w1 = Pct $w1; w2 = Pct (1 - $w1) }
  $why = [ordered]@{ gg = "Oba dala gol: $HN $(Rate $h $bt)/$($h.n), $AN $(Rate $a $bt)/$($a.n)<br>$gl"
    o55 = "6+ golova: $HN $(Rate $h $s6)/$($h.n), $AN $(Rate $a $s6)/$($a.n)<br>$gl"
    o45 = "5+ golova: $HN $(Rate $h $s5)/$($h.n), $AN $(Rate $a $s5)/$($a.n)<br>$gl"
    u55 = "6+ golova bilo je: $HN $(Rate $h $s6)/$($h.n), $AN $(Rate $a $s6)/$($a.n)<br>$gl"
    w1 = $recTxt; w2 = $recTxt }
  $utc = [datetime]::Parse($g.startTimeUTC, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
  $local = [System.TimeZoneInfo]::ConvertTimeFromUtc($utc, $tz)
  if ($local.Date -lt $today) { continue }
  $k = $local.ToString('yyyy-MM-dd')
  if (-not $days.ContainsKey($k)) { $days[$k] = New-Object System.Collections.ArrayList }
  [void]$days[$k].Add([ordered]@{ id = "nhl$($g.id)"; league = 'NHL (USA)'; time = $local.ToString('HH:mm'); home = TName $g.homeTeam; away = TName $g.awayTeam
    hl = $g.homeTeam.darkLogo; al = $g.awayTeam.darkLogo; p = $p; why = $why })
}
$dl = @(foreach ($k in ($days.Keys | Sort-Object)) { [ordered]@{ date = $k; matches = @($days[$k] | Sort-Object { $_.time }) } })
[IO.File]::WriteAllText((Join-Path $root 'nhl.json'), (ConvertTo-Json ([ordered]@{ hockey = [ordered]@{ days = $dl } }) -Depth 8), $enc)
Write-Host "NHL: $(@($upcoming).Count) utakmica u rasporedu, $((@($dl) | ForEach-Object { $_.matches.Count } | Measure-Object -Sum).Sum) sa statistikom"
