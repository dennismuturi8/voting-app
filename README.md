# 🗳️ Kubernetes Voting App — Docker Cats vs Dogs

A cloud-native distributed voting application deployed on a **kubeadm Kubernetes cluster** on AWS, using **ArgoCD** for GitOps continuous delivery, **NGINX Ingress** on a private subnet, and an **AWS ALB** on a public subnet as the entry point. The entire infrastructure is provisioned and configured automatically using **Terraform**, **Ansible**, and a single `manage.sh` script.

---

## 📐 Architecture Overview

```
Internet
    │
    ▼
[AWS ALB - Public Subnet]           ← AWS-managed load balancer
    │  forwards to NodePort 31000
    ▼
[NGINX Ingress Controller]          ← runs on private k8s nodes
    │  routes by Host header (host-based routing)
    ├──► vote service (ClusterIP:80)
    └──► result service (ClusterIP:80)
              │
    ┌─────────┴──────────┐
    │                    │
[Worker App]          [Redis]        ← vote processor + queue
    │
[PostgreSQL]                         ← persistent vote storage
```

### Components

| Component | Description |
|---|---|
| **AWS ALB** | Application Load Balancer on the public subnet — the only internet-facing resource |
| **NGINX Ingress** | In-cluster ingress controller exposed via NodePort `31000` on private subnet nodes |
| **Vote App** | Python Flask frontend — where users cast their vote (Cats vs Dogs) |
| **Result App** | Node.js frontend — displays live vote results |
| **Worker** | .NET background processor — moves votes from Redis queue to PostgreSQL |
| **Redis** | In-memory queue that temporarily holds incoming votes |
| **PostgreSQL** | Persistent database for final vote tallies |
| **ArgoCD** | GitOps controller — automatically syncs the cluster state from this GitHub repository |
| **Prometheus** | Metrics collection for the entire cluster |
| **Grafana** | Visualisation dashboards for cluster and app metrics |
| **Alertmanager** | Handles alerts fired by Prometheus rules |

### Why This Architecture?

| Decision | Reason |
|---|---|
| ALB on public subnet | Only the ALB is internet-facing — the cluster and all apps are fully private |
| NGINX as NodePort | Simple TCP forwarding — no AWS API calls needed, no OIDC/IRSA required |
| App services as ClusterIP | Only NGINX needs to be reachable externally; all app services stay internal |
| Host-based routing | Path-based routing breaks the vote app's internal form POST and static asset loading |
| nip.io for DNS | Zero-config wildcard DNS for testing without needing a registered domain |
| ArgoCD for GitOps | Declarative, auditable deployments — push to git, cluster self-updates |
| Prometheus on worker nodes | Keeps monitoring workloads off the control plane which has a NoSchedule taint |

---

## 📁 Repository Structure

```
voting-app/
├── manage.sh                        # ← entrypoint: run this for everything
├── Terraform/
│   └── main.tf                      # AWS infrastructure + cluster bootstrap
├── Ansible/
│   └── plybk.yaml                   # cluster configuration playbook
├── argocd/
│   └── argocd-app.yaml              # registers all apps with ArgoCD (single file)
├── k8s/
│   ├── vote/
│   │   ├── vote-deployment.yaml
│   │   └── vote-service.yaml        # ClusterIP:80
│   ├── result/
│   │   ├── result-deployment.yaml
│   │   └── result-service.yaml      # ClusterIP:80
│   ├── worker/
│   │   └── worker-deployment.yaml
│   ├── redis/
│   │   ├── redis-deployment.yaml
│   │   └── redis-service.yaml       # ClusterIP:6379
│   ├── db/
│   │   ├── db-deployment.yaml
│   │   └── db-service.yaml          # ClusterIP:5432
│   └── ingress/
│       └── voting-app-ingress.yaml  # host-based NGINX ingress rules
└── README.md
```

---

## 🧰 Prerequisites

Before you begin, make sure you have the following installed on your **local machine**:

