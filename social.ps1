# Tips of the Day - Facebook objave: pravi kartice (1080x1350 PNG) i raspored objava za danas.
# Izlaz: social\<datum>\NN.png i social\posts.json (objavljuje ih post.ps1 preko Make webhooka).
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$data = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data.json') | ConvertFrom-Json
$today = $data.today
$hist = $null; $hf = Join-Path $root 'history.json'; if (Test-Path $hf) { $hist = Get-Content -Raw -Encoding UTF8 $hf | ConvertFrom-Json }
$logos = @{}; $lf = Join-Path $root 'logos.json'
if (Test-Path $lf) { (Get-Content -Raw -Encoding UTF8 $lf | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $logos[$_.Name] = $_.Value } }
$outDir = Join-Path $root "social\$today"; New-Item -ItemType Directory -Force $outDir | Out-Null
Get-ChildItem (Join-Path $root 'social') -Directory | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and $_.Name -lt ([datetime]::ParseExact($today,'yyyy-MM-dd',$null).AddDays(-3).ToString('yyyy-MM-dd')) } | Remove-Item -Recurse -Force
$SITE = 'https://tipsoftheday.win'

$MK = @{
  'football' = @{ gg='Oba daju gol'; o15='Više od 1.5 gola'; o25='Više od 2.5 gola'; u25='Manje od 2.5 gola'; c8='Korneri 8+'; y3='Žuti kartoni 3+'; hs='Domaćin daje gol'; as='Gost daje gol'; w1='Pobjeda domaćina'; x='Neriješeno'; w2='Pobjeda gosta' }
  'basketball' = @{ w1='Pobjeda domaćina'; w2='Pobjeda gosta'; o220='Više od 220.5'; u220='Manje od 220.5'; m10='Pobjeda 10+ razlike'; h110='Domaćin 110+'; o160='Više od 160.5'; u160='Manje od 160.5'; h80='Domaćin 80+' }
}
function MkName($s, $m) { $t = $MK[$s][$m]; if ($t) { $t } else { $m } }

# ---------- crtanje ----------
$W = 1080; $H = 1350
$C = @{ gold=[System.Drawing.Color]::FromArgb(244,196,67); green=[System.Drawing.Color]::FromArgb(61,214,140); white=[System.Drawing.Color]::FromArgb(238,244,239)
        muted=[System.Drawing.Color]::FromArgb(157,176,163); red=[System.Drawing.Color]::FromArgb(255,107,107); dark=[System.Drawing.Color]::FromArgb(11,26,18)
        card=[System.Drawing.Color]::FromArgb(30,255,255,255); line=[System.Drawing.Color]::FromArgb(40,255,255,255) }
function F($size, $style = 'Bold', $fam = 'Segoe UI') { New-Object System.Drawing.Font $fam, $size, ([System.Drawing.FontStyle]$style), ([System.Drawing.GraphicsUnit]::Pixel) }
function B($c) { New-Object System.Drawing.SolidBrush $c }
function RR($x, $y, $w, $h, $r) { $p = New-Object System.Drawing.Drawing2D.GraphicsPath; $d = $r * 2
  $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90); $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90); $p.CloseFigure(); $p }
