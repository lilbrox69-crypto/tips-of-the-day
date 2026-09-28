# Tips of the Day - objavljuje zakazane Facebook objave (social/posts.json) preko Make webhooka.
# Pokreće ga .github/workflows/post.yml svakih 30 min; stanje (sta je vec objavljeno) je u cache/posted.json.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $env:MAKE_WEBHOOK) { Write-Host 'Nema MAKE_WEBHOOK secreta - preskacem.'; exit 0 }
$tzId = if ($IsLinux) { 'Europe/Sarajevo' } else { 'Central European Standard Time' }
$now = [System.TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, [System.TimeZoneInfo]::FindSystemTimeZoneById($tzId))
$today = $now.ToString('yyyy-MM-dd'); $hm = $now.ToString('HH:mm')
$sched = Invoke-RestMethod "https://tipsoftheday.win/social/posts.json?x=$([guid]::NewGuid())"
if ($sched.date -ne $today) { Write-Host "Raspored je za $($sched.date), danas je $today - nista."; exit 0 }
$stFile = Join-Path $root 'cache/posted.json'
$st = if (Test-Path $stFile) { Get-Content -Raw $stFile | ConvertFrom-Json } else { $null }
$done = @(); if ($st -and $st.date -eq $today) { $done = @($st.done) }
$late = $now.AddMinutes(-100).ToString('HH:mm')   # ako je GitHub zakasnio, objava i dalje ide (do 100 min), starije se preskacu
$sent = 0
foreach ($p in @($sched.posts)) {
  if ($done -contains $p.t -or $p.t -gt $hm) { continue }
  if ($p.t -lt $late) { $done += $p.t; Write-Host "Preskacem zakasnjelu $($p.t) $($p.kind)"; continue }
  if ($sent -ge 2) { break }
  $body = @{ image = $p.image; text = $p.text; kind = $p.kind } | ConvertTo-Json -Compress
  Invoke-RestMethod -Method Post -Uri $env:MAKE_WEBHOOK -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) | Out-Null
  Write-Host "Objavljeno $($p.t) $($p.kind)"; $done += $p.t; $sent++
  Start-Sleep -Seconds 20
}
New-Item -ItemType Directory -Force (Split-Path $stFile) | Out-Null
[IO.File]::WriteAllText($stFile, (@{ date = $today; done = @($done) } | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding($false)))
