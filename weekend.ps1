# Tiket vikenda - petkom ujutro: statistika za subotu i nedjelju (samo jake lige) i najsigurniji tiket od 4 para.
# Pise cache\weekend.json (video.ps1 i social.ps1 od njega prave video i objavu). Poziva se iz update.ps1.
# -Fri 2026-10-02 = rucni test za taj petak (bez provjere dana i sata).
param([string]$Fri = '', [switch]$NoFetch)   # -NoFetch = test bez API poziva (koristi postojece af_sat/af_sun.json)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$tz = [System.TimeZoneInfo]::FindSystemTimeZoneById('Central European Standard Time')
$now = [System.TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $tz)
if (-not $Fri) {
  if ($now.DayOfWeek -ne 'Friday' -or $now.Hour -lt 5) { return }
  $Fri = $now.ToString('yyyy-MM-dd')
}
$wf = Join-Path $root 'cache\weekend.json'
if (Test-Path $wf) { $old = Get-Content -Raw -Encoding UTF8 $wf | ConvertFrom-Json; if ($old.date -eq $Fri) { Write-Host "Tiket vikenda: vec napravljen za $Fri"; return } }
$fd = [datetime]::ParseExact($Fri, 'yyyy-MM-dd', $null)
$days = @(@('SUB', $fd.AddDays(1).ToString('yyyy-MM-dd'), 'af_sat.json'), @('NED', $fd.AddDays(2).ToString('yyyy-MM-dd'), 'af_sun.json'))

$legs = New-Object System.Collections.ArrayList
foreach ($d in $days) {
  if (-not $NoFetch) { & (Join-Path $root 'update_af.ps1') -Date $d[1] -OutFile $d[2] -Top }
  $af = Get-Content -Raw -Encoding UTF8 (Join-Path $root $d[2]) | ConvertFrom-Json
  foreach ($m in @($af.days[0].matches | Where-Object { $_ -and $_.o -and [string]$_.time -ge '12:00' -and [string]$_.time -le '22:30' })) {   # samo dnevne/vecernje utakmice
    foreach ($pr in $m.p.PSObject.Properties) { $q = $m.o.($pr.Name)
      # isti uslovi kao tiket dana: nas procenat >= 75, kladionice >= ~60%, kvota bar 1.15
      if ($q -and [double]$q -ge 1.15 -and $pr.Value -ne $null -and $pr.Value -ge 75 -and (100 / [double]$q * 0.95) -ge 60) {
        $imp = 100 / [double]$q * 0.95
        [void]$legs.Add([pscustomobject]@{ sport = 'football'; mk = $pr.Name; key = "football:$($m.id)"; home = $m.home; away = $m.away; hl = $m.hl; al = $m.al
          league = $m.league; time = $m.time; day = $d[0]; date = $d[1]; p = [int]$pr.Value; o = [double]$q
          score = [math]::Min([double]$pr.Value, $imp) + 0.5 * [math]::Max(0, [double]$pr.Value - $imp) }) } } }
}
Write-Host "Tiket vikenda: $($legs.Count) kandidata"
# 4 para sa ukupnom kvotom bar 2.50 i najvecom sansom; ako ne moze -> 3 para sa 1.70+
$top = @($legs | Sort-Object @{ e = { $_.score }; Descending = $true }, @{ e = { $_.o }; Descending = $true } | Select-Object -First 20)
$n = $top.Count; $script:best = $null; $script:bestS = -1
function Try-Set($set, [double]$min) {
  if (@($set | ForEach-Object { $_.key } | Select-Object -Unique).Count -ne $set.Count) { return }
  $odd = 1.0; $s = 1.0; foreach ($z in $set) { $odd *= $z.o; $s *= $z.score / 100 }
  if ($odd -ge $min -and $s -gt $script:bestS) { $script:bestS = $s; $script:best = $set } }
for ($a = 0; $a -lt $n; $a++) { for ($b = $a + 1; $b -lt $n; $b++) { for ($c = $b + 1; $c -lt $n; $c++) { for ($e = $c + 1; $e -lt $n; $e++) { Try-Set @($top[$a], $top[$b], $top[$c], $top[$e]) 2.5 } } } }
if (-not $script:best) { for ($a = 0; $a -lt $n; $a++) { for ($b = $a + 1; $b -lt $n; $b++) { for ($c = $b + 1; $c -lt $n; $c++) { Try-Set @($top[$a], $top[$b], $top[$c]) 1.7 } } } }
if (-not $script:best) { Write-Host 'Tiket vikenda: nema dovoljno sigurnih parova'; return }
$sel = @($script:best | Sort-Object date, time | Select-Object sport, mk, key, home, away, hl, al, league, time, day, date, p, o)
$odd = 1.0; $pp = 1.0; foreach ($l in $sel) { $odd *= $l.o; $pp *= $l.p / 100 }
$wk = [ordered]@{ date = $Fri; sat = $days[0][1]; sun = $days[1][1]; odd = [math]::Round($odd, 2); p = [int][math]::Round($pp * 100); n = $legs.Count; legs = $sel; hit = $null }
[IO.File]::WriteAllText($wf, ($wk | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Tiket vikenda: $($sel.Count) para, kvota $($wk.odd)"
