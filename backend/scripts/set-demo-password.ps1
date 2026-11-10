# Stores the password of the demo accounts in Secret Manager as 'demo-password' and lets the
# API's service account read it. Run ./setup.ps1 first and ./deploy.ps1 afterwards.
# ./deploy.ps1 loads the demo data (an admin, crew and customers) into an empty database only
# when this secret exists; every demo account then signs in with this password.
# The password is read without echo and piped to gcloud's stdin: it is never printed, written
# to disk or put on a command line.
# Usage:  ./scripts/set-demo-password.ps1
param(
  [ValidatePattern('^[A-Za-z0-9._+-]+@[A-Za-z0-9.-]+$')][string]$Account = 'redefine073@gmail.com',
  [ValidatePattern('^[a-z][a-z0-9-]{4,28}[a-z0-9]$')][string]$Project = 'redefine-8a0b828f',
  [ValidatePattern('^[a-z][a-z0-9-]{4,28}[a-z0-9]$')][string]$ServiceAccountName = 'redefine-api'
)

# gcloud reports progress on stderr; under 'Stop' Windows PowerShell 5.1 treats that as a failure.
$ErrorActionPreference = 'Continue'

$SecretName = 'demo-password'
$ServiceAccount = "${ServiceAccountName}@${Project}.iam.gserviceaccount.com"

$Gcloud = (Get-Command gcloud.cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $Gcloud) { throw 'gcloud.cmd is not on PATH. Install the Google Cloud SDK first.' }

# Runs gcloud as the pinned account/project and throws on a non-zero exit code.
function Invoke-Gcloud {
  & $Gcloud @args "--account=$Account" "--project=$Project" --quiet
  if ($LASTEXITCODE -ne 0) { throw "gcloud $($args -join ' ') failed (exit code $LASTEXITCODE)." }
}

# Same, with exactly $Bytes as gcloud's stdin: a PowerShell pipe would append a newline.
function Invoke-GcloudWithStdin([byte[]]$Bytes, [string[]]$GcloudArgs) {
  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $env:ComSpec
  $startInfo.Arguments = '/d /s /c ""{0}" {1} --account={2} --project={3} --quiet"' -f $Gcloud, ($GcloudArgs -join ' '), $Account, $Project
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardInput = $true

  # Process.Start writes the console encoding's BOM to the pipe (UTF-8 after `chcp 65001`).
  $consoleEncoding = [Console]::InputEncoding
  $hasBom = $consoleEncoding.GetPreamble().Length -gt 0
  if ($hasBom) { [Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false) }
  try {
    $process = [System.Diagnostics.Process]::Start($startInfo)
  } finally {
    if ($hasBom) { [Console]::InputEncoding = $consoleEncoding }
  }
  try {
    try {
      $process.StandardInput.BaseStream.Write($Bytes, 0, $Bytes.Length)
      $process.StandardInput.Close()
    } catch [System.IO.IOException] {
      # gcloud exited before reading stdin; its exit code is reported below.
    }
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "gcloud $($GcloudArgs -join ' ') failed (exit code $($process.ExitCode))." }
  } finally {
    $process.Dispose()
  }
}

function ConvertTo-PlainText([Security.SecureString]$Secure) {
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
  try {
    [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
}

function Assert-ServiceAccount {
  $existing = @(Invoke-Gcloud iam service-accounts list '--format=value(email)')
  if ($existing -notcontains $ServiceAccount) { throw "Service account $ServiceAccount does not exist. Run ./setup.ps1 first." }
}

function Test-SecretExists {
  $existing = @(Invoke-Gcloud secrets list '--format=value(name)' | ForEach-Object { ($_ -split '/')[-1] })
  $existing -contains $SecretName
}

# Creates the secret with this value, or adds a version when it exists, then grants read access.
function Save-Secret([byte[]]$Bytes, [bool]$Exists) {
  if ($Exists) {
    Invoke-GcloudWithStdin $Bytes @('secrets', 'versions', 'add', $SecretName, '--data-file=-')
  } else {
    Invoke-GcloudWithStdin $Bytes @('secrets', 'create', $SecretName, '--replication-policy=automatic', '--data-file=-')
  }
  Invoke-Gcloud secrets add-iam-policy-binding $SecretName "--member=serviceAccount:$ServiceAccount" '--role=roles/secretmanager.secretAccessor' '--condition=None' '--format=none'
}

# Checked before prompting so a missing setup fails before the password is typed.
Assert-ServiceAccount
$exists = Test-SecretExists

$password = ConvertTo-PlainText (Read-Host -Prompt 'Demo password (12+ characters, no spaces)' -AsSecureString)
# One of the demo accounts is an admin, so ask for more than the API's eight-character minimum.
if ($password -cnotmatch '^[\x21-\x7E]{12,128}\z') {
  throw 'The demo password must be 12 to 128 printable ASCII characters without spaces.'
}
if ($password -cne (ConvertTo-PlainText (Read-Host -Prompt 'Repeat the demo password' -AsSecureString))) {
  throw 'The two entries do not match. Nothing was stored.'
}

$bytes = [Text.Encoding]::UTF8.GetBytes($password)
$password = $null
try {
  Save-Secret $bytes $exists
} finally {
  [Array]::Clear($bytes, 0, $bytes.Length)
}

Write-Host "Stored the demo password as a new version of '$SecretName'." -ForegroundColor Green
Write-Host 'Run ./deploy.ps1: an empty database gets the demo data with this password.'
Write-Host 'Accounts that already exist keep the password they were created with.'
