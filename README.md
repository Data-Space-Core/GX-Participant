# GX-Participant

This repository is a GitOps-ready ArgoCD project for deploying one participant stack into a tenant cluster such as `gx-participant1`.

It is based on the participant-side components used by the Eclipse EDC Minimum Viable Dataspace demo:

- EDC control plane
- EDC data plane
- EDC Identity Hub
- static `did:web` hosting through NGINX
- PostgreSQL
- HashiCorp Vault
- MinIO object storage

This repo is designed to work with the central governance services you already deployed in `gxdch`:

- GXDCH compliance stack
- GXDCH issuer stack

It does not include a wallet UI by default. For the EDC connector-to-connector path, Identity Hub is the relevant component. A wallet can be added later if you want human-facing OIDC4VC flows.

## Repository Layout

```text
platform-apps/
  argocd/
    gx-participant-application.yaml
  gx-participant/
    appproject.yaml
    gx-participant-core-application.yaml
    kustomization.yaml
    namespace.yaml
    core/
      ...
scripts/
  build-mvd-participant-images.sh
  generate-participant-bootstrap.sh
  render-participant-seed.sh
```

## Repository URL

The manifests currently point to:

```text
https://github.com/Data-Space-Core/GX-Participant.git
```

If your repository URL differs, update:

- `platform-apps/argocd/gx-participant-application.yaml`
- `platform-apps/gx-participant/appproject.yaml`
- `platform-apps/gx-participant/gx-participant-core-application.yaml`

## Scope

This stack deploys the participant runtime side:

- `gx-participant-controlplane`
- `gx-participant-dataplane`
- `gx-participant-identityhub`
- `gx-participant-did`
- `gx-participant-postgres`
- `gx-participant-vault`
- `gx-participant-minio`

It is intended to be installed inside a tenant vCluster such as `gx-participant1`.

## Important Prerequisites

### 1. Build and publish the participant runtime images

Use the local Eclipse EDC `MinimumViableDataspace` checkout to build the participant images:

```bash
./scripts/build-mvd-participant-images.sh /path/to/MinimumViableDataspace ghcr.io/your-org
```

This expects the MVD repo root and tags/pushes:

- `controlplane:latest` -> `ghcr.io/your-org/controlplane:latest`
- `dataplane:latest` -> `ghcr.io/your-org/dataplane:latest`
- `identity-hub:latest` -> `ghcr.io/your-org/identity-hub:latest`

After pushing the images, update:

- `platform-apps/gx-participant/core/controlplane-deployment.yaml`
- `platform-apps/gx-participant/core/dataplane-deployment.yaml`
- `platform-apps/gx-participant/core/identityhub-deployment.yaml`

### 2. Generate participant bootstrap material

Before syncing the stack, generate:

- a participant EC keypair for STS and transfer proxy signing
- a participant `did:web` document
- a client secret for STS OAuth
- an NGINX config for static DID hosting

Helper script:

```bash
./scripts/generate-participant-bootstrap.sh gx-participant1 gxdch-participant1.dil.collab-cloud.eu/identity gx-participant > participant-bootstrap.yaml
kubectl apply -f participant-bootstrap.yaml
```

The second argument can be either:

- a dedicated hostname, for example `identity.gx-participant1.dil.collab-cloud.eu`
- or a host plus path, for example `gx-participant1.dil.collab-cloud.eu/identity`

For the path-based example, the resulting DID will be:

```text
did:web:gx-participant1.dil.collab-cloud.eu:identity
```

and the public DID document must be reachable at:

```text
https://gx-participant1.dil.collab-cloud.eu/identity/did.json
```

Internally, the bundled NGINX server serves the document at:

```text
/did.json
```

so your gateway should rewrite:

```text
/identity/did.json -> /did.json
```

This bootstrap creates:

- `Secret/participant-bootstrap`
- `ConfigMap/participant-did-config`

The stack expects those resources to exist before sync.

## Bootstrap

1. Push this repository to GitHub.
2. Build and publish the participant images.
3. Update the image references in the deployment manifests.
4. Create the namespace in the tenant cluster once:

```bash
kubectl create namespace gx-participant
```

5. Generate and apply the participant bootstrap:

```bash
./scripts/generate-participant-bootstrap.sh gx-participant1 gx-participant1.dil.collab-cloud.eu/identity gx-participant | kubectl apply -f -
```

