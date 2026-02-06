$line = Get-Content -Path "lib/features/manager/screens/gerente_page.dart" -TotalCount 56 | Select-Object -Last 1
Write-Host "Line 56: $line"
$bytes = [System.Text.Encoding]::Default.GetBytes($line)
Write-Host "Bytes (Default): $($bytes -join ' ')"
$utf8bytes = [System.Text.Encoding]::UTF8.GetBytes($line)
Write-Host "Bytes (UTF8 as read): $($utf8bytes -join ' ')"

# Show char codes
foreach ($c in $line.ToCharArray()) {
    Write-Host "$c : $([int]$c)" -NoNewline
    Write-Host " | " -NoNewline
}
