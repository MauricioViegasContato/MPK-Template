$files = Get-ChildItem -Path "lib" -Recurse -Filter *.dart

foreach ($file in $files) {
    $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
    
    # Common Portuguese Characters (Double Encoded)
    $content = $content.Replace('ÃƒÂ¡', 'á')
    $content = $content.Replace('ÃƒÂ¢', 'â')
    $content = $content.Replace('ÃƒÂ£', 'ã')
    $content = $content.Replace('ÃƒÂ©', 'é')
    $content = $content.Replace('ÃƒÂª', 'ê')
    $content = $content.Replace('ÃƒÂ­', 'í')
    $content = $content.Replace('ÃƒÂ³', 'ó')
    $content = $content.Replace('ÃƒÂ´', 'ô')
    $content = $content.Replace('ÃƒÂµ', 'õ')
    $content = $content.Replace('ÃƒÂº', 'ú')
    $content = $content.Replace('ÃƒÂ§', 'ç')
    $content = $content.Replace('ÃƒÂ', 'à') # Fallback if followed by space or specific char, usually à is C3 A0 -> ÃƒÂ [NBSP] which is invisible.
    
    # Uppercase and Special cases
    $content = $content.Replace('Ãƒâ€¡', 'Ç')
    $content = $content.Replace('ÃƒÆ’', 'Ã')
    $content = $content.Replace('Ã¢â‚¬â€œ', '–') # En-dash
    
    # Emoji / Symbols
    $content = $content.Replace('Ã¢Å“â€¦', '✅')
    $content = $content.Replace('Ã¢Â Å’', '❌')
    $content = $content.Replace('Ã°Å¸â€ â€ ', '🚨')
    $content = $content.Replace('Ã¢Å¡Â Ã¯Â¸Â ', '⚠️')
    $content = $content.Replace('R\$', 'R$') # Fix potential R\+Escaped$
    
    # Specific fix for 'Início' if the general rule missed ( ÃƒÂ followed by anything)
    # The general rule above handles 'ÃƒÂ­' -> 'í'.
    
    # Fix 'ÃƒÂ§ÃƒÂµ' -> 'çõ' (Handled individually)
    # Fix 'ÃƒÂ§ÃƒÂ£' -> 'çã' (Handled individually)

    # Specific word fixes if generic ones fail for edge cases:
    $content = $content.Replace('InÃƒÂcio', 'Início')
    $content = $content.Replace('RelatÃƒÂ³rios', 'Relatórios')
    $content = $content.Replace('SolicitaÃƒÂ§ÃƒÂµes', 'Solicitações')
    $content = $content.Replace('UsuÃƒÂ¡rio', 'Usuário')
    $content = $content.Replace('formulÃƒÂ¡rio', 'formulário')
    $content = $content.Replace('InÃƒÂ cio', 'Início') # Sometimes space happens
    
    # Save back
    Set-Content -Path $file.FullName -Value $content -Encoding UTF8
}

Write-Host "Encoding fixed!"
