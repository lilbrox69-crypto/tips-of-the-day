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
if (Test-Path $pf) { $parr = Get-Content -Raw -Encoding UTF8 $pf | ConvertFrom-Json; foreach ($pp in $parr) { if ($pp -and $pp.hit -eq $null -and $pp.date -lt $today -and [string]$pp.key -like 'football:af*') { $ids += ([string]$pp.key).Substring(11) } } }
# + utakmice iz tiketa koje jos cekaju rezultat
$tfile = Join-Path $cacheDir 'tickets.json'
if (Test-Path $tfile) { $tarr = Get-Content -Raw -Encoding UTF8 $tfile | ConvertFrom-Json; foreach ($t in $tarr) { if ($t -and $t.hit -eq $null -and $t.date -lt $today) { foreach ($l in $t.legs) { if ([string]$l.key -like 'football:af*') { $ids += ([string]$l.key).Substring(11) } } } } }
$ids = @($ids | Select-Object -Unique)
$idPaths = @(); for ($i = 0; $i -lt $ids.Count; $i += 20) { $idPaths += 'fixtures?ids=' + (($ids[$i..([math]::Min($i + 19, $ids.Count - 1))]) -join '-') }
$sres = Get-Many $idPaths
foreach ($r in $sres.Values) { Save-FxStats $r.response }
[IO.File]::WriteAllText($fxFile, ($fxStats | ConvertTo-Json -Depth 3 -Compress), $enc)

# ---------- 4) kvote: sve kladionice, srednja vrijednost (medijan) po opciji ----------
$odds = @{}
$o1 = Get-One "odds?date=$today&timezone=Europe/Sarajevo&page=1"
$oPages = @($o1)
if ($o1 -and $o1.paging.total -gt 1) { $more = Get-Many @(2..$o1.paging.total | ForEach-Object { "odds?date=$today&timezone=Europe/Sarajevo&page=$_" }); $oPages += @($more.Values) }
function Median($xs) { $s = @($xs | Sort-Object); if ($s.Count -eq 0) { return $null }; $m = [int][math]::Floor($s.Count / 2); if ($s.Count % 2) { $s[$m] } else { ($s[$m - 1] + $s[$m]) / 2 } }
$map = @(@('w1',1,'Home'), @('x',1,'Draw'), @('w2',1,'Away'), @('o15',5,'Over 1.5'), @('o25',5,'Over 2.5'), @('u25',5,'Under 2.5'),
  @('gg',8,'Yes'), @('hs',28,'No'), @('hs',43,'Yes'), @('hs',16,'Over 0.5'), @('as',27,'No'), @('as',44,'Yes'), @('as',17,'Over 0.5'),
  @('c8',45,'Over 7.5'), @('y3',80,'Over 2.5'))
foreach ($pg in $oPages) {
  foreach ($r in $pg.response) {
    $vals = @{}
    foreach ($bk in $r.bookmakers) {
      foreach ($m in $map) {
        $b = @($bk.bets | Where-Object { $_.id -eq $m[1] })[0]; if (-not $b) { continue }
        $v = @($b.values | Where-Object { [string]$_.value -eq $m[2] })[0]; if (-not $v) { continue }
        if (-not $vals.ContainsKey($m[0])) { $vals[$m[0]] = New-Object System.Collections.ArrayList }
        [void]$vals[$m[0]].Add([double]$v.odd)
      }
    }
    $o = [ordered]@{}; foreach ($mk in @($map | ForEach-Object { $_[0] } | Select-Object -Unique)) { if ($vals.ContainsKey($mk)) { $o[$mk] = [math]::Round((Median $vals[$mk]), 2) } }
    if ($o.Count) { $odds[[string]$r.fixture.id] = $o }
  }
}
Write-Host "  kvote: $($odds.Count) utakmica, $(@($oPages).Count) stranica"
# ---------- 5) procenti ----------
# Forma: zadnjih 10 (novije vrijede vise, 0.9^i) + zadnjih 6 na istom terenu (domacin kod kuce, gost u gostima).
# Prikaz na kartici i dalje pokazuje obicnih zadnjih 10.
function Rows($list, $t) { @($list | ForEach-Object { $h = $_.hid -eq $t; $gf = if ($h) { $_.hg } else { $_.ag }; $ga = if ($h) { $_.ag } else { $_.hg }
  [pscustomobject]@{ gf = [double]$gf; ga = [double]$ga; res = $(if ($gf -gt $ga) { 'P' } elseif ($gf -eq $ga) { 'N' } else { 'I' }) } }) }
