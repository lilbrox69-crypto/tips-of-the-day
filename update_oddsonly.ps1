# Sportovi samo s kvotama preko The Odds API (besplatno 500 kredita mjesecno) - dodano 19.10.2026: boks i MMA.
# Procenat = vjerovatnoca iz kvota kladionica bez marze (nema besplatne statistike boraca).
# Krediti: API se zove SAMO jednom dnevno (prvo pokretanje od 05h), poslije se koristi kes cache\oddsonly_<datum>.json.
# Samo prikaz na stranici - NE ulazi u statistiku, Rezultate, Tiket dana ni Facebook.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$key = (Get-Content -Raw -Encoding UTF8 (Join-Path $root 'config.json') | ConvertFrom-Json).oddsApiKey
$tz = [System.TimeZoneInfo]::FindSystemTimeZoneById('Central European Standard Time')
$nowLoc = [System.TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $tz)
$dayLoc = $nowLoc.Date
# nocno pokretanje (prije 05h) gleda jucerasnju vecer (borbe idu kasno u noc)
$anchor = if ($nowLoc.Hour -lt 5) { $dayLoc.AddDays(-1) } else { $dayLoc }
$fromUtc = [System.TimeZoneInfo]::ConvertTimeToUtc($anchor.AddHours(10), $tz)
$toUtc = [System.TimeZoneInfo]::ConvertTimeToUtc($anchor.AddDays(1).AddHours(8), $tz)
$inv = [Globalization.CultureInfo]::InvariantCulture
$enc = New-Object System.Text.UTF8Encoding($false)

# kljuc na stranici -> sport kod The Odds API (novi sport = novi red; totals = i vise/manje od linije, kosta 2 kredita)
$SPORTS = @(
  @{ key = 'boxing'; api = 'boxing_boxing'; name = 'Boks'; totals = $false }
  @{ key = 'mma'; api = 'mma_mixed_martial_arts'; name = 'MMA'; totals = $false }
)

$cacheFile = Join-Path $root "cache\oddsonly_$($anchor.ToString('yyyy-MM-dd')).json"
$raw = @{}
if (Test-Path $cacheFile) {
  (Get-Content -Raw -Encoding UTF8 $cacheFile | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $raw[$_.Name] = @($_.Value) }
  Write-Host 'Boks/MMA: koristim jutarnje kvote (bez trosenja kredita)'
} elseif ($key -and $nowLoc.Hour -ge 5) {
  foreach ($S in $SPORTS) {
    $mk = if ($S.totals) { 'h2h,totals' } else { 'h2h' }
    try {
      $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 40 "https://api.the-odds-api.com/v4/sports/$($S.api)/odds?regions=eu&markets=$mk&oddsFormat=decimal&apiKey=$key"
      $arr = $r.Content | ConvertFrom-Json; $raw[$S.key] = @($arr)   # PS 5.1: niz iz JSON-a prvo dodijeliti
      Write-Host "  $($S.name): $(@($raw[$S.key]).Count) dogadjaja, krediti preostalo $($r.Headers['x-requests-remaining'])"
    } catch { Write-Host "  $($S.name) greska: $($_.Exception.Message)" }
  }
  if ($raw.Count) { [IO.File]::WriteAllText($cacheFile, ($raw | ConvertTo-Json -Depth 12 -Compress), $enc) }
  # stari kes (stariji od 3 dana) brisi
  Get-ChildItem (Join-Path $root 'cache') -Filter 'oddsonly_*.json' | Where-Object { $_.Name -lt "oddsonly_$($anchor.AddDays(-3).ToString('yyyy-MM-dd')).json" } | Remove-Item -Force -ErrorAction SilentlyContinue
} else { Write-Host 'Boks/MMA: nema kesa, a prije 05h se krediti ne trose' }

function Median($a) { $s = @($a | Sort-Object); if (-not $s.Count) { return $null }; $n = $s.Count; if ($n % 2) { return [double]$s[[int](($n - 1) / 2)] }; return ([double]$s[$n / 2 - 1] + [double]$s[$n / 2]) / 2 }
function Pct([double]$x) { [int][math]::Round([math]::Max(1.0, [math]::Min(99.0, $x * 100))) }
function Esc([string]$s) { return [Net.WebUtility]::HtmlEncode($s) }

