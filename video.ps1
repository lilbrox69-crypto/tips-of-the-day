# Tips of the Day - uspravni video (Reels 1080x1920) za tiket dana i jucerasnje rezultate.
# Crta slicice (System.Drawing), ffmpeg ih spaja u MP4. Izlaz: social\<datum>\ticket.mp4 i results.mp4
param([string]$Only = '')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$data = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data.json') | ConvertFrom-Json
$today = $data.today
$hist = $null; $hf = Join-Path $root 'history.json'; if (Test-Path $hf) { $hist = Get-Content -Raw -Encoding UTF8 $hf | ConvertFrom-Json }
$logos = @{}; $lf = Join-Path $root 'logos.json'
if (Test-Path $lf) { (Get-Content -Raw -Encoding UTF8 $lf | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $logos[$_.Name] = $_.Value } }
$outDir = Join-Path $root "social\$today"; New-Item -ItemType Directory -Force $outDir | Out-Null
$ff = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $ff) { Write-Host 'Video: nema ffmpeg - preskacem'; return }

$W = 1080; $H = 1920; $FPS = 25
$MK = @{
  'football' = @{ gg='Oba daju gol'; o15='Više od 1.5 gola'; o25='Više od 2.5 gola'; u25='Manje od 2.5 gola'; c8='Korneri 8+'; y3='Žuti kartoni 3+'; hs='Domaćin daje gol'; as='Gost daje gol'; w1='Pobjeda domaćina'; x='Neriješeno'; w2='Pobjeda gosta' }
  'basketball' = @{ w1='Pobjeda domaćina'; w2='Pobjeda gosta'; o220='Više od 220.5'; u220='Manje od 220.5'; m10='Pobjeda 10+'; h110='Domaćin 110+'; o160='Više od 160.5'; u160='Manje od 160.5'; h80='Domaćin 80+' }
}
function MkName($s, $m) { $t = $MK[[string]$s][[string]$m]; if ($t) { $t } else { [string]$m } }
$gold = [System.Drawing.Color]::FromArgb(244,196,67); $green = [System.Drawing.Color]::FromArgb(61,214,140); $white = [System.Drawing.Color]::FromArgb(238,244,239)
$muted = [System.Drawing.Color]::FromArgb(170,190,176); $red = [System.Drawing.Color]::FromArgb(255,107,107); $dark = [System.Drawing.Color]::FromArgb(11,26,18)
$fontCache = @{}
function F([float]$size, $style = 'Bold', $fam = 'Segoe UI') { $k = "$fam|$style|$size"; if (-not $fontCache[$k]) { $fontCache[$k] = New-Object System.Drawing.Font $fam, $size, ([System.Drawing.FontStyle]$style), ([System.Drawing.GraphicsUnit]::Pixel) }; $fontCache[$k] }
function B($c, [int]$alpha = 255) { New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb([math]::Max(0, [math]::Min(255, $alpha)), $c)) }
function RR([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) { $p = New-Object System.Drawing.Drawing2D.GraphicsPath; $d = $r * 2
  $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90); $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90); $p.CloseFigure(); $p }
$crests = @{}
function Crest($url) {
  if (-not $url) { return $null }; if ($crests.ContainsKey($url)) { return $crests[$url] }
  $img = $null
  try { $bytes = if ($logos[$url] -and ([string]$logos[$url]).StartsWith('data:')) { [Convert]::FromBase64String(([string]$logos[$url]).Split(',')[1]) } else { (New-Object System.Net.WebClient).DownloadData($url) }
        $img = [System.Drawing.Image]::FromStream((New-Object System.IO.MemoryStream(,$bytes))) } catch { $img = $null }
  $crests[$url] = $img; $img
}
function Ease([double]$t) { $t = [math]::Max(0, [math]::Min(1, $t)); 1 - [math]::Pow(1 - $t, 3) }   # ease-out
function Fit($g, $text, $font, $maxW) { $t = [string]$text; while ($t.Length -gt 3 -and $g.MeasureString($t, $font).Width -gt $maxW) { $t = $t.Substring(0, $t.Length - 2) }; if ($t -ne [string]$text) { $t = $t.TrimEnd() + '…' }; $t }
$sfC = New-Object System.Drawing.StringFormat; $sfC.Alignment = 'Center'; $sfC.LineAlignment = 'Center'
$sfR = New-Object System.Drawing.StringFormat; $sfR.Alignment = 'Far'