$crestCache = @{}
function Crest($url) {
  if (-not $url) { return $null }; if ($crestCache.ContainsKey($url)) { return $crestCache[$url] }
  $img = $null
  try {
    $bytes = $null
    if ($logos[$url] -and ([string]$logos[$url]).StartsWith('data:')) { $bytes = [Convert]::FromBase64String(([string]$logos[$url]).Split(',')[1]) }
    else { $wc = New-Object System.Net.WebClient; $bytes = $wc.DownloadData($url) }
    $ms = New-Object System.IO.MemoryStream(,$bytes); $img = [System.Drawing.Image]::FromStream($ms)
  } catch { $img = $null }
  $crestCache[$url] = $img; $img
}
function DrawCrest($g, $url, $x, $y, $s) {
  $g.FillEllipse((B ([System.Drawing.Color]::FromArgb(235,255,255,255))), $x, $y, $s, $s)
  $img = Crest $url
  if ($img) { $pad = [int]($s * 0.14); $g.DrawImage($img, $x + $pad, $y + $pad, $s - 2 * $pad, $s - 2 * $pad) }
}
function Fit($g, $text, $font, $maxW) { $t = [string]$text; while ($t.Length -gt 3 -and $g.MeasureString($t, $font).Width -gt $maxW) { $t = $t.Substring(0, $t.Length - 2) }; if ($t -ne [string]$text) { $t = $t.TrimEnd() + '…' }; $t }
function Canvas($hue) {
  $bmp = New-Object System.Drawing.Bitmap $W, $H; $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'; $g.InterpolationMode = 'HighQualityBicubic'
  $rect = New-Object System.Drawing.Rectangle 0, 0, $W, $H
  $top = [System.Drawing.Color]::FromArgb($hue[0], $hue[1], $hue[2])
  $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, $top, ([System.Drawing.Color]::FromArgb(7,16,11)), 90
  $g.FillRectangle($bg, $rect)
  # teren u pozadini
  $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(18,255,255,255)), 4
  $g.DrawEllipse($pen, 690, -170, 560, 560); $g.DrawLine($pen, 0, 110, $W, 110)
  # brend
  $g.DrawString('TIPS', (F 34 'Bold' 'Arial Black'), (B $C.white), 60, 38)
  $g.DrawString('OF THE', (F 34 'Bold' 'Arial Black'), (B $C.green), 172, 38)
  $g.DrawString('DAY', (F 34 'Bold' 'Arial Black'), (B $C.gold), 330, 38)
  $dt = [datetime]::ParseExact($today, 'yyyy-MM-dd', $null)
  $days = @('Nedjelja','Ponedjeljak','Utorak','Srijeda','Četvrtak','Petak','Subota')
  $ds = "$($days[[int]$dt.DayOfWeek]) · $($dt.Day).$($dt.Month).$($dt.Year)."
  $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Far'
  $g.DrawString($ds, (F 30 'Bold'), (B $C.muted), (New-Object System.Drawing.RectangleF 500, 44, 520, 44), $sf)
  @{ bmp = $bmp; g = $g }
}
function Title($g, $title, $sub, $color) {
  $g.DrawString($title, (F 84 'Bold' 'Arial Black'), (B $color), 52, 128)
  if ($sub) { $g.DrawString($sub, (F 34 'Regular'), (B $C.white), 60, 250) }
}
function Footer($g) {
  $p = RR 250 ($H - 150) 580 84 42
  $gb = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Rectangle 250, ($H - 150), 580, 84), $C.gold, $C.green, 0
  $g.FillPath($gb, $p)
  $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
  $g.DrawString('tipsoftheday.win', (F 46 'Bold' 'Arial Black'), (B $C.dark), (New-Object System.Drawing.RectangleF 250, ($H - 150), 580, 84), $sf)
  $g.DrawString('Statistika, ne garancija  ·  18+  ·  igraj odgovorno', (F 24 'Regular'), (B $C.muted), (New-Object System.Drawing.RectangleF 0, ($H - 56), $W, 40), $sf)
}
# jedan red: grbovi, timovi, liga/vrijeme, opcija, procenat i kvota (ili rezultat)
function Row($g, $y, $h, $it, $idx) {
  $g.FillPath((B $C.card), (RR 40 $y 1000 $h 30))
  if ($idx) { $g.DrawString([string]$idx, (F 56 'Bold' 'Arial Black'), (B $C.gold), 58, ($y + ($h - 80) / 2)) }
  $cx = if ($idx) { 130 } else { 66 }
  $showMeta = $h -ge 200; $s = [int][math]::Min(74, ($h - 40 - $(if ($showMeta) { 44 } else { 0 })) / 2 - 4)
  $c1 = $y + 20; $c2 = $c1 + $s + 8
  DrawCrest $g $it.hl $cx $c1 $s
  DrawCrest $g $it.al $cx $c2 $s
  $tx = $cx + $s + 22; $maxW = 600 - ($tx - 130)
  $g.DrawString((Fit $g $it.home (F 38 'Bold') $maxW), (F 38 'Bold'), (B $C.white), $tx, ($c1 + $s / 2 - 26))
  $g.DrawString((Fit $g $it.away (F 38 'Bold') $maxW), (F 38 'Bold'), (B $C.white), $tx, ($c2 + $s / 2 - 26))
  $meta = (@($it.mk, $it.league, $it.time) | Where-Object { $_ }) -join '  ·  '
  if ($showMeta) { $g.DrawString((Fit $g $meta (F 26 'Regular') 700), (F 26 'Regular'), (B $C.muted), ($cx), ($y + $h - 48)) }
  $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Far'
  if ($it.res -ne $null) {
    $ok = [int]$it.res -eq 1; $col = if ($ok) { $C.green } else { $C.red }
    $cy = if ($h -ge 200) { $y + 40 } else { $y + 16 }; $g.FillEllipse((B $col), 930, $cy, 80, 80)
    $pen = New-Object System.Drawing.Pen $C.dark, 10; $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
    if ($ok) { $g.DrawLines($pen, [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF 950, ($cy + 42)), (New-Object System.Drawing.PointF 964, ($cy + 58)), (New-Object System.Drawing.PointF 992, ($cy + 22)))) }
    else { $g.DrawLine($pen, 952, ($cy + 22), 988, ($cy + 58)); $g.DrawLine($pen, 988, ($cy + 22), 952, ($cy + 58)) }
    if ($it.sc) { $g.DrawString([string]$it.sc, (F 40 'Bold' 'Arial Black'), (B $C.white), (New-Object System.Drawing.RectangleF 700, ($cy + 90), 318, 60), $sf) }
  } else {
    $g.DrawString("$($it.p)%", (F 70 'Bold' 'Arial Black'), (B $C.gold), (New-Object System.Drawing.RectangleF 700, ($y + 24), 318, 100), $sf)
    if ($it.o) {
      $ot = 'kvota ' + ('{0:0.00}' -f [double]$it.o).Replace(',', '.')
      $ow = $g.MeasureString($ot, (F 28 'Bold')).Width + 36
      $g.FillPath((B ([System.Drawing.Color]::FromArgb(60,255,255,255))), (RR (1012 - $ow) ($y + 128) $ow 50 25))
      $g.DrawString($ot, (F 28 'Bold'), (B $C.white), (1012 - $ow + 18), ($y + 135))
    }
  }
}
function Save($cv, $n) { $p = Join-Path $outDir ('{0:00}.png' -f $n); $cv.bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png); $cv.g.Dispose(); $cv.bmp.Dispose(); "$SITE/social/$today/$('{0:00}' -f $n).png?v=$today" }

