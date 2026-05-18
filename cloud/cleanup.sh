#!/usr/bin/env bash
# Tear down everything deploy.sh created. Idempotent.
set -euo pipefail

REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-hermes-deepseek-gateway}"
REPO_NAME="${REPO_NAME:-hermes-deepseek}"
UI_BUCKET="${UI_BUCKET:-${GCP_PROJECT:-}-hermes-ui}"
RUNTIME_SA_NAME="${RUNTIME_SA_NAME:-gateway-runner}"

if [[ -z "${GCP_PROJECT:-}" ]]; then
  echo "ERROR: GCP_PROJECT not set." >&2
  exit 1
fi
gcloud config set project "$GCP_PROJECT" >/dev/null

echo "==> Deleting Cloud Run service"
gcloud run services delete "$SERVICE_NAME" --region="$REGION" --quiet 2>/dev/null || echo "  (already gone)"

echo "==> Emptying and deleting UI bucket"
gcloud storage rm -r "gs://${UI_BUCKET}" --quiet 2>/dev/null || echo "  (already gone)"

echo "==> Deleting Artifact Registry repo (all images)"
gcloud artifacts repositories delete "$REPO_NAME" --location="$REGION" --quiet 2>/dev/null || echo "  (already gone)"

echo "==> Deleting runtime service account"
gcloud iam service-accounts delete "${RUNTIME_SA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com" --quiet 2>/dev/null || echo "  (already gone)"

echo
echo "Cleanup done. Cloud Build's _cloudbuild bucket may still exist (it's reused across builds — safe to leave or delete manually)."