6. Apply the root ArgoCD application:

```bash
kubectl apply -n argocd -f platform-apps/argocd/gx-participant-application.yaml
```

## Services and Ports

- `gx-participant-controlplane`
  - `8080` health
  - `8081` management API
  - `8082` DSP protocol
  - `8083` control API
  - `8084` catalog API
- `gx-participant-dataplane`
  - `8080` health
  - `8083` control API
  - `11001` public transfer endpoint
- `gx-participant-identityhub`
  - `7080` health
  - `7081` credentials API
  - `7082` identity API
  - `7083` DID endpoint
  - `7086` STS API
- `gx-participant-did`
  - `80` static DID hosting through NGINX
- `gx-participant-postgres`
  - `5432`
- `gx-participant-vault`
  - `8200`
- `gx-participant-minio`
  - `9000` S3 API
  - `9001` console

## Suggested Envoy Gateway Routes

One clean host model is:

- `cp.gx-participant1.dil.collab-cloud.eu` -> `gx-participant-controlplane`
- `dp.gx-participant1.dil.collab-cloud.eu` -> `gx-participant-dataplane`
- `identity.gx-participant1.dil.collab-cloud.eu` -> `gx-participant-identityhub`

If you stay with a single hostname plus paths, the minimum routes are:

- `https://gx-participant1.dil.collab-cloud.eu/identity/did.json` -> `gx-participant-did:80` with rewrite to `/did.json`
- `https://gx-participant1.dil.collab-cloud.eu/identity/api/identity/...` -> `gx-participant-identityhub:7082`
- `https://gx-participant1.dil.collab-cloud.eu/identity/api/credentials/...` -> `gx-participant-identityhub:7081`
- `https://gx-participant1.dil.collab-cloud.eu/identity/api/sts/...` -> `gx-participant-identityhub:7086`
- `https://gx-participant1.dil.collab-cloud.eu/cp/api/management/...` -> `gx-participant-controlplane:8081`
- `https://gx-participant1.dil.collab-cloud.eu/cp/api/catalog/...` -> `gx-participant-controlplane:8084`
- `https://gx-participant1.dil.collab-cloud.eu/cp/api/dsp/...` -> `gx-participant-controlplane:8082`
- `https://gx-participant1.dil.collab-cloud.eu/dp/api/public/...` -> `gx-participant-dataplane:11001`

For path-based routing, strip the external prefix before forwarding:

- `/identity/...` -> `/...`
- `/cp/...` -> `/...`
- `/dp/...` -> `/...`

## Governance Integration

The manifests already include placeholders for the central `gxdch` governance endpoints:

- issuer identity API
- issuer admin API
- issuer issuance API
- compliance API
- registry API
- notary API

Update `platform-apps/gx-participant/core/participant-settings-configmap.yaml` with your real URLs before sync.

These URLs are used for:

- participant bootstrap and seeding
- holder registration in the central issuer
- later policy and credential flows

## Seeding the Participant

After the stack is up and externally reachable, use:

```bash
./scripts/render-participant-seed.sh gx-participant1 gx-participant1.dil.collab-cloud.eu/identity
```

This prints example `curl` commands for:

- creating the participant context in its own Identity Hub
- registering the participant in the central issuer admin API

It does not call the APIs automatically, because the exact issuer auth and external URLs vary by environment.

## MinIO

MinIO is included as simple object storage for participant-owned assets. It is not fully wired into a specific EDC asset definition out of the box. Treat it as the tenant-local object store to back future HTTP/S3-style assets.

## Operational Notes

- Vault is deployed in dev mode for simplicity. This is not production-grade.
- PostgreSQL uses one PVC and local credentials from a Kubernetes Secret.
- MinIO uses one PVC and local credentials from a Kubernetes Secret.
- This stack is for one participant. Clone or template it for `gx-participant2`.
- The participant uses Identity Hub for connector trust. No separate wallet component is required for the core EDC DCP path.

## Sources

Primary sources used for this repo design:

- Eclipse EDC MinimumViableDataspace: https://github.com/eclipse-edc/MinimumViableDataspace
- Eclipse EDC Identity Hub documentation: https://eclipse-edc.github.io/documentation/for-adopters/identity-hub/
