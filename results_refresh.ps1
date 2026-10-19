# Rezultati za tipove koji jos cekaju (svako pokretanje, ne samo prvo u danu).
# Utakmice koje zavrse iza nocnog pokretanja (Amerika, NBA, kasni termini) dobiju rezultat vec u jutarnjem pokretanju.
# Trosi malo poziva: fudbal 1 poziv na 20 utakmica, kosarka 1 poziv po danu.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'results_lib.ps1')
$cfg = Get-Content -Raw (Join-Path $root 'config.json') | ConvertFrom-Json
$key = $cfg.apiSportsKey; if (-not $key) { Write-Host 'Rezultati: nema kljuca'; return }
$tz = [System.TimeZoneInfo]::FindSystemTimeZoneById('Central European Standard Time')
$today = [System.TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $tz).ToString('yyyy-MM-dd')
$resFile = Join-Path $root 'cache\results.json'
$have = @{}; if (Test-Path $resFile) { (Get-Content -Raw -Encoding UTF8 $resFile | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $have[$_.Name] = $_.Value } }

# tipovi i tiketi koji jos cekaju (od prije danas)
$pending = New-Object System.Collections.ArrayList
$pf = Join-Path $root 'cache\picks.json'
if (Test-Path $pf) { $arr = Get-Content -Raw -Encoding UTF8 $pf | ConvertFrom-Json; foreach ($p in $arr) { if ($p -and $p.hit -eq $null -and $p.date -lt $today) { [void]$pending.Add([pscustomobject]@{ key = [string]$p.key; date = $p.date; mk = $p.mk }) } } }
$tf = Join-Path $root 'cache\tickets.json'
if (Test-Path $tf) { $arr = Get-Content -Raw -Encoding UTF8 $tf | ConvertFrom-Json; foreach ($t in $arr) { if ($t -and $t.hit -eq $null -and $t.date -lt $today) { foreach ($l in $t.legs) { [void]$pending.Add([pscustomobject]@{ key = [string]$l.key; date = $t.date; mk = $l.mk }) } } } }
# treba nam rezultat, a za kornere/kartone i statistika
$needF = @($pending | Where-Object { $_.key -like 'football:af*' } | Where-Object { $r = $have[$_.key]; -not $r -or $r.x -or ($_.mk -in 'c8', 'y3' -and $r.hc -eq $null) } | ForEach-Object { $_.key.Substring(11) } | Select-Object -Unique)
# dan za koji je utakmica bila u tipovima (da se vidi ako je API pomjeri na drugi dan)
$pday = @{}; foreach ($x in $pending) { if (-not $pday[$x.key] -or $x.date -lt $pday[$x.key]) { $pday[$x.key] = $x.date } }
$needB = @($pending | Where-Object { $_.key -match '^basketball:(as|bb)\d+$' } | Where-Object { -not $have[$_.key] -and -not $have[($_.key -replace ':as', ':bb')] } | ForEach-Object { $_.date } | Select-Object -Unique)
$hdr = @{ 'x-apisports-key' = $key }
$res = @{}; $FIN = @('FT', 'AET', 'PEN')
function StatV($f, $teamId, $type) { $s = @($f.statistics | Where-Object { [string]$_.team.id -eq $teamId })[0]; if (-not $s) { return $null }; $v = @($s.statistics | Where-Object { $_.type -eq $type })[0].value; if ($v -eq $null) { return $null }; [int]$v }
for ($i = 0; $i -lt $needF.Count; $i += 20) {
  $chunk = $needF[$i..([math]::Min($i + 19, $needF.Count - 1))] -join '-'
  try { $r = Invoke-RestMethod -Uri "https://v3.football.api-sports.io/fixtures?ids=$chunk" -Headers $hdr -TimeoutSec 60 } catch { Write-Host "Rezultati fudbal greska: $($_.Exception.Message)"; continue }
  foreach ($f in $r.response) {
    # odgodjena / otkazana / prekinuta (ili pomjerena na kasniji dan): par se ponistava kao kod kladionica (kvota 1.00)
    $fk = "football:af$($f.fixture.id)"; $st = $f.fixture.status.short
    $fday = [System.TimeZoneInfo]::ConvertTimeFromUtc(([datetimeoffset]::Parse($f.fixture.date)).UtcDateTime, $tz).ToString('yyyy-MM-dd')
    if ($st -in 'PST', 'CANC', 'ABD' -or ($st -in 'NS', 'TBD' -and $pday[$fk] -and $fday -gt $pday[$fk])) { $res[$fk] = [ordered]@{ x = $st }; continue }
    if ($st -notin $FIN) { continue }
    $h = [string]$f.teams.home.id; $a = [string]$f.teams.away.id
    $e = [ordered]@{ h = [int]$f.goals.home; a = [int]$f.goals.away }
    $hc = StatV $f $h 'Corner Kicks'; $ac = StatV $f $a 'Corner Kicks'
    if ($hc -ne $null -and $ac -ne $null -and ($hc + $ac) -gt 0) { $e.hc = $hc; $e.ac = $ac; $e.hy = [int](StatV $f $h 'Yellow Cards'); $e.ay = [int](StatV $f $a 'Yellow Cards') }
    $res["football:af$($f.fixture.id)"] = $e
  }
}
foreach ($d in $needB) {
  try { $r = Invoke-RestMethod -Uri "https://v1.basketball.api-sports.io/games?date=$d&timezone=Europe/Sarajevo" -Headers $hdr -TimeoutSec 60 } catch { Write-Host "Rezultati kosarka greska: $($_.Exception.Message)"; continue }
  foreach ($g in $r.response) { if ($g.status.short -in 'FT', 'AOT') { $res["basketball:bb$($g.id)"] = [ordered]@{ h = [int]$g.scores.home.total; a = [int]$g.scores.away.total } } }
}
if ($res.Count) { Save-Results $root $res }
Write-Host "Rezultati: cekalo $($pending.Count), fudbal upita $($needF.Count), kosarka dana $($needB.Count), novih rezultata $($res.Count)"
