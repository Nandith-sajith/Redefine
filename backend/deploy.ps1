# Deploys the Redefine API to Cloud Run from source. Run ./setup.ps1 once first.
# Usage:  ./deploy.ps1
#         ./deploy.ps1 -SeedDemo $false
#         ./deploy.ps1 -Database redefine
param(
  # The demo accounts include an admin, so they are only loaded (into an empty database) when
  # the 'demo-password' secret exists: see ./scripts/set-demo-password.ps1.
  [bool]$SeedDemo = $true,
  # Empty = auto-detect: 'redefine' if that database exists, else '(default)'.
  [ValidatePattern('^(\(default\)|[a-z][a-z0-9-]{2,61}[a-z0-9])$')][string]$Database = '',
  [ValidatePattern('^[A-Za-z0-9._+-]+@[A-Za-z0-9.-]+$')][string]$Account = 'redefine073@gmail.com',
  [ValidatePattern('^[a-z][a-z0-9-]{4,28}[a-z0-9]$')][string]$Project = 'redefine-8a0b828f',
  [ValidatePattern('^[a-z][a-z0-9-]+$')][string]$Region = 'us-central1',
  [ValidatePattern('^[a-z][a-z0-9-]+$')][string]$Service = 'redefine-api',
  [ValidatePattern('^[a-z][a-z0-9-]{4,28}[a-z0-9]$')][string]$ServiceAccountName = 'redefine-api',
  [ValidatePattern('^https://[A-Za-z0-9.-]+(:[0-9]+)?$')][string]$PublicBaseUrl = 'https://redefine-api-867740771011.us-central1.run.app'
)

# gcloud reports progress on stderr; under 'Stop' Windows PowerShell 5.1 treats that as a failure.
$ErrorActionPreference = 'Continue'

$NamedDatabase = 'redefine'
$ServiceAccount = "${ServiceAccountName}@${Project}.iam.gserviceaccount.com"
# Secret Manager secret -> env var; each is attached only if the secret exists.
$SecretEnv = [ordered]@{ 'stripe-secret-key' = 'STRIPE_SECRET_KEY'; 'admin-invite-code' = 'ADMIN_INVITE_CODE'; 'demo-password' = 'DEMO_PASSWORD' }

$Gcloud = (Get-Command gcloud.cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $Gcloud) { throw 'gcloud.cmd is not on PATH. Install the Google Cloud SDK first.' }

# Runs gcloud as the pinned account/project and throws on a non-zero exit code.
function Invoke-Gcloud {
  & $Gcloud @args "--account=$Account" "--project=$Project" --quiet
  if ($LASTEXITCODE -ne 0) { throw "gcloud $($args -join ' ') failed (exit code $LASTEXITCODE)." }
}

function Get-FirestoreDatabases {
  $json = (Invoke-Gcloud firestore databases list '--format=json') -join "`n"
  if (-not $json.Trim()) { return }
  foreach ($db in (ConvertFrom-Json $json)) {
    [pscustomobject]@{ Id = ($db.name -split '/')[-1]; Type = $db.type }
  }
}

function Resolve-DatabaseId {
  $databases = @(Get-FirestoreDatabases)
  $id = $Database
  if (-not $id) {
    $id = '(default)'
    if ($databases | Where-Object { $_.Id -eq $NamedDatabase }) { $id = $NamedDatabase }
  }
  $db = $databases | Where-Object { $_.Id -eq $id }
  if (-not $db) { throw "Firestore database '$id' does not exist. Run ./setup.ps1 first." }
  if ($db.Type -ne 'FIRESTORE_NATIVE') { throw "Firestore database '$id' is $($db.Type), not FIRESTORE_NATIVE. Run ./setup.ps1 first." }
  $id
}

function Assert-ServiceAccount {
  $existing = @(Invoke-Gcloud iam service-accounts list '--format=value(email)')
  if ($existing -notcontains $ServiceAccount) { throw "Service account $ServiceAccount does not exist. Run ./setup.ps1 first." }
}

# Names of the secrets in $SecretEnv that exist in Secret Manager.
function Get-AttachableSecrets {
  $existing = @(Invoke-Gcloud secrets list '--format=value(name)' | ForEach-Object { ($_ -split '/')[-1] })
  $SecretEnv.Keys | Where-Object { $existing -contains $_ }
}

function Publish-Service([string]$DatabaseId, [string[]]$Secrets, [bool]$Seed) {
  $envVars = @(
    'PERSISTENCE=firestore'
    "GCP_PROJECT=$Project"
    "FIRESTORE_DATABASE=$DatabaseId"
    "PUBLIC_BASE_URL=$PublicBaseUrl"
    "SEED_DEMO=$($Seed.ToString().ToLower())"
  ) -join ','
  # --set-secrets replaces every secret binding; with none left, clear any stale ones.
  $secretsArg = '--clear-secrets'
  if ($Secrets) { $secretsArg = '--set-secrets=' + (($Secrets | ForEach-Object { "$($SecretEnv[$_])=${_}:latest" }) -join ',') }

  Push-Location $PSScriptRoot
  try {
    Invoke-Gcloud run deploy $Service '--source=.' "--region=$Region" '--allow-unauthenticated' '--max-instances=1' "--service-account=$ServiceAccount" "--set-env-vars=$envVars" $secretsArg
  } finally {
    Pop-Location
  }
}

function Get-Health {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  for ($attempt = 1; ; $attempt++) {
    try {
      return Invoke-RestMethod -Uri "$PublicBaseUrl/health" -TimeoutSec 30
    } catch {
      if ($attempt -ge 5) { throw "GET $PublicBaseUrl/health failed: $($_.Exception.Message)" }
      Start-Sleep -Seconds 5
    }
  }
}

$databaseId = Resolve-DatabaseId
Assert-ServiceAccount
$secrets = @(Get-AttachableSecrets)
# The API refuses to seed a Firestore database with the public default demo password.
$seed = $SeedDemo -and ($secrets -contains 'demo-password')
if (-not $seed) { $secrets = @($secrets | Where-Object { $_ -ne 'demo-password' }) }

Write-Host "Deploying '$Service' to project '$Project' in '$Region' (database '$databaseId')..." -ForegroundColor Cyan
Publish-Service $databaseId $secrets $seed

$health = Get-Health
if ($health.persistence -ne 'firestore') {
  throw "Deployed, but $PublicBaseUrl/health reports persistence '$($health.persistence)' instead of 'firestore'."
}

Write-Host ''
Write-Host "Deployed: $PublicBaseUrl" -ForegroundColor Green
Write-Host "  Persistence : firestore ($databaseId)"
Write-Host "  Payments    : $($health.payments)"
if ($secrets -notcontains 'stripe-secret-key') {
  Write-Host '  No stripe-secret-key secret: run ./scripts/set-stripe-key.ps1 and deploy again to take card payments.'
} elseif ($health.payments -eq 'manual') {
  Write-Warning 'stripe-secret-key is attached but the API reports manual payments. Check the stored key.'
}
if ($secrets -notcontains 'admin-invite-code') {
  Write-Host '  No admin-invite-code secret: run ./scripts/set-admin-invite-code.ps1 and deploy again to allow admin signup.'
}
if ($seed) {
  Write-Host '  Demo data   : loaded if the database was empty (accounts use the demo-password secret).'
} elseif ($SeedDemo) {
  Write-Host '  No demo-password secret: the demo data was not loaded. Run ./scripts/set-demo-password.ps1 and deploy again to load it.'
}
