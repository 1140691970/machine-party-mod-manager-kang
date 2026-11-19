param(
    [Parameter(Mandatory)][string]$Path,
    [string]$Thumbprint = $env:WINDOWS_SIGNING_THUMBPRINT,
    [string]$Subject = $env:WINDOWS_SIGNING_SUBJECT
)
$ErrorActionPreference = 'Stop'
$signature = Get-AuthenticodeSignature -LiteralPath $Path
if (!$env:WINDOWS_SIGNING_PROVIDER -and !$Thumbprint -and !$Subject) {
    if ($signature.Status -eq 'NotSigned') {
        Write-Host "No publisher configured; accepting unsigned Windows artifact $Path."
        return
    }
    # Reused builds may already have a valid publisher even when none is pinned.
    $publisherMatches = $true
} elseif ($env:WINDOWS_SIGNING_PROVIDER -eq 'azure') {
    # Public Trust leaf certificates rotate. Pin the validated publisher's full X.500 name.
    $publisherMatches = $Subject -and ($signature.SignerCertificate.Subject -ceq $Subject)
} else {
    $publisherMatches = ($Thumbprint -match '^[a-fA-F0-9]{40}$') -and ($signature.SignerCertificate.Thumbprint -eq $Thumbprint)
}
if ($signature.Status -ne 'Valid' -or $signature.SignatureType -ne 'Authenticode' -or
    !$publisherMatches -or !$signature.TimeStamperCertificate) {
    throw "Expected a trusted, embedded, timestamped Authenticode signature from the configured publisher on $Path (status: $($signature.Status))."
}
