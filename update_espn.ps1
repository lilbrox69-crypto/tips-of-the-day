# NBA, NHL i NFL preko ESPN-a (besplatno, bez kljuca) - dodano 19.10.2026 umjesto balldontlie (update_us.ps1).
# Kvote su prave kvote DraftKingsa (ESPN): pobjednik (s produzecima) i vise/manje od linije kladionice.
# Samo prikaz na stranici - NE ulazi u statistiku, Rezultate ni Tiket dana (Bilal: "statistika samo fudbal").
# Prikazuju se utakmice "veceras/noceras": pocetak od danas 10:00 do sutra 07:00 po nasem vremenu, samo one koje imaju kvote.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$tz = [System.TimeZoneInfo]::FindSystemTimeZoneById('Central European Standard Time')
$nowLoc = [System.TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $tz)
$dayLoc = $nowLoc.Date
$fromUtc = [System.TimeZoneInfo]::ConvertTimeToUtc($dayLoc.AddHours(10), $tz)
$toUtc = [System.TimeZoneInfo]::ConvertTimeToUtc($dayLoc.AddDays(1).AddHours(7), $tz)
$inv = [Globalization.CultureInfo]::InvariantCulture

function Erf([double]$x) {
  $sg = [math]::Sign($x); $x = [math]::Abs($x); $t = 1 / (1 + 0.3275911 * $x)
  $y = 1 - (((((1.061405429 * $t - 1.453152027) * $t) + 1.421413741) * $t - 0.284496736) * $t + 0.254829592) * $t * [math]::Exp(-$x * $x)
  return $sg * $y
}
function Phi([double]$z) { return 0.5 * (1 + (Erf ($z / [math]::Sqrt(2)))) }
function PoisCdf([double]$lam, [int]$k) { $s = 0.0; $term = [math]::Exp(-$lam); for ($i = 0; $i -le $k; $i++) { if ($i -gt 0) { $term *= $lam / $i }; $s += $term }; return $s }
function Pct([double]$x) { [int][math]::Round([math]::Max(1.0, [math]::Min(99.0, $x * 100))) }
# americka kvota (-205 / +170) -> decimalna (1.49 / 2.70)
function Dec($am) {
  if ($am -eq $null) { return $null }; $s = ([string]$am).Trim(); if ($s -eq '' -or $s -eq 'EVEN') { if ($s -eq 'EVEN') { return 2.0 }; return $null }
  $v = [double]::Parse($s.TrimStart('+'), $inv); if ($v -eq 0) { return $null }
  if ($v -gt 0) { return [math]::Round(1 + $v / 100, 2) } else { return [math]::Round(1 + 100 / [math]::Abs($v), 2) }
}
function Esc([string]$s) { return [Net.WebUtility]::HtmlEncode($s) }
function Get-Espn($url) {
  for ($t = 0; $t -lt 3; $t++) { try { return Invoke-RestMethod $url -TimeoutSec 40 } catch { Write-Host "  ESPN greska: $($_.Exception.Message)"; Start-Sleep -Seconds 5 } }
  return $null
}
function Logo([string]$path, [string]$abbr) {
  if (-not $abbr) { return $null }
  return "https://a.espncdn.com/combiner/i?img=/i/teamlogos/$path/500/$($abbr.ToLower()).png&h=96&w=96"
}

# sport: kljuc na stranici, ESPN putanja, dani istorije, sd ukupno, sd razlike, prednost domaceg, poisson (hokej)
$LEAGUES = @(
  @{ key = 'basketball'; path = 'basketball/nba'; logo = 'nba'; name = 'NBA'; back = 14; sdT = 18.0; sdM = 12.5; adv = 2.0; pois = $false; unit = 'poena' }
  @{ key = 'hockey'; path = 'hockey/nhl'; logo = 'nhl'; name = 'NHL'; back = 14; sdT = 0; sdM = 2.1; adv = 0.15; pois = $true; unit = 'golova' }
  @{ key = 'nfl'; path = 'football/nfl'; logo = 'nfl'; name = 'NFL'; back = 42; sdT = 13.5; sdM = 13.5; adv = 1.5; pois = $false; unit = 'poena' }
)
$out = [ordered]@{}
foreach ($L in $LEAGUES) {
  Write-Host "ESPN $($L.name)"
  # 1) forma: zadnjih 10 zavrsenih utakmica svakog tima
  # ESPN ne prima raspon datuma - jedan poziv po danu (NFL samo dani kad se igra)
  $pastEv = New-Object System.Collections.ArrayList
  for ($i = 1; $i -le $L.back; $i++) {
    $pd = $dayLoc.AddDays(-$i)
    if ($L.key -eq 'nfl' -and $pd.DayOfWeek -notin 'Thursday', 'Saturday', 'Sunday', 'Monday') { continue }
    $r = Get-Espn "https://site.api.espn.com/apis/site/v2/sports/$($L.path)/scoreboard?dates=$($pd.ToString('yyyyMMdd'))"
    if ($r) { foreach ($e in $r.events) { [void]$pastEv.Add($e) } }
  }
  $hist = @{}
  if ($pastEv.Count) {
    $fin = @($pastEv | Where-Object { $_.status.type.completed -and $_.competitions[0].competitors.Count -eq 2 } | Sort-Object { [datetime]$_.date } -Descending)
    foreach ($e in $fin) {
      $cs = $e.competitions[0].competitors
      foreach ($c in $cs) {
        $o = @($cs | Where-Object { $_.id -ne $c.id })[0]
        $tid = [string]$c.id; if (-not $hist.ContainsKey($tid)) { $hist[$tid] = New-Object System.Collections.ArrayList }
        if ($hist[$tid].Count -lt 10) { [void]$hist[$tid].Add([pscustomobject]@{ pf = [double]$c.score; pa = [double]$o.score; w = [int]([double]$c.score -gt [double]$o.score) }) }
      }
    }
  }
  function TS($tid) {
    $g = $hist[[string]$tid]; if (-not $g -or $g.Count -lt 3) { return $null }
    $n = $g.Count
    [pscustomobject]@{ n = $n; pf = [math]::Round(($g | Measure-Object pf -Average).Average, 1); pa = [math]::Round(($g | Measure-Object pa -Average).Average, 1); w = ($g | Measure-Object w -Sum).Sum }
  }
  # 2) danasnje/vecerasnje utakmice s kvotama
  $evs = New-Object System.Collections.ArrayList
  foreach ($d in @($dayLoc, $dayLoc.AddDays(1))) {
    $sb = Get-Espn "https://site.api.espn.com/apis/site/v2/sports/$($L.path)/scoreboard?dates=$($d.ToString('yyyyMMdd'))"
    if ($sb) { foreach ($e in $sb.events) { if (-not @($evs | Where-Object { $_.id -eq $e.id }).Count) { [void]$evs.Add($e) } } }
  }
  $list = New-Object System.Collections.ArrayList
  foreach ($e in $evs) {
    $st = [datetime]::Parse($e.date, $inv, [Globalization.DateTimeStyles]::AdjustToUniversal)
    if ($st -lt $fromUtc -or $st -ge $toUtc) { continue }
    if ($e.status.type.state -ne 'pre') { continue }
    $c = $e.competitions[0]
    $hc = @($c.competitors | Where-Object { $_.homeAway -eq 'home' })[0]; $ac = @($c.competitors | Where-Object { $_.homeAway -eq 'away' })[0]
    $od = @($c.odds)[0]; if (-not $hc -or -not $ac -or -not $od) { continue }
    $o1 = Dec $od.moneyline.home.close.odds; $o2 = Dec $od.moneyline.away.close.odds
    $oo = Dec $od.total.over.close.odds; $ou = Dec $od.total.under.close.odds
    $line = $null; if ($od.overUnder) { $line = [double]$od.overUnder }
    if (-not $o1 -or -not $o2) { continue }   # bez kvota za pobjednika ne prikazujemo
    # trziste (kladionica) bez marze
    $mw = (1 / $o1) / ((1 / $o1) + (1 / $o2))
    $mo = if ($oo -and $ou) { (1 / $oo) / ((1 / $oo) + (1 / $ou)) } else { 0.5 }
    # model iz forme (ako oba tima imaju bar 3 utakmice), pa 45% model / 55% kladionica (isto kao fudbal)
    $hs = TS $hc.id; $as2 = TS $ac.id
    $pw = $mw; $po = $mo; $eh = $null; $ea = $null
    if ($hs -and $as2) {
      $eh = ($hs.pf + $as2.pa) / 2 + $L.adv / 2; $ea = ($as2.pf + $hs.pa) / 2 - $L.adv / 2
      $mm = $eh - $ea
      if ($L.pois) {
        $lam = [math]::Max(1.0, $eh + $ea)
        $mdlO = if ($line) { 1 - (PoisCdf $lam ([int][math]::Floor($line))) } else { 0.5 }
      } else { $mdlO = if ($line) { 1 - (Phi (($line - ($eh + $ea)) / $L.sdT)) } else { 0.5 } }
      $mdlW = Phi ($mm / $L.sdM)
      $pw = 0.45 * $mdlW + 0.55 * $mw; $po = 0.45 * $mdlO + 0.55 * $mo
    }
    $HN = Esc $hc.team.displayName; $AN = Esc $ac.team.displayName
    $recH = if ($hc.records) { [string]@($hc.records)[0].summary } else { '' }; $recA = if ($ac.records) { [string]@($ac.records)[0].summary } else { '' }
    $form = if ($hs -and $as2) { "Zadnjih $($hs.n): $HN $($hs.w)-$($hs.n - $hs.w), prosjek $($hs.pf):$($hs.pa) &middot; zadnjih $($as2.n): $AN $($as2.w)-$($as2.n - $as2.w), $($as2.pf):$($as2.pa)" } else { "Sezona tek počinje - procjena uglavnom iz kvota kladionice" }
    $rec = if ($recH -or $recA) { "<br>Omjer u sezoni: $HN $recH &middot; $AN $recA" } else { '' }
    $exp = if ($eh -ne $null) { "<br>Očekivano oko $([math]::Round($eh + $ea, 1)) $($L.unit)" } else { '' }
    $lnTxt = if ($line) { ('{0:0.0}' -f $line).Replace(',', '.') } else { '' }
    $p = [ordered]@{ w1 = Pct $pw; w2 = Pct (1 - $pw) }
    $q = [ordered]@{ w1 = $o1; w2 = $o2 }
    $why = [ordered]@{ w1 = "$form$rec<br>Kladionica: $HN $('{0:0}' -f ($mw * 100))% (s produžecima)"; w2 = "$form$rec<br>Kladionica: $AN $('{0:0}' -f ((1 - $mw) * 100))% (s produžecima)" }
    if ($line -and $oo -and $ou) {
      $p.ov = Pct $po; $p.un = Pct (1 - $po); $q.ov = $oo; $q.un = $ou
      $why.ov = "<b>Linija: više od $lnTxt</b> $($L.unit)$exp<br>$form"; $why.un = "<b>Linija: manje od $lnTxt</b> $($L.unit)$exp<br>$form"
    }
    $loc = [System.TimeZoneInfo]::ConvertTimeFromUtc($st, $tz)
    [void]$list.Add([pscustomobject]@{ utc = $st; m = [ordered]@{ id = "esp$($e.id)"; league = $L.name; time = $loc.ToString('HH:mm'); home = $hc.team.displayName; away = $ac.team.displayName
      hl = (Logo $L.logo $hc.team.abbreviation); al = (Logo $L.logo $ac.team.abbreviation); ln = $line; p = $p; o = $q; why = $why } })
  }
  $ms = @($list | Sort-Object utc | ForEach-Object { $_.m })
  Write-Host "  $($L.name): $($ms.Count) utakmica s kvotama"
  if ($ms.Count) { $out[$L.key] = [ordered]@{ days = @([ordered]@{ date = $dayLoc.ToString('yyyy-MM-dd'); matches = $ms }) } }
}
[IO.File]::WriteAllText((Join-Path $root 'espn.json'), ($out | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
