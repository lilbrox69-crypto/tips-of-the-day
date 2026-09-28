# Tips of the Day - stranice za Google na svih 17 jezika (+ sitemap.xml, robots.txt, og.png).
# Pravi se svako jutro iz data.json. Izlaz: seo_out\ (kopira se u korijen stranice).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$data = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data.json') | ConvertFrom-Json
$today = $data.today; $dt = [datetime]::ParseExact($today, 'yyyy-MM-dd', $null)
$out = Join-Path $root 'seo_out'; if (Test-Path $out) { Remove-Item $out -Recurse -Force }; New-Item -ItemType Directory $out | Out-Null
$SITE = 'https://tipsoftheday.win'
function Enc($s) { ([string]$s).Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;') }

# jezik: putanja, naslov, opis, [tiket dana, top 3 po opciji, ukupna kvota, otvori sve tipove, statistika/18+, danas]
$LANGS = [ordered]@{
  bs = @('tiket-dana', 'Tiket dana i fudbalski tipovi za danas – statistička analiza', 'Besplatan tiket dana i top 3 tipa po opciji, izračunati statistikom forme, međusobnih susreta i kvota. Fudbal i košarka, svako jutro.', @('Tiket dana', 'Statistički tipovi za danas – top 3 po opciji', 'Ukupna kvota', 'Otvori sve tipove dana', 'Statistika, ne garancija · 18+ · igraj odgovorno', 'Danas'))
  hr = @('hr', 'Tiket dana i nogometni tipovi za danas – statistička analiza', 'Besplatan tiket dana i top 3 tipa po opciji, izračunati statistikom forme, međusobnih susreta i koeficijenata. Nogomet i košarka, svako jutro.', @('Tiket dana', 'Statistički tipovi za danas – top 3 po opciji', 'Ukupni koeficijent', 'Otvori sve tipove dana', 'Statistika, ne jamstvo · 18+ · igraj odgovorno', 'Danas'))
  sr = @('sr', 'Tiket dana i fudbalski tipovi za danas – statistička analiza', 'Besplatan tiket dana i top 3 tipa po opciji, izračunati statistikom forme, međusobnih duela i kvota. Fudbal i košarka, svako jutro.', @('Tiket dana', 'Statistički tipovi za danas – top 3 po opciji', 'Ukupna kvota', 'Otvori sve tipove dana', 'Statistika, ne garancija · 18+ · igraj odgovorno', 'Danas'))
  en = @('en', 'Bet of the Day & Football Tips Today – Statistical Analysis', 'Free bet of the day and the top 3 picks for every market, calculated from form, head-to-head and odds statistics. Football and basketball, every morning.', @('Bet of the day', 'Statistical tips for today – top 3 per market', 'Total odds', 'Open all of today''s tips', 'Statistics, not a guarantee · 18+ · gamble responsibly', 'Today'))
  de = @('de', 'Tipp des Tages & Fußballtipps für heute – statistische Analyse', 'Kostenloser Kombitipp des Tages und die Top 3 Tipps pro Wette, berechnet aus Form, direkten Duellen und Quoten. Fußball und Basketball, jeden Morgen.', @('Tipp des Tages', 'Statistische Tipps für heute – Top 3 pro Wette', 'Gesamtquote', 'Alle Tipps des Tages öffnen', 'Statistik, keine Garantie · 18+ · verantwortungsvoll spielen', 'Heute'))
  it = @('it', 'Schedina del giorno e pronostici calcio di oggi – analisi statistica', 'Schedina del giorno gratis e i 3 migliori pronostici per ogni mercato, calcolati da forma, scontri diretti e quote. Calcio e basket, ogni mattina.', @('Schedina del giorno', 'Pronostici statistici di oggi – top 3 per mercato', 'Quota totale', 'Apri tutti i pronostici di oggi', 'Statistica, non una garanzia · 18+ · gioca responsabilmente', 'Oggi'))
  es = @('es', 'Combinada del día y pronósticos de fútbol de hoy – análisis estadístico', 'Combinada del día gratis y los 3 mejores pronósticos por mercado, calculados con forma, enfrentamientos directos y cuotas. Fútbol y baloncesto, cada mañana.', @('Combinada del día', 'Pronósticos estadísticos de hoy – top 3 por mercado', 'Cuota total', 'Ver todos los pronósticos de hoy', 'Estadística, no garantía · 18+ · juega con responsabilidad', 'Hoy'))
  fr = @('fr', 'Combiné du jour et pronostics foot du jour – analyse statistique', 'Combiné du jour gratuit et les 3 meilleurs pronostics par marché, calculés à partir de la forme, des confrontations et des cotes. Football et basket, chaque matin.', @('Combiné du jour', 'Pronostics statistiques du jour – top 3 par marché', 'Cote totale', 'Voir tous les pronostics du jour', 'Statistiques, pas une garantie · 18+ · jouez responsable', 'Aujourd''hui'))
  pt = @('pt', 'Bilhete do dia e palpites de futebol de hoje – análise estatística', 'Bilhete do dia grátis e os 3 melhores palpites por mercado, calculados com forma, confrontos diretos e odds. Futebol e basquete, toda manhã.', @('Bilhete do dia', 'Palpites estatísticos de hoje – top 3 por mercado', 'Odd total', 'Ver todos os palpites de hoje', 'Estatística, não garantia · 18+ · jogue com responsabilidade', 'Hoje'))
  tr = @('tr', 'Günün kuponu ve bugünün futbol tahminleri – istatistiksel analiz', 'Ücretsiz günün kuponu ve her bahis türü için en iyi 3 tahmin; form, aralarındaki maçlar ve oranlardan hesaplandı. Futbol ve basketbol, her sabah.', @('Günün kuponu', 'Bugünün istatistiksel tahminleri – bahis türü başına ilk 3', 'Toplam oran', 'Bugünün tüm tahminlerini aç', 'İstatistik, garanti değil · 18+ · sorumlu oyna', 'Bugün'))
  sq = @('sq', 'Bileta e ditës dhe parashikimet e futbollit për sot – analizë statistikore', 'Bileta e ditës falas dhe 3 parashikimet më të mira për çdo treg, të llogaritura nga forma, përballjet dhe koeficientët. Futboll dhe basketboll, çdo mëngjes.', @('Bileta e ditës', 'Parashikime statistikore për sot – top 3 për treg', 'Koeficienti total', 'Hap të gjitha parashikimet e sotme', 'Statistikë, jo garanci · 18+ · luaj me përgjegjësi', 'Sot'))
  pl = @('pl', 'Kupon dnia i typy piłkarskie na dziś – analiza statystyczna', 'Darmowy kupon dnia i 3 najlepsze typy dla każdego rynku, wyliczone z formy, meczów bezpośrednich i kursów. Piłka nożna i koszykówka, każdego ranka.', @('Kupon dnia', 'Statystyczne typy na dziś – top 3 na rynek', 'Kurs łączny', 'Otwórz wszystkie dzisiejsze typy', 'Statystyka, nie gwarancja · 18+ · graj odpowiedzialnie', 'Dziś'))
  ro = @('ro', 'Biletul zilei și ponturi fotbal azi – analiză statistică', 'Biletul zilei gratuit și cele mai bune 3 ponturi pe fiecare piață, calculate din formă, meciuri directe și cote. Fotbal și baschet, în fiecare dimineață.', @('Biletul zilei', 'Ponturi statistice pentru azi – top 3 pe piață', 'Cotă totală', 'Deschide toate ponturile de azi', 'Statistică, nu garanție · 18+ · joacă responsabil', 'Azi'))
  el = @('el', 'Δελτίο της ημέρας και προγνωστικά ποδοσφαίρου σήμερα – στατιστική ανάλυση', 'Δωρεάν δελτίο της ημέρας και οι 3 καλύτερες προβλέψεις ανά αγορά, από φόρμα, αλληλοσυγκρούσεις και αποδόσεις. Ποδόσφαιρο και μπάσκετ, κάθε πρωί.', @('Δελτίο της ημέρας', 'Στατιστικές προβλέψεις για σήμερα – top 3 ανά αγορά', 'Συνολική απόδοση', 'Όλες οι σημερινές προβλέψεις', 'Στατιστική, όχι εγγύηση · 18+ · παίξτε υπεύθυνα', 'Σήμερα'))
  ru = @('ru', 'Экспресс дня и прогнозы на футбол сегодня – статистический анализ', 'Бесплатный экспресс дня и топ-3 прогноза на каждый рынок, рассчитанные по форме, личным встречам и коэффициентам. Футбол и баскетбол, каждое утро.', @('Экспресс дня', 'Статистические прогнозы на сегодня – топ-3 по рынку', 'Общий коэффициент', 'Открыть все прогнозы на сегодня', 'Статистика, не гарантия · 18+ · играйте ответственно', 'Сегодня'))
  nl = @('nl', 'Combi van de dag en voetbaltips vandaag – statistische analyse', 'Gratis combi van de dag en de top 3 tips per markt, berekend uit vorm, onderlinge duels en quoteringen. Voetbal en basketbal, elke ochtend.', @('Combi van de dag', 'Statistische tips voor vandaag – top 3 per markt', 'Totale quotering', 'Open alle tips van vandaag', 'Statistiek, geen garantie · 18+ · speel verantwoord', 'Vandaag'))
  ar = @('ar', 'قسيمة اليوم وتوقعات كرة القدم اليوم – تحليل إحصائي', 'قسيمة اليوم مجانًا وأفضل 3 توقعات لكل سوق، محسوبة من الأداء والمواجهات المباشرة والاحتمالات. كرة القدم وكرة السلة، كل صباح.', @('قسيمة اليوم', 'توقعات إحصائية لليوم – أفضل 3 لكل سوق', 'الاحتمال الإجمالي', 'افتح كل توقعات اليوم', 'إحصاءات وليست ضمانًا · 18+ · العب بمسؤولية', 'اليوم'))
}
# opcije po jeziku: gg o15 o25 u25 c8 y3 hs as w1 x w2 | kosarka w1 w2 o160 u160 o220 u220
$MKT = @{
  bs = 'Oba daju gol|Više od 1.5 gola|Više od 2.5 gola|Manje od 2.5 gola|Korneri 8+|Žuti kartoni 3+|Domaćin daje gol|Gost daje gol|Pobjeda domaćina|Neriješeno|Pobjeda gosta|Više od 160.5|Manje od 160.5|Više od 220.5|Manje od 220.5'
  hr = 'Oba daju gol|Više od 1.5 gola|Više od 2.5 gola|Manje od 2.5 gola|Korneri 8+|Žuti kartoni 3+|Domaćin daje gol|Gost daje gol|Pobjeda domaćina|Neriješeno|Pobjeda gosta|Više od 160.5|Manje od 160.5|Više od 220.5|Manje od 220.5'
  sr = 'Oba daju gol|Više od 1.5 gola|Više od 2.5 gola|Manje od 2.5 gola|Korneri 8+|Žuti kartoni 3+|Domaćin daje gol|Gost daje gol|Pobeda domaćina|Nerešeno|Pobeda gosta|Više od 160.5|Manje od 160.5|Više od 220.5|Manje od 220.5'
  en = 'Both teams to score|Over 1.5 goals|Over 2.5 goals|Under 2.5 goals|Corners 8+|Yellow cards 3+|Home team to score|Away team to score|Home win|Draw|Away win|Over 160.5|Under 160.5|Over 220.5|Under 220.5'
  de = 'Beide Teams treffen|Über 1,5 Tore|Über 2,5 Tore|Unter 2,5 Tore|Ecken 8+|Gelbe Karten 3+|Heimteam trifft|Gast trifft|Heimsieg|Unentschieden|Auswärtssieg|Über 160,5|Unter 160,5|Über 220,5|Unter 220,5'
  it = 'Goal/Goal|Over 1.5|Over 2.5|Under 2.5|Calci d''angolo 8+|Cartellini gialli 3+|Segna la squadra di casa|Segna la squadra ospite|Vittoria casa|Pareggio|Vittoria trasferta|Over 160.5|Under 160.5|Over 220.5|Under 220.5'
  es = 'Ambos marcan|Más de 1.5 goles|Más de 2.5 goles|Menos de 2.5 goles|Córners 8+|Tarjetas amarillas 3+|Marca el local|Marca el visitante|Gana el local|Empate|Gana el visitante|Más de 160.5|Menos de 160.5|Más de 220.5|Menos de 220.5'
  fr = 'Les deux équipes marquent|Plus de 1,5 but|Plus de 2,5 buts|Moins de 2,5 buts|Corners 8+|Cartons jaunes 3+|L''équipe à domicile marque|L''équipe extérieure marque|Victoire à domicile|Match nul|Victoire à l''extérieur|Plus de 160,5|Moins de 160,5|Plus de 220,5|Moins de 220,5'
  pt = 'Ambas marcam|Mais de 1.5 gols|Mais de 2.5 gols|Menos de 2.5 gols|Escanteios 8+|Cartões amarelos 3+|Mandante marca|Visitante marca|Vitória do mandante|Empate|Vitória do visitante|Mais de 160.5|Menos de 160.5|Mais de 220.5|Menos de 220.5'
  tr = 'Karşılıklı gol|1.5 üst|2.5 üst|2.5 alt|Korner 8+|Sarı kart 3+|Ev sahibi gol atar|Deplasman gol atar|Ev sahibi kazanır|Beraberlik|Deplasman kazanır|160.5 üst|160.5 alt|220.5 üst|220.5 alt'
  sq = 'Të dyja shënojnë|Mbi 1.5 gola|Mbi 2.5 gola|Nën 2.5 gola|Kënde 8+|Kartonë të verdhë 3+|Vendasit shënojnë|Mysafirët shënojnë|Fitore e vendasve|Barazim|Fitore e mysafirëve|Mbi 160.5|Nën 160.5|Mbi 220.5|Nën 220.5'
  pl = 'Obie drużyny strzelą|Powyżej 1,5 gola|Powyżej 2,5 gola|Poniżej 2,5 gola|Rzuty rożne 8+|Żółte kartki 3+|Gospodarze strzelą|Goście strzelą|Wygrana gospodarzy|Remis|Wygrana gości|Powyżej 160,5|Poniżej 160,5|Powyżej 220,5|Poniżej 220,5'
  ro = 'Ambele marchează|Peste 1.5 goluri|Peste 2.5 goluri|Sub 2.5 goluri|Cornere 8+|Cartonașe galbene 3+|Gazdele marchează|Oaspeții marchează|Victorie gazde|Egal|Victorie oaspeți|Peste 160.5|Sub 160.5|Peste 220.5|Sub 220.5'
  el = 'Γκολ-Γκολ|Over 1.5|Over 2.5|Under 2.5|Κόρνερ 8+|Κίτρινες κάρτες 3+|Σκοράρει η γηπεδούχος|Σκοράρει η φιλοξενούμενη|Νίκη γηπεδούχου|Ισοπαλία|Νίκη φιλοξενούμενου|Over 160.5|Under 160.5|Over 220.5|Under 220.5'
  ru = 'Обе забьют|Больше 1.5 гола|Больше 2.5 гола|Меньше 2.5 гола|Угловые 8+|Жёлтые карточки 3+|Хозяева забьют|Гости забьют|Победа хозяев|Ничья|Победа гостей|Больше 160.5|Меньше 160.5|Больше 220.5|Меньше 220.5'
  nl = 'Beide teams scoren|Meer dan 1,5 goals|Meer dan 2,5 goals|Minder dan 2,5 goals|Hoekschoppen 8+|Gele kaarten 3+|Thuisploeg scoort|Uitploeg scoort|Thuisoverwinning|Gelijkspel|Uitoverwinning|Meer dan 160,5|Minder dan 160,5|Meer dan 220,5|Minder dan 220,5'
  ar = 'كلا الفريقين يسجل|أكثر من 1.5 هدف|أكثر من 2.5 هدف|أقل من 2.5 هدف|ركنيات 8+|بطاقات صفراء 3+|صاحب الأرض يسجل|الضيف يسجل|فوز صاحب الأرض|تعادل|فوز الضيف|أكثر من 160.5|أقل من 160.5|أكثر من 220.5|أقل من 220.5'
}
$FK = @('gg','o15','o25','u25','c8','y3','hs','as','w1','x','w2'); $BK = @('w1','w2','o160','u160','o220','u220')
function MkL($lang, $sport, $k) {
  $a = $MKT[$lang].Split('|')
  if ($sport -eq 'basketball') { $i = @{ w1 = 8; w2 = 10; o160 = 11; u160 = 12; o220 = 13; u220 = 14 }[$k]; if ($i -ne $null) { return $a[$i] } else { return $k } }
  $i = [array]::IndexOf($FK, $k); if ($i -ge 0) { $a[$i] } else { $k }
}
$fb = @(($data.days | Where-Object { $_.date -eq $today }).matches | Where-Object { $_ })
$bb = @(); if ($data.sports.basketball) { $bb = @(($data.sports.basketball.days | Where-Object { $_.date -eq $today }).matches | Where-Object { $_ }) }
function Top3($list, $k) { @($list | Where-Object { $_.p.$k -ne $null } | Sort-Object { - [int]$_.p.$k } | Select-Object -First 3) }
$fmtO = { param($o) if ($o) { ('{0:0.00}' -f [double]$o).Replace(',', '.') } else { '' } }

$alt = ($LANGS.Keys | ForEach-Object { $p = $LANGS[$_][0]; "<link rel=`"alternate`" hreflang=`"$_`" href=`"$SITE/$p/`">" }) -join "`n"
$ogImg = "$SITE/og.png?v=$today"
foreach ($lang in $LANGS.Keys) {
  $c = $LANGS[$lang]; $path = $c[0]; $title = $c[1]; $desc = $c[2]; $t = $c[3]
  $dstr = "$($dt.Day).$($dt.Month).$($dt.Year)."
  $dir = if ($lang -eq 'ar') { ' dir="rtl"' } else { '' }
  $sb = New-Object System.Text.StringBuilder
  # tiket dana
  if ($data.ticket -and @($data.ticket.legs).Count) {
    [void]$sb.Append("<section class=`"tk`"><h2>🎫 $(Enc $t[0]) · $dstr</h2><ol>")
    foreach ($l in $data.ticket.legs) { [void]$sb.Append("<li><b>$(Enc $l.home) – $(Enc $l.away)</b> <span>$(Enc $l.time) · $(Enc $l.league)</span><em>$(Enc (MkL $lang $l.sport $l.mk)) · $(& $fmtO $l.o)</em></li>") }
    [void]$sb.Append("</ol><p class=`"sum`">$(Enc $t[2]): <strong>$(& $fmtO $data.ticket.odd)</strong></p></section>")
  }
  [void]$sb.Append("<h2>$(Enc $t[1])</h2>")
  foreach ($k in $FK) {
    $top = Top3 $fb $k; if (-not $top.Count) { continue }
    [void]$sb.Append("<section><h3>⚽ $(Enc (MkL $lang 'football' $k))</h3><ul>")
    foreach ($m in $top) { [void]$sb.Append("<li><b>$(Enc $m.home) – $(Enc $m.away)</b> <span>$(Enc $m.time) · $(Enc $m.league)</span><em>$([int]$m.p.$k)%$(if ($m.o -and $m.o.$k) { ' · ' + (& $fmtO $m.o.$k) })</em></li>") }
    [void]$sb.Append('</ul></section>')
  }
  foreach ($k in $BK) {
    $top = Top3 $bb $k; if (-not $top.Count) { continue }
    [void]$sb.Append("<section><h3>🏀 $(Enc (MkL $lang 'basketball' $k))</h3><ul>")
    foreach ($m in $top) { [void]$sb.Append("<li><b>$(Enc $m.home) – $(Enc $m.away)</b> <span>$(Enc $m.time) · $(Enc $m.league)</span><em>$([int]$m.p.$k)%$(if ($m.o -and $m.o.$k) { ' · ' + (& $fmtO $m.o.$k) })</em></li>") }
    [void]$sb.Append('</ul></section>')
  }
  $html = @"
<!doctype html>
<html lang="$lang"$dir>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$(Enc $title) – $dstr | Tips of the Day</title>
<meta name="description" content="$(Enc $desc)">
<link rel="canonical" href="$SITE/$path/">
$alt
<link rel="alternate" hreflang="x-default" href="$SITE/">
<meta property="og:type" content="website">
<meta property="og:title" content="$(Enc $title) – $dstr">
<meta property="og:description" content="$(Enc $desc)">
<meta property="og:image" content="$ogImg">
<meta property="og:url" content="$SITE/$path/">
<meta name="twitter:card" content="summary_large_image">
<meta name="theme-color" content="#0f2a1c">
<link rel="icon" href="$SITE/icon-192.png">
<style>
:root{--g:#F4C443;--gr:#3DD68C;--ink:#EEF4EF;--mu:#9DB0A3;--bg:#07130D}
*{box-sizing:border-box}body{margin:0;background:linear-gradient(180deg,#123d27,var(--bg) 480px);color:var(--ink);font:16px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:760px;margin:0 auto;padding:20px 16px 40px}
.brand{font:900 22px "Arial Black",Arial,sans-serif;letter-spacing:.02em}.brand i{font-style:normal;color:var(--gr)}.brand u{text-decoration:none;color:var(--g)}
h1{font-size:28px;line-height:1.2;margin:14px 0 6px;color:var(--g)}h2{font-size:21px;margin:26px 0 10px}h3{font-size:17px;margin:18px 0 6px;color:var(--g)}
p.d{color:var(--mu);margin:0 0 16px}
.cta{display:block;text-align:center;margin:18px 0;padding:14px;border-radius:30px;background:linear-gradient(90deg,var(--g),var(--gr));color:#0b1a12;font-weight:900;font-size:18px;text-decoration:none}
ul,ol{list-style:none;margin:0;padding:0}li{background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.1);border-radius:14px;padding:10px 14px;margin:0 0 8px;display:grid;gap:2px}
li span{color:var(--mu);font-size:13px}li em{font-style:normal;font-weight:700;color:var(--g)}
.tk{border:1px solid rgba(244,196,67,.5);border-radius:18px;padding:12px 14px;background:rgba(244,196,67,.07)}.tk h2{margin-top:4px}.sum{font-size:20px;margin:8px 0 0}.sum strong{color:var(--g);font-size:26px}
footer{color:var(--mu);font-size:13px;text-align:center;margin-top:26px}nav{display:flex;flex-wrap:wrap;gap:8px;justify-content:center;margin-top:14px}nav a{color:var(--mu);font-size:13px}
</style>
</head>
<body><main>
<div class="brand">TIPS <i>OF THE</i> <u>DAY</u></div>
<h1>$(Enc $title)</h1>
<p class="d">$(Enc $t[5]): $dstr — $(Enc $desc)</p>
<a class="cta" href="$SITE/">$(Enc $t[3]) →</a>
$($sb.ToString())
<a class="cta" href="$SITE/">$(Enc $t[3]) →</a>
<footer>$(Enc $t[4])<nav>$(($LANGS.Keys | ForEach-Object { "<a href=`"$SITE/$($LANGS[$_][0])/`" hreflang=`"$_`">$($_.ToUpper())</a>" }) -join ' ')</nav></footer>
</main></body></html>
"@
  $d = Join-Path $out $path; New-Item -ItemType Directory -Force $d | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'index.html'), $html, (New-Object System.Text.UTF8Encoding($false)))
}
# /tipovi-za-danas/ = ista bosanska stranica (druga fraza koju ljudi kucaju)
$bsHtml = [IO.File]::ReadAllText((Join-Path $out 'tiket-dana\index.html'), [Text.Encoding]::UTF8)
New-Item -ItemType Directory -Force (Join-Path $out 'tipovi-za-danas') | Out-Null
$bsHtml2 = $bsHtml.Replace('Tiket dana i fudbalski tipovi za danas – statistička analiza', 'Fudbalski tipovi za danas i tiket dana – statistika i analiza')
[IO.File]::WriteAllText((Join-Path $out 'tipovi-za-danas\index.html'), $bsHtml2, (New-Object System.Text.UTF8Encoding($false)))
# sitemap + robots
$urls = @("$SITE/", "$SITE/tipovi-za-danas/") + ($LANGS.Keys | ForEach-Object { "$SITE/$($LANGS[$_][0])/" })
$sm = '<?xml version="1.0" encoding="UTF-8"?>' + "`n" + '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' + (($urls | ForEach-Object { "<url><loc>$_</loc><lastmod>$today</lastmod><changefreq>daily</changefreq></url>" }) -join '') + '</urlset>'
[IO.File]::WriteAllText((Join-Path $out 'sitemap.xml'), $sm, (New-Object System.Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $out 'robots.txt'), "User-agent: *`nAllow: /`nSitemap: $SITE/sitemap.xml`n", (New-Object System.Text.UTF8Encoding($false)))
# slika za dijeljenje linka = danasnja kartica tiketa (ako postoji), inace naslovna
$og = Join-Path $root 'social\fb_naslovna.png'
$pj = Join-Path $root 'social\posts.json'; if (Test-Path $pj) { $tp = @((Get-Content -Raw -Encoding UTF8 $pj | ConvertFrom-Json).posts | Where-Object { $_.kind -eq 'ticket' })[0]; if ($tp) { $f = Join-Path $root ("social\$today\" + (($tp.image -split '/')[-1] -split '\?')[0]); if (Test-Path $f) { $og = $f } } }
if (Test-Path $og) { Copy-Item $og (Join-Path $out 'og.png') -Force }
Write-Host "SEO: $($LANGS.Count) jezika + tipovi-za-danas, sitemap, robots"