# ---------- podaci ----------
$fb = @(($data.days | Where-Object { $_.date -eq $today }).matches | Where-Object { $_ })
$bb = @(); if ($data.sports.basketball) { $bb = @(($data.sports.basketball.days | Where-Object { $_.date -eq $today }).matches | Where-Object { $_ }) }
function Top($list, $sport, $mks, $after, $n = 3, $minO = 0) {
  $c = foreach ($m in $list) { foreach ($k in $mks) { $p = $m.p.$k; if ($p -ne $null -and [string]$m.time -gt $after) {
    $o = if ($m.o) { $m.o.$k } else { $null }; if ($minO -and (-not $o -or [double]$o -lt $minO)) { continue }
    [pscustomobject]@{ id = $m.id; home = $m.home; away = $m.away; hl = $m.hl; al = $m.al; league = $m.league; time = $m.time; p = [int]$p; o = $o; k = $k; mk = (MkName $sport $k); m = $m } } } }
  $seen = @{}; $out = @(); foreach ($x in ($c | Sort-Object @{ e = { $_.p }; Descending = $true }, @{ e = { $_.time } })) { if ($seen[$x.id]) { continue }; $seen[$x.id] = 1; $out += $x; if ($out.Count -ge $n) { break } }; $out
}
function Pct($x) { "$([int]$x.p)%" }
function Line($x) { "⚽ $($x.home) – $($x.away) ($($x.time)) · $($x.mk) · $([int]$x.p)%" + $(if ($x.o) { " · kvota $(('{0:0.00}' -f [double]$x.o).Replace(',', '.'))" } else { '' }) }
$TAG = ''   # zavrsni dio (link, pitanje, 18+) dodaje AddPost
$posts = New-Object System.Collections.ArrayList; $n = 0
$NM = $fb.Count + $bb.Count
# pitanje na kraju objave -> komentari -> Facebook objavu pokaze vecem broju ljudi
$Q = @{ results = 'Jesi li igrao jučerašnji tiket? Pohvali se u komentaru 👇'; ticket = 'Igraš li današnji tiket? Napiši "IGRAM" u komentar 👇'
        weekend = 'Igraš li tiket vikenda? Napiši "IGRAM" u komentar 👇'
        match = 'Šta ti kažeš – prolazi ili ne? 👇'; stats = 'Koliko tvoj tipster pogađa? 😉 Napiši u komentar 👇'; evening = 'Koju utakmicu večeras gledaš? 👇' }
