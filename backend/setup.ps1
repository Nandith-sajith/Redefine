# One-time Google Cloud setup for the Redefine API. Idempotent: safe to re-run.
# Enables the APIs, ensures a Firestore NATIVE database in Toronto and creates
# the Cloud Run runtime service account.
# Usage:  ./setup.ps1
param(
  [ValidatePattern('^[A-Za-z0-9._+-]+@[A-Za-z0-9.-]+$')][string]$Account = 'redefine073@gmail.com',
  [ValidatePattern('^[a-z][a-z0-9-]{4,28}[a-z0-9]$')][string]$Project = 'redefine-8a0b828f',
  [ValidatePattern('^[a-z][a-z0-9-]+$')][string]$Location = 'northamerica-northeast2',
  [ValidatePattern('^[a-z][a-z0-9-]{4,28}[a-z0-9]$')][string]$ServiceAccountName = 'redefine-api'
)

# gcloud reports progress on stderr; under 'Stop' Windows PowerShell 5.1 treats that as a failure.
$ErrorActionPreference = 'Continue'

$NamedDatabase = 'redefine'
$ServiceAccount = "${ServiceAccountName}@${Project}.iam.gserviceaccount.com"

$Gcloud = (Get-Command gcloud.cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $Gcloud) { throw 'gcloud.cmd is not on PATH. Install the Google Cloud SDK first.' }

# Runs gcloud as the pinned account/project and throws on a non-zero exit code.
function Invoke-Gcloud {
  & $Gcloud @args "--account=$Account" "--project=$Project" --quiet
  if ($LASTEXITCODE -ne 0) { throw "gcloud $($args -join ' ') failed (exit code $LASTEXITCODE)." }
}

# A freshly enabled API or a new service account can take a minute to become usable.
function Invoke-WithRetry([scriptblock]$Step) {
  for ($attempt = 1; ; $attempt++) {
    try {
      $out = & $Step
      return $out
    } catch {
      if ($attempt -ge 6) { throw }
      Write-Host "Not ready yet, retrying in 10 s ($attempt of 5)..." -ForegroundColor Yellow
      Start-Sleep -Seconds 10
    }
  }
}

function Get-FirestoreDatabases {
  $json = (Invoke-Gcloud firestore databases list '--format=json') -join "`n"
  if (-not $json.Trim()) { return }
  foreach ($db in (ConvertFrom-Json $json)) {
    [pscustomobject]@{
      Id        = ($db.name -split '/')[-1]
      Type      = $db.type
      Location  = $db.locationId
      Protected = $db.deleteProtectionState -eq 'DELETE_PROTECTION_ENABLED'
    }
  }
}

# The named database wins once it exists (deploy.ps1 prefers it). Otherwise (default) is used
# when it is free or already NATIVE in $Location, e.g. not a Datastore-mode default.
function Select-DatabaseId($Databases) {
  $default = $Databases | Where-Object { $_.Id -eq '(default)' }
  if ($Databases | Where-Object { $_.Id -eq $NamedDatabase }) { return $NamedDatabase }
  if (-not $default) { return '(default)' }
  if ($default.Type -eq 'FIRESTORE_NATIVE' -and $default.Location -eq $Location) { return '(default)' }
  $NamedDatabase
}

# Ensures the database exists with delete protection and returns its id.
function Initialize-Database {
  $databases = @(Invoke-WithRetry { Get-FirestoreDatabases })
  $id = Select-DatabaseId $databases
  $db = $databases | Where-Object { $_.Id -eq $id }
  if (-not $db) {
    Write-Host "Creating Firestore database '$id' in $Location..."
    Invoke-Gcloud firestore databases create "--database=$id" "--location=$Location" '--type=firestore-native' '--delete-protection' '--format=none' | Out-Host
    return $id
  }
  if ($db.Type -ne 'FIRESTORE_NATIVE') {
    throw "Firestore database '$id' is $($db.Type); the API needs FIRESTORE_NATIVE. Delete or rename it, then re-run."
  }
  if ($db.Location -ne $Location) {
    Write-Warning "Firestore database '$id' is in $($db.Location), not $Location. Using it as is."
  }
  if (-not $db.Protected) {
    Write-Host "Enabling delete protection on Firestore database '$id'..."
    Invoke-Gcloud firestore databases update "--database=$id" '--delete-protection' '--format=none' | Out-Host
  }
  $id
}

function Initialize-ServiceAccount {
  $existing = @(Invoke-Gcloud iam service-accounts list '--format=value(email)')
  if ($existing -notcontains $ServiceAccount) {
    Write-Host "Creating service account $ServiceAccount..."
    Invoke-Gcloud iam service-accounts create $ServiceAccountName '--display-name=Redefine API runtime'
  }
  Invoke-WithRetry {
    Invoke-Gcloud projects add-iam-policy-binding $Project "--member=serviceAccount:$ServiceAccount" '--role=roles/datastore.user' '--condition=None' '--format=none'
  }
}

Write-Host "Setting up project '$Project' as $Account..." -ForegroundColor Cyan
Invoke-Gcloud services enable firestore.googleapis.com secretmanager.googleapis.com run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com iam.googleapis.com

$database = Initialize-Database
Initialize-ServiceAccount

Write-Host ''
Write-Host 'Setup complete.' -ForegroundColor Green
Write-Host "  Firestore database : $database"
Write-Host "  Service account    : $ServiceAccount"
Write-Host ''
Write-Host 'Optional: ./scripts/set-stripe-key.ps1 (card payments), ./scripts/set-admin-invite-code.ps1 (admin signup),'
Write-Host '          ./scripts/set-demo-password.ps1 (demo data).'
Write-Host "Then run ./deploy.ps1; it uses database '$database' (same as -Database '$database')."
