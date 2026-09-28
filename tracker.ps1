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
if (Test-Path $picksFile) { $arr = Get-Content -Raw -Encoding UTF8 $picksFile | ConvertFrom-Json; foreach ($p in $arr) { if ($p -and $p.date) { [void]$picks.Add($p) } } }
$picksLocked = @($picks | Where-Object { $_.date -eq $today }).Count -gt 0   # prvo (jutarnje) pokretanje zakljucava danasnje tipove
# zakljucava se SAMO ako ima fudbala i ako je vec 5 ujutro ili kasnije (nocna pokretanja ne smiju zakljucati dan bez fudbala)
$hourLocal = [System.TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, [System.TimeZoneInfo]::FindSystemTimeZoneById('Central European Standard Time')).Hour
$canLock = (@($data.days | Where-Object { $_.date -eq $today } | ForEach-Object { $_.matches }).Count -gt 0) -and $hourLocal -ge 5   # fudbal je u data.days
if (-not $canLock) { Write-Host "Tracker: danasnji tipovi i tiket se NE zakljucavaju (nema fudbala ili je prije 5h)" }
$results = @{}
if (Test-Path $resFile) { (Get-Content -Raw -Encoding UTF8 $resFile | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $results[$_.Name] = $_.Value } }
# kosarka: isti API-Basketball id je nekad zapisan kao "as123" (stari izvor), a rezultat kao "bb123" - vazi oboje
foreach ($k in @($results.Keys)) { if ($k -match '^basketball:(as|bb)(\d+)$') { $alt = "basketball:$(if ($matches[1] -eq 'as') { 'bb' } else { 'as' })$($matches[2])"; if (-not $results.ContainsKey($alt)) { $results[$alt] = $results[$k] } } }

# 0) samokorekcija: ako neka opcija u nekom sportu (zadnjih 45 dana, bar 25 provjerenih tipova) prolazi
#    cesce/rjedje nego sto smo rekli, pomjeri danasnje procente za tu opciju (oprezno, najvise +-12)
$todayD0 = [datetime]::ParseExact($today, 'yyyy-MM-dd', $null)
$judged = @($picks | Where-Object { $_.v -ne 'm' -and $_.hit -is [bool] -and ([datetime]::ParseExact($_.date, 'yyyy-MM-dd', $null)) -ge $todayD0.AddDays(-45) })
$calib = @{}
foreach ($g in ($judged | Group-Object { "$($_.sport)|$($_.mk)" })) {
  $n = $g.Count; if ($n -lt 25) { continue }
  $pAvg = ($g.Group | Measure-Object p -Average).Average
  $hit = @($g.Group | Where-Object { $_.hit }).Count / $n * 100
  $calib[$g.Name] = [math]::Max(-12, [math]::Min(12, ($hit - $pAvg) * $n / ($n + 60)))
}
function Adjust($sport, $ms) {
  foreach ($m in $ms) { if (-not $m) { continue }; foreach ($pr in $m.p.PSObject.Properties) {
    $d = $calib["$sport|$($pr.Name)"]; if ($d -and $pr.Value -ne $null) { $pr.Value = [int][math]::Max(1, [math]::Min(99, [math]::Round($pr.Value + $d))) } } }
}
if ($calib.Count) {
  Adjust 'football' @(($data.days | Where-Object { $_.date -eq $today }).matches)
  foreach ($p in $data.sports.PSObject.Properties) { Adjust $p.Name @(($p.Value.days | Where-Object { $_.date -eq $today }).matches) }
  Write-Host "Samokorekcija: $(($calib.GetEnumerator() | ForEach-Object { "$($_.Key) $([math]::Round($_.Value,1))" }) -join ', ')"
}

