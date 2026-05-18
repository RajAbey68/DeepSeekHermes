#!/usr/bin/env bash
# One-command deploy for Hermes-DeepSeek gateway on GCP (scale-to-zero, free-tier-friendly).
# Usage:
#   export DEEPSEEK_API_KEY=sk-...          # required, get from platform.deepseek.com
#   export GCP_PROJECT=your-project-id      # required
#   ./deploy.sh
set -euo pipefail

# ---------- config (edit if you want) ----------
REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-hermes-deepseek-gateway}"
REPO_NAME="${REPO_NAME:-hermes-deepseek}"
IMAGE_TAG="${IMAGE_TAG:-v1}"
UI_BUCKET="${UI_BUCKET:-${GCP_PROJECT:-}-hermes-ui}"
RUNTIME_SA_NAME="${RUNTIME_SA_NAME:-gateway-runner}"
# Cloud Run sizing (smallest practical for Node + Rust binary):
MEMORY="${MEMORY:-512Mi}"           # 256Mi often OOMs at startup; 512Mi is safer
CPU="${CPU:-1}"                     # 0.5 is allowed but slower cold starts
CONCURRENCY="${CONCURRENCY:-40}"
MAX_INSTANCES="${MAX_INSTANCES:-3}"
MIN_INSTANCES=0                     # scale to zero
# ------------------------------------------------

if [[ -z "${GCP_PROJECT:-}" ]]; then
  echo "ERROR: GCP_PROJECT not set. Run: export GCP_PROJECT=your-project-id" >&2
  exit 1
fi
if [[ -z "${DEEPSEEK_API_KEY:-}" ]]; then
  echo "ERROR: DEEPSEEK_API_KEY not set. Get one from https://platform.deepseek.com" >&2
  exit 1
fi

gcloud config set project "$GCP_PROJECT" >/dev/null

echo "==> Enabling required APIs (idempotent, may take a minute the first time)"
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  storage.googleapis.com

echo "==> Creating Artifact Registry repo (if missing)"
gcloud artifacts repositories describe "$REPO_NAME" --location="$REGION" >/dev/null 2>&1 || \
  gcloud artifacts repositories create "$REPO_NAME" \
    --repository-format=docker --location="$REGION" \
    --description="Hermes-DeepSeek gateway images"

IMAGE_URI="${REGION}-docker.pkg.dev/${GCP_PROJECT}/${REPO_NAME}/gateway:${IMAGE_TAG}"

echo "==> Building image with Cloud Build (remote, no local Docker needed)"
echo "    image: ${IMAGE_URI}"
gcloud builds submit . --tag "$IMAGE_URI" --quiet

echo "==> Creating runtime service account (least privilege: no roles needed)"
RUNTIME_SA_EMAIL="${RUNTIME_SA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com"
gcloud iam service-accounts describe "$RUNTIME_SA_EMAIL" >/dev/null 2>&1 || \
  gcloud iam service-accounts create "$RUNTIME_SA_NAME" \
    --display-name="Hermes-DeepSeek gateway runtime"

echo "==> Deploying Cloud Run service (min=0, scale-to-zero)"
gcloud run deploy "$SERVICE_NAME" \
  --image="$IMAGE_URI" \
  --region="$REGION" \
  --platform=managed \
  --allow-unauthenticated \
  --service-account="$RUNTIME_SA_EMAIL" \
  --memory="$MEMORY" \
  --cpu="$CPU" \
  --concurrency="$CONCURRENCY" \
  --min-instances="$MIN_INSTANCES" \
  --max-instances="$MAX_INSTANCES" \
  --port=8080 \
  --set-env-vars="DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY}" \
  --quiet

SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" --region="$REGION" --format='value(status.url)')

echo "==> Creating GCS bucket for UI hosting (if missing)"
if ! gcloud storage buckets describe "gs://${UI_BUCKET}" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${UI_BUCKET}" \
    --location="$REGION" \
    --uniform-bucket-level-access \
    --public-access-prevention=inherited
  # Make objects publicly readable
  gcloud storage buckets add-iam-policy-binding "gs://${UI_BUCKET}" \
    --member=allUsers --role=roles/storage.objectViewer
fi

echo "==> Uploading UI (rewriting gateway URL)"
TMP_UI=$(mktemp -t ui.XXXXXX.html)
trap 'rm -f "$TMP_UI"' EXIT
sed "s|http://localhost:8080|${SERVICE_URL}|g" ../ui.html > "$TMP_UI"
gcloud storage cp "$TMP_UI" "gs://${UI_BUCKET}/index.html" \
  --content-type=text/html \
  --cache-control="public, max-age=300"

UI_URL="https://storage.googleapis.com/${UI_BUCKET}/index.html"

cat <<EOF

============================================================
  Deployment complete.

  Gateway API:  ${SERVICE_URL}
  Health:       ${SERVICE_URL}/health
  Chat UI:      ${UI_URL}

  Smoke test:
    curl -sS -X POST "${SERVICE_URL}/ai/chat/completions" \\
      -H 'Content-Type: application/json' \\
      -d '{"model":"deepseek/deepseek-chat","messages":[{"role":"user","content":"hi"}]}'

  Estimated monthly cost (personal use, ~100 req/day, ~3k req/mo):
    Cloud Run (min=0):           ~\$0     (free tier: 2M req, 360k GB-s, 180k vCPU-s)
    Cloud Storage (UI, <1 MB):   ~\$0     (free tier: 5 GB)
    Egress (UI + replies):       <\$0.50
    DeepSeek API (pay-per-token, varies by model and prompt):
      deepseek-chat:             ~\$0.50 - \$3
      deepseek-reasoner:         ~\$2 - \$8  (reasoning tokens add up)
    --------------------------------------------------------
    Total: ~\$1 - \$10 / month

  Cleanup (when you're done):  ./cleanup.sh
============================================================
EOF
