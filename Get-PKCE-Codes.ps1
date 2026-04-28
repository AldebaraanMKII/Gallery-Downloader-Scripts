############################################
# Generate a random code_verifier (64 characters)
function New-CodeVerifier {
    param([int]$length = 64)
    $chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~'
    $verifier = -join (1..$length | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    return $verifier
}
############################################
# Generate the code_challenge (S256 method)
function New-CodeChallenge {
    param([string]$code_verifier)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($code_verifier)
    $hash = $sha256.ComputeHash($bytes)

    # Base64 URL-safe encoding (RFC 7636)
    $challenge = [Convert]::ToBase64String($hash) -replace '\+', '-' -replace '/', '_' -replace '=', ''
    return $challenge
}
############################################
# Usage
$code_verifier = New-CodeVerifier
$code_challenge = New-CodeChallenge -code_verifier $code_verifier
Write-Host "Code Verifier: $code_verifier" -ForegroundColor Cyan
Write-Host "Code Challenge: $code_challenge" -ForegroundColor Cyan
pause