# 1) danasnje top 3 po opciji (isto kao na stranici)
$lists = @{ football = @(($data.days | Where-Object { $_.date -eq $today }).matches) }
foreach ($p in $data.sports.PSObject.Properties) { $lists[$p.Name] = @(($p.Value.days | Where-Object { $_.date -eq $today }).matches) }
foreach ($sport in @(if ($picksLocked) { } else { $lists.Keys })) {
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

# 1b) sjena "samo statistika" (v = 'm') - ne prikazuje se, samo za poredjenje
if (-not $picksLocked) {
  foreach ($sf in 'shadow_af.json', 'shadow_bb.json') {
    $sp = Join-Path $root $sf; if (-not (Test-Path $sp)) { continue }
    $sj = Get-Content -Raw -Encoding UTF8 $sp | ConvertFrom-Json; if ($sj.date -ne $today) { continue }
    foreach ($x in $sj.picks) { [void]$picks.Add([pscustomobject]@{ date = $today; sport = $x.sport; mk = $x.mk; key = $x.key; home = $x.home; away = $x.away; p = [int]$x.p; hit = $null; v = 'm' }) }
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
  # utakmica zavrsena, ali liga nikad ne posalje kornere/kartone -> ne moze se ocijeniti, ne prikazuje se kao "ceka se"
  elseif ($r -and $p.mk -in 'c8', 'y3' -and $hourLocal -ge 5) { $p.hit = 'void' }
  # rezultat nije stigao ni 2 dana poslije (odgodjeno, prekinuto i sl.)
  elseif (([datetime]::ParseExact($p.date, 'yyyy-MM-dd', $null)) -lt $todayD.AddDays(-1)) { $p.hit = 'void' }
}

# 2b) Tiket dana: 3 najsigurnija tipa sa kvotom (razlicite utakmice, kvota bar 1.20, procenat bar 65)
$legs = New-Object System.Collections.ArrayList
foreach ($sport in $lists.Keys) { foreach ($m in @($lists[$sport] | Where-Object { $_ -and $_.o })) {
  foreach ($pr in $m.p.PSObject.Properties) { $q = $m.o.($pr.Name)
    if ($q -and [double]$q -ge 1.15 -and $pr.Value -ne $null -and $pr.Value -ge 75 -and (100 / [double]$q * 0.95) -ge 60) {   # kandidati: nas procenat >= 75 i kladionice >= ~63%; najsigurniji se biraju po score-u
      [void]$legs.Add([pscustomobject]@{ sport = $sport; mk = $pr.Name; key = "${sport}:$($m.id)"; home = $m.home; away = $m.away; hl = $m.hl; al = $m.al; league = $m.league; time = $m.time; p = [int]$pr.Value; o = [double]$q }) } } } }
$ticket = New-Object System.Collections.ArrayList; $used = @{}
# najpametniji izbor iz SVIH opcija i sportova: sigurnost = manji od (nas procenat, procenat iz kvote bez marze),
# plus pola nase prednosti nad kladionicom. Tako ulaze tipovi gdje se statistika i trziste slazu.
foreach ($l in $legs) { $imp = 100 / $l.o * 0.95; $l | Add-Member -NotePropertyName score -NotePropertyValue ([math]::Min($l.p, $imp) + 0.5 * [math]::Max(0, $l.p - $imp)) }
# TIKET: 3 para, ukupna kvota NIKAD ispod 1.70. Od svih kombinacija 3 para (razlicite utakmice) sa kvotom >= 1.70
# bira onu sa najvecom sansom (proizvod score-ova). Ako 3 nikako ne daju 1.70 -> 4 para, pa 2 para.
$top = @($legs | Sort-Object @{ e = { $_.score }; Descending = $true }, @{ e = { $_.o }; Descending = $true } | Select-Object -First 22)
$n = $top.Count; $best = $null; $bestS = -1
function Try-Set($set) {
  if (@($set | ForEach-Object { $_.key } | Select-Object -Unique).Count -ne $set.Count) { return }
  $odd = 1.0; $s = 1.0; foreach ($z in $set) { $odd *= $z.o; $s *= $z.score / 100 }
  if ($odd -ge 1.70 -and $s -gt $script:bestS) { $script:bestS = $s; $script:best = $set } }
for ($a = 0; $a -lt $n; $a++) { for ($b = $a + 1; $b -lt $n; $b++) { for ($c = $b + 1; $c -lt $n; $c++) { Try-Set @($top[$a], $top[$b], $top[$c]) } } }
if (-not $best) { for ($a = 0; $a -lt $n; $a++) { for ($b = $a + 1; $b -lt $n; $b++) { for ($c = $b + 1; $c -lt $n; $c++) { for ($d = $c + 1; $d -lt $n; $d++) { Try-Set @($top[$a], $top[$b], $top[$c], $top[$d]) } } } } }
if (-not $best) { for ($a = 0; $a -lt $n; $a++) { for ($b = $a + 1; $b -lt $n; $b++) { Try-Set @($top[$a], $top[$b]) } } }
if ($best) { foreach ($l in $best) { [void]$ticket.Add($l) } }
$tFile = Join-Path $root 'cache\tickets.json'
$tickets = New-Object System.Collections.ArrayList
if (Test-Path $tFile) { $arr = Get-Content -Raw -Encoding UTF8 $tFile | ConvertFrom-Json; foreach ($t in $arr) { if ($t -and $t.date) { [void]$tickets.Add($t) } } }
$tkToday = @($tickets | Where-Object { $_.date -eq $today })[0]
if ($tkToday) { $data | Add-Member -NotePropertyName ticket -NotePropertyValue $tkToday -Force }   # jutarnji tiket ostaje cijeli dan
elseif ($ticket.Count -ge 2) {
  $odd = 1.0; $pp = 1.0; foreach ($l in $ticket) { $odd *= $l.o; $pp *= $l.p / 100 }
  $tk = [ordered]@{ date = $today; odd = [math]::Round($odd, 2); p = [int][math]::Round($pp * 100); legs = @($ticket); hit = $null }
  $data | Add-Member -NotePropertyName ticket -NotePropertyValue $tk -Force
  [void]$tickets.Add([pscustomobject]$tk)
}
# provjera starih tiketa: prolazi samo ako su prosli svi tipovi
foreach ($t in $tickets) {
  if ($t.hit -ne $null -or $t.date -ge $today) { continue }
  $vals = @($t.legs | ForEach-Object { $r = if ($_.key) { $results[[string]$_.key] } else { $null }; if ($r) { Judge $_.sport $_.mk $r } else { $null } })
  if (@($vals | Where-Object { $_ -eq $false }).Count) { $t.hit = $false }
  elseif (@($vals | Where-Object { $_ -eq $true }).Count -eq $vals.Count) { $t.hit = $true }
  elseif (([datetime]::ParseExact($t.date, 'yyyy-MM-dd', $null)) -lt $todayD0.AddDays(-10)) { $t.hit = 'void' }
}
if (-not $canLock -and -not $picksLocked) { $tickets = @($tickets | Where-Object { $_.date -ne $today }) }
[IO.File]::WriteAllText($tFile, ('[' + ((@($tickets | Select-Object -Last 90) | ForEach-Object { $_ | ConvertTo-Json -Depth 5 -Compress }) -join ',') + ']'), $enc)
$tw = @($tickets | Where-Object { $_.hit -is [bool] -and ([datetime]::ParseExact($_.date, 'yyyy-MM-dd', $null)) -ge $todayD0.AddDays(-30) })
$ticketTrack = [ordered]@{ n = $tw.Count; hit = @($tw | Where-Object { $_.hit }).Count }

# 3) cuvanje (zadnjih 60 dana) i statistika zadnjih 30 dana
$keep = @($picks | Where-Object { ([datetime]::ParseExact($_.date, 'yyyy-MM-dd', $null)) -ge $todayD.AddDays(-60) })
$keepSave = if (-not $canLock -and -not $picksLocked) { @($keep | Where-Object { $_.date -ne $today }) } else { $keep }
[IO.File]::WriteAllText($picksFile, (ConvertTo-Json @($keepSave) -Depth 3 -Compress), $enc)
$win = @($keep | Where-Object { $_.v -ne 'm' -and $_.hit -is [bool] -and ([datetime]::ParseExact($_.date, 'yyyy-MM-dd', $null)) -ge $todayD.AddDays(-30) })
$bySport = [ordered]@{}
foreach ($g in ($win | Group-Object sport)) { $bySport[$g.Name] = [ordered]@{ n = $g.Count; hit = @($g.Group | Where-Object { $_.hit }).Count } }
$shw = @($keep | Where-Object { $_.v -eq 'm' -and $_.hit -is [bool] -and ([datetime]::ParseExact($_.date, 'yyyy-MM-dd', $null)) -ge $todayD.AddDays(-30) })
$cmp = [ordered]@{ saKvotama = [ordered]@{ n = $win.Count; hit = @($win | Where-Object { $_.hit }).Count }; bezKvota = [ordered]@{ n = $shw.Count; hit = @($shw | Where-Object { $_.hit }).Count } }
Write-Host "Poredjenje: sa kvotama $($cmp.saKvotama.hit)/$($cmp.saKvotama.n), samo statistika $($cmp.bezKvota.hit)/$($cmp.bezKvota.n)"
$track = [ordered]@{ days = 30; n = $win.Count; hit = @($win | Where-Object { $_.hit }).Count; sports = $bySport; ticket = $ticketTrack; cmp = $cmp }
$data | Add-Member -NotePropertyName track -NotePropertyValue $track -Force

# 4) istorija za stranicu "Rezultati" (zadnjih 30 dana): history.json
function ScoreOf($key) { $r = if ($key) { $results[[string]$key] } else { $null }; if ($r) { "$([int]$r.h)-$([int]$r.a)" } else { '' } }
function HitVal($v) { if ($v -is [bool]) { return [int]$v } ; return $null }   # 1 proslo, 0 palo, null ceka
$hdays = New-Object System.Collections.ArrayList
for ($i = 0; $i -le 30; $i++) {
  $ds = $todayD.AddDays(-$i).ToString('yyyy-MM-dd')
  # prvo fudbal pa kosarka; poniste (void) utakmice se ne prikazuju
  $dp = @($keep | Where-Object { $_.date -eq $ds -and $_.v -ne 'm' -and -not ($_.hit -is [string] -and $_.hit -eq 'void') } | Sort-Object @{ e = { if ($_.sport -eq 'football') { 0 } else { 1 } } })
  $tk = @($tickets | Where-Object { $_.date -eq $ds })[0]
  if (-not $dp.Count -and -not $tk) { continue }
  $day = [ordered]@{ date = $ds }
  if ($tk) {
    $day.t = [ordered]@{ odd = $tk.odd; p = $tk.p; r = (HitVal $tk.hit); legs = @($tk.legs | ForEach-Object {
      $rr = if ($_.key) { $results[[string]$_.key] } else { $null }; $v = if ($rr) { Judge $_.sport $_.mk $rr } else { $null }
      [ordered]@{ s = $_.sport; m = $_.mk; h = $_.home; a = $_.away; hl = $_.hl; al = $_.al; o = $_.o; p = $_.p; r = (HitVal $v); sc = (ScoreOf $_.key) } }) }
  }
  $day.k = @($dp | ForEach-Object { [ordered]@{ s = $_.sport; m = $_.mk; h = $_.home; a = $_.away; p = $_.p; r = (HitVal $_.hit); sc = (ScoreOf $_.key) } })
  [void]$hdays.Add($day)
}
[IO.File]::WriteAllText((Join-Path $root 'history.json'), ([ordered]@{ today = $today; days = @($hdays) } | ConvertTo-Json -Depth 6 -Compress), $enc)
[IO.File]::WriteAllText($dataFile, ($data | ConvertTo-Json -Depth 12), $enc)
Write-Host "Pracenje: danas zapisano $(@($keep | Where-Object { $_.date -eq $today }).Count) tipova; zadnjih 30 dana $($track.hit)/$($track.n)"