function Get-Stats($t, $venue) {
  $g = $last[$t]; if (-not $g -or $g.Count -lt 8) { return $null }
  $rows = Rows $g $t
  $n = $rows.Count
  $vg = @($hist[$t] | Where-Object { if ($venue -eq 'h') { $_.hid -eq $t } else { $_.aid -eq $t } } | Sort-Object { [datetime]$_.d } -Descending | Select-Object -First 6)
  $vrows = Rows $vg $t
  $W = 0.0; $acc = @{ gf = 0.0; ga = 0.0; scored = 0.0; conceded = 0.0; btts = 0.0; o15 = 0.0; o25 = 0.0 }
  $add = { param($r, $w) $script:W += $w; $acc.gf += $w * $r.gf; $acc.ga += $w * $r.ga; $acc.scored += $w * [int]($r.gf -gt 0); $acc.conceded += $w * [int]($r.ga -gt 0)
    $acc.btts += $w * [int]($r.gf -gt 0 -and $r.ga -gt 0); $acc.o15 += $w * [int](($r.gf + $r.ga) -ge 2); $acc.o25 += $w * [int](($r.gf + $r.ga) -ge 3) }
  $script:W = 0.0
  for ($i = 0; $i -lt $rows.Count; $i++) { & $add $rows[$i] ([math]::Pow(0.9, $i)) }
  if ($vrows.Count -ge 3) { for ($i = 0; $i -lt $vrows.Count; $i++) { & $add $vrows[$i] ([math]::Pow(0.9, $i)) } }
  $wr = [pscustomobject]@{ gf = $acc.gf / $script:W; ga = $acc.ga / $script:W; scored = $acc.scored / $script:W; conceded = $acc.conceded / $script:W
    btts = $acc.btts / $script:W; o15 = $acc.o15 / $script:W; o25 = $acc.o25 / $script:W }
  [pscustomobject]@{ n = $n; gf = [math]::Round((($rows | Measure-Object gf -Sum).Sum / $n), 2); ga = [math]::Round((($rows | Measure-Object ga -Sum).Sum / $n), 2)
    scored = @($rows | Where-Object { $_.gf -gt 0 }).Count; conceded = @($rows | Where-Object { $_.ga -gt 0 }).Count
    btts = @($rows | Where-Object { $_.gf -gt 0 -and $_.ga -gt 0 }).Count; o15 = @($rows | Where-Object { ($_.gf + $_.ga) -ge 2 }).Count
    o25 = @($rows | Where-Object { ($_.gf + $_.ga) -ge 3 }).Count; o35 = @($rows | Where-Object { ($_.gf + $_.ga) -ge 4 }).Count
    form = (($rows | Select-Object -First 5 | ForEach-Object { $_.res }) -join ''); wr = $wr }
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
# povrede: svaki igrac koji sigurno ne igra smanjuje ocekivane golove tima za 4% (najvise 20%)
function CalcP($hs, $as, $hc, $ac, [int]$injH, [int]$injA) {
  $h = $hs.wr; $a = $as.wr
  $lh = [math]::Max(0.2, (($h.gf + $a.ga) / 2) * 1.08 * (1 - [math]::Min(0.2, 0.04 * $injH)) * (1 + [math]::Min(0.1, 0.02 * $injA)))
  $la = [math]::Max(0.2, (($a.gf + $h.ga) / 2) * 0.94 * (1 - [math]::Min(0.2, 0.04 * $injA)) * (1 + [math]::Min(0.1, 0.02 * $injH)))
  $pH = 0.5 * (1 - [math]::Exp(-$lh)) + 0.5 * (($h.scored + $a.conceded) / 2)
  $pA = 0.5 * (1 - [math]::Exp(-$la)) + 0.5 * (($a.scored + $h.conceded) / 2)
  $bt = ($h.btts + $a.btts) / 2; $tot = $lh + $la
  $o15 = 0.5 * (PoissonOver $tot 1.5) + 0.5 * (($h.o15 + $a.o15) / 2)
  $o25 = 0.5 * (PoissonOver $tot 2.5) + 0.5 * (($h.o25 + $a.o25) / 2)
  $w1 = 0.0; $dr = 0.0; $w2 = 0.0
  for ($i = 0; $i -le 8; $i++) { for ($j = 0; $j -le 8; $j++) { $q = (PoissonP $lh $i) * (PoissonP $la $j); if ($i -gt $j) { $w1 += $q } elseif ($i -eq $j) { $dr += $q } else { $w2 += $q } } }
  $sum = $w1 + $dr + $w2
  $pc8 = $null; $py3 = $null
  if ($hc -and $ac) {
    $lc = ($hc.cf + $ac.ca) / 2 + ($ac.cf + $hc.ca) / 2
    $pc8 = Pct (0.5 * (PoissonOver $lc 7.5) + 0.5 * ((($hc.c8 / $hc.n) + ($ac.c8 / $ac.n)) / 2))
    $py3 = Pct (0.5 * (PoissonOver (($hc.yt + $ac.yt) / 2) 2.5) + 0.5 * ((($hc.y3 / $hc.n) + ($ac.y3 / $ac.n)) / 2))
  }
  @{ xg = @([math]::Round($lh, 2), [math]::Round($la, 2))
     p = [ordered]@{ gg = Pct (0.5 * $pH * $pA + 0.5 * $bt); o15 = Pct $o15; o25 = Pct $o25; u25 = Pct (1 - $o25); hs = Pct $pH; as = Pct $pA
       w1 = Pct ($w1 / $sum); x = Pct ($dr / $sum); w2 = Pct ($w2 / $sum); c8 = $pc8; y3 = $py3 } }
}

$list = New-Object System.Collections.ArrayList
$pairs = @{}; $ctx = @{}
foreach ($g in $games) {
  $ht = [string]$g.teams.home.id; $at = [string]$g.teams.away.id
  $hs = Get-Stats $ht 'h'; $as = Get-Stats $at 'a'; if (-not $hs -or -not $as) { continue }
  $hc = Get-CStats $ht; $ac = Get-CStats $at
  $c = CalcP $hs $as $hc $ac 0 0
  $utc = [datetime]::Parse($g.fixture.date, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
  $local = [System.TimeZoneInfo]::ConvertTimeFromUtc($utc, $tz)
  $m = [ordered]@{ id = "af$($g.fixture.id)"; league = "$($g.league.name) ($($g.league.country))"; time = $local.ToString('HH:mm')
    home = $g.teams.home.name; away = $g.teams.away.name; hl = $g.teams.home.logo; al = $g.teams.away.logo
    xg = $c.xg; p = $c.p
    hs = ($hs | Select-Object * -ExcludeProperty wr); as = ($as | Select-Object * -ExcludeProperty wr); hc = $hc; ac = $ac }
  $oo = $odds[[string]$g.fixture.id]; if ($oo) { $m.o = $oo }
  $pairs[$m.id] = @($ht, $at); $ctx[$m.id] = @($hs, $as, $hc, $ac)
  [void]$list.Add($m)
}

# ---------- 5b) povrede i suspenzije za kandidate za top 3 ----------
$icand = @{}
foreach ($mk in 'gg','o15','o25','u25','hs','as','w1','x','w2','c8','y3') { foreach ($m in @($list | Where-Object { $_.p[$mk] -ne $null } | Sort-Object { - [int]$_.p[$mk] } | Select-Object -First 12)) { $icand[$m.id] = $m } }
$ipaths = @{}; foreach ($id in $icand.Keys) { $ipaths[$id] = "injuries?fixture=$($id.Substring(2))" }
$ires = Get-Many @($ipaths.Values)
$nI = 0
foreach ($id in $icand.Keys) {
  $r = $ires[$ipaths[$id]]; if (-not $r -or -not $r.results) { continue }
  $out_ = @($r.response | Where-Object { $_.player.type -eq 'Missing Fixture' })
  $nh = @($out_ | Where-Object { [string]$_.team.id -eq $pairs[$id][0] }).Count; $na = @($out_ | Where-Object { [string]$_.team.id -eq $pairs[$id][1] }).Count
  if ($nh + $na -eq 0) { continue }
  $x = $ctx[$id]; $c = CalcP $x[0] $x[1] $x[2] $x[3] $nh $na
  $m = $icand[$id]; $m.p = $c.p; $m.xg = $c.xg; $m.inj = @($nh, $na); $nI++
}
Write-Host "  povrede: uracunate za $nI utakmica ($($icand.Count) kandidata)"
# ---------- 6) medjusobni susreti (zadnjih 5) za kandidate za top 3 ----------
$H2HM = @('gg','o15','o25','u25','hs','as','w1','x','w2')
$cand = @{}
foreach ($mk in $H2HM) { foreach ($m in @($list | Where-Object { $_.p[$mk] -ne $null } | Sort-Object { - [int]$_.p[$mk] } | Select-Object -First 12)) { $cand[$m.id] = $m } }
$hpaths = @{}; foreach ($id in $cand.Keys) { $hpaths[$id] = "fixtures/headtohead?h2h=$($pairs[$id][0])-$($pairs[$id][1])&last=8" }
$hres = Get-Many @($hpaths.Values)
$nH = 0
foreach ($id in $cand.Keys) {
  $r = $hres[$hpaths[$id]]; if (-not $r) { continue }
  $ht = $pairs[$id][0]
  $games = @($r.response | Where-Object { $_.fixture.status.short -in $FIN } | Sort-Object { [datetime]$_.fixture.date } -Descending | Select-Object -First 5)
  if ($games.Count -lt 3) { continue }
  $rows = @($games | ForEach-Object { $c = Compact $_; $isH = $c.hid -eq $ht
    [pscustomobject]@{ gf = $(if ($isH) { $c.hg } else { $c.ag }); ga = $(if ($isH) { $c.ag } else { $c.hg }) } })
  $n = $rows.Count
  $rate = @{
    gg = @($rows | Where-Object { $_.gf -gt 0 -and $_.ga -gt 0 }).Count / $n; o15 = @($rows | Where-Object { ($_.gf + $_.ga) -ge 2 }).Count / $n
    o25 = @($rows | Where-Object { ($_.gf + $_.ga) -ge 3 }).Count / $n; u25 = @($rows | Where-Object { ($_.gf + $_.ga) -le 2 }).Count / $n
    hs = @($rows | Where-Object { $_.gf -gt 0 }).Count / $n; as = @($rows | Where-Object { $_.ga -gt 0 }).Count / $n
    w1 = @($rows | Where-Object { $_.gf -gt $_.ga }).Count / $n; x = @($rows | Where-Object { $_.gf -eq $_.ga }).Count / $n; w2 = @($rows | Where-Object { $_.gf -lt $_.ga }).Count / $n }
  $wt = 0.25 * $n / 5   # do 25% uticaja; manje ako ima manje od 5 susreta
  $m = $cand[$id]
  foreach ($mk in $H2HM) { if ($m.p[$mk] -ne $null) { $m.p[$mk] = [int][math]::Round((1 - $wt) * $m.p[$mk] + $wt * $rate[$mk] * 100) } }
  $m.h2h = [ordered]@{ n = $n; w = @($rows | Where-Object { $_.gf -gt $_.ga }).Count; d = @($rows | Where-Object { $_.gf -eq $_.ga }).Count; l = @($rows | Where-Object { $_.gf -lt $_.ga }).Count
    gf = ($rows | Measure-Object gf -Sum).Sum; ga = ($rows | Measure-Object ga -Sum).Sum; res = (($rows | ForEach-Object { "$($_.gf)-$($_.ga)" }) -join ', ') }
  $nH++
}
Write-Host "  H2H: $nH utakmica ($($cand.Count) kandidata)"
# ---------- 7) sigurnije: mijesanje sa trzistem (kvote) i samo utakmice koje kladionice nude ----------
function Imp($o, $k) { if ($o.Contains($k) -and $o[$k] -gt 1) { return 1 / [double]$o[$k] } ; return $null }
foreach ($m in $list) {
  $o = $m.o; if (-not $o) { continue }
  $imp = @{}
  $a = Imp $o 'w1'; $b = Imp $o 'x'; $c = Imp $o 'w2'
  if ($a -and $b -and $c) { $t = $a + $b + $c; $imp.w1 = $a / $t; $imp.x = $b / $t; $imp.w2 = $c / $t }
  $ov = Imp $o 'o25'; $un = Imp $o 'u25'
  if ($ov -and $un) { $imp.o25 = $ov / ($ov + $un); $imp.u25 = $un / ($ov + $un) } elseif ($ov) { $imp.o25 = $ov * 0.95 } elseif ($un) { $imp.u25 = $un * 0.95 }
  foreach ($k in 'o15','gg','hs','as','c8','y3') { $v = Imp $o $k; if ($v) { $imp[$k] = [math]::Min(0.99, $v * 0.95) } }   # 5% marza kladionice
  foreach ($k in $imp.Keys) { if ($m.p[$k] -ne $null) { $m.p[$k] = [int][math]::Round(0.65 * $m.p[$k] + 0.35 * $imp[$k] * 100) } }
}
$withOdds = @($list | Where-Object { $_.o })
if ($withOdds.Count -ge 20) { Write-Host "  samo utakmice sa kvotama: $($withOdds.Count) od $($list.Count)"; $list = New-Object System.Collections.ArrayList (, $withOdds) }
$out = [ordered]@{ date = $today; days = @([ordered]@{ date = $today; matches = @($list | Sort-Object { $_.time }) }) }
[IO.File]::WriteAllText((Join-Path $root 'af.json'), ($out | ConvertTo-Json -Depth 8), $enc)
Write-Host "API-Football gotovo: $($list.Count) utakmica sa statistikom, $(@($list | Where-Object { $_.o }).Count) sa kvotama, $($script:calls) poziva"
