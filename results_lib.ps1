# Zajednicko: rezultati zavrsenih utakmica za pracenje pogodaka (cache\results.json, kljuc "sport:id")
function Save-Results($root, $entries) {
  $file = Join-Path $root 'cache\results.json'
  $all = @{}
  if (Test-Path $file) { (Get-Content -Raw -Encoding UTF8 $file | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $all[$_.Name] = $_.Value } }
  foreach ($k in $entries.Keys) { $all[$k] = $entries[$k] }
  [IO.File]::WriteAllText($file, ($all | ConvertTo-Json -Depth 4 -Compress), (New-Object System.Text.UTF8Encoding($false)))
}
