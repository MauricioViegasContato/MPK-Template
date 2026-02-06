# Pure ASCII Script to fix encoding issues
# Bad Prefix: ÃƒÂ (C3 83 C2) -> chars: 0xC3, 0x192, 0xC2
$p = [string][char]0xC3 + [string][char]0x192 + [string][char]0xC2

# Mappings (Suffix Byte -> Target Unicode Char)
# ¡ (A1) -> á (E1)
$rep_a_acute = @{ Bad = $p + [char]0xA1; Good = [string][char]0xE1 }
# © (A9) -> é (E9)
$rep_e_acute = @{ Bad = $p + [char]0xA9; Good = [string][char]0xE9 }
# SoftHyphen (AD) -> í (ED)
$rep_i_acute = @{ Bad = $p + [char]0xAD; Good = [string][char]0xED }
# ³ (B3) -> ó (F3)
$rep_o_acute = @{ Bad = $p + [char]0xB3; Good = [string][char]0xF3 }
# º (BA) -> ú (FA)
$rep_u_acute = @{ Bad = $p + [char]0xBA; Good = [string][char]0xFA }
# £ (A3) -> ã (E3)
$rep_a_tilde = @{ Bad = $p + [char]0xA3; Good = [string][char]0xE3 }
# µ (B5) -> õ (F5)
$rep_o_tilde = @{ Bad = $p + [char]0xB5; Good = [string][char]0xF5 }
# § (A7) -> ç (E7)
$rep_c_cedil = @{ Bad = $p + [char]0xA7; Good = [string][char]0xE7 }
# ¢ (A2) -> â (E2)
$rep_a_circ  = @{ Bad = $p + [char]0xA2; Good = [string][char]0xE2 }
# ª (AA) -> ê (EA)
$rep_e_circ  = @{ Bad = $p + [char]0xAA; Good = [string][char]0xEA }
# ´ (B4) -> ô (F4)
$rep_o_circ  = @{ Bad = $p + [char]0xB4; Good = [string][char]0xF4 }
# NBSP (A0) -> à (E0)
$rep_a_grave = @{ Bad = $p + [char]0xA0; Good = [string][char]0xE0 }

# Upper Cedilla Ç (C3 87) -> Ãƒâ€¡ (C3 192 E2 80 A1)
# 0xE2 0x80 0xA1 is Double Dagger (2021)
$bad_C_cedil = [string][char]0xC3 + [string][char]0x192 + [string][char]0x2021
$good_C_cedil = [string][char]0xC7

# Upper Ã (C3 83) -> ÃƒÆ’ (C3 192 192)
$bad_A_tilde = [string][char]0xC3 + [string][char]0x192 + [string][char]0x192
$good_A_tilde = [string][char]0xC3

# Special Case for 'In__cio' where the sequence might be different
# In + ÃƒÂ + cio (with space? or just the soft hyphen match above?)
# We will rely on $rep_i_acute (0xAD) first.

$replacements = @(
    $rep_a_acute, $rep_e_acute, $rep_i_acute, $rep_o_acute, $rep_u_acute,
    $rep_a_tilde, $rep_o_tilde, $rep_c_cedil, $rep_a_circ, $rep_e_circ,
    $rep_o_circ, $rep_a_grave
)

$files = Get-ChildItem -Path "lib" -Recurse -Filter *.dart

foreach ($file in $files) {
    # Get content as raw string (capturing the corruption as Unicode chars)
    $content = Get-Content -Path $file.FullName -Raw
    
    if (-not $content) { continue }

    $original = $content
    $changed = $false

    foreach ($r in $replacements) {
        if ($content.Contains($r.Bad)) {
            $content = $content.Replace($r.Bad, $r.Good)
            $changed = $true
        }
    }
    
    if ($content.Contains($bad_C_cedil)) {
        $content = $content.Replace($bad_C_cedil, $good_C_cedil)
        $changed = $true
    }
    
    if ($content.Contains($bad_A_tilde)) {
        $content = $content.Replace($bad_A_tilde, $good_A_tilde)
        $changed = $true
    }
    
    # Check specifically for "In-cio" if specific chars failed
    # InÃƒÂ cio -> In + C3 192 C2 A0 + cio (A0 is NBSP) -> Matches 'à' pattern?
    # No, 'Í' is C3 8D. 'í' is C3 AD.
    # If text is InÃƒÂ cio, it might be space.
    if ($content.Contains("In" + $rep_a_grave.Bad + "cio")) {
         # This would replace to Inàcio. Fix to Início.
         $content = $content.Replace("In" + $rep_a_grave.Good + "cio", "In" + [string][char]0xED + "cio")
         $changed = $true
    }
    
    if ($changed) {
        Write-Host "Fixed $($file.Name)"
        # Save as UTF8 (Powershell 5.1 includes BOM, which is standard)
        $content | Out-File -FilePath $file.FullName -Encoding UTF8
    }
}
Write-Host "Done."
