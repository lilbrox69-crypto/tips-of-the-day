# Skida grbove klubova iz data.json, smanjuje ih na 48x48 i pise logos.json (url -> data URI)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$logoDir = Join-Path $root 'cache\logos'; New-Item -ItemType Directory -Force $logoDir | Out-Null
$data = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data.json') | ConvertFrom-Json
$urls = New-Object System.Collections.Generic.HashSet[string]
# samo grbovi utakmica koje danas ulaze u top 3 bilo koje opcije (stranica prikazuje samo njih)
$lists = @(@($data.days) + @($data.sports.PSObject.Properties | ForEach-Object { $_.Value.days }) | Where-Object { $_ -and $_.date -eq $data.today })
foreach ($d in $lists) {
  $ms = @($d.matches | Where-Object { $_ }); if (-not $ms.Count) { continue }
  foreach ($mk in @($ms | ForEach-Object { $_.p.PSObject.Properties.Name } | Sort-Object -Unique)) {
    foreach ($m in @($ms | Where-Object { $_.p.$mk -ne $null } | Sort-Object { - [int]$_.p.$mk } | Select-Object -First 3)) {
      foreach ($u in @($m.hl, $m.al)) { if ($u) { [void]$urls.Add([string]$u) } }
    }
  }
}
if ($data.ticket) { foreach ($l in $data.ticket.legs) { foreach ($u in @($l.hl, $l.al)) { if ($u) { [void]$urls.Add([string]$u) } } } }
$wc = New-Object System.Net.WebClient
$wc.Headers.Add('User-Agent', 'Mozilla/5.0 TipsOfTheDay')
$map = [ordered]@{}
$md5 = [System.Security.Cryptography.MD5]::Create()
foreach ($u in $urls) {
  $hash = -join ($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($u)) | ForEach-Object { $_.ToString('x2') })
  $isSvg = $u -match '\.svg($|\?)'
  $file = Join-Path $logoDir ($hash + $(if ($isSvg) { '.svg' } else { '.png' }))
  try {
    if (-not (Test-Path $file)) {
      $bytes = $wc.DownloadData($u)
      if ($isSvg) {
        if ($bytes.Length -gt 40000) { continue }   # prevelik svg - preskoci
        [IO.File]::WriteAllBytes($file, $bytes)
      } else {
        $ms = New-Object IO.MemoryStream(,$bytes)
        $img = [System.Drawing.Image]::FromStream($ms)
        $size = 48; $scale = [math]::Min($size / $img.Width, $size / $img.Height)
        $w = [int][math]::Max(1, $img.Width * $scale); $h = [int][math]::Max(1, $img.Height * $scale)
        $bmp = New-Object System.Drawing.Bitmap $size, $size
        $gr = [System.Drawing.Graphics]::FromImage($bmp)
        $gr.InterpolationMode = 'HighQualityBicubic'; $gr.SmoothingMode = 'HighQuality'; $gr.Clear([System.Drawing.Color]::Transparent)
        $gr.DrawImage($img, [int](($size - $w) / 2), [int](($size - $h) / 2), $w, $h)
        $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
        $gr.Dispose(); $bmp.Dispose(); $img.Dispose(); $ms.Dispose()
      }
    }
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($file))
    $map[$u] = $(if ($isSvg) { 'data:image/svg+xml;base64,' } else { 'data:image/png;base64,' }) + $b64
  } catch { Write-Host "  grb nije skinut: $u" }
}
[IO.File]::WriteAllText((Join-Path $root 'logos.json'), ($map | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Grbovi: $($map.Count) od $($urls.Count)"
