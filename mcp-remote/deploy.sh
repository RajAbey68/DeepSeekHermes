#!/usr/bin/env bash
# Deploy deephermes-mcp-remote to Cloud Run.
# Prereqs: gcloud authed, billing linked on $PROJECT.
# First run: also creates Secret Manager secret `MCPClientKeys` (prompts for keys).
set -euo pipefail

PROJECT=leadsync-489921
PROJECT_NUMBER=116263110764
REGION=us-central1
SERVICE=deephermes-mcp
SECRET=MCPClientKeys
GATEWAY_URL=https://deephermes-${PROJECT_NUMBER}.${REGION}.run.app
RUNTIME_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# ---- 1. Ensure APIs ----
echo "==> Enabling APIs"
gcloud services enable \
  cloudbuild.googleapis.com run.googleapis.com \
  artifactregistry.googleapis.com secretmanager.googleapis.com \
  --project="$PROJECT" >/dev/null

# ---- 2. Ensure Secret Manager secret exists ----
if gcloud secrets describe "$SECRET" --project="$PROJECT" >/dev/null 2>&1; then
  echo "==> Secret '$SECRET' already exists — leaving as-is"
else
  echo "==> Secret '$SECRET' missing — generating 3 random keys and creating it"
  KEYS=$(for i in 1 2 3; do openssl rand -hex 32; done | paste -sd, -)
  printf "%s" "$KEYS" | gcloud secrets create "$SECRET" \
    --replication-policy=automatic --data-file=- \
    --project="$PROJECT" --quiet >/dev/null
  unset KEYS
  echo
  echo "    Keys stored in Secret Manager. Retrieve with:"
  echo "    gcloud secrets versions access latest --secret=${SECRET} --project=${PROJECT}"
  echo
fi

# ---- 3. Grant runtime SA access to the secret ----
echo "==> Granting secret-accessor to ${RUNTIME_SA}"
gcloud secrets add-iam-policy-binding "$SECRET" \
  --member="serviceAccount:${RUNTIME_SA}" \
  --role="roles/secretmanager.secretAccessor" \
  --project="$PROJECT" --quiet >/dev/null

# ---- 4. Build the container ----
IMAGE="gcr.io/${PROJECT}/${SERVICE}"
echo "==> Cloud Build → ${IMAGE}"
gcloud builds submit . --tag "$IMAGE" --project="$PROJECT" --quiet

# ---- 5. Deploy ----
echo "==> Deploying Cloud Run service '${SERVICE}'"
gcloud run deploy "$SERVICE" \
  --image "$IMAGE" \
  --region "$REGION" \
  --platform managed \
  --allow-unauthenticated \
  --memory 512Mi --cpu 1 \
  --min-instances 0 --max-instances 3 \
  --port 8080 \
  --set-env-vars="DEEPSEEK_GATEWAY_URL=${GATEWAY_URL}" \
  --update-secrets="MCP_CLIENT_KEYS=${SECRET}:latest" \
  --project="$PROJECT" --quiet

URL=$(gcloud run services describe "$SERVICE" --region="$REGION" --project="$PROJECT" --format='value(status.url)')
echo
echo "============================================================"
echo "  Deployed:    ${URL}"
echo "  Health:      ${URL}/health"
echo "  MCP endpoint: ${URL}/mcp  (POST, with Authorization: Bearer <client-key>)"
echo
echo "  To list current client keys (one-off, careful — they print):"
echo "    gcloud secrets versions access latest --secret=${SECRET} --project=${PROJECT}"
echo
echo "  To rotate / add a key:"
echo "    NEW=\$(openssl rand -hex 32)"
echo "    OLD=\$(gcloud secrets versions access latest --secret=${SECRET} --project=${PROJECT})"
echo "    printf '%s,%s' \"\$OLD\" \"\$NEW\" | gcloud secrets versions add ${SECRET} --data-file=- --project=${PROJECT}"
echo "============================================================"
