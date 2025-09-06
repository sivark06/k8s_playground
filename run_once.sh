#!/bin/bash
# ==============================================================================
# This script performs the one-time setup for GitHub Actions OIDC with GCP.
# It creates a Workload Identity Pool, a Provider, a Service Account,
# and grants the necessary permissions for your GitHub repo to deploy
# resources to your GCP project.
#
# IMPORTANT: Set the following variables before running.
# ==============================================================================

# --- Your Configuration ---
GCP_PROJECT_ID="gcp-projectid-999999" #Your GCP project ID
GCP_PROJECT_NUMBER="999999999999" # Project Number
GITHUB_REPO="owner/repo" # Format: "owner/repository"
SERVICE_ACCOUNT_NAME="service-account-name" # Service account name
# --------------------------

set -e -u -o pipefail # Exit on error, treat unset variables as errors, and fail on pipeline errors.

# Enable IAM Credentials API if not already
echo "Enabling required services..."
gcloud services enable iamcredentials.googleapis.com --project "${GCP_PROJECT_ID}"

# Create a workload identity pool and provider for GitHub
POOL="github-oidc"
PROVIDER="github-provider"

echo "Creating Workload Identity Pool..."
gcloud iam workload-identity-pools create "${POOL}" \
  --project="${GCP_PROJECT_ID}" \
  --location="global" \
  --display-name="GitHub OIDC Pool" --quiet || echo "Pool '${POOL}' already exists."

echo "Creating OIDC Provider..."
gcloud iam workload-identity-pools providers create-oidc "${PROVIDER}" \
  --project="${GCP_PROJECT_ID}" \
  --location="global" \
  --workload-identity-pool="${POOL}" \
  --display-name="GitHub Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
  --issuer-uri="https://token.actions.githubusercontent.com" --quiet || echo "Provider '${PROVIDER}' already exists."

# Create a deployer service account
echo "Creating Service Account..."
gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
  --project "${GCP_PROJECT_ID}" \
  --display-name "GitHub Terraform Deployer" --quiet || echo "Service Account '${SERVICE_ACCOUNT_NAME}' already exists."

SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

# Grant roles (adjust if you want tighter scope)
echo "Granting 'Editor' role to Service Account..."
gcloud projects add-iam-policy-binding "${GCP_PROJECT_ID}" \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/editor"

# Allow GitHub repo to impersonate the SA via OIDC
echo "Binding Service Account to GitHub repository..."
gcloud iam service-accounts add-iam-policy-binding "${SERVICE_ACCOUNT_EMAIL}" \
  --project="${GCP_PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${GCP_PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL}/attribute.repository/${GITHUB_REPO}"

echo "✅ OIDC setup complete for repo ${GITHUB_REPO}."
