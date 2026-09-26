# TipRadar - kosarka (NBA), americki fudbal (NFL), bejzbol (MLB) preko balldontlie.io (besplatni plan)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$key = (Get-Content -Raw -Encoding UTF8 (Join-Path $root 'config.json') | ConvertFrom-Json).balldontlieKey
$headers = @{ Authorization = $key }
$tz = [System.TimeZoneInfo]::FindSystemTimeZoneById('Central European Standard Time')
$nowLocal = [System.TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $tz)
$today = $nowLocal.Date

function Get-Bdl($url) {
  for ($t = 0; $t -lt 3; $t++) {
    try { $r = Invoke-RestMethod $url -Headers $headers -TimeoutSec 30; Start-Sleep -Seconds 13; return $r }
    catch { Write-Host "  greska: $($_.Exception.Message) - cekam"; Start-Sleep -Seconds 65 }
  }
  return $null
}
function Get-AllPages($base) {
  $all = New-Object System.Collections.ArrayList; $cursor = $null
  do {
    $url = $base + '&per_page=100' + $(if ($cursor) { "&cursor=$cursor" } else { '' })
    $r = Get-Bdl $url; if (-not $r) { break }
    foreach ($g in $r.data) { [void]$all.Add($g) }
    $cursor = $r.meta.next_cursor
  } while ($cursor)
  return $all
}
function DatesQuery($from, $to) { $q = ''; for ($d = $from; $d -le $to; $d = $d.AddDays(1)) { $q += '&dates[]=' + $d.ToString('yyyy-MM-dd') }; return $q.TrimStart('&') }

# normalizacija utakmica
function Norm-Game($g, $lg) {
  switch ($lg) {
    'mlb' {
      $final = ($g.status_state -eq 'final' -or $g.status -match 'FINAL')
      return [pscustomobject]@{ id = $g.id; utc = $g.date; final = $final
        hid = $g.home_team.id; aid = $g.away_team.id; hn = $g.home_team.display_name; an = $g.away_team.display_name
        hs = $g.home_team_data.runs; as = $g.away_team_data.runs }
    }
    default {
      $final = ($g.status_state -eq 'final' -or $g.status -match '^Final')
      $utc = if ($g.datetime) { $g.datetime } else { $g.date }
      return [pscustomobject]@{ id = $g.id; utc = $utc; final = $final
        hid = $g.home_team.id; aid = $g.visitor_team.id; hn = $g.home_team.full_name; an = $g.visitor_team.full_name
        hs = $g.home_team_score; as = $g.visitor_team_score }
    }
  }
}

function Erf([double]$x) {
  $s = [math]::Sign($x); $x = [math]::Abs($x); $t = 1 / (1 + 0.3275911 * $x)
  $y = 1 - (((((1.061405429 * $t - 1.453152027) * $t) + 1.421413741) * $t - 0.284496736) * $t + 0.254829592) * $t * [math]::Exp(-$x * $x)
  return $s * $y
}
function Phi([double]$z) { return 0.5 * (1 + (Erf ($z / [math]::Sqrt(2)))) }
function Pct([double]$x) { [int][math]::Round([math]::Max([double]0.0, [math]::Min([double]1.0, $x)) * 100) }
function PoisP([double]$l, [int]$k) { $f = 1.0; for ($i = 2; $i -le $k; $i++) { $f *= $i }; return [math]::Exp(-$l) * [math]::Pow($l, $k) / $f }