function Background($g, [double]$t, $c1) {
  $rect = New-Object System.Drawing.Rectangle 0, 0, $W, $H
  $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, $c1, ([System.Drawing.Color]::FromArgb(6,14,10)), 90
  $g.FillRectangle($bg, $rect); $bg.Dispose()
  # sjaj koji se polako pomjera
  $cx = 540 + 260 * [math]::Sin($t * 0.9); $gp = New-Object System.Drawing.Drawing2D.GraphicsPath; $gp.AddEllipse($cx - 520, -380, 1040, 1040)
  $pb = New-Object System.Drawing.Drawing2D.PathGradientBrush $gp; $pb.CenterColor = [System.Drawing.Color]::FromArgb(70, 244, 196, 67); $pb.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 244, 196, 67))
  $g.FillPath($pb, $gp); $pb.Dispose()
  $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(20,255,255,255)), 5
  $g.DrawEllipse($pen, 290, 1480, 500, 500); $g.DrawLine($pen, 0, 1730, $W, 1730); $pen.Dispose()
}
function Brand($g, [double]$a) {
  $al = [int](255 * $a)
  $g.DrawString('TIPS', (F 46 'Bold' 'Arial Black'), (B $white $al), 250, 90)
  $g.DrawString('OF THE', (F 46 'Bold' 'Arial Black'), (B $green $al), 402, 90)
  $g.DrawString('DAY', (F 46 'Bold' 'Arial Black'), (B $gold $al), 616, 90)
}
function LegCard($g, [float]$x, [float]$y, $l, $res, [double]$pop) {
  $g.FillPath((B $white 34), (RR $x $y 1000 238 34))
  $cs = if ($res -ne $null) { 78 } else { 92 }; $gap = if ($res -ne $null) { 88 } else { 104 }; $fs = if ($res -ne $null) { 40 } else { 44 }
  $i = 0; foreach ($u in @($l.hl, $l.al)) { $cy = $y + 18 + $i * $gap; $g.FillEllipse((B $white 240), ($x + 26), $cy, $cs, $cs); $img = Crest $u; if ($img) { $pd = $cs * 0.16; $g.DrawImage($img, ($x + 26 + $pd), ($cy + $pd), ($cs - 2 * $pd), ($cs - 2 * $pd)) }; $i++ }
  $g.DrawString((Fit $g $l.home (F $fs) 540), (F $fs), (B $white), ($x + 130), ($y + 18 + $cs / 2 - $fs * 0.7))
  $g.DrawString((Fit $g $l.away (F $fs) 540), (F $fs), (B $white), ($x + 130), ($y + 18 + $gap + $cs / 2 - $fs * 0.7))
  if ($res -ne $null) {
    $ok = [int]$res.r -eq 1; $col = if ($ok) { $green } else { $red }
    $s = 96 * $pop
    if ($s -gt 2) {
      $cx = $x + 910; $cy = $y + 80
      $g.FillEllipse((B $col), ($cx - $s / 2), ($cy - $s / 2), $s, $s)
      $pen = New-Object System.Drawing.Pen $dark, ([float](12 * $pop)); $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
      if ($ok) { $g.DrawLines($pen, [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF ($cx - 24 * $pop), ($cy + 2 * $pop)), (New-Object System.Drawing.PointF ($cx - 6 * $pop), ($cy + 20 * $pop)), (New-Object System.Drawing.PointF ($cx + 26 * $pop), ($cy - 20 * $pop)))) }
      else { $g.DrawLine($pen, ($cx - 20 * $pop), ($cy - 20 * $pop), ($cx + 20 * $pop), ($cy + 20 * $pop)); $g.DrawLine($pen, ($cx + 20 * $pop), ($cy - 20 * $pop), ($cx - 20 * $pop), ($cy + 20 * $pop)) }
      $pen.Dispose()
    }
    $g.DrawString([string]$res.sc, (F 46 'Bold' 'Arial Black'), (B $white), (New-Object System.Drawing.RectangleF ($x + 640), ($y + 150), 340, 70), $sfR)
    if ($l.mkName) { $mk = [string]$l.mkName; $mw = $g.MeasureString($mk, (F 28)).Width + 36
      $g.FillPath((B $gold 70), (RR ($x + 26) ($y + 190) $mw 42 21)); $g.DrawString($mk, (F 28), (B $white), ($x + 44), ($y + 193)) }
  } else {
    $g.DrawString(('{0:0.00}' -f [double]$l.o).Replace(',', '.'), (F 64 'Bold' 'Arial Black'), (B $gold), (New-Object System.Drawing.RectangleF ($x + 640), ($y + 30), 340, 90), $sfR)
    if ($l.tag) { $g.DrawString([string]$l.tag, (F 28), (B $muted), (New-Object System.Drawing.RectangleF ($x + 640), ($y + 108), 340, 40), $sfR) }
    $mk = [string]$l.mkName; $mw = $g.MeasureString($mk, (F 30)).Width + 40
    $g.FillPath((B $gold 60), (RR ($x + 980 - $mw) ($y + 150) $mw 58 29))
    $g.DrawString($mk, (F 30), (B $white), ($x + 1000 - $mw), ($y + 158))
  }
}
function Cta($g, [double]$a, [double]$t) {
  if ($a -le 0) { return }
  $sc = 1 + 0.04 * [math]::Sin($t * 6); $pw = 760 * $sc; $ph = 130 * $sc; $px = (1080 - $pw) / 2; $py = 1780 - $ph / 2
  $gb = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.RectangleF $px, $py, $pw, $ph), ([System.Drawing.Color]::FromArgb([int](255 * $a), $gold)), ([System.Drawing.Color]::FromArgb([int](255 * $a), $green)), 0
  $g.FillPath($gb, (RR $px $py $pw $ph ($ph / 2))); $gb.Dispose()
  $g.DrawString('tipsoftheday.win', (F (62 * $sc) 'Bold' 'Arial Black'), (B $dark ([int](255 * $a))), (New-Object System.Drawing.RectangleF 0, $py, 1080, $ph), $sfC)
  $g.DrawString('Svi tipovi dana BESPLATNO · Zaprati stranicu', (F 32), (B $white ([int](255 * $a))), (New-Object System.Drawing.RectangleF 0, 1640, $W, 70), $sfC)
  $g.DrawString('Statistika, ne garancija · 18+', (F 28 'Regular'), (B $muted ([int](200 * $a))), (New-Object System.Drawing.RectangleF 0, 1858, $W, 50), $sfC)
}