| Tool | What it does | Install |
|---|---|---|
| `terraform` | Provisions AWS infrastructure | https://developer.hashicorp.com/terraform/install |
| `ansible` | Configures the cluster remotely | `pip install ansible` |
| `jq` | Parses Terraform JSON outputs | `sudo apt install jq` / `brew install jq` |
| `nslookup` | Resolves ALB DNS to IP | included in most systems |
| AWS CLI | Authenticates with AWS | https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html |

You also need:
- An **AWS account** with permissions to create VPCs, EC2 instances, ALBs, and security groups
- An **SSH key pair** in AWS EC2 (the `.pem` file downloaded to your machine)
- A kubeadm-provisioned cluster already running (Terraform handles this)

---

## 🚀 Deploying Everything — One Command

The entire setup — infrastructure provisioning, cluster configuration, monitoring, and app deployment — is handled by a single script:

```bash
# 1. Clone this repository
git clone https://github.com/dennismuturi8/voting-app.git
cd voting-app

# 2. Make the script executable
chmod +x manage.sh

# 3. Run the full deployment
./manage.sh up
```

### What `./manage.sh up` Does Automatically

It runs the following steps in order:

```
[1/4] Terraform      → provisions VPC, subnets, bastion, k8s nodes, ALB, security groups
                        + bootstraps cluster (installs ArgoCD + NGINX via null_resource)
[2/4] Extract IPs    → reads bastion IP, control plane IP, worker IPs, SSH key from Terraform
[3/4] Ansible prep   → starts SSH agent, adds your key, generates inventory.ini automatically
[4/4] Ansible        → configures cluster, installs Helm + Prometheus stack, applies ArgoCD apps
```

At the end it automatically prints your **ArgoCD password**, **Grafana password**, and **app URLs**.

---

## 🛠️ manage.sh — All Commands

```bash
./manage.sh up        # Provision infra + configure cluster + deploy apps (full setup)
./manage.sh down      # Destroy all AWS infrastructure + delete inventory.ini
./manage.sh ansible   # Re-run Ansible only — useful after config changes (no Terraform)
./manage.sh status    # Show ArgoCD app sync and health status
./manage.sh password  # Print ArgoCD and Grafana admin passwords
./manage.sh urls      # nslookup the ALB and print all app URLs
./manage.sh ssh       # Open an SSH session to the control plane via bastion
./manage.sh proxy     # Start a SOCKS5 proxy on localhost:9090 for browser-based UI access
```

### Tearing Everything Down

```bash
./manage.sh down
```

This runs `terraform destroy` to delete all AWS resources and removes the generated `Ansible/inventory.ini`. You will be asked to confirm before anything is deleted.

---

## 🔐 Accessing the Cluster Manually

The Kubernetes control plane sits on a **private subnet** — it has no public IP. You access it by hopping through the **bastion host** (jumphost) which is on the public subnet.

### Step 1 — Add Your SSH Key to the Agent

```bash
# Start the SSH agent
eval $(ssh-agent -s)

# Add your private key (replace with your actual key path)
ssh-add /path/to/your-key.pem

# Verify the key was loaded
ssh-add -l
```

> 💡 You only need to do this once per terminal session. The `manage.sh` script handles this automatically whenever you run any command.

### Step 2 — Choose Your Access Method

**Option A — Two-hop (step by step)**

```bash
# First: SSH into the bastion with agent forwarding (-A forwards your key)
ssh -A ubuntu@<BASTION-PUBLIC-IP>

# Then from inside the bastion, SSH into the control plane
ssh ubuntu@<CONTROL-PLANE-PRIVATE-IP>
```

**Option B — Single command with port-forward (recommended for UI access)**

```bash
# SSH directly to the control plane via bastion and tunnel port 8080 for ArgoCD
ssh -L 8080:localhost:8080 -J ubuntu@<BASTION-PUBLIC-IP> ubuntu@<CONTROL-PLANE-PRIVATE-IP>
```

Then open `https://localhost:8080` in your browser to access ArgoCD.

**Option C — One command via manage.sh (easiest)**

```bash
./manage.sh ssh
```

This automatically reads all IPs from Terraform outputs, sets up the SSH agent, and drops you directly into the control plane.

### Step 3 — Verify the Cluster is Healthy

Once on the control plane, run:

