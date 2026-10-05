# Deploys the Redefine API to Google Cloud Run.
# Usage:  ./deploy.ps1            (uses current gcloud project)
#         ./deploy.ps1 -Project my-proj -Region us-central1
param(
  [string]$Project = (gcloud config get-value project 2>$null),
  [string]$Region  = "us-central1",
  [string]$Service = "redefine-api"
)

Write-Host "Deploying '$Service' to project '$Project' in '$Region'..." -ForegroundColor Cyan

gcloud services enable run.googleapis.com cloudbuild.googleapis.com --project $Project

gcloud run deploy $Service `
  --source . `
  --project $Project `
  --region $Region `
  --platform managed `
  --allow-unauthenticated `
  --port 8080

Write-Host "`nService URL:" -ForegroundColor Green
gcloud run services describe $Service --project $Project --region $Region --format "value(status.url)"