function Render($name, $seconds, [scriptblock]$draw) {
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ("totd_" + $name); if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }; New-Item -ItemType Directory $tmp | Out-Null
  $n = [int]($seconds * $FPS)
  $bmp = New-Object System.Drawing.Bitmap $W, $H; $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'; $g.InterpolationMode = 'HighQualityBicubic'
  $jpg = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
  $ep = New-Object System.Drawing.Imaging.EncoderParameters 1; $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 92L
  for ($i = 0; $i -lt $n; $i++) { & $draw $g ($i / $FPS); $bmp.Save((Join-Path $tmp ('f{0:0000}.jpg' -f $i)), $jpg, $ep) }
  $g.Dispose(); $bmp.Dispose()
  $out = Join-Path $outDir "$name.mp4"
  & $ff -y -loglevel error -framerate $FPS -i (Join-Path $tmp 'f%04d.jpg') -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" -shortest -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p -c:a aac -b:a 96k -movflags +faststart $out
  Remove-Item $tmp -Recurse -Force
  Write-Host "Video: $out ($([math]::Round((Get-Item $out).Length / 1MB, 1)) MB)"
}

# ---------- 1) video tiketa dana ----------
if ($data.ticket -and @($data.ticket.legs).Count -and $Only -ne 'results') {
  $t0 = $data.ticket; $legs = @($t0.legs | ForEach-Object { $_ | Add-Member -NotePropertyName mkName -NotePropertyValue (MkName $_.sport $_.mk) -Force -PassThru })
  $dt = [datetime]::ParseExact($today, 'yyyy-MM-dd', $null)
  $legStart = 1.3; $legGap = 1.1; $tot = $legStart + $legs.Count * $legGap + 0.4; $dur = $tot + 4.5
  Render 'ticket' $dur {
    param($g, $t)
    Background $g $t ([System.Drawing.Color]::FromArgb(86,66,12))
    Brand $g (Ease ($t / 0.5))
    $e = Ease (($t - 0.2) / 0.6); $g.DrawString('TIKET DANA', (F 132 'Bold' 'Arial Black'), (B $gold ([int](255 * $e))), (New-Object System.Drawing.RectangleF 0, (190 + 60 * (1 - $e)), $W, 180), $sfC)
    $g.DrawString("$($dt.Day).$($dt.Month).$($dt.Year).  ·  $($legs.Count) para", (F 44 'Regular'), (B $white ([int](255 * $e))), (New-Object System.Drawing.RectangleF 0, 370, $W, 70), $sfC)
    $y = 450; $step = if ($legs.Count -gt 3) { 250 } else { 280 }
    for ($k = 0; $k -lt $legs.Count; $k++) { $p = Ease (($t - $legStart - $k * $legGap) / 0.55); if ($p -gt 0) { LegCard $g (40 + 1100 * (1 - $p)) ($y + $k * $step) $legs[$k] $null 0 } }
    $p = Ease (($t - $tot) / 0.5)
    if ($p -gt 0) {
      $sc = 0.6 + 0.4 * $p; $bw = 1000 * $sc; $bh = 170 * $sc; $bx = ($W - $bw) / 2; $by = $y + $legs.Count * $step + 10
      $g.FillPath((B $gold ([int](90 * $p))), (RR $bx $by $bw $bh (30 * $sc)))
      $g.DrawString('UKUPNA KVOTA', (F (44 * $sc)), (B $white ([int](255 * $p))), ($bx + 40 * $sc), ($by + 58 * $sc))
      $g.DrawString(('{0:0.00}' -f [double]$t0.odd).Replace(',', '.'), (F (104 * $sc) 'Bold' 'Arial Black'), (B $gold ([int](255 * $p))), (New-Object System.Drawing.RectangleF $bx, ($by + 10 * $sc), ($bw - 40 * $sc), $bh), $sfR)
    }
    Cta $g (Ease (($t - $tot - 1.0) / 0.5)) $t
  }
}

