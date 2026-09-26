# Trojka Dana - dnevno osvjezavanje podataka
# Povlaci utakmice i rezultate sa football-data.org, racuna procente i pise data.json
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$token = (Get-Content -Raw -Encoding UTF8 (Join-Path $root 'config.json') | ConvertFrom-Json).footballDataToken
$headers = @{ 'X-Auth-Token' = $token }
$tz = [System.TimeZoneInfo]::FindSystemTimeZoneById('Central European Standard Time')

$comps = [ordered]@{
  PL = 'Premier liga'; PD = 'La Liga'; SA = 'Serie A'; BL1 = 'Bundesliga'; FL1 = 'Ligue 1'
  DED = 'Eredivisie'; PPL = 'Primeira Liga'; ELC = 'Championship'; CL = 'Liga prvaka'
  BSA = 'Brasileirao'; CLI = 'Copa Libertadores'
}

function Get-Api($path) {
  for ($try = 0; $try -lt 3; $try++) {
    try {
      $r = Invoke-RestMethod ("https://api.football-data.org/v4/" + $path) -Headers $headers -TimeoutSec 30
      Start-Sleep -Milliseconds 6500   # besplatni plan: 10 poziva u minuti
      return $r
    } catch {
      Write-Host "  greska ($path): $($_.Exception.Message) - cekam"
      Start-Sleep -Seconds 65
    }
  }
  return $null
}