function Build-Hist($games, $line) {
  $hist = @{}
  foreach ($g in ($games | Where-Object { $_.final -and $_.hs -ne $null -and $_.as -ne $null } | Sort-Object { [datetime]$_.utc } -Descending)) {
    foreach ($side in 'h','a') {
      $tid = [string]$(if ($side -eq 'h') { $g.hid } else { $g.aid })
      $pf = [double]$(if ($side -eq 'h') { $g.hs } else { $g.as }); $pa = [double]$(if ($side -eq 'h') { $g.as } else { $g.hs })
      if (-not $hist.ContainsKey($tid)) { $hist[$tid] = New-Object System.Collections.ArrayList }
      if ($hist[$tid].Count -lt 10) { [void]$hist[$tid].Add([pscustomobject]@{ pf = $pf; pa = $pa; w = [int]($pf -gt $pa); over = [int](($pf + $pa) -gt $line) }) }
    }
  }
  return $hist
}
function TStats($hist, $tid) {
  $g = $hist[[string]$tid]; if (-not $g -or $g.Count -lt 4) { return $null }
  $n = $g.Count
  [pscustomobject]@{ n = $n
    pf = [math]::Round((($g | Measure-Object pf -Sum).Sum / $n), 1)
    pa = [math]::Round((($g | Measure-Object pa -Sum).Sum / $n), 1)
    w = ($g | Measure-Object w -Sum).Sum
    over = ($g | Measure-Object over -Sum).Sum }
}
function Add-Day($days, $g, $lgName, $p, $why) {
  $utc = [datetime]::Parse($g.utc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
  $local = [System.TimeZoneInfo]::ConvertTimeFromUtc($utc, $tz)
  if ($local.Date -lt $today -or $local.Date -gt $today.AddDays(7)) { return }
  $k = $local.ToString('yyyy-MM-dd')
  if (-not $days.ContainsKey($k)) { $days[$k] = New-Object System.Collections.ArrayList }
  [void]$days[$k].Add([ordered]@{ id = "bdl$($g.id)"; league = $lgName; time = $local.ToString('HH:mm'); home = $g.hn; away = $g.an; p = $p; why = $why })
}
function Days-Out($days) { if ($days.Count -eq 0) { return ,@() }; @(foreach ($k in ($days.Keys | Sort-Object)) { [ordered]@{ date = $k; matches = @($days[$k] | Sort-Object { $_.time }) } }) }
function Cache-Season($lg, $url) {
  $file = Join-Path $root "cache_$lg.json"
  if (Test-Path $file) { $arr = Get-Content -Raw -Encoding UTF8 $file | ConvertFrom-Json; return @($arr | ForEach-Object { $_ }) }
  Write-Host "  prvi put: skidam proslu sezonu ($lg)"
  $raw = Get-AllPages $url
  $norm = @($raw | ForEach-Object { Norm-Game $_ $lg } | Where-Object { $_.final })
  [IO.File]::WriteAllText($file, ($norm | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
  return $norm
}
function Esc([string]$s) { return [Net.WebUtility]::HtmlEncode($s) }

$out = [ordered]@{}
$yr = $today.Year

# ---------- NBA ----------
Write-Host 'NBA'
$nbaSeason = if ($today.Month -ge 9) { $yr } else { $yr - 1 }
$recent = Get-AllPages ('https://api.balldontlie.io/v1/games?' + (DatesQuery $today.AddDays(-25) $today.AddDays(7)))
$nba = @($recent | ForEach-Object { Norm-Game $_ 'nba' })
$prev = Cache-Season 'nba' ("https://api.balldontlie.io/v1/games?seasons[]=$($nbaSeason - 1)&postseason=false")
$hist = Build-Hist (@($nba) + @($prev)) 220.5
$days = @{}
foreach ($g in ($nba | Where-Object { -not $_.final })) {
  $h = TStats $hist $g.hid; $a = TStats $hist $g.aid; if (-not $h -or -not $a) { continue }
  $eh = ($h.pf + $a.pa) / 2 + 1.5; $ea = ($a.pf + $h.pa) / 2 - 1.5; $m = $eh - $ea; $tot = $eh + $ea
  $w1 = Phi ($m / 12.5)
  $o = 0.5 * (1 - (Phi ((220.5 - $tot) / 17))) + 0.5 * ((($h.over / $h.n) + ($a.over / $a.n)) / 2)
  $p = [ordered]@{ w1 = Pct $w1; w2 = Pct (1 - $w1); o220 = Pct $o; u220 = Pct (1 - $o)
    m10 = Pct ((1 - (Phi ((9.5 - $m) / 12.5))) + (Phi ((-9.5 - $m) / 12.5))); h110 = Pct (1 - (Phi ((109.5 - $eh) / 11))) }
  $HN = Esc $g.hn; $AN = Esc $g.an
  $rec = "Zadnjih $($h.n): $HN $($h.w)-$($h.n - $h.w), prosjek $($h.pf):$($h.pa) &middot; $AN $($a.w)-$($a.n - $a.w), $($a.pf):$($a.pa)"
  $why = [ordered]@{ w1 = $rec; w2 = $rec
    o220 = "Preko 220.5: $HN $($h.over)/$($h.n), $AN $($a.over)/$($a.n)<br>Ocekivano oko $([math]::Round($tot)) poena"
    u220 = "Preko 220.5 bilo: $HN $($h.over)/$($h.n), $AN $($a.over)/$($a.n)<br>Ocekivano oko $([math]::Round($tot)) poena"
    m10 = "Ocekivana razlika oko $([math]::Round([math]::Abs($m),1)) poena<br>$rec"
    h110 = "$HN daje prosjecno $($h.pf), $AN prima $($a.pa)<br>Ocekivano za $HN oko $([math]::Round($eh))" }
  Add-Day $days $g 'NBA' $p $why
}
$out.basketball = [ordered]@{ days = (Days-Out $days) }

# ---------- NFL ----------
Write-Host 'NFL'
$nflSeason = if ($today.Month -ge 8) { $yr } else { $yr - 1 }
$nfl = @(Get-AllPages "https://api.balldontlie.io/nfl/v1/games?seasons[]=$nflSeason" | ForEach-Object { Norm-Game $_ 'nfl' })
$prev = Cache-Season 'nfl' ("https://api.balldontlie.io/nfl/v1/games?seasons[]=$($nflSeason - 1)")
$hist = Build-Hist (@($nfl) + @($prev)) 45.5
$days = @{}
foreach ($g in ($nfl | Where-Object { -not $_.final })) {
  $h = TStats $hist $g.hid; $a = TStats $hist $g.aid; if (-not $h -or -not $a) { continue }
  $eh = ($h.pf + $a.pa) / 2 + 1.2; $ea = ($a.pf + $h.pa) / 2 - 1.2; $m = $eh - $ea; $tot = $eh + $ea
  $w1 = Phi ($m / 13.5)
  $o = 0.5 * (1 - (Phi ((45.5 - $tot) / 13.5))) + 0.5 * ((($h.over / $h.n) + ($a.over / $a.n)) / 2)
  $p = [ordered]@{ w1 = Pct $w1; w2 = Pct (1 - $w1); o45 = Pct $o; u45 = Pct (1 - $o) }
  $HN = Esc $g.hn; $AN = Esc $g.an
  $rec = "Zadnjih $($h.n): $HN $($h.w)-$($h.n - $h.w), prosjek $($h.pf):$($h.pa) &middot; $AN $($a.w)-$($a.n - $a.w), $($a.pf):$($a.pa)"
  $ov = "Preko 45.5: $HN $($h.over)/$($h.n), $AN $($a.over)/$($a.n)<br>Ocekivano oko $([math]::Round($tot)) poena"
  Add-Day $days $g 'NFL' $p ([ordered]@{ w1 = $rec; w2 = $rec; o45 = $ov; u45 = $ov })
}
$out.nfl = [ordered]@{ days = (Days-Out $days) }

# ---------- MLB ----------
Write-Host 'MLB'
$mlb = @(Get-AllPages ('https://api.balldontlie.io/mlb/v1/games?' + (DatesQuery $today.AddDays(-21) $today.AddDays(3))) | ForEach-Object { Norm-Game $_ 'mlb' })
$hist = Build-Hist $mlb 8.5
$days = @{}
foreach ($g in ($mlb | Where-Object { -not $_.final })) {
  $h = TStats $hist $g.hid; $a = TStats $hist $g.aid; if (-not $h -or -not $a) { continue }
  $lh = [math]::Max(0.5, ($h.pf + $a.pa) / 2 * 1.02); $la = [math]::Max(0.5, ($a.pf + $h.pa) / 2 * 0.98)
  $pw = 0.0; $pt = 0.0; $pu = 0.0
  for ($i = 0; $i -le 20; $i++) { $pi = PoisP $lh $i; for ($j = 0; $j -le 20; $j++) { $pp = $pi * (PoisP $la $j)
    if ($i -gt $j) { $pw += $pp } elseif ($i -eq $j) { $pt += $pp }
    if (($i + $j) -le 8) { $pu += $pp } } }
  $w1 = $pw / (1 - $pt)
  $o = 0.5 * (1 - $pu) + 0.5 * ((($h.over / $h.n) + ($a.over / $a.n)) / 2)
  $p = [ordered]@{ w1 = Pct $w1; w2 = Pct (1 - $w1); o85 = Pct $o; u85 = Pct (1 - $o) }
  $HN = Esc $g.hn; $AN = Esc $g.an
  $rec = "Zadnjih $($h.n): $HN $($h.w)-$($h.n - $h.w), prosjek runova $($h.pf):$($h.pa) &middot; $AN $($a.w)-$($a.n - $a.w), $($a.pf):$($a.pa)"
  $ov = "Preko 8.5 runova: $HN $($h.over)/$($h.n), $AN $($a.over)/$($a.n)<br>Ocekivano oko $([math]::Round($lh + $la,1)) runova"
  Add-Day $days $g 'MLB' $p ([ordered]@{ w1 = $rec; w2 = $rec; o85 = $ov; u85 = $ov })
}
$out.mlb = [ordered]@{ days = (Days-Out $days) }

# rezultati za pracenje pogodaka
. (Join-Path $root 'results_lib.ps1')
$res = @{}
foreach ($pair in @(@('basketball', $nba), @('nfl', $nfl), @('mlb', $mlb))) {
  foreach ($g in ($pair[1] | Where-Object { $_.final -and $_.hs -ne $null })) { $res["$($pair[0]):bdl$($g.id)"] = [ordered]@{ h = [int]$g.hs; a = [int]$g.as } }
}
Save-Results $root $res
[IO.File]::WriteAllText((Join-Path $root 'us.json'), ($out | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("US gotovo: NBA {0}, NFL {1}, MLB {2} dana" -f @($out.basketball.days).Count, @($out.nfl.days).Count, @($out.mlb.days).Count)
