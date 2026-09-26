# TipRadar - hokej, rukomet, odbojka, evropska kosarka preko API-Sports (besplatni plan)
# Besplatno: samo jucer/danas/sutra po datumu i sezone 2022-2024. Zato:
#  - pocetna statistika = sezona 2024 (kes po ligi, skida se jednom)
#  - svaki dan se cuvaju zavrsene utakmice (kes raste i statistika postaje svjeza)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$key = (Get-Content -Raw -Encoding UTF8 (Join-Path $root 'config.json') | ConvertFrom-Json).apiSportsKey
$headers = @{ 'x-apisports-key' = $key }
$tz = [System.TimeZoneInfo]::FindSystemTimeZoneById('Central European Standard Time')
$today = [System.TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $tz).Date
$cacheDir = Join-Path $root 'cache'; New-Item -ItemType Directory -Force $cacheDir | Out-Null
$enc = New-Object System.Text.UTF8Encoding($false)
. (Join-Path $root 'results_lib.ps1')

$WL = @{
  hockey = @{ ids = @(57,35,16,19,51,10,91,70,18,12,47); names = @('SHL','Champions Hockey League') }
  handball = @{ ids = @(39,103,34,23,49,78,84,113,75,100,37,120,2,115); names = @('EHF Champions League','EHF European League','Premijer') }
  volleyball = @{ ids = @(); names = @('SuperLega','PlusLiga','Efeler','Sultanlar','Serie A1','Ligue A','Superleague','Champions League','Tauron','1. Bundesliga') }
  basketball = @{ ids = @(120,198,117,52,104,2,40,82,60,30,89,32,1,13); names = @('Eurocup','EuroCup','Champions League','Basket League','KLS') }
}

function Get-AS($sport, $path) {
  for ($t = 0; $t -lt 3; $t++) {
    try {
      $r = Invoke-RestMethod ("https://v1.$sport.api-sports.io/" + $path) -Headers $headers -TimeoutSec 30
      Start-Sleep -Milliseconds 6500
      if ($r.errors -and ($r.errors | Get-Member -MemberType NoteProperty)) { Write-Host "  API: $($r.errors | ConvertTo-Json -Compress)"; return $null }
      return $r
    } catch { Write-Host "  greska: $($_.Exception.Message)"; Start-Sleep -Seconds 30 }
  }
  return $null
}
function In-WL($sport, $g) {
  if ($sport -eq 'basketball' -and $g.league.name -eq 'NBA') { return $false }
  if ($sport -eq 'hockey' -and ([int]$g.league.id -eq 57 -or $g.league.name -eq 'NHL')) { return $false }   # NHL ide iz zvanicnog NHL API-ja (update_nhl.ps1)
  if ($WL[$sport].ids -contains [int]$g.league.id) { return $true }
  foreach ($n in $WL[$sport].names) { if ($g.league.name -like "*$n*" -and $g.league.name -notlike '*Women*' -and $g.league.name -notlike '2.*') { return $true } }
  return $false
}
function Norm-AS($sport, $g) {
  $st = $g.status.short
  $final = $st -in @('FT','AOT','AP','AET','AW','AFT','PEN')
  $hs = $g.scores.home; $as = $g.scores.away
  if ($hs -is [psobject] -and $hs.total -ne $null) { $hs = $hs.total; $as = $as.total }   # kosarka: scores.home.total
  [pscustomobject]@{ id = $g.id; utc = $g.date; final = $final; league = $g.league.name; country = $g.country.name; lid = $g.league.id
    hid = $g.teams.home.id; aid = $g.teams.away.id; hn = $g.teams.home.name; an = $g.teams.away.name; hs = $hs; as = $as; hl = $g.teams.home.logo; al = $g.teams.away.logo }
}
function Load-Json($file) { if (Test-Path $file) { return @(Get-Content -Raw -Encoding UTF8 $file | ConvertFrom-Json) } ; return @() }
function Save-Json($file, $obj) { [IO.File]::WriteAllText($file, (ConvertTo-Json @($obj) -Depth 5), $enc) }

function Erf([double]$x) { $s = [math]::Sign($x); $x = [math]::Abs($x); $t = 1 / (1 + 0.3275911 * $x)
  $y = 1 - (((((1.061405429 * $t - 1.453152027) * $t) + 1.421413741) * $t - 0.284496736) * $t + 0.254829592) * $t * [math]::Exp(-$x * $x); return $s * $y }
