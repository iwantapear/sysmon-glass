param(
    [string]$Thumbprint,
    [string]$Subject = 'CN=SysMon Glass Local Signing',
    [switch]$CreateIfMissing,
    [Parameter(Position = 0)][string[]]$Targets,
    [string[]]$TimestampServers = @('http://timestamp.digicert.com', 'http://timestamp.sectigo.com', 'http://timestamp.globalsign.com/tsa/r6advanced1'),
    [switch]$ExportPublic,
    [string]$ExportPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-SigningCert {
    param([string]$Thumb, [string]$SubjectName, [switch]$Create)
    $store = 'Cert:\CurrentUser\My'
    if ($Thumb) {
        $found = Get-Item (Join-Path $store $Thumb) -ErrorAction SilentlyContinue
        if (-not $found) { throw "Certificate $Thumb not found in $store" }
        return $found
    }
    $codeSigning = '1.3.6.1.5.5.7.3.3'
    $candidates = @(Get-ChildItem $store | Where-Object {
        $_.Subject -eq $SubjectName -and
        $_.EnhancedKeyUsageList.ObjectId -contains $codeSigning -and
        $_.NotAfter -gt (Get-Date) -and $_.HasPrivateKey
    })
    if ($candidates.Count -gt 1) { throw "Multiple matching certificates; pass -Thumbprint to disambiguate. $(($candidates | ForEach-Object Thumbprint) -join ', ')" }
    if ($candidates.Count -eq 1) { return $candidates[0] }
    if (-not $Create) { throw "No signing certificate for '$SubjectName' in $store. Run with -CreateIfMissing to create one." }
    # Self-signed, machine-bound (non-exportable key). Public part can still be exported and trusted elsewhere.
    New-SelfSignedCertificate -Type CodeSigningCert -Subject $SubjectName -KeyAlgorithm RSA -KeyLength 3072 -HashAlgorithm SHA256 -CertStoreLocation $store -KeyExportPolicy NonExportable -NotAfter (Get-Date).AddYears(5)
}

$cert = Get-SigningCert -Thumb $Thumbprint -SubjectName $Subject -Create:$CreateIfMissing
Write-Host "Signing certificate: $($cert.Thumbprint) $($cert.Subject) expires $($cert.NotAfter.ToString('yyyy-MM-dd'))"

if ($Targets) {
    foreach ($target in $Targets) {
        $resolved = (Resolve-Path -LiteralPath $target -ErrorAction Stop).Path
        $signature = $null
        foreach ($server in $TimestampServers) {
            try { $signature = Set-AuthenticodeSignature -FilePath $resolved -Certificate $cert -TimestampServer $server -HashAlgorithm SHA256 -ErrorAction Stop; break }
            catch { Write-Warning "Timestamp server failed ($server): $($_.Exception.Message)" }
        }
        if (-not $signature) {
            # Untimestamped stays valid until the certificate expires; note it and continue.
            Write-Warning 'All timestamp servers unreachable; signing WITHOUT timestamp.'
            $signature = Set-AuthenticodeSignature -FilePath $resolved -Certificate $cert -HashAlgorithm SHA256 -ErrorAction Stop
        }
        if ($signature.Status -ne 'Valid') { throw "Signing failed for ${resolved}: $($signature.Status) $($signature.StatusMessage)" }
        $timeStamper = if ($signature.TimeStamperCertificate) { $signature.TimeStamperCertificate.Subject } else { '<none>' }
        Write-Host "SIGNED: $resolved (status=$($signature.Status), TSA=$timeStamper)"
    }
}

if ($ExportPublic) {
    $path = if ($ExportPath) { $ExportPath } else { Join-Path $PSScriptRoot 'artifacts\SysMon.Glass.signing.cer' }
    $dir = Split-Path $path -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    # Public key only; safe to copy anywhere. Importing it into another user's Root+TrustedPeople trusts this build there.
    Export-Certificate -Cert $cert -FilePath $path -Force | Out-Null
    Write-Host "PUBLIC CERT: $path"
    Write-Host 'On another machine, run once (a Windows confirmation dialog will appear):'
    Write-Host "  Import-Certificate -FilePath '$path' -CertStoreLocation Cert:\CurrentUser\Root"
    Write-Host "  Import-Certificate -FilePath '$path' -CertStoreLocation Cert:\CurrentUser\TrustedPeople"
}