function AddPost($t, $kind, $img, $text) {
  # 1. red = udica, 2. red = link (Facebook skrati tekst poslije 2-3 reda, link mora biti gore)
  $lines = ([string]$text).Split("`n"); $hook = $lines[0]; $body = (($lines | Select-Object -Skip 1) -join "`n").Trim()
  $cta = if ($kind -eq 'results') { '👉 Današnji tiket i svi tipovi: https://tipsoftheday.win' } else { '👉 Svi tipovi dana besplatno: https://tipsoftheday.win' }
  $more = if ($NM -gt 20 -and $kind -notin 'results', 'stats') { "`n`n🔎 Danas smo analizirali $NM utakmica – ovdje su samo najbolji. Ostale opcije (golovi, korneri, kartoni, pobjede, košarka) čekaju te na stranici." } else { '' }
  $q = if ($Q[$kind]) { $Q[$kind] } else { 'Koji od ova 3 bi ti stavio na tiket? 👇' }
  # u pola objava jasno kazemo da je sve besplatno (bez VIP grupa i placanja - za razliku od konkurencije)
  $free = if ($kind -in 'results', 'ticket', 'stats', 'evening', 'OBA DAJU GOL', 'KOŠARKA DANA', 'weekend') { "`n`n💯 Tips of the Day je POTPUNO BESPLATAN – bez registracije, bez VIP grupa, bez plaćanja. Samo uđi na https://tipsoftheday.win i sve je tu." } else { '' }
  $final = "$hook`n$cta`n`n$body$more$free`n`n💬 $q`n`n🔔 Zaprati stranicu – tiket dana stiže svako jutro u 8h.`nStatistika, ne garancija · 18+ · igraj odgovorno`n#tiketdana #tipovi #fudbal #kosarka #tipsoftheday"
  # tiket i rezultati idu kao VIDEO (Reels) ako ga je video.ps1 napravio; slika ostaje rezerva
  $vid = ''; if ($kind -in 'ticket', 'results', 'weekend' -and (Test-Path (Join-Path $outDir "$kind.mp4"))) { $vid = "$SITE/social/$today/$kind.mp4?v=$today" }
  [void]$posts.Add([ordered]@{ t = $t; kind = $kind; image = $img; video = $vid; text = $final })
}

