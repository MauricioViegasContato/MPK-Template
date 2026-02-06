# Character definitions (Unicode integers)
$c_Atilde = [char]0xC3   # Ã
$c_florin = [char]0x192  # ƒ (Window-1252 0x83 maps to U+0192)
$c_Acirc  = [char]0xC2   # Â

# Suffixes (UTF-8 second byte interpreted as Windows-1252 char)
$c_exclam = [char]0xA1   # ¡ (A1) -> á
$c_copy   = [char]0xA9   # © (A9) -> é
$c_soft   = [char]0xAD   # Soft Hyphen (AD) -> í (Likely invisible or '­')
$c_sup3   = [char]0xB3   # ³ (B3) -> ó
$c_ordM   = [char]0xBA   # º (BA) -> ú
$c_pound  = [char]0xA3   # £ (A3) -> ã
$c_micro  = [char]0xB5   # µ (B5) -> õ
$c_sect   = [char]0xA7   # § (A7) -> ç
$c_cent   = [char]0xA2   # ¢ (A2) -> â (Wait, â is E2? No, â is C3 A2. A2 is ¢. Correct)
$c_ordF   = [char]0xAA   # ª (AA) -> ê
$c_acute  = [char]0xB4   # ´ (B4) -> ô
$c_nbsp   = [char]0xA0   # NBSP (A0) -> à

# Construct Bad Strings
$bad_prefix = "$c_Atilde$c_florin$c_Acirc"

$bad_a_acute = "$bad_prefix$c_exclam"
$bad_e_acute = "$bad_prefix$c_copy"
$bad_i_acute = "$bad_prefix$c_soft"
$bad_o_acute = "$bad_prefix$c_sup3"
$bad_u_acute = "$bad_prefix$c_ordM"
$bad_a_tilde = "$bad_prefix$c_pound"
$bad_o_tilde = "$bad_prefix$c_micro"
$bad_c_cedil = "$bad_prefix$c_sect"
$bad_a_circ  = "$bad_prefix$c_cent"
$bad_e_circ  = "$bad_prefix$c_ordF"
$bad_o_circ  = "$bad_prefix$c_acute"
$bad_a_grave = "$bad_prefix$c_nbsp"

# Exception for 'Ç' (Ãƒâ€¡)
# Ã (C3) -> Ãƒ (C3 192)
# ‡ (87) -> â€¡ (E2 80 A1)
$c_acir = [char]0xE2
$c_euro = [char]0x20AC
$c_ddag = [char]0xA1 # Wait, 2021 utf8 is E2 80 A1. 0x87 mapped to 2021.
# If 2021 was written as UTF8: E2 80 A1.
# E2 -> â (E2).
# 80 -> € (20AC).
# A1 -> ¡ (A1).
$bad_C_cedil = "$c_Atilde$c_florin$c_acir$c_euro$c_exclam" # Ãƒâ€¡

# Exception for 'Ã' (ÃƒÆ’)
# Ã (C3) -> Ãƒ
# 83 -> ƒ
# So ÃƒÆ’ -> Ãƒ + ƒ (192)
$bad_A_tilde_upper = "$c_Atilde$c_florin$c_florin"

$files = Get-ChildItem -Path "lib" -Recurse -Filter *.dart

foreach ($file in $files) {
    $content = Get-Content -Path $file.FullName -Raw
    
    if (-not $content) { continue }

    $changed = $false
    
    if ($content.Contains($bad_a_acute)) { $content = $content.Replace($bad_a_acute, "á"); $changed = $true }
    if ($content.Contains($bad_e_acute)) { $content = $content.Replace($bad_e_acute, "é"); $changed = $true }
    if ($content.Contains($bad_i_acute)) { $content = $content.Replace($bad_i_acute, "í"); $changed = $true }
    if ($content.Contains($bad_o_acute)) { $content = $content.Replace($bad_o_acute, "ó"); $changed = $true }
    if ($content.Contains($bad_u_acute)) { $content = $content.Replace($bad_u_acute, "ú"); $changed = $true }
    if ($content.Contains($bad_a_tilde)) { $content = $content.Replace($bad_a_tilde, "ã"); $changed = $true }
    if ($content.Contains($bad_o_tilde)) { $content = $content.Replace($bad_o_tilde, "õ"); $changed = $true }
    if ($content.Contains($bad_c_cedil)) { $content = $content.Replace($bad_c_cedil, "ç"); $changed = $true }
    if ($content.Contains($bad_a_circ))  { $content = $content.Replace($bad_a_circ, "â"); $changed = $true }
    if ($content.Contains($bad_e_circ))  { $content = $content.Replace($bad_e_circ, "ê"); $changed = $true }
    if ($content.Contains($bad_o_circ))  { $content = $content.Replace($bad_o_circ, "ô"); $changed = $true }
    if ($content.Contains($bad_a_grave)) { $content = $content.Replace($bad_a_grave, "à"); $changed = $true }
    if ($content.Contains($bad_C_cedil)) { $content = $content.Replace($bad_C_cedil, "Ç"); $changed = $true }
    if ($content.Contains($bad_A_tilde_upper)) { $content = $content.Replace($bad_A_tilde_upper, "Ã"); $changed = $true }

    # Special case for í if soft hyphen is missing or handled differently
    $bad_i_alt = "In$c_Atilde$c_florin$c_Acirc ci" # Try to match In...cio pattern partially
    # Or just replace known words
    if ($content.Contains('InÃƒÂcio')) { $content = $content.Replace('InÃƒÂcio', 'Início'); $changed = $true }

    if ($changed) {
        Write-Host "Fixed $($file.Name)"
        $content | Out-File -FilePath $file.FullName -Encoding UTF8
    }
}
Write-Host "Done."
