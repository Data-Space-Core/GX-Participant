#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <participant-name> <host-or-host/path> [namespace]" >&2
  exit 1
fi

participant_name="$1"
participant_input="$2"
namespace="${3:-gx-participant}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

private_key="$tmp_dir/sts-private-key.pem"
public_key="$tmp_dir/sts-public-key.pem"
public_der="$tmp_dir/sts-public-key.der"
sts_client_secret="$tmp_dir/sts-client-secret.txt"

openssl ecparam -name prime256v1 -genkey -noout -out "$private_key" >/dev/null 2>&1
openssl ec -in "$private_key" -pubout -out "$public_key" >/dev/null 2>&1
openssl pkey -pubin -in "$public_key" -outform DER -out "$public_der" >/dev/null 2>&1
openssl rand -base64 32 | tr -d '\n' > "$sts_client_secret"

participant_host="${participant_input%%/*}"
participant_path=""
if [[ "$participant_input" == */* ]]; then
  participant_path="/${participant_input#*/}"
  participant_path="${participant_path%/}"
fi

if [[ -z "$participant_host" ]]; then
  echo "Participant host must not be empty" >&2
  exit 1
fi

did_id="did:web:${participant_host}"
did_doc_path="/did.json"
if [[ -n "$participant_path" ]]; then
  IFS='/' read -r -a path_parts <<< "${participant_path#/}"
  for part in "${path_parts[@]}"; do
    if [[ -n "$part" ]]; then
      did_id="${did_id}:${part}"
    fi
  done
fi

participant_public_alias="${participant_name}-publickey"
participant_private_alias="${did_id}-alias"
sts_client_secret_alias="${did_id}-sts-client-secret"

pub_hex="$(openssl ec -pubin -in "$public_key" -text -noout 2>/dev/null | awk '
  /pub:/ { capture=1; next }
  /ASN1 OID:/ { capture=0 }
  capture {
    gsub(/[:[:space:]]/, "")
    printf "%s", $0
  }
  END { print "" }
')"
pub_hex="${pub_hex#04}"
pub_x="${pub_hex:0:64}"
pub_y="${pub_hex:64:64}"
x_b64="$(printf '%s' "$pub_x" | xxd -r -p | basenc --base64url -w0)"
y_b64="$(printf '%s' "$pub_y" | xxd -r -p | basenc --base64url -w0)"

cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: participant-bootstrap
  namespace: ${namespace}
type: Opaque
stringData:
  participant-name.txt: ${participant_name}
  participant-did.txt: ${did_id}
  participant-public-key-alias.txt: ${participant_public_alias}
  participant-private-key-alias.txt: ${participant_private_alias}
  participant-sts-client-secret-alias.txt: ${sts_client_secret_alias}
  sts-client-secret.txt: $(cat "$sts_client_secret")
  sts-private-key.pem: |
$(sed 's/^/    /' "$private_key")
  sts-public-key.pem: |
$(sed 's/^/    /' "$public_key")
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: participant-did-config
  namespace: ${namespace}
data:
  nginx.conf: |
    events {}
    http {
      server {
        listen 80;
        location = ${did_doc_path} {
          alias /var/www/did.json;
          default_type application/json;
        }
      }
    }
  did.json: |
    {
      "id": "${did_id}",
      "@context": [
        "https://www.w3.org/ns/did/v1",
        "https://w3id.org/security/suites/jws-2020/v1"
      ],
      "verificationMethod": [
        {
          "id": "${did_id}#key-1",
          "type": "JsonWebKey2020",
          "controller": "${did_id}",
          "publicKeyJwk": {
            "kty": "EC",
            "crv": "P-256",
            "x": "${x_b64}",
            "y": "${y_b64}"
          }
        }
      ],
      "authentication": [
        "${did_id}#key-1"
      ],
      "assertionMethod": [
        "${did_id}#key-1"
      ],
      "service": []
    }
EOF