```bash
kubectl get nodes          # all nodes should show Ready
kubectl get pods -A        # all system pods should be Running or Completed
```

---

## 📊 Monitoring — Prometheus, Grafana & Alertmanager

The `kube-prometheus-stack` Helm chart is installed automatically by Ansible during `./manage.sh up`. It deploys Prometheus, Grafana, and Alertmanager **on worker nodes only** (not the control plane — which has a `NoSchedule` taint by default in kubeadm).

> You do **not** need to create any service YAML files for monitoring. The Helm chart automatically creates all services, deployments, and configs.

### Retrieve the Grafana Password

```bash
# Via manage.sh (easiest — run from your local machine)
./manage.sh password

# Or manually on the control plane
kubectl get secret prometheus-grafana \
  -n monitoring \
  -o jsonpath="{.data.admin-password}" | base64 --decode && echo
```

Login credentials:
```
Username : admin
Password : <output from command above>
```

### Access Monitoring UIs

**Via port-forward (one service at a time) — run on control plane:**

```bash
# Grafana — dashboards and visualisations
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80
# Open in browser: http://localhost:3000

# Prometheus — raw metrics and PromQL queries
kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n monitoring 9091:9090
# Open in browser: http://localhost:9091

# Alertmanager — alert routing and silencing
kubectl port-forward svc/prometheus-kube-prometheus-alertmanager -n monitoring 9093:9093
# Open in browser: http://localhost:9093
```

**Via SOCKS proxy (access all UIs at once — recommended):**

```bash
./manage.sh proxy
```

Then configure your browser (see SOCKS Proxy section below) and open:

```
Grafana      : http://prometheus-grafana.monitoring.svc.cluster.local
Prometheus   : http://prometheus-kube-prometheus-prometheus.monitoring:9090
Alertmanager : http://prometheus-kube-prometheus-alertmanager.monitoring:9093
```

---

## 🚀 Deploying with ArgoCD

ArgoCD is the GitOps engine. It watches this GitHub repository and automatically deploys any changes you push — no manual `kubectl apply` needed after the initial setup.

### Retrieve the ArgoCD Admin Password

```bash
# Via manage.sh (easiest — run from your local machine)
./manage.sh password

# Or manually on the control plane
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath="{.data.password}" | base64 --decode && echo
```

Login credentials:
```
Username : admin
Password : <output from command above>
```

### Access the ArgoCD UI

**Via port-forward — run on the control plane:**

```bash
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf \
  port-forward svc/argocd-server -n argocd 8080:443

# Open in browser: https://localhost:8080
```

**Via SSH tunnel from your local machine:**

```bash
ssh -A -L 8080:localhost:8080 ubuntu@<BASTION-PUBLIC-IP> \
    ssh -L 8080:localhost:8080 ubuntu@<CONTROL-PLANE-PRIVATE-IP>

# Then open: https://localhost:8080
```

**Via SOCKS proxy (recommended — access everything at once):**

```bash
./manage.sh proxy
# Then open: https://argocd-server.argocd.svc.cluster.local
```

### How ArgoCD Deploys the Apps

All six apps are registered with ArgoCD via a single manifest file applied from GitHub:

```bash
kubectl apply -f \
  https://raw.githubusercontent.com/dennismuturi8/voting-app/main/argocd/argocd-app.yaml
```

This is applied automatically by Ansible during `./manage.sh up`. Each app in the file points ArgoCD to a specific folder in this repository:

| ArgoCD App | Git Path | Namespace | What it deploys |
|---|---|---|---|
| `vote-app` | `k8s/vote/` | `voting` | Vote frontend + service |
| `result-app` | `k8s/result/` | `voting` | Result frontend + service |
| `worker-app` | `k8s/worker/` | `voting` | Background vote processor |
| `redis-app` | `k8s/redis/` | `voting` | Redis queue + service |
| `db-app` | `k8s/db/` | `voting` | PostgreSQL + service |
| `ingress-voting-app` | `k8s/ingress/` | `voting` | NGINX ingress routing rules |

**Auto-sync is enabled** with `prune: true` and `selfHeal: true` — whenever you push a change to any of these folders, ArgoCD detects it within minutes and automatically applies the update to the cluster.

