#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <participant-name> <host-or-host/path> [issuer-base-url]" >&2
  exit 1
fi

participant_name="$1"
participant_input="$2"
issuer_base_url="${3:-https://gxdch.dil.collab-cloud.eu/issuer}"

participant_host="${participant_input%%/*}"
participant_path=""
if [[ "$participant_input" == */* ]]; then
  participant_path="/${participant_input#*/}"
  participant_path="${participant_path%/}"
fi

did_id="did:web:${participant_host}"
if [[ -n "$participant_path" ]]; then
  IFS='/' read -r -a path_parts <<< "${participant_path#/}"
  for part in "${path_parts[@]}"; do
    if [[ -n "$part" ]]; then
      did_id="${did_id}:${part}"
    fi
  done
fi

participant_id_b64="$(printf '%s' "$did_id" | basenc --base64url -w0)"
identity_base="https://${participant_host}${participant_path}/api/identity"
credentials_endpoint="https://${participant_host}${participant_path}/api/credentials/v1/participants/${participant_id_b64}"
dsp_endpoint="https://${participant_host}/cp/api/dsp"

cat <<EOF
# Create participant context in local Identity Hub
curl --location '${identity_base}/v1alpha/participants/' \\
  --header 'Content-Type: application/json' \\
  --header 'x-api-key: <IDENTITY_HUB_SUPERUSER_KEY>' \\
  --data '{
    "roles": [],
    "serviceEndpoints": [
      {
        "type": "CredentialService",
        "serviceEndpoint": "${credentials_endpoint}",
        "id": "${participant_name}-credentialservice-1"
      },
      {
        "type": "ProtocolEndpoint",
        "serviceEndpoint": "${dsp_endpoint}",
        "id": "${participant_name}-dsp"
      }
    ],
    "active": true,
    "participantId": "${did_id}",
    "did": "${did_id}",
    "key": {
      "keyId": "${did_id}#key-1",
      "privateKeyAlias": "${did_id}#key-1",
      "keyGeneratorParams": {
        "algorithm": "EC"
      }
    }
  }'

# Register participant holder in central issuer
curl --location '${issuer_base_url}/api/admin/v1alpha/participants/<ISSUER_CONTEXT_ID>/holders' \\
  --header 'Content-Type: application/json' \\
  --header 'x-api-key: <ISSUER_ADMIN_API_KEY>' \\
  --data '{
    "did": "${did_id}",
    "participantId": "${did_id}",
    "name": "${participant_name}"
  }'
EOF
