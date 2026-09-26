# Posjete stranice iz Cloudflare Web Analytics (GraphQL) -> analytics.json za analitika.html
# Kljuc: okruzenje CF_API_TOKEN (GitHub secret) ili config.json cfApiToken. Samo citanje analitike.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$enc = New-Object System.Text.UTF8Encoding($false)
$out = Join-Path $root 'analytics.json'
$token = $env:CF_API_TOKEN
if (-not $token) { try { $token = (Get-Content -Raw -Encoding UTF8 (Join-Path $root 'config.json') | ConvertFrom-Json).cfApiToken } catch {} }
$tz = [System.TimeZoneInfo]::FindSystemTimeZoneById('Central European Standard Time')
$now = [System.TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $tz)
if (-not $token) {
  [IO.File]::WriteAllText($out, (([ordered]@{ connected = $false; generatedAt = $now.ToString('yyyy-MM-dd HH:mm') }) | ConvertTo-Json), $enc)
  Write-Host 'Analitika: nema Cloudflare kljuca (CF_API_TOKEN)'; return
}
$account = 'cebe60636baa9a78290edc49ba7e1e15'
$from = [datetime]::UtcNow.AddDays(-30).ToString('yyyy-MM-dd'); $to = [datetime]::UtcNow.ToString('yyyy-MM-dd')
$f = "{ date_geq: `"$from`", date_leq: `"$to`", requestHost: `"tipsoftheday.win`" }"
$q = @"
{ viewer { accounts(filter: { accountTag: "$account" }) {
  byDay: rumPageloadEventsAdaptiveGroups(limit: 40, filter: $f, orderBy: [date_ASC]) { count sum { visits } dimensions { date } }
  byCountry: rumPageloadEventsAdaptiveGroups(limit: 12, filter: $f, orderBy: [sum_visits_DESC]) { count sum { visits } dimensions { countryName } }
  byDevice: rumPageloadEventsAdaptiveGroups(limit: 5, filter: $f, orderBy: [sum_visits_DESC]) { count sum { visits } dimensions { deviceType } }
  byRef: rumPageloadEventsAdaptiveGroups(limit: 10, filter: $f, orderBy: [sum_visits_DESC]) { count sum { visits } dimensions { refererHost } }
  byPath: rumPageloadEventsAdaptiveGroups(limit: 10, filter: $f, orderBy: [count_DESC]) { count sum { visits } dimensions { requestPath } }
} } }
"@
$body = @{ query = $q } | ConvertTo-Json -Compress
$r = Invoke-RestMethod 'https://api.cloudflare.com/client/v4/graphql' -Method Post -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/json' -Body $body -TimeoutSec 60
if ($r.errors) { throw ("Cloudflare: " + (($r.errors | ForEach-Object { $_.message }) -join '; ')) }
$a = $r.data.viewer.accounts[0]
function Rows($list, $dim) { @($list | ForEach-Object { [ordered]@{ k = [string]$_.dimensions.$dim; visits = [int]$_.sum.visits; views = [int]$_.count } }) }
$res = [ordered]@{
  connected = $true; generatedAt = $now.ToString('yyyy-MM-dd HH:mm'); from = $from; to = $to
  days = Rows $a.byDay 'date'; countries = Rows $a.byCountry 'countryName'; devices = Rows $a.byDevice 'deviceType'
  referrers = Rows $a.byRef 'refererHost'; paths = Rows $a.byPath 'requestPath'
}
[IO.File]::WriteAllText($out, ($res | ConvertTo-Json -Depth 5), $enc)
Write-Host "Analitika: $(@($res.days).Count) dana, ukupno posjeta $((@($res.days) | ForEach-Object { $_.visits } | Measure-Object -Sum).Sum)"