### Check App Sync Status

```bash
# Via manage.sh
./manage.sh status

# Or manually on the control plane
kubectl get applications -n argocd \
  -o custom-columns='APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'
```

---

## 🌐 Accessing the Applications

### Step 1 — Get the ALB IP

```bash
# Via manage.sh (easiest)
./manage.sh urls

# Or manually via nslookup
nslookup <your-alb-dns>.us-east-1.elb.amazonaws.com
```

Example nslookup output:
```
Name:    k8s-alb-1484168575.us-east-1.elb.amazonaws.com
Address: 54.123.45.67    ← copy this IP
```

> ⚠️ ALB IPs are **not static** — AWS can reassign them at any time. For a permanent URL, use Option B below with a CNAME record pointing to the ALB **DNS name** (not the IP).

### Option A — nip.io (Free, No Domain Needed)

`nip.io` is a free wildcard DNS service. Any domain in the format `*.YOUR-IP.nip.io` automatically resolves to `YOUR-IP` — no sign-up or configuration needed.

| App | URL |
|---|---|
| 🐱🐶 **Vote** | `http://vote.<ALB-IP>.nip.io` |
| 📊 **Results** | `http://result.<ALB-IP>.nip.io` |

Example using the IP above:
```
http://vote.54.123.45.67.nip.io
http://result.54.123.45.67.nip.io
```

### Option B — Real Domain (~$1–3/year)

For a permanent, professional URL you can share in your portfolio:

| Registrar | Cheap TLDs | Price |
|---|---|---|
| **Namecheap** | `.xyz`, `.online`, `.site` | ~$1–3/year |
| **Cloudflare** | `.com` | ~$10/year (at cost) |
| **AWS Route 53** | `.click`, `.link` | ~$3–5/year |

After buying a domain, create **CNAME records** pointing to your ALB DNS name (not the IP):

```dns
vote.yourdomain.xyz    CNAME → k8s-alb-xxxx.us-east-1.elb.amazonaws.com
result.yourdomain.xyz  CNAME → k8s-alb-xxxx.us-east-1.elb.amazonaws.com
```

Then update the `host:` fields in `k8s/ingress/voting-app-ingress.yaml` to match your new domain and push to git — ArgoCD will apply the change automatically.

---

## 🧦 SOCKS Proxy — Access All UIs at Once

Instead of running a separate `port-forward` for every service, a SOCKS proxy lets your browser reach **any ClusterIP or service DNS** inside the cluster directly — ArgoCD, Grafana, Prometheus and Alertmanager all at the same time.

### Step 1 — Start the Proxy

```bash
# Via manage.sh (recommended)
./manage.sh proxy

# Or manually
ssh -D 9090 -N -J ubuntu@<BASTION-PUBLIC-IP> ubuntu@<CONTROL-PLANE-PRIVATE-IP>
```

Leave this terminal open. Press `Ctrl+C` to stop the proxy when done.

### Step 2 — Configure Your Browser