$out = [ordered]@{}
foreach ($S in $SPORTS) {
  $list = New-Object System.Collections.ArrayList
  foreach ($e in @($raw[$S.key])) {
    if (-not $e -or -not $e.commence_time) { continue }
    $st = [datetime]::Parse($e.commence_time, $inv, [Globalization.DateTimeStyles]::AdjustToUniversal)
    if ($st -lt $fromUtc -or $st -ge $toUtc) { continue }
    $hn = [string]$e.home_team; $an = [string]$e.away_team
    # kvota = srednja (medijan) od svih kladionica
    $ph = @(); $pa = @(); $tl = @{}
    foreach ($b in @($e.bookmakers)) { foreach ($m in @($b.markets)) {
      if ($m.key -eq 'h2h') { foreach ($o in @($m.outcomes)) { if ($o.name -eq $hn) { $ph += [double]$o.price } elseif ($o.name -eq $an) { $pa += [double]$o.price } } }
      if ($m.key -eq 'totals') { foreach ($o in @($m.outcomes)) { $lk = [string]$o.point; if (-not $tl[$lk]) { $tl[$lk] = @{ Over = @(); Under = @() } }; if ($o.name -in 'Over', 'Under') { $tl[$lk][$o.name] += [double]$o.price } } }
    } }
    $o1 = Median $ph; $o2 = Median $pa
    if (-not $o1 -or -not $o2 -or $ph.Count -lt 2) { continue }   # bar 2 kladionice
    $o1 = [math]::Round($o1, 2); $o2 = [math]::Round($o2, 2)
    $pw = (1 / $o1) / ((1 / $o1) + (1 / $o2))
    $HNe = Esc $hn; $ANe = Esc $an   # PS: $hn i $HN su ista varijabla!
    $p = [ordered]@{ w1 = Pct $pw; w2 = Pct (1 - $pw) }; $q = [ordered]@{ w1 = $o1; w2 = $o2 }
    $src = "Procjena iz kvota $($ph.Count) kladionica (bez marže)"
    $why = [ordered]@{ w1 = "$src<br>$HNe $([int][math]::Round($pw * 100))% &middot; $ANe $([int][math]::Round((1 - $pw) * 100))%"; w2 = "$src<br>$ANe $([int][math]::Round((1 - $pw) * 100))% &middot; $HNe $([int][math]::Round($pw * 100))%" }
    $line = $null
    if ($S.totals -and $tl.Count) {
      $best = $tl.GetEnumerator() | Sort-Object { - ([math]::Min($_.Value.Over.Count, $_.Value.Under.Count)) } | Select-Object -First 1
      $oo = Median $best.Value.Over; $ou = Median $best.Value.Under
      if ($oo -and $ou) { $line = [double]::Parse($best.Key, $inv); $po = (1 / $oo) / ((1 / $oo) + (1 / $ou))
        $p.ov = Pct $po; $p.un = Pct (1 - $po); $q.ov = [math]::Round($oo, 2); $q.un = [math]::Round($ou, 2)
        $why.ov = "<b>Linija: više od $($best.Key)</b><br>$src"; $why.un = "<b>Linija: manje od $($best.Key)</b><br>$src" }
    }
    $loc = [System.TimeZoneInfo]::ConvertTimeFromUtc($st, $tz)
    [void]$list.Add([pscustomobject]@{ utc = $st; m = [ordered]@{ id = "odd$($e.id)"; league = $S.name; time = $loc.ToString('HH:mm'); home = $hn; away = $an; ln = $line; p = $p; o = $q; why = $why } })
  }
  $ms = @($list | Sort-Object utc | ForEach-Object { $_.m })
  Write-Host "  $($S.name): $($ms.Count) za danas/noćas"
  if ($ms.Count) { $out[$S.key] = [ordered]@{ days = @([ordered]@{ date = $dayLoc.ToString('yyyy-MM-dd'); matches = $ms }) } }
}
[IO.File]::WriteAllText((Join-Path $root 'oddsonly.json'), ($out | ConvertTo-Json -Depth 8), $enc)