# ---------- 1b) petkom: tiket vikenda (cache\weekend.json pravi weekend.ps1) ----------
$wf = Join-Path $root 'cache\weekend.json'
$wk = if (Test-Path $wf) { Get-Content -Raw -Encoding UTF8 $wf | ConvertFrom-Json } else { $null }
if ($wk -and $wk.date -eq $today -and @($wk.legs).Count -and $Only -ne 'results') {
  $legs = @($wk.legs | ForEach-Object { $_ | Add-Member -NotePropertyName mkName -NotePropertyValue (MkName $_.sport $_.mk) -Force -PassThru |
    Add-Member -NotePropertyName tag -NotePropertyValue "$(if ($_.day -eq 'SUB') { 'Subota' } else { 'Nedjelja' }) $($_.time)" -Force -PassThru })
  $d1 = [datetime]::ParseExact($wk.sat, 'yyyy-MM-dd', $null); $d2 = [datetime]::ParseExact($wk.sun, 'yyyy-MM-dd', $null)
  $legStart = 1.3; $legGap = 1.0; $tot = $legStart + $legs.Count * $legGap + 0.4; $dur = $tot + 4.5
  Render 'weekend' $dur {
    param($g, $t)
    Background $g $t ([System.Drawing.Color]::FromArgb(20,46,96))
    Brand $g (Ease ($t / 0.5))
    $e = Ease (($t - 0.2) / 0.6); $g.DrawString('TIKET VIKENDA', (F 96 'Bold' 'Arial Black'), (B $gold ([int](255 * $e))), (New-Object System.Drawing.RectangleF 0, (200 + 60 * (1 - $e)), $W, 160), $sfC)
    $g.DrawString("Subota i nedjelja $($d1.Day).–$($d2.Day).$($d2.Month).  ·  $($legs.Count) para", (F 42 'Regular'), (B $white ([int](255 * $e))), (New-Object System.Drawing.RectangleF 0, 370, $W, 70), $sfC)
    $y = 450; $step = if ($legs.Count -gt 3) { 250 } else { 280 }
    for ($k = 0; $k -lt $legs.Count; $k++) { $p = Ease (($t - $legStart - $k * $legGap) / 0.55); if ($p -gt 0) { LegCard $g (40 + 1100 * (1 - $p)) ($y + $k * $step) $legs[$k] $null 0 } }
    $p = Ease (($t - $tot) / 0.5)
    if ($p -gt 0) {
      $sc = 0.6 + 0.4 * $p; $bw = 1000 * $sc; $bh = 170 * $sc; $bx = ($W - $bw) / 2; $by = $y + $legs.Count * $step + 10
      $g.FillPath((B $gold ([int](90 * $p))), (RR $bx $by $bw $bh (30 * $sc)))
      $g.DrawString('UKUPNA KVOTA', (F (44 * $sc)), (B $white ([int](255 * $p))), ($bx + 40 * $sc), ($by + 58 * $sc))
      $g.DrawString(('{0:0.00}' -f [double]$wk.odd).Replace(',', '.'), (F (104 * $sc) 'Bold' 'Arial Black'), (B $gold ([int](255 * $p))), (New-Object System.Drawing.RectangleF $bx, ($by + 10 * $sc), ($bw - 40 * $sc), $bh), $sfR)
    }
    Cta $g (Ease (($t - $tot - 1.0) / 0.5)) $t
  }
}