**Using FoxyProxy (Chrome/Firefox extension — recommended):**
1. Install [FoxyProxy Standard](https://getfoxyproxy.org/)
2. Click the extension → Options → Add Proxy
3. Set: Type `SOCKS5`, Host `127.0.0.1`, Port `9090`
4. Enable it

**Using system proxy settings (Ubuntu/Linux):**

Go to Settings → Network → Network Proxy → Manual:
```
SOCKS Host : 127.0.0.1
Port       : 9090
```

### Step 3 — Open Any Service in Your Browser

With the proxy active, paste any of these directly into your browser:

```
ArgoCD       : https://argocd-server.argocd.svc.cluster.local
Grafana      : http://prometheus-grafana.monitoring.svc.cluster.local
Prometheus   : http://prometheus-kube-prometheus-prometheus.monitoring:9090
Alertmanager : http://prometheus-kube-prometheus-alertmanager.monitoring:9093
```

---

## ⚙️ Ingress Configuration

Host-based routing is used so each app is served at its own root `/`. This is important because the Docker voting app hardcodes its HTML form action to `/` — path-based routing (`/vote`, `/result`) would break form submissions and static assets (CSS, JS).

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: voting-app-ingress
  namespace: voting
  annotations:
    kubernetes.io/ingress.class: "nginx"
    # No rewrite-target annotation needed with host-based routing
spec:
  rules:
  - host: vote.<ALB-IP>.nip.io        # or your real domain e.g. vote.yourdomain.xyz
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: vote                 # must exactly match metadata.name in vote-service.yaml
            port:
              number: 80
  - host: result.<ALB-IP>.nip.io      # or your real domain e.g. result.yourdomain.xyz
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: result               # must exactly match metadata.name in result-service.yaml
            port:
              number: 80
```

> ⚠️ The service `name:` in the ingress **must exactly match** the `metadata.name` in your service YAML files. A mismatch causes a `503 Service Temporarily Unavailable` error from NGINX.

---

## 🛠️ Useful kubectl Commands

Run these on the control plane after SSHing in with `./manage.sh ssh`:

```bash
# ── Cluster health ──────────────────────────────────────────────────────────
kubectl get nodes                              # all nodes should be Ready
kubectl get pods -A                            # all pods across every namespace

# ── Voting app ──────────────────────────────────────────────────────────────
kubectl get all -n voting                      # all resources in voting namespace
kubectl get svc -n voting                      # confirm service names and types
kubectl describe ingress voting-app-ingress -n voting   # check ingress routing + endpoints
kubectl logs -n ingress-nginx \
  $(kubectl get pods -n ingress-nginx \
    -o jsonpath='{.items[0].metadata.name}') --tail=50  # NGINX controller logs

# ── ArgoCD ──────────────────────────────────────────────────────────────────
kubectl get applications -n argocd             # sync and health status of all apps
kubectl describe application vote-app -n argocd             # details for one app

# ── Monitoring ──────────────────────────────────────────────────────────────
kubectl get pods -n monitoring                 # confirm all monitoring pods are Running
kubectl get pods -n monitoring -o wide         # shows which node each pod landed on

# ── Restart a deployment ────────────────────────────────────────────────────
kubectl rollout restart deployment/vote -n voting
kubectl rollout restart deployment/result -n voting
```

---

## 🔎 Troubleshooting

### 503 Service Temporarily Unavailable
NGINX reached the ingress rule but could not find the backend service. Check:
```bash
kubectl get svc -n voting
kubectl describe ingress voting-app-ingress -n voting   # look at the Endpoints field
```
The `name:` in the ingress backend must **exactly match** the service `metadata.name`.

### App Loads but Looks Unstyled (No Colours, No Layout)
Static assets (`/static/css/`, `/static/js/`) are 404ing. This happens when using **path-based routing** (`/vote`) with a rewrite, which breaks asset paths. The fix is host-based routing — make sure your ingress uses `host: vote.<IP>.nip.io` with `path: /` and no `rewrite-target` annotation.

### Vote Form Does Nothing / 404 After Clicking Cats or Dogs
The vote form POSTs to `/` internally. If you use path-based routing, the POST goes to the root of the ALB DNS with no matching rule. Switch to host-based routing — the ingress in this repo is already configured correctly.

### ArgoCD Shows OutOfSync or Sync Failed
Click the app tile in the ArgoCD UI → look for the red error banner. Common causes:
- Service name mismatch between ingress and service YAML files
- Namespace does not exist (add `CreateNamespace=true` to `syncOptions`)
- Invalid regex path used with `pathType: Prefix` — use `ImplementationSpecific` for regex

### Monitoring Pods Stuck in Pending
The control plane has a `NoSchedule` taint by default in kubeadm. Prometheus components are pinned to worker nodes using `nodeSelector: role=worker`. Check that worker nodes are labelled:
```bash
kubectl get nodes --show-labels    # workers should have role=worker
```
If the label is missing, Ansible re-applies it on every run of `./manage.sh ansible`.

### Can't SSH to Control Plane
Make sure your SSH agent has the key loaded before running any manage.sh command:
```bash
ssh-add -l                         # should list your key fingerprint
ssh-add /path/to/your-key.pem      # add it if the list is empty
```