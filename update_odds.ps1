# Kvote preko The Odds API (besplatno 500 kredita/mjesec). Dopisuje "o" (kvote) danasnjim utakmicama u data.json.
# Jedan poziv = 2 kredita (h2h + totals, regija eu). Dnevni budzet = preostali krediti / preostali dani u mjesecu.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$key = (Get-Content -Raw -Encoding UTF8 (Join-Path $root 'config.json') | ConvertFrom-Json).oddsApiKey
if (-not $key) { Write-Host 'Kvote: nema kljuca'; return }
$tz = [System.TimeZoneInfo]::FindSystemTimeZoneById('Central European Standard Time')
$enc = New-Object System.Text.UTF8Encoding($false)
$dataFile = Join-Path $root 'data.json'
$data = Get-Content -Raw -Encoding UTF8 $dataFile | ConvertFrom-Json
$today = $data.today
$cacheDir = Join-Path $root 'cache'; New-Item -ItemType Directory -Force $cacheDir | Out-Null

# nasa liga -> kljuc sporta kod The Odds API
$MAP = [ordered]@{
  'Liga prvaka' = 'soccer_uefa_champs_league'; 'Premier liga' = 'soccer_epl'; 'La Liga' = 'soccer_spain_la_liga'; 'Serie A' = 'soccer_italy_serie_a'
  'Bundesliga' = 'soccer_germany_bundesliga'; 'Ligue 1' = 'soccer_france_ligue_one'; 'Eredivisie' = 'soccer_netherlands_eredivisie'
  'Primeira Liga' = 'soccer_portugal_primeira_liga'; 'Championship' = 'soccer_efl_champ'; 'Brasileirao' = 'soccer_brazil_campeonato'; 'Copa Libertadores' = 'soccer_conmebol_copa_libertadores'
  'NBA' = 'basketball_nba'; 'Euroleague (Europe)' = 'basketball_euroleague'
  'NHL (USA)' = 'icehockey_nhl'; 'Liiga (Finland)' = 'icehockey_liiga'; 'SHL (Sweden)' = 'icehockey_sweden_hockey_league'
  'Bundesliga (Germany)' = 'handball_germany_bundesliga'; 'NFL' = 'americanfootball_nfl'; 'MLB' = 'baseball_mlb'
}
# totals linija -> nase opcije [over, under] po sportu
$TOT = @{
  football = @{ '2.5' = @('o25','u25'); '1.5' = @('o15',$null) }
  hockey = @{ '5.5' = @('o55','u55'); '4.5' = @('o45',$null) }
  handball = @{ '55.5' = @('o55','u55') }; nfl = @{ '45.5' = @('o45','u45') }; mlb = @{ '8.5' = @('o85','u85') }
  basketball = @{ '220.5' = @('o220','u220'); '160.5' = @('o160','u160') }
}

