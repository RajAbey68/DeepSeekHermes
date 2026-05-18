#!/usr/bin/env bash
# One-command secret rotation. Run this in your Terminal — it will:
#   1. Prompt you (silent input) for your NEW DeepSeek API key
#   2. Create the secret in Secret Manager (or add a new version if it exists)
#   3. Grant Cloud Run's runtime SA access to read it
#   4. Switch the deephermes service from --set-env-vars to --update-secrets
#      (removes the plaintext env var on the same revision)
#   5. Smoke-test the new key works
#
# Nothing ever appears in this shell's history because `read -s` doesn't echo.
set -euo pipefail

PROJECT=leadsync-489921
PROJECT_NUMBER=116263110764
REGION=us-central1
SERVICE=deephermes
SECRET=deepseek-api-key
RUNTIME_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

echo "==> Paste your NEW DeepSeek API key (input hidden, then press Enter)"
read -rs NEW_KEY
echo
if [[ -z "$NEW_KEY" ]]; then
  echo "ERROR: empty key" >&2; exit 1
fi
if [[ ! "$NEW_KEY" =~ ^sk- ]]; then
  echo "WARNING: that doesn't look like a DeepSeek key (no sk- prefix). Continue anyway? [y/N]"
  read -r yn
  [[ "$yn" == "y" || "$yn" == "Y" ]] || exit 1
fi

echo "==> Creating or updating secret '${SECRET}' in project '${PROJECT}'"
if gcloud secrets describe "$SECRET" --project="$PROJECT" >/dev/null 2>&1; then
  echo "    secret exists — adding a new version"
  printf "%s" "$NEW_KEY" | gcloud secrets versions add "$SECRET" \
    --data-file=- --project="$PROJECT" --quiet 2>&1 | tail -2
else
  echo "    secret not present — creating"
  printf "%s" "$NEW_KEY" | gcloud secrets create "$SECRET" \
    --replication-policy=automatic --data-file=- \
    --project="$PROJECT" --quiet 2>&1 | tail -2
fi
unset NEW_KEY  # remove from this shell's memory immediately

echo "==> Granting secret-accessor to ${RUNTIME_SA}"
gcloud secrets add-iam-policy-binding "$SECRET" \
  --member="serviceAccount:${RUNTIME_SA}" \
  --role="roles/secretmanager.secretAccessor" \
  --project="$PROJECT" \
  --quiet 2>&1 | tail -3

echo "==> Switching Cloud Run service to reference the secret (removes plaintext env var)"
gcloud run services update "$SERVICE" \
  --region="$REGION" \
  --update-secrets="DEEPSEEK_API_KEY=${SECRET}:latest" \
  --remove-env-vars=DEEPSEEK_API_KEY \
  --project="$PROJECT" \
  --quiet 2>&1 | tail -5

echo
echo "==> Smoke-testing the new key (may cold-start, give it 10–30s)"
URL="https://${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
RESPONSE=$(curl -sS --max-time 60 -X POST "$URL/ai/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"deepseek-chat","messages":[{"role":"user","content":"Reply with exactly: rotated-ok"}],"max_tokens":10}')
CONTENT=$(echo "$RESPONSE" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("choices",[{}])[0].get("message",{}).get("content","(no content)"))' 2>/dev/null || echo "$RESPONSE")
echo "    response: $CONTENT"
if [[ "$CONTENT" == "rotated-ok" ]]; then
  echo
  echo "✅ Rotation complete. The old leaked key is no longer wired to Cloud Run."
  echo "   Last step: delete it on platform.deepseek.com/api_keys so it stops working entirely."
else
  echo
  echo "⚠️  Smoke test response didn't match exactly — gateway may still be warming up,"
  echo "    or the new key was wrong. Re-run the curl manually:"
  echo "    curl -sS -X POST $URL/ai/chat/completions -H 'Content-Type: application/json' -d '{\"model\":\"deepseek-chat\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}'"
fi