# 1) 06:30 rezultati juče
$yd = ([datetime]::ParseExact($today, 'yyyy-MM-dd', $null)).AddDays(-1).ToString('yyyy-MM-dd')
$yh = if ($hist) { @($hist.days | Where-Object { $_.date -eq $yd })[0] } else { $null }
if ($yh -and $yh.t -and $yh.t.r -ne $null) {
  $n++; $cv = Canvas @(20,70,44); $ok = [int]$yh.t.r -eq 1
  $dt = [datetime]::ParseExact($yd, 'yyyy-MM-dd', $null)
  Title $cv.g 'REZULTATI' "Tiket dana od $($dt.Day).$($dt.Month). · kvota $(('{0:0.00}' -f [double]$yh.t.odd).Replace(',', '.'))" $C.gold
  $legs = @($yh.t.legs); $rh = if ($legs.Count -gt 3) { 168 } else { 220 }; $y = 320
  foreach ($l in $legs) { Row $cv.g $y $rh ([pscustomobject]@{ home = $l.h; away = $l.a; hl = $l.hl; al = $l.al; mk = (MkName $l.s $l.m); res = $l.r; sc = $l.sc }) $null; $y += $rh + 16 }
  $bx = RR 40 ($y + 6) 1000 110 30; $g = $cv.g
  $g.FillPath((B $(if ($ok) { [System.Drawing.Color]::FromArgb(70,61,214,140) } else { [System.Drawing.Color]::FromArgb(70,255,107,107) })), $bx)
  $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
  $g.DrawString($(if ($ok) { 'TIKET PROŠAO' } else { 'TIKET PAO' }), (F 60 'Bold' 'Arial Black'), (B $(if ($ok) { $C.green } else { $C.red })), (New-Object System.Drawing.RectangleF 40, ($y + 6), 1000, 110), $sf)
  $kk = @($yh.k | Where-Object { $_.r -ne $null }); $kh = @($kk | Where-Object { $_.r -eq 1 }).Count
  Footer $g; $img = Save $cv $n
  $lines = ($legs | ForEach-Object { "$(if ([int]$_.r -eq 1) { '✅' } else { '❌' }) $($_.h) – $($_.a) · $(MkName $_.s $_.m) · $($_.sc)" }) -join "`n"
  $head = if ($ok) { "✅✅ TIKET DANA JE PROŠAO! Kvota $(('{0:0.00}' -f [double]$yh.t.odd).Replace(',', '.')) 🎉" } else { "❌ Jučerašnji tiket dana (kvota $(('{0:0.00}' -f [double]$yh.t.odd).Replace(',', '.'))) nije prošao." }
  AddPost '08:00' 'results' $img ("$head`n`n$lines`n`n📊 Svi jučerašnji tipovi: $kh/$($kk.Count) pogođeno. Objavljujemo sve rezultate — i pogođene i promašene.$TAG")
}