function Phi([double]$z) { 0.5 * (1 + (Erf ($z / [math]::Sqrt(2)))) }
function Pct([double]$x) { [int][math]::Round([math]::Max([double]0.0, [math]::Min([double]1.0, $x)) * 100) }
function PoisP([double]$l, [int]$k) { $f = 1.0; for ($i = 2; $i -le $k; $i++) { $f *= $i }; [math]::Exp(-$l) * [math]::Pow($l, $k) / $f }
function Esc([string]$s) { [Net.WebUtility]::HtmlEncode($s) }

function Hist($games) {
  $h = @{}
  foreach ($g in ($games | Where-Object { $_.final -and $_.hs -ne $null -and $_.as -ne $null } | Sort-Object { [datetime]$_.utc } -Descending)) {
    foreach ($side in 'h','a') {
      $tid = [string]$(if ($side -eq 'h') { $g.hid } else { $g.aid })
      $pf = [double]$(if ($side -eq 'h') { $g.hs } else { $g.as }); $pa = [double]$(if ($side -eq 'h') { $g.as } else { $g.hs })
      if (-not $h.ContainsKey($tid)) { $h[$tid] = New-Object System.Collections.ArrayList }
      if ($h[$tid].Count -lt 10) { [void]$h[$tid].Add([pscustomobject]@{ pf = $pf; pa = $pa }) }
    }
  }
  return $h
}
function TS($h, $tid) {
  $g = $h[[string]$tid]; if (-not $g -or $g.Count -lt 5) { return $null }
  $n = $g.Count
  [pscustomobject]@{ n = $n; pf = [math]::Round((($g | Measure-Object pf -Sum).Sum / $n), 1); pa = [math]::Round((($g | Measure-Object pa -Sum).Sum / $n), 1)
    w = @($g | Where-Object { $_.pf -gt $_.pa }).Count; games = $g }
}
function Rate($s, $cond) { @($s.games | Where-Object -FilterScript $cond).Count }
function RateOf($s, $cond) { if (-not $s -or -not $s.n) { return 0.0 }; return [double](@($s.games | Where-Object -FilterScript $cond).Count) / [double]$s.n }