# ---------- 2) video rezultata (jucerasnji tiket) ----------
$yd = ([datetime]::ParseExact($today, 'yyyy-MM-dd', $null)).AddDays(-1).ToString('yyyy-MM-dd')
$yh = if ($hist) { @($hist.days | Where-Object { $_.date -eq $yd })[0] } else { $null }
if ($yh -and $yh.t -and $yh.t.r -ne $null -and $Only -ne 'ticket') {
  $ok = [int]$yh.t.r -eq 1; $legs = @($yh.t.legs | ForEach-Object { [pscustomobject]@{ home = $_.h; away = $_.a; hl = $_.hl; al = $_.al; r = $_.r; sc = ([string]$_.sc).Replace('-', ':'); mkName = (MkName $_.s $_.m) } })
  $dt = [datetime]::ParseExact($yd, 'yyyy-MM-dd', $null)
  $legStart = 1.2; $legGap = 0.5; $checkStart = $legStart + $legs.Count * $legGap + 0.4; $checkGap = 0.7; $stamp = $checkStart + $legs.Count * $checkGap + 0.3; $dur = $stamp + 5
  Render 'results' $dur {
    param($g, $t)
    Background $g $t ($(if ($ok) { [System.Drawing.Color]::FromArgb(14,84,48) } else { [System.Drawing.Color]::FromArgb(84,24,24) }))
    Brand $g (Ease ($t / 0.5))
    $e = Ease (($t - 0.2) / 0.6); $g.DrawString('REZULTATI', (F 132 'Bold' 'Arial Black'), (B $gold ([int](255 * $e))), (New-Object System.Drawing.RectangleF 0, (190 + 60 * (1 - $e)), $W, 180), $sfC)
    $g.DrawString("Tiket dana od $($dt.Day).$($dt.Month).  ·  kvota $(('{0:0.00}' -f [double]$yh.t.odd).Replace(',', '.'))", (F 44 'Regular'), (B $white ([int](255 * $e))), (New-Object System.Drawing.RectangleF 0, 370, $W, 70), $sfC)
    $y = 450; $step = if ($legs.Count -gt 3) { 250 } else { 280 }
    for ($k = 0; $k -lt $legs.Count; $k++) {
      $p = Ease (($t - $legStart - $k * $legGap) / 0.5); if ($p -le 0) { continue }
      $pop = $t - $checkStart - $k * $checkGap; $pp = if ($pop -le 0) { 0 } elseif ($pop -lt 0.25) { 1.25 * ($pop / 0.25) } elseif ($pop -lt 0.4) { 1.25 - 0.25 * (($pop - 0.25) / 0.15) } else { 1 }
      LegCard $g (40 + 1100 * (1 - $p)) ($y + $k * $step) $legs[$k] $legs[$k] $pp
    }
    $p = $t - $stamp
    if ($p -gt 0) {
      $s = if ($p -lt 0.3) { 2.2 - 1.2 * ($p / 0.3) } else { 1 }; $al = [int](255 * [math]::Min(1, $p / 0.2))
      $st = $g.Save(); $g.TranslateTransform(540, 1140); $g.RotateTransform(-8); $g.ScaleTransform($s, $s)
      $col = if ($ok) { $green } else { $red }
      $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb($al, $col)), 14
      $g.FillPath((B $dark ([int]($al * 0.85))), (RR -450 -120 900 240 40)); $g.DrawPath($pen, (RR -450 -120 900 240 40)); $pen.Dispose()
      $g.DrawString($(if ($ok) { 'PROŠAO!' } else { 'NIJE PROŠAO' }), (F $(if ($ok) { 150 } else { 104 }) 'Bold' 'Arial Black'), (B $col $al), (New-Object System.Drawing.RectangleF -450, -120, 900, 240), $sfC)
      $g.Restore($st)
    }
    Cta $g (Ease (($t - $stamp - 1.2) / 0.5)) $t
  }
}