# 2) 07:00 tiket dana
if ($data.ticket -and @($data.ticket.legs).Count) {
  $n++; $cv = Canvas @(92,70,10); $t = $data.ticket; $legs = @($t.legs)
  Title $cv.g 'TIKET DANA' "$($legs.Count) para · najveća šansa za kvotu 1.70+" $C.gold
  $rh = if ($legs.Count -gt 3) { 168 } else { 232 }; $y = 320
  foreach ($l in $legs) { Row $cv.g $y $rh ([pscustomobject]@{ home = $l.home; away = $l.away; hl = $l.hl; al = $l.al; league = $l.league; time = $l.time; mk = (MkName $l.sport $l.mk); p = $l.p; o = $l.o }) $null; $y += $rh + 16 }
  $g = $cv.g; $g.FillPath((B ([System.Drawing.Color]::FromArgb(60,244,196,67))), (RR 40 ($y + 6) 1000 120 30))
  $g.DrawString('UKUPNA KVOTA', (F 34 'Bold'), (B $C.white), 80, ($y + 44))
  $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Far'
  $g.DrawString(('{0:0.00}' -f [double]$t.odd).Replace(',', '.'), (F 80 'Bold' 'Arial Black'), (B $C.gold), (New-Object System.Drawing.RectangleF 500, ($y + 10), 510, 110), $sf)
  Footer $g; $img = Save $cv $n
  $lines = ($legs | ForEach-Object { "$(if ($_.sport -eq 'basketball') { '🏀' } else { '⚽' }) $($_.home) – $($_.away) ($($_.time))`n   ➜ $(MkName $_.sport $_.mk) @ $(('{0:0.00}' -f [double]$_.o).Replace(',', '.'))" }) -join "`n"
  AddPost '08:30' 'ticket' $img ("🎫 TIKET DANA · ukupna kvota $(('{0:0.00}' -f [double]$t.odd).Replace(',', '.'))`n`n$lines`n`nOdabrano statistikom iz svih liga svijeta: forma, međusobni susreti, povrede i kvote. Rezultat objavljujemo sutra ujutro, prošao ili ne. 🍀$TAG")
}

# 3) 08:30 utakmica dana (najsigurniji tip sa kvotom)
$best = @(Top $fb 'football' @('o15','gg','o25','w1','w2','hs','as') '10:00' 1 1.15)
if ($best.Count) {
  $x = $best[0]; $m = $x.m; $n++; $cv = Canvas @(16,60,90)
  Title $cv.g 'UTAKMICA DANA' "$($x.league)" $C.gold
  Row $cv.g 320 250 $x $null
  $g = $cv.g; $y = 600
  $facts = @()
  if ($m.hs -and $m.hs.form) { $facts += "Forma domaćina: $($m.hs.form)  ·  gostiju: $($m.as.form)" }
  if ($m.hs -and $m.hs.n) { $facts += "Domaćin daje $($m.hs.gf) · prima $($m.hs.ga) gola po utakmici" }
  if ($m.as -and $m.as.n) { $facts += "Gost daje $($m.as.gf) · prima $($m.as.ga) gola po utakmici" }
  if ($m.h2h -and $m.h2h.n) { $facts += "Međusobno ($($m.h2h.n)): $($m.h2h.res)" }
  if ($m.xg) { $facts += "Očekivani golovi (xG): $($m.xg[0]) – $($m.xg[1])" }
  foreach ($f in $facts | Select-Object -First 5) { $g.FillEllipse((B $C.green), 64, ($y + 16), 18, 18); $g.DrawString((Fit $g $f (F 34 'Regular') 900), (F 34 'Regular'), (B $C.white), 100, $y); $y += 70 }
  Footer $g; $img = Save $cv $n
  AddPost '09:30' 'match' $img ("⭐ UTAKMICA DANA`n`n⚽ $($x.home) – $($x.away) ($($x.time), $($x.league))`n➜ $($x.mk): $([int]$x.p)% šanse" + $(if ($x.o) { " · kvota $(('{0:0.00}' -f [double]$x.o).Replace(',', '.'))" } else { '' }) + "`n`n📊 " + ($facts -join "`n📊 ") + $TAG)
}

