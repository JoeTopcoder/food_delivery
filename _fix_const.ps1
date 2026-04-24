param([string]$filePath)

$content = [System.IO.File]::ReadAllText($filePath, [System.Text.Encoding]::UTF8)
$result = [System.Text.StringBuilder]::new($content.Length)
$i = 0
$len = $content.Length
$changed = $false

while ($i -lt $len) {
    # Check for "const " at current position
    if ($i + 6 -le $len -and $content.Substring($i, 6) -eq 'const ') {
        # Walk forward past whitespace and identifier to find opening ( or [
        $j = $i + 6
        while ($j -lt $len -and $content[$j] -ne '(' -and $content[$j] -ne '[' -and $content[$j] -ne '{') { $j++ }
        if ($j -lt $len) {
            $openChar = $content[$j]
            $closeChar = if ($openChar -eq '(') { ')' } elseif ($openChar -eq '[') { ']' } else { '}' }
            $depth = 0; $k = $j
            while ($k -lt $len) {
                if ($content[$k] -eq $openChar) { $depth++ }
                elseif ($content[$k] -eq $closeChar) { $depth--; if ($depth -eq 0) { break } }
                $k++
            }
            $inner = $content.Substring($j, [Math]::Min($k - $j + 1, $content.Length - $j))
            if ($inner -match 'AppTheme\.\w+|Colors\.grey\[\d+\]') {
                # Skip the "const " — do not append it
                $changed = $true
                $i += 6
                continue
            }
        }
    }
    [void]$result.Append($content[$i])
    $i++
}

if ($changed) {
    [System.IO.File]::WriteAllText($filePath, $result.ToString(), [System.Text.Encoding]::UTF8)
    Write-Host "Fixed: $filePath"
} else {
    Write-Host "NoChange: $filePath"
}