$result = [ordered]@{}
foreach ($sport in @('basketball')) {
  Write-Host "== $sport"
  $recFile = Join-Path $cacheDir "as_$sport.json"
  $rec = @{}; foreach ($g in (Load-Json $recFile)) { $rec[[string]$g.id] = $g }
  $upcoming = @()
  foreach ($off in -1,0,1) {
    $r = Get-AS $sport ("games?date=" + $today.AddDays($off).ToString('yyyy-MM-dd') + "&timezone=Europe/Sarajevo")
    if (-not $r) { continue }
    foreach ($raw in $r.response) {
      if (-not (In-WL $sport $raw)) { continue }
      $g = Norm-AS $sport $raw
      if ($g.final) { $rec[[string]$g.id] = $g } elseif ($raw.status.short -eq 'NS') { $upcoming += $g }
    }
  }
  Save-Json $recFile @($rec.Values)
  $res = @{}; foreach ($g in $rec.Values) { if ($g.hs -ne $null -and $g.as -ne $null) { $res["${sport}:as$($g.id)"] = [ordered]@{ h = [int]$g.hs; a = [int]$g.as } } }
  Save-Results $root $res
  # pocetna statistika: sezona 2024 za svaku ligu koja se pojavi
  $base = @()
  foreach ($lid in ($upcoming | Select-Object -ExpandProperty lid -Unique)) {
    $bf = Join-Path $cacheDir "base_${sport}_$lid.json"
    if (-not (Test-Path $bf)) {
      Write-Host "  prvi put: liga $lid, sezona 2024"
      $r = Get-AS $sport "games?league=$lid&season=2024"
      $list = if ($r) { @($r.response | ForEach-Object { Norm-AS $sport $_ } | Where-Object { $_.final }) } else { @() }
      if ($list.Count -eq 0) {   # neke lige koriste format 2024-2025
        $r = Get-AS $sport "games?league=$lid&season=2024-2025"
        $list = if ($r) { @($r.response | ForEach-Object { Norm-AS $sport $_ } | Where-Object { $_.final }) } else { @() }
      }
      Save-Json $bf $list
    }
    $base += Load-Json $bf
  }
  $hist = Hist (@($rec.Values) + @($base))
  $days = @{}
  foreach ($g in $upcoming) {
    $h = TS $hist $g.hid; $a = TS $hist $g.aid; if (-not $h -or -not $a) { continue }
    $HN = Esc $g.hn; $AN = Esc $g.an
    $recTxt = "Zadnjih $($h.n): $HN $($h.w)-$($h.n - $h.w), prosjek $($h.pf):$($h.pa) &middot; $AN $($a.w)-$($a.n - $a.w), $($a.pf):$($a.pa)"
    $p = [ordered]@{}; $why = [ordered]@{}
    switch ($sport) {
      'hockey' {
        $lh = [math]::Max(0.5, ($h.pf + $a.pa) / 2 * 1.05); $la = [math]::Max(0.5, ($a.pf + $h.pa) / 2 * 0.97)
        $ph = 0.0; $pt = 0.0; $pa2 = 0.0; $o55 = 0.0; $o45 = 0.0
        for ($i = 0; $i -le 12; $i++) { $pi = PoisP $lh $i; for ($j = 0; $j -le 12; $j++) { $pp = $pi * (PoisP $la $j)
          if ($i -gt $j) { $ph += $pp } elseif ($i -eq $j) { $pt += $pp } else { $pa2 += $pp }
          if (($i + $j) -ge 6) { $o55 += $pp }; if (($i + $j) -ge 5) { $o45 += $pp } } }
        $w1 = $ph + $pt * ($ph / ($ph + $pa2))
        $gg = 0.5 * ((1 - [math]::Exp(-$lh)) * (1 - [math]::Exp(-$la))) + 0.5 * (((RateOf $h { $_.pf -gt 0 -and $_.pa -gt 0 }) + (RateOf $a { $_.pf -gt 0 -and $_.pa -gt 0 })) / 2)
        $r55 = ((RateOf $h { ($_.pf + $_.pa) -ge 6 }) + (RateOf $a { ($_.pf + $_.pa) -ge 6 })) / 2
        $r45 = ((RateOf $h { ($_.pf + $_.pa) -ge 5 }) + (RateOf $a { ($_.pf + $_.pa) -ge 5 })) / 2
        $o55 = 0.5 * $o55 + 0.5 * $r55; $o45 = 0.5 * $o45 + 0.5 * $r45
        $p = [ordered]@{ gg = Pct $gg; o55 = Pct $o55; o45 = Pct $o45; u55 = Pct (1 - $o55); w1 = Pct $w1; w2 = Pct (1 - $w1) }
        $gl = "Ocekivani golovi $([math]::Round($lh,1)) - $([math]::Round($la,1))"
        $why = [ordered]@{ gg = "Oba dala gol: $HN $(Rate $h { $_.pf -gt 0 -and $_.pa -gt 0 })/$($h.n), $AN $(Rate $a { $_.pf -gt 0 -and $_.pa -gt 0 })/$($a.n)<br>$gl"
          o55 = "6+ golova: $HN $(Rate $h { ($_.pf + $_.pa) -ge 6 })/$($h.n), $AN $(Rate $a { ($_.pf + $_.pa) -ge 6 })/$($a.n)<br>$gl"
          o45 = "5+ golova: $HN $(Rate $h { ($_.pf + $_.pa) -ge 5 })/$($h.n), $AN $(Rate $a { ($_.pf + $_.pa) -ge 5 })/$($a.n)<br>$gl"
          u55 = "6+ golova bilo je: $HN $(Rate $h { ($_.pf + $_.pa) -ge 6 })/$($h.n), $AN $(Rate $a { ($_.pf + $_.pa) -ge 6 })/$($a.n)<br>$gl"
          w1 = $recTxt; w2 = $recTxt }
      }
      'handball' {
        $eh = ($h.pf + $a.pa) / 2 + 0.8; $ea = ($a.pf + $h.pa) / 2 - 0.8; $m = $eh - $ea; $tot = $eh + $ea
        $w1 = Phi (($m - 0.5) / 6); $w2 = 1 - (Phi (($m + 0.5) / 6))
        $ro = ((RateOf $h { ($_.pf + $_.pa) -gt 55.5 }) + (RateOf $a { ($_.pf + $_.pa) -gt 55.5 })) / 2
        $o = 0.5 * (1 - (Phi ((55.5 - $tot) / 6.5))) + 0.5 * $ro
        $p = [ordered]@{ w1 = Pct $w1; w2 = Pct $w2; o55 = Pct $o; u55 = Pct (1 - $o) }
        $ov = "56+ golova: $HN $(Rate $h { ($_.pf + $_.pa) -gt 55.5 })/$($h.n), $AN $(Rate $a { ($_.pf + $_.pa) -gt 55.5 })/$($a.n)<br>Ocekivano oko $([math]::Round($tot)) golova"
        $why = [ordered]@{ w1 = $recTxt; w2 = $recTxt; o55 = $ov; u55 = $ov }
      }
      'volleyball' {
        $hs = ($h.games | Measure-Object pf -Sum).Sum; $hl = ($h.games | Measure-Object pa -Sum).Sum
        $as_ = ($a.games | Measure-Object pf -Sum).Sum; $al = ($a.games | Measure-Object pa -Sum).Sum
        $rh = $hs / [math]::Max(1, $hs + $hl); $ra = $as_ / [math]::Max(1, $as_ + $al)
        $q = [math]::Min(0.9, [math]::Max(0.1, ($rh + (1 - $ra)) / 2 + 0.02)); $r_ = 1 - $q
        $w1 = [math]::Pow($q,3) * (1 + 3 * $r_ + 6 * $r_ * $r_)
        $p = [ordered]@{ w1 = Pct $w1; w2 = Pct (1 - $w1); s4 = Pct (1 - [math]::Pow($q,3) - [math]::Pow($r_,3)); s5 = Pct (6 * $q * $q * $r_ * $r_) }
        $st = "Osvojeni setovi: $HN $($hs):$($hl), $AN $($as_):$($al) (zadnjih $($h.n) i $($a.n) meceva)"
        $why = [ordered]@{ w1 = "$recTxt<br>$st"; w2 = "$recTxt<br>$st"; s4 = $st; s5 = $st }
      }
      'basketball' {
        $eh = ($h.pf + $a.pa) / 2 + 2; $ea = ($a.pf + $h.pa) / 2 - 2; $m = $eh - $ea; $tot = $eh + $ea
        $w1 = Phi ($m / 11)
        $ro = ((RateOf $h { ($_.pf + $_.pa) -gt 160.5 }) + (RateOf $a { ($_.pf + $_.pa) -gt 160.5 })) / 2
        $o = 0.5 * (1 - (Phi ((160.5 - $tot) / 15))) + 0.5 * $ro
        $p = [ordered]@{ w1 = Pct $w1; w2 = Pct (1 - $w1); o160 = Pct $o; u160 = Pct (1 - $o)
          m10 = Pct ((1 - (Phi ((9.5 - $m) / 11))) + (Phi ((-9.5 - $m) / 11))); h80 = Pct (1 - (Phi ((79.5 - $eh) / 9))) }
        $ov = "161+ poena: $HN $(Rate $h { ($_.pf + $_.pa) -gt 160.5 })/$($h.n), $AN $(Rate $a { ($_.pf + $_.pa) -gt 160.5 })/$($a.n)<br>Ocekivano oko $([math]::Round($tot)) poena"
        $why = [ordered]@{ w1 = $recTxt; w2 = $recTxt; o160 = $ov; u160 = $ov; m10 = "Ocekivana razlika oko $([math]::Round([math]::Abs($m),1))<br>$recTxt"; h80 = "$HN daje prosjecno $($h.pf), $AN prima $($a.pa)" }
      }
    }
    $utc = [datetime]::Parse($g.utc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
    $local = [System.TimeZoneInfo]::ConvertTimeFromUtc($utc, $tz)
    if ($local.Date -lt $today) { continue }
    $k = $local.ToString('yyyy-MM-dd')
    if (-not $days.ContainsKey($k)) { $days[$k] = New-Object System.Collections.ArrayList }
    [void]$days[$k].Add([ordered]@{ id = "as$($g.id)"; league = "$($g.league) ($($g.country))"; time = $local.ToString('HH:mm'); home = $g.hn; away = $g.an; hl = $g.hl; al = $g.al; p = $p; why = $why })
  }
  $dl = @(foreach ($k in ($days.Keys | Sort-Object)) { [ordered]@{ date = $k; matches = @($days[$k] | Sort-Object { $_.time }) } })
  $result[$sport] = [ordered]@{ days = $dl }
  Write-Host "  $sport : $(@($dl).Count) dana, $((@($dl) | ForEach-Object { $_.matches.Count } | Measure-Object -Sum).Sum) utakmica"
}
[IO.File]::WriteAllText((Join-Path $root 'as.json'), ($result | ConvertTo-Json -Depth 8), $enc)