# 4..) top 3 po opciji - svaka u svoje vrijeme, samo utakmice koje još nisu počele
$slots = @(
  @{ t='10:30'; s='football'; mks=@('gg');  title='OBA DAJU GOL'; hue=@(18,84,52); emo='⚽⚽' }
  @{ t='11:30'; s='football'; mks=@('o25'); title='VIŠE OD 2.5'; hue=@(92,40,20); emo='🔥' }
  @{ t='13:00'; s='football'; mks=@('w1','w2'); title='POBJEDE DANA'; hue=@(40,40,100); emo='🏆' }
  @{ t='14:30'; s='football'; mks=@('o15'); title='2+ GOLA'; hue=@(20,80,80); emo='🎯' }
  @{ t='15:30'; s='football'; mks=@('c8');  title='KORNERI 8+'; hue=@(70,70,20); emo='🚩' }
  @{ t='16:30'; s='basketball'; mks=@('w1','w2','o160','o220'); title='KOŠARKA DANA'; hue=@(100,50,10); emo='🏀' }
  @{ t='18:30'; s='football'; mks=@('hs','as'); title='DAJE GOL'; hue=@(20,70,40); emo='⚽' }
)
foreach ($sl in $slots) {
  $list = if ($sl.s -eq 'basketball') { $bb } else { $fb }
  $after = ([datetime]::ParseExact($sl.t, 'HH:mm', $null)).AddMinutes(20).ToString('HH:mm')
  $top = @(Top $list $sl.s $sl.mks $after 3)
  if ($top.Count -lt 2) { continue }
  $n++; $cv = Canvas $sl.hue; Title $cv.g $sl.title 'Top 3 najsigurnija tipa · utakmice koje tek počinju' $C.gold
  $y = 320; $i = 0; foreach ($x in $top) { $i++; Row $cv.g $y 250 $x $i; $y += 266 }
  Footer $cv.g; $img = Save $cv $n
  $ic = if ($sl.s -eq 'basketball') { '🏀' } else { '⚽' }
  $lines = ($top | ForEach-Object { "$ic $($_.home) – $($_.away) ($($_.time))`n   ➜ $($_.mk): $([int]$_.p)%" + $(if ($_.o) { " · kvota $(('{0:0.00}' -f [double]$_.o).Replace(',', '.'))" } else { '' }) }) -join "`n"
  AddPost $sl.t $sl.title $img "$($sl.emo) $($sl.title) – top 3 za danas`n`n$lines$TAG"
}

# 12:00 petkom: tiket vikenda (subota + nedjelja; jake lige, a u reprezentativnoj pauzi sve)
$wf = Join-Path $root 'cache\weekend.json'
$wk = if (Test-Path $wf) { Get-Content -Raw -Encoding UTF8 $wf | ConvertFrom-Json } else { $null }
if ($wk -and $wk.date -eq $today -and @($wk.legs).Count) {
  $n++; $cv = Canvas @(20,46,96); $legs = @($wk.legs)
  $d1 = [datetime]::ParseExact($wk.sat, 'yyyy-MM-dd', $null); $d2 = [datetime]::ParseExact($wk.sun, 'yyyy-MM-dd', $null)
  $cv.g.DrawString('TIKET VIKENDA', (F 76 'Bold' 'Arial Black'), (B $C.gold), 52, 134)
  $cv.g.DrawString("Subota i nedjelja $($d1.Day).–$($d2.Day).$($d2.Month). · $($legs.Count) para · kvota $(('{0:0.00}' -f [double]$wk.odd).Replace(',', '.'))", (F 34 'Bold'), (B $C.white), 60, 250)
  # ukupna kvota je u podnaslovu, pa 4 para stanu sa opcijom i danom
  $rh = if ($legs.Count -gt 3) { 200 } else { 232 }; $y = 320
  foreach ($l in $legs) { Row $cv.g $y $rh ([pscustomobject]@{ home = $l.home; away = $l.away; hl = $l.hl; al = $l.al; league = $null; time = "$(if ($l.day -eq 'SUB') { 'Sub' } else { 'Ned' }) $($l.time)"; mk = (MkName $l.sport $l.mk); p = $l.p; o = $l.o }) $null; $y += $rh + 16 }
  $g = $cv.g; Footer $g; $img = Save $cv $n
  $lines = ($legs | ForEach-Object { "⚽ $($_.home) – $($_.away) ($(if ($_.day -eq 'SUB') { 'subota' } else { 'nedjelja' }) $($_.time))`n   ➜ $(MkName $_.sport $_.mk) @ $(('{0:0.00}' -f [double]$_.o).Replace(',', '.'))" }) -join "`n"
  AddPost '12:00' 'weekend' $img ("📅 TIKET VIKENDA · ukupna kvota $(('{0:0.00}' -f [double]$wk.odd).Replace(',', '.'))`n`n$lines`n`nNajsigurniji parovi za subotu i nedjelju: forma, međusobni susreti, povrede i kvote. Tiket dana stiže i u subotu i u nedjelju ujutro. 🍀$TAG")
}

# 17:30 statistika zadnjih 30 dana
if ($data.track -and $data.track.n -ge 10) {
  $tr = $data.track; $n++; $cv = Canvas @(50,30,90); $g = $cv.g
  Title $g 'NAŠI REZULTATI' 'Zadnjih 30 dana · svaki tip provjeren' $C.gold
  $boxes = @(,@('TIPOVI', $tr.hit, $tr.n))
  if ($tr.sports.football) { $boxes += ,@('FUDBAL', $tr.sports.football.hit, $tr.sports.football.n) }
  if ($tr.sports.basketball) { $boxes += ,@('KOŠARKA', $tr.sports.basketball.hit, $tr.sports.basketball.n) }
  if ($tr.ticket -and $tr.ticket.n) { $boxes += ,@('TIKET DANA', $tr.ticket.hit, $tr.ticket.n) }
  $y = 330; $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Far'
  foreach ($b in $boxes) {
    $pc = [math]::Round(100 * $b[1] / [math]::Max(1.0, [double]$b[2]))
    $g.FillPath((B $C.card), (RR 40 $y 1000 170 30))
    $g.DrawString($b[0], (F 40 'Bold'), (B $C.white), 80, ($y + 30)); $g.DrawString("$($b[1]) od $($b[2]) pogođeno", (F 30 'Regular'), (B $C.muted), 80, ($y + 92))
    $g.DrawString("$pc%", (F 84 'Bold' 'Arial Black'), (B $(if ($pc -ge 70) { $C.green } else { $C.gold })), (New-Object System.Drawing.RectangleF 560, ($y + 20), 450, 130), $sf)
    $y += 190
  }
  Footer $g; $img = Save $cv $n
  AddPost '17:30' 'stats' $img ("📊 Naši rezultati u zadnjih 30 dana`n`n" + (($boxes | ForEach-Object { "• $($_[0].Substring(0,1))$($_[0].Substring(1).ToLower()): $($_[1])/$($_[2]) ($([math]::Round(100 * $_[1] / [math]::Max(1.0, [double]$_[2])))%)" }) -join "`n") + "`n`nSvaki tip je javno zapisan ujutro i provjeren poslije utakmice. Kalendar sa svim rezultatima: tipsoftheday.win/#rezultati$TAG")
}

# 19:30 večernji tipovi (utakmice od 20h)
$ev = @(Top $fb 'football' @('o15','gg','o25','w1','w2') '19:59' 3 1.15)
if ($ev.Count -ge 2) {
  $n++; $cv = Canvas @(30,30,70); Title $cv.g 'VEČERAS' 'Najsigurniji tipovi za utakmice od 20h' $C.gold
  $y = 320; $i = 0; foreach ($x in $ev) { $i++; Row $cv.g $y 250 $x $i; $y += 266 }
  Footer $cv.g; $img = Save $cv $n
  AddPost '19:30' 'evening' $img ("🌙 VEČERAS – najsigurniji tipovi`n`n" + (($ev | ForEach-Object { Line $_ }) -join "`n") + $TAG)
}

$enc = New-Object System.Text.UTF8Encoding($false)
$json = [ordered]@{ date = $today; posts = @($posts | Sort-Object { $_.t }) } | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText((Join-Path $root 'social\posts.json'), $json, $enc)
Write-Host "Social: $($posts.Count) objava za $today"