function Norm([string]$s) {
  $s = $s.Normalize([Text.NormalizationForm]::FormD)
  $s = -join ($s.ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' })
  $s = $s.ToLower() -replace "nott'm", 'nottingham' -replace '\butd\b', 'united' -replace '\bman\b', 'manchester' -replace '\bwolves\b', 'wolverhampton' -replace "[^a-z0-9 ]", ' '
  ($s -split '\s+' | Where-Object { $_ -and $_ -notin @('fc','afc','cf','sc','ac','as','ss','club','de','cd','ud','sd','rc','rcd','sv','vfl','vfb','tsg','fsv','bv','ssc','us','ogc','stade','the','calcio','and') }) -join ' '
}
function Grams([string]$s) { $s = " $s "; $g = @{}; for ($i = 0; $i -lt $s.Length - 2; $i++) { $g[$s.Substring($i,3)] = 1 }; return $g }
function Sim([string]$a, [string]$b) {
  $ga = Grams (Norm $a); $gb = Grams (Norm $b); $inter = 0
  foreach ($k in $ga.Keys) { if ($gb.ContainsKey($k)) { $inter++ } }
  $union = $ga.Count + $gb.Count - $inter; if ($union -eq 0) { return 0 }; return $inter / $union
}
function Median($xs) { $s = @($xs | Sort-Object); if ($s.Count -eq 0) { return $null }; $m = [int][math]::Floor($s.Count / 2); if ($s.Count % 2) { $s[$m] } else { ($s[$m - 1] + $s[$m]) / 2 } }

# danasnje utakmice po sportu i kljucu
$todayLists = @{ football = @(($data.days | Where-Object { $_.date -eq $today }).matches) }
foreach ($p in $data.sports.PSObject.Properties) { $todayLists[$p.Name] = @(($p.Value.days | Where-Object { $_.date -eq $today }).matches) }
$want = @{}   # oddsKey -> @{ sport; matches }
foreach ($sport in $todayLists.Keys) {
  foreach ($m in $todayLists[$sport]) {
    if (-not $m) { continue }
    if ([string]$m.id -like 'af*') { continue }
    $m.PSObject.Properties.Remove('o')
    $k = $MAP[[string]$m.league]; if (-not $k) { continue }
    if ($sport -eq 'football' -and $k -like 'handball*') { continue }
    if ($sport -eq 'handball' -and $k -notlike 'handball*') { continue }
    if (-not $want.ContainsKey($k)) { $want[$k] = @{ sport = $sport; matches = New-Object System.Collections.ArrayList } }
    [void]$want[$k].matches.Add($m)
  }
}
if ($want.Count -eq 0) { Write-Host 'Kvote: danas nema utakmica u ligama sa kvotama'; return }

# budzet
$stateFile = Join-Path $cacheDir 'odds_state.json'
$remaining = 500; if (Test-Path $stateFile) { $st = Get-Content -Raw $stateFile | ConvertFrom-Json; if ($st.month -eq $today.Substring(0,7)) { $remaining = [int]$st.remaining } }
$d = [datetime]::ParseExact($today, 'yyyy-MM-dd', $null)
$daysLeft = [DateTime]::DaysInMonth($d.Year, $d.Month) - $d.Day + 1
$budget = [math]::Floor($remaining / $daysLeft)

$filled = 0; $calls = 0
foreach ($k in ($want.Keys | Sort-Object { - $want[$_].matches.Count })) {
  $cf = Join-Path $cacheDir "odds_${today}_$k.json"
  $events = $null
  if (Test-Path $cf) { $events = Get-Content -Raw -Encoding UTF8 $cf | ConvertFrom-Json }
  elseif ($budget -ge 2) {
    try {
      $r = Invoke-WebRequest "https://api.the-odds-api.com/v4/sports/$k/odds?regions=eu&markets=h2h,totals&oddsFormat=decimal&apiKey=$key" -UseBasicParsing -TimeoutSec 30
      $remaining = [int]$r.Headers['x-requests-remaining']; $budget -= 2; $calls++
      [IO.File]::WriteAllText($cf, $r.Content, $enc)
      $events = $r.Content | ConvertFrom-Json
    } catch { Write-Host "  kvote greska $k : $($_.Exception.Message)" }
  }
  if (-not $events) { continue }
  $sport = $want[$k].sport
  foreach ($m in $want[$k].matches) {
    $best = $null; $bs = 0
    foreach ($e in $events) {
      $loc = [System.TimeZoneInfo]::ConvertTimeFromUtc(([datetime]::Parse($e.commence_time, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)), $tz)
      if ($loc.ToString('yyyy-MM-dd') -ne $today) { continue }
      $sh = Sim $m.home $e.home_team; $sa = Sim $m.away $e.away_team
      if ($sh -lt 0.2 -or $sa -lt 0.2) { continue }
      $sc = $sh + $sa - [math]::Abs(($loc.TimeOfDay - [timespan]::Parse($m.time)).TotalHours) * 0.05   # dupli mec istog dana: blize vrijeme pobjedjuje
      if ($sc -gt $bs) { $bs = $sc; $best = $e }
    }
    if (-not $best) { continue }
    $o = [ordered]@{}; $h2h = @{ w1 = @(); x = @(); w2 = @() }; $tot = @{}
    foreach ($bk in $best.bookmakers) {
      foreach ($mk in $bk.markets) {
        if ($mk.key -eq 'h2h') {
          foreach ($oc in $mk.outcomes) {
            if ($oc.name -eq $best.home_team) { $h2h.w1 += [double]$oc.price } elseif ($oc.name -eq $best.away_team) { $h2h.w2 += [double]$oc.price } elseif ($oc.name -eq 'Draw') { $h2h.x += [double]$oc.price }
          }
        } elseif ($mk.key -eq 'totals' -and $TOT[$sport]) {
          foreach ($oc in $mk.outcomes) {
            $pt = ([double]$oc.point).ToString([Globalization.CultureInfo]::InvariantCulture)
            $pair = $TOT[$sport][$pt]; if (-not $pair) { continue }
            $ok = if ($oc.name -eq 'Over') { $pair[0] } else { $pair[1] }
            if ($ok) { if (-not $tot.ContainsKey($ok)) { $tot[$ok] = @() }; $tot[$ok] += [double]$oc.price }
          }
        }
      }
    }
    # hokej: nasa pobjeda ukljucuje produzetke, pa kvote iz 3-way (sa X) ne vaze
    if (-not ($sport -eq 'hockey' -and $h2h.x.Count)) { foreach ($kk in 'w1','x','w2') { $v = Median $h2h[$kk]; if ($v) { $o[$kk] = [math]::Round($v, 2) } } }
    foreach ($kk in $tot.Keys) { $v = Median $tot[$kk]; if ($v) { $o[$kk] = [math]::Round($v, 2) } }
    if ($o.Count) { $m | Add-Member -NotePropertyName o -NotePropertyValue $o -Force; $filled++ }
  }
}
[IO.File]::WriteAllText($stateFile, (@{ month = $today.Substring(0,7); remaining = $remaining } | ConvertTo-Json), $enc)
[IO.File]::WriteAllText($dataFile, ($data | ConvertTo-Json -Depth 12), $enc)
Write-Host "Kvote: $filled utakmica, $calls poziva, ostalo kredita $remaining"
