### README: GKE ML Playground (Istio + Argo CD + Kubeflow Pipelines/KServe)

#### Overview
This repo spins up a cost-optimized, personal GKE Playground that you can destroy/recreate daily in minutes—ideal for demos and learning. It’s wired for GitOps with Argo CD so your stack rehydrates from GitHub automatically.

What you get:
- GKE single-zone cluster (VPC-native) with Workload Identity
- Two node pools:
  - system-pool: small, scales to 0 when idle
  - workload-pool: beefy, scales from 0 for ML workloads
- Istio (ingress gateway with LoadBalancer)
- Argo CD (App of Apps pattern)
- Kubeflow light stack: Pipelines + KServe (optional to switch to full Kubeflow)
- Optional GitHub Actions workflow using GCP OIDC (no long-lived JSON keys)

Designed for:
- Fast destroy/apply cycles
- Low idle cost, bursty when needed
- Public portfolio/repo showcasing IaC + GitOps

#### Repo Structure
```
.
├─ infra/
│  └─ terraform/
│     ├─ main.tf
│     ├─ variables.tf
│     ├─ providers.tf
│     ├─ versions.tf
│     └─ outputs.tf
├─ apps/
│  ├─ kustomization.yaml
│  ├─ root-app/
│  │  └─ app-of-apps.yaml
│  ├─ istio/
│  │  ├─ kustomization.yaml
│  │  ├─ ns.yaml
│  │  └─ istio-operator.yaml
│  ├─ argocd-addons/
│  │  ├─ kustomization.yaml
│  │  └─ server-lb.yaml
│  └─ kubeflow/
│     ├─ kustomization.yaml
│     ├─ pipelines/
│     │  ├─ kustomization.yaml
│     │  └─ ns.yaml
│     └─ kserve/
│        ├─ kustomization.yaml
│        └─ ns.yaml
└─ .github/
   └─ workflows/
      └─ ci.yaml  (optional; uses GCP OIDC)
```

#### Prerequisites
- GCP project with billing enabled
- Service account with sufficient permissions and a JSON key locally for first run (later replace with OIDC):
  - Example: k8splaykey.json
- Tools:
  - Terraform >= 1.5
  - gcloud SDK
  - kubectl
  - (optional) istioctl for local installs/debug

#### Quick Start (Local)
1) Set your project variables
- Copy your service account key into infra/terraform (do not commit it).
- Create infra/terraform/terraform.tfvars:
```hcl
project_id       = "YOUR_PROJECT_ID"
project_number   = "YOUR_PROJECT_NUMBER"
region           = "us-central1"
zone             = "us-central1-a"
credentials_file = "k8splaykey.json"
```

2) Initialize and apply
```bash
cd infra/terraform
terraform init
terraform apply -auto-approve
```

3) Connect kubectl
- Terraform outputs a convenient command. Or run:
```bash
gcloud container clusters get-credentials ml-gke --zone us-central1-a --project YOUR_PROJECT_ID
```

4) Bootstrap Argo CD “App of Apps”
- Update repo URL in apps/root-app/app-of-apps.yaml (repoURL + branch).
- Apply it to Argo CD:
```bash
kubectl apply -n argocd -f apps/root-app/app-of-apps.yaml
```

5) Verify components
```bash
kubectl -n istio-system get svc istio-ingressgateway
kubectl -n argocd get svc argocd-server
kubectl -n kubeflow get svc ml-pipeline-ui
```

6) Access UIs
- Argo CD:
  - External IP: kubectl -n argocd get svc argocd-server
  - Initial admin password:
    - kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
- Kubeflow Pipelines UI:
  - External IP: kubectl -n kubeflow get svc ml-pipeline-ui

7) Destroy when done
```bash
cd infra/terraform
terraform destroy -auto-approve
```

#### What’s Installed

- Istio via IstioOperator:
  - Namespace: istio-system
  - Ingress Gateway exposed as a LoadBalancer for easy access
- Argo CD add-on:
  - argocd-server exposed as a LoadBalancer (quick external access)
- Kubeflow light stack:
  - Pipelines standalone (UI exposed as LoadBalancer)
  - KServe with default runtimes
- Managed Prometheus enabled on cluster for basic metrics

You can switch to full Kubeflow by swapping manifests in apps/kubeflow.

#### Cost Optimization Notes
- Single-zone cluster
- Public nodes (no Cloud NAT costs)
- Node pools scale to zero when idle
- Workload pool uses large machine types but starts at 0—only spins up on demand
- You can further reduce:
  - workload_node_machine_type to e2-standard-8
  - max node count to 1

#### GitHub Actions (Optional, Recommended)
- Uses Workload Identity Federation (OIDC). No JSON keys stored in GitHub.
- .github/workflows/ci.yaml:
  - Auth to GCP
  - terraform init/plan/apply in infra/terraform
  - kubectl apply the App of Apps to ensure Argo CD syncs

One-time GCP setup for OIDC (from your machine):
- Create workload identity pool/provider and a deployer service account.
- Grant roles/impersonation to your GitHub repo principal.
- Then push the workflow and it will run on push to main.

In apps/root-app/app-of-apps.yaml, set:
- spec.source.repoURL: your repo URL
- spec.source.targetRevision: your branch (e.g., main)

#### Customization

- Change machine types or autoscaling limits:
  - infra/terraform/variables.tf
  - system/workload pools min/max nodes and machine types
- Flip to private cluster + Cloud NAT:
  - Add private_cluster_config and NAT resources in main.tf (expect extra cost)
- Switch to full Kubeflow:
  - Replace apps/kubeflow folder with upstream Kubeflow manifests (or add an additional Application in App of Apps)
- Domain + TLS:
  - Add a DNS A record pointing to istio-ingressgateway external IP
  - Add Istio Gateway + VirtualService, and cert-manager for Let’s Encrypt

#### Troubleshooting

- Argo CD app stuck OutOfSync:
  - Check Argo CD UI or: kubectl -n argocd get applications
  - Describe the app: kubectl -n argocd describe application root-app
- No external IP:
  - Ensure the Service type is LoadBalancer
  - Check GCP quotas for external addresses
- Pods pending:
  - Node autoscaler may be scaling from 0; give it a few minutes
  - Check cluster autoscaler events:
    - kubectl -n kube-system logs deploy/cluster-autoscaler -c cluster-autoscaler
- KServe model inference not working:
  - Confirm Istio sidecar injected (namespace label istio-injection=enabled)
  - Check KServe InferenceService events:
    - kubectl get inferenceservices -A
    - kubectl describe inferenceservice <name> -n <ns>

#### Security Notes
- This is a personal Playground optimized for convenience:
  - Argo CD server and KFP UI are exposed via LoadBalancer without auth hardening
- For shared or public demos:
  - Lock down access using Istio Gateways + authn/authz or an OAuth2 proxy
  - Restrict master authorized networks
  - Use private cluster and Cloud NAT

#### License
- GNU General Public License v3.0

#### Credits
- Kubernetes on GKE with Terraform
- Istio
- Argo CD
- Kubeflow Pipelines
- KServe

#### Badges (optional)
You can add badges for Terraform, GKE, Argo CD, and GitHub Actions build status once your repo is public.

Need help tailoring for your project or adding full Kubeflow? Open an issue or reach out!