# --- Glavni izvor: API-Football (Pro). football-data.org ostaje kao rezerva. ---
$afOk = $false
try {
  & (Join-Path $root 'update_af.ps1')
  $af = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'af.json') | ConvertFrom-Json
  $todayStr = [System.TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $tz).ToString('yyyy-MM-dd')
  if ($af.date -eq $todayStr -and @($af.days[0].matches).Count -gt 0) { $afOk = $true; $dayList = @($af.days) }
} catch { Write-Host "API-Football preskocen: $($_.Exception.Message)" }
if (-not $afOk) {
$finished = @{}   # match id -> match
$upcoming = @{}
foreach ($code in $comps.Keys) {
  Write-Host "Liga $code"
  $cur = Get-Api "competitions/$code/matches"
  if (-not $cur) { continue }
  $startYear = [int]$cur.filters.season
  if (-not $startYear) { $startYear = [int]($cur.matches | Select-Object -First 1).season.startDate.Substring(0,4) }
  $prev = Get-Api ("competitions/$code/matches?season=" + ($startYear - 1) + "&status=FINISHED")
  $all = @($cur.matches) + @(if ($prev) { $prev.matches })
  foreach ($m in $all) {
    if (-not $m) { continue }
    $m | Add-Member -NotePropertyName compCode -NotePropertyValue $code -Force
    if ($m.status -eq 'FINISHED' -and $m.score.fullTime.home -ne $null) { $finished[[string]$m.id] = $m }
    elseif ($m.status -in @('SCHEDULED','TIMED')) { $upcoming[[string]$m.id] = $m }
  }
}

# --- Korneri i zuti kartoni: football-data.co.uk CSV (besplatno) ---
$csvCodes = @{ PL='E0'; ELC='E1'; PD='SP1'; SA='I1'; BL1='D1'; FL1='F1'; DED='N1'; PPL='P1' }
function Norm([string]$s) {
  $s = $s.Normalize([Text.NormalizationForm]::FormD)
  $s = -join ($s.ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' })
  $s = $s.ToLower() -replace "nott'm", 'nottingham' -replace '\butd\b', 'united' -replace '\bman\b', 'manchester' -replace '\bwolves\b', 'wolverhampton' -replace "[^a-z0-9 ]", ' '
  $s = ($s -split '\s+' | Where-Object { $_ -and $_ -notin @('fc','afc','cf','sc','ac','as','ss','club','de','cd','ud','sd','rc','rcd','sv','vfl','vfb','tsg','fsv','bv','ssc','us','ogc','stade','the','calcio','and') }) -join ' '
  return $s
}
function Grams([string]$s) { $s = " $s "; $g = @{}; for ($i = 0; $i -lt $s.Length - 2; $i++) { $g[$s.Substring($i,3)] = 1 }; return $g }
$gramCache = @{}
function Sim([string]$a, [string]$b) {
  if (-not $gramCache.ContainsKey($a)) { $gramCache[$a] = Grams (Norm $a) }
  if (-not $gramCache.ContainsKey($b)) { $gramCache[$b] = Grams (Norm $b) }
  $ga = $gramCache[$a]; $gb = $gramCache[$b]; $inter = 0
  foreach ($k in $ga.Keys) { if ($gb.ContainsKey($k)) { $inter++ } }
  $union = $ga.Count + $gb.Count - $inter
  if ($union -eq 0) { return 0 } ; return $inter / $union
}
$byCompDate = @{}
foreach ($m in $finished.Values) {
  $k = $m.compCode + '|' + $m.utcDate.Substring(0,10)
  if (-not $byCompDate.ContainsKey($k)) { $byCompDate[$k] = New-Object System.Collections.ArrayList }
  [void]$byCompDate[$k].Add($m)
}
$extra = @{}   # match id -> korneri/kartoni
$yr = (Get-Date).Year; if ((Get-Date).Month -lt 7) { $yr-- }
$seasonCodes = @(('{0:D2}{1:D2}' -f ($yr % 100), (($yr + 1) % 100)), ('{0:D2}{1:D2}' -f (($yr - 1) % 100), ($yr % 100)))
foreach ($code in $csvCodes.Keys) {
  foreach ($sc in $seasonCodes) {
    try {
      $bytes = (New-Object System.Net.WebClient).DownloadData("https://www.football-data.co.uk/mmz4281/$sc/$($csvCodes[$code]).csv")
      $csv = [Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF) | ConvertFrom-Csv
    }
    catch { Write-Host "  CSV $code $sc nije dostupan"; continue }
    foreach ($r in $csv) {
      if (-not $r.HC -or -not $r.HomeTeam) { continue }
      try { $d = [datetime]::ParseExact($r.Date, [string[]]@('dd/MM/yyyy','dd/MM/yy'), [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None) } catch { continue }
      $best = $null; $bestScore = 0
      foreach ($off in -1,0,1) {
        $cands = $byCompDate[$code + '|' + $d.AddDays($off).ToString('yyyy-MM-dd')]
        foreach ($m in $cands) {
          $hn = if ($m.homeTeam.shortName) { $m.homeTeam.shortName } else { $m.homeTeam.name }
          $an = if ($m.awayTeam.shortName) { $m.awayTeam.shortName } else { $m.awayTeam.name }
          $score = [math]::Max((Sim $r.HomeTeam $hn), (Sim $r.HomeTeam $m.homeTeam.name)) + [math]::Max((Sim $r.AwayTeam $an), (Sim $r.AwayTeam $m.awayTeam.name))
          if ($off -ne 0) { $score -= 0.1 }
          if ($score -gt $bestScore) { $bestScore = $score; $best = $m }
        }
      }
      if ($best -and $bestScore -ge 0.55) {
        $extra[[string]$best.id] = [pscustomobject]@{ hc = [int]$r.HC; ac = [int]$r.AC; hy = [int]$r.HY; ay = [int]$r.AY }
      }
    }
  }
}
Write-Host "Korneri/kartoni povezani za $($extra.Count) utakmica"
# rezultati za pracenje pogodaka
. (Join-Path $root 'results_lib.ps1')
$res = @{}; $cut = [datetime]::UtcNow.AddDays(-12)
foreach ($m in $finished.Values) {
  if ([datetime]::Parse($m.utcDate, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal) -lt $cut) { continue }
  $e = [ordered]@{ h = [int]$m.score.fullTime.home; a = [int]$m.score.fullTime.away }
  $x = $extra[[string]$m.id]; if ($x) { $e.hc = $x.hc; $e.ac = $x.ac; $e.hy = $x.hy; $e.ay = $x.ay }
  $res["football:$($m.id)"] = $e
}
Save-Results $root $res

$cHist = @{}
foreach ($m in ($finished.Values | Sort-Object { [datetime]$_.utcDate } -Descending)) {
  $x = $extra[[string]$m.id]; if (-not $x) { continue }
  foreach ($side in 'home','away') {
    $key = if ($side -eq 'home') { [string]$m.homeTeam.id } else { [string]$m.awayTeam.id }
    if (-not $cHist.ContainsKey($key)) { $cHist[$key] = New-Object System.Collections.ArrayList }
    if ($cHist[$key].Count -lt 10) {
      [void]$cHist[$key].Add([pscustomobject]@{
        cf = if ($side -eq 'home') { $x.hc } else { $x.ac }
        ca = if ($side -eq 'home') { $x.ac } else { $x.hc }
        ct = $x.hc + $x.ac; yt = $x.hy + $x.ay
      })
    }
  }
}
function Get-CStats($teamId) {
  $g = $cHist[[string]$teamId]
  if (-not $g -or $g.Count -lt 5) { return $null }
  $n = $g.Count
  [pscustomobject]@{
    n = $n
    cf = [math]::Round((($g | Measure-Object cf -Sum).Sum / $n), 1)
    ca = [math]::Round((($g | Measure-Object ca -Sum).Sum / $n), 1)
    ct = [math]::Round((($g | Measure-Object ct -Sum).Sum / $n), 1)
    c8 = @($g | Where-Object { $_.ct -ge 8 }).Count
    yt = [math]::Round((($g | Measure-Object yt -Sum).Sum / $n), 1)
    y3 = @($g | Where-Object { $_.yt -ge 3 }).Count
  }
}

# Istorija po timu (najnovije prvo)
$hist = @{}
foreach ($m in ($finished.Values | Sort-Object { [datetime]$_.utcDate } -Descending)) {
  $h = [int]$m.score.fullTime.home; $a = [int]$m.score.fullTime.away
  foreach ($side in 'home','away') {
    $team = if ($side -eq 'home') { $m.homeTeam } else { $m.awayTeam }
    $gf = if ($side -eq 'home') { $h } else { $a }
    $ga = if ($side -eq 'home') { $a } else { $h }
    $key = [string]$team.id
    if (-not $hist.ContainsKey($key)) { $hist[$key] = New-Object System.Collections.ArrayList }
    if ($hist[$key].Count -lt 10) {
      $res = if ($gf -gt $ga) { 'P' } elseif ($gf -eq $ga) { 'N' } else { 'I' }
      [void]$hist[$key].Add([pscustomobject]@{ gf = $gf; ga = $ga; res = $res })
    }
  }
}

function Get-Stats($teamId) {
  $g = $hist[[string]$teamId]
  if (-not $g -or $g.Count -lt 5) { return $null }
  $n = $g.Count
  [pscustomobject]@{
    n = $n
    gf = [math]::Round((($g | Measure-Object gf -Sum).Sum / $n), 2)
    ga = [math]::Round((($g | Measure-Object ga -Sum).Sum / $n), 2)
    scored = @($g | Where-Object { $_.gf -gt 0 }).Count
    conceded = @($g | Where-Object { $_.ga -gt 0 }).Count
    btts = @($g | Where-Object { $_.gf -gt 0 -and $_.ga -gt 0 }).Count
    o15 = @($g | Where-Object { ($_.gf + $_.ga) -ge 2 }).Count
    o25 = @($g | Where-Object { ($_.gf + $_.ga) -ge 3 }).Count
    o35 = @($g | Where-Object { ($_.gf + $_.ga) -ge 4 }).Count
    form = (($g | Select-Object -First 5 | ForEach-Object { $_.res }) -join '')
  }
}

function PoissonP($lambda, $k) {
  $f = 1.0; for ($i = 2; $i -le $k; $i++) { $f *= $i }
  return [math]::Exp(-$lambda) * [math]::Pow($lambda, $k) / $f
}
function PoissonOver($lambda, $line) {
  $below = 0.0; for ($k = 0; $k -le [math]::Floor($line); $k++) { $below += PoissonP $lambda $k }
  return 1 - $below
}
function Pct([double]$x) { [int][math]::Round([math]::Max([double]0.0, [math]::Min([double]1.0, $x)) * 100) }

$days = @{}
$todayLocal = [System.TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $tz).Date
foreach ($m in $upcoming.Values) {
  $utc = [datetime]::Parse($m.utcDate, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
  $local = [System.TimeZoneInfo]::ConvertTimeFromUtc($utc, $tz)
  if ($local.Date -lt $todayLocal -or $local.Date -gt $todayLocal.AddDays(21)) { continue }
  $hs = Get-Stats $m.homeTeam.id; $as = Get-Stats $m.awayTeam.id
  if (-not $hs -or -not $as) { continue }

  $lh = [math]::Max(0.2, (($hs.gf + $as.ga) / 2) * 1.08)
  $la = [math]::Max(0.2, (($as.gf + $hs.ga) / 2) * 0.94)
  $pH = 0.5 * (1 - [math]::Exp(-$lh)) + 0.5 * ((($hs.scored / $hs.n) + ($as.conceded / $as.n)) / 2)
  $pA = 0.5 * (1 - [math]::Exp(-$la)) + 0.5 * ((($as.scored / $as.n) + ($hs.conceded / $hs.n)) / 2)
  $bttsRate = (($hs.btts / $hs.n) + ($as.btts / $as.n)) / 2
  $tot = $lh + $la
  $o15 = 0.5 * (PoissonOver $tot 1.5) + 0.5 * ((($hs.o15 / $hs.n) + ($as.o15 / $as.n)) / 2)
  $o25 = 0.5 * (PoissonOver $tot 2.5) + 0.5 * ((($hs.o25 / $hs.n) + ($as.o25 / $as.n)) / 2)
  $o35 = 0.5 * (PoissonOver $tot 3.5) + 0.5 * ((($hs.o35 / $hs.n) + ($as.o35 / $as.n)) / 2)
  $w1 = 0.0; $dr = 0.0; $w2 = 0.0
  for ($i = 0; $i -le 8; $i++) { for ($j = 0; $j -le 8; $j++) {
    $p = (PoissonP $lh $i) * (PoissonP $la $j)
    if ($i -gt $j) { $w1 += $p } elseif ($i -eq $j) { $dr += $p } else { $w2 += $p }
  } }
  $s = $w1 + $dr + $w2
  $hc = Get-CStats $m.homeTeam.id; $ac = Get-CStats $m.awayTeam.id
  $pc8 = $null; $py3 = $null
  if ($hc -and $ac) {
    $lc = ($hc.cf + $ac.ca) / 2 + ($ac.cf + $hc.ca) / 2
    $pc8 = Pct (0.5 * (PoissonOver $lc 7.5) + 0.5 * ((($hc.c8 / $hc.n) + ($ac.c8 / $ac.n)) / 2))
    $ly = ($hc.yt + $ac.yt) / 2
    $py3 = Pct (0.5 * (PoissonOver $ly 2.5) + 0.5 * ((($hc.y3 / $hc.n) + ($ac.y3 / $ac.n)) / 2))
  }

  $dateKey = $local.ToString('yyyy-MM-dd')
  if (-not $days.ContainsKey($dateKey)) { $days[$dateKey] = New-Object System.Collections.ArrayList }
  [void]$days[$dateKey].Add([ordered]@{
    id = $m.id
    league = $comps[$m.compCode]
    time = $local.ToString('HH:mm')
    home = if ($m.homeTeam.shortName) { $m.homeTeam.shortName } else { $m.homeTeam.name }
    away = if ($m.awayTeam.shortName) { $m.awayTeam.shortName } else { $m.awayTeam.name }
    hl = $m.homeTeam.crest; al = $m.awayTeam.crest
    xg = @([math]::Round($lh, 2), [math]::Round($la, 2))
    p = [ordered]@{
      gg = Pct (0.5 * $pH * $pA + 0.5 * $bttsRate)
      o15 = Pct $o15; o25 = Pct $o25; o35 = Pct $o35; u25 = Pct (1 - $o25)
      hs = Pct $pH; as = Pct $pA
      w1 = Pct ($w1 / $s); x = Pct ($dr / $s); w2 = Pct ($w2 / $s)
      c8 = $pc8; y3 = $py3
    }
    hs = $hs; as = $as; hc = $hc; ac = $ac
  })
}

$dayList = foreach ($k in ($days.Keys | Sort-Object)) {
  [ordered]@{ date = $k; matches = @($days[$k] | Sort-Object { $_.time }) }
}
}   # kraj rezerve football-data.org
$todayLocal = [System.TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $tz).Date
$out = [ordered]@{
  generatedAt = [System.TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $tz).ToString('yyyy-MM-dd HH:mm')
  today = $todayLocal.ToString('yyyy-MM-dd')
  leagues = @($comps.Values)
  days = @($dayList)
}
try { & (Join-Path $root 'update_us.ps1') } catch { Write-Host "US sportovi preskoceni: $($_.Exception.Message)" }
try { & (Join-Path $root 'update_as.ps1') } catch { Write-Host "API-Sports preskocen: $($_.Exception.Message)" }
# NHL, hokej, rukomet, odbojka, NFL i MLB iskljuceni (26.9.2026) - ostaju fudbal i kosarka
$sports = [ordered]@{}
foreach ($f in 'us.json','as.json','nhl.json') {
  $p = Join-Path $root $f; if (-not (Test-Path $p)) { continue }
  $j = Get-Content -Raw -Encoding UTF8 $p | ConvertFrom-Json
  foreach ($prop in $j.PSObject.Properties) {
    $days = @($prop.Value.days | Where-Object { $_ -and $_.date })
    if ($sports.Contains($prop.Name)) {
      $byDate = @{}; foreach ($d in (@($sports[$prop.Name].days) + $days)) { if (-not $byDate.ContainsKey($d.date)) { $byDate[$d.date] = New-Object System.Collections.ArrayList }; foreach ($m in $d.matches) { [void]$byDate[$d.date].Add($m) } }
      $sports[$prop.Name] = [ordered]@{ days = @(foreach ($k in ($byDate.Keys | Sort-Object)) { [ordered]@{ date = $k; matches = @($byDate[$k] | Sort-Object { $_.time }) } }) }
    } else { $sports[$prop.Name] = [ordered]@{ days = $days } }
  }
}
foreach ($k in @($sports.Keys)) { if ($k -ne 'basketball') { $sports.Remove($k) } }
$out.sports = $sports
$json = $out | ConvertTo-Json -Depth 10
[IO.File]::WriteAllText((Join-Path $root 'data.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
try { & (Join-Path $root 'update_odds.ps1') } catch { Write-Host "Kvote preskocene: $($_.Exception.Message)" }
try { & (Join-Path $root 'tracker.ps1') } catch { Write-Host "Pracenje preskoceno: $($_.Exception.Message)" }
try { & (Join-Path $root 'build_logos.ps1') } catch { Write-Host "Grbovi preskoceni: $($_.Exception.Message)" }
Write-Host "Gotovo:$(@($dayList).Count) dana, $((@($dayList) | ForEach-Object { $_.matches.Count } | Measure-Object -Sum).Sum) utakmica"
