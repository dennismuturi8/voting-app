# 🗳️ Kubernetes Voting App — Docker Cats vs Dogs

A cloud-native distributed voting application deployed on a **kubeadm Kubernetes cluster** on AWS, using **ArgoCD** for GitOps, **NGINX Ingress** on a private subnet, and an **AWS ALB** on a public subnet as the entry point.

---

## 📐 Architecture Overview

```
Internet
    │
    ▼
[AWS ALB - Public Subnet]
    │  forwards to NodePort 31000
    ▼
[NGINX Ingress Controller - Private Subnet]
    │  routes by Host header
    ├──► vote service (ClusterIP:80)
    └──► result service (ClusterIP:80)
         │
    [Worker → Redis → PostgreSQL]
```

### Components

| Component | Description |
|---|---|
| **ALB** | AWS Application Load Balancer on public subnet — entry point for all traffic |
| **NGINX Ingress** | In-cluster ingress controller exposed via NodePort on private subnet |
| **Vote App** | Python Flask frontend — cast your vote |
| **Result App** | Node.js frontend — view live results |
| **Worker** | .NET background processor — moves votes from Redis to PostgreSQL |
| **Redis** | In-memory queue for incoming votes |
| **PostgreSQL** | Persistent storage for final vote counts |
| **ArgoCD** | GitOps controller — syncs cluster state from this repository |

---

## 🔐 Accessing the Cluster

The Kubernetes master node sits on a **private subnet** and is not directly reachable from the internet. Access is via a **bastion/jumphost** on the public subnet.

### Step 1 — Add your SSH key to the agent

```bash
# Start the SSH agent if not already running
eval $(ssh-agent -s)

# Add your private key
ssh-add /path/to/<your-key.pem>

# Verify it was added
ssh-add -l
```

### Step 2.0 — SSH into the Jumphost with Agent Forwarding

```bash
ssh -A ubuntu@<BASTION_HOST-PUBLIC-IP>
```

> The `-A` flag forwards your SSH agent to the jumphost so you can hop to private instances without copying your key.

### Step 2.1 — SSH from Jumphost to the K8s Master Node

```bash
ssh ubuntu@<CONTROL_PLANE-PRIVATE-IP>
```
### Step 2.2 - This is a quick way to Control Plane using one command 

```bash
ssh -L 8080:localhost:8080 -J ubuntu@<BASTION_HOST-PUBLIC-IP> ubuntu@<CONTROL_PLANE-PRIVATE-IP>
```
> This is fast and I would recommend using this command.

## Step 2.3 - Professional — SOCKS Proxy for Multiple Services

If you want to access multiple services (ArgoCD, Grafana, etc.) without
starting a dozen port-forwards, use a SOCKS proxy.

### I. Start a Dynamic Tunnel

```bash
ssh -D 9090 -J ubuntu@<BASTION_IP> ubuntu@<CONTROL_PLANE_IP>
```

### II. Configure your Browser

Use a browser extension like **FoxyProxy** or change your system proxy
settings to use a **SOCKS5 proxy** at `localhost:9090`.

### III. Access the UI

You can now reach any service directly using its internal **Cluster IP**
or **NodePort** — no additional port-forwards needed.


### Step 3 — Verify Cluster is Healthy

```bash
kubectl get nodes
kubectl get pods -A
```

---

## 🚀 Deploying with ArgoCD

### Retrieve the ArgoCD Admin Password

```bash
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath="{.data.password}" | base64 --decode && echo
```

Login credentials:
```
Username: admin
Password: <output from command above>
```


### Access the ArgoCD UI

ArgoCD runs inside the cluster. Access it via port-forward from the master node:

```bash
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf port-forward svc/argocd-server -n argocd 8080:443
```

Then open your browser at:
```
https://localhost:8080
```

> If accessing remotely via SSH tunnel, run this on your **local machine**:
> ```bash
> ssh -A -L 8080:localhost:8080 ubuntu@<JUMPHOST-PUBLIC-IP> \
>     ssh -L 8080:localhost:8080 ubuntu@<MASTER-NODE-PRIVATE-IP>
> ```
> Then open `https://localhost:8080` in your local browser.


---

## 🌐 Accessing the Applications

### Step 1 — Get the ALB IP via nslookup (Option 1)

ALB DNS names resolve to one or more IPs. Run this to get the IP:

```bash
nslookup <your-alb-dns>.us-east-1.elb.amazonaws.com
```

Example output:
```
Name:    k8s-alb-xxxxxxxxx.us-east-1.elb.amazonaws.com
Address: 54.123.45.67    ← use this IP
```
## Option 2 — Cheap Real Domain (~$1–3/year)

If you want a real domain for your portfolio/project:

| Registrar | Cheap TLDs | Price |
|---|---|---|
| **Namecheap** | `.xyz`, `.online`, `.site` | ~$1–3/year |
| **Cloudflare** | `.com` | ~$10/year (at cost) |
| **AWS Route 53** | `.click`, `.link` | ~$3–5/year |

Then create **CNAME records** in Route 53 or Cloudflare:

```dns
vote.yourdomain.xyz    CNAME → k8s-alb-xxxx.us-east-1.elb.amazonaws.com
result.yourdomain.xyz  CNAME → k8s-alb-xxxx.us-east-1.elb.amazonaws.com
```

> ⚠️ ALB IPs are **not static** — they can change. For production use a real domain with a CNAME record pointing to the ALB DNS name.

### Step 2 — Access the Apps via nip.io

Using the IP from the nslookup output, open your browser:

| App | URL |
|---|---|
| 🐱🐶 **Vote** | `http://vote.<ALB-IP>.nip.io` |
| 📊 **Results** | `http://result.<ALB-IP>.nip.io` |

Example (replace with your actual ALB IP):
```
http://vote.54.123.45.67.nip.io
http://result.54.123.45.67.nip.io
```

> `nip.io` is a free wildcard DNS service that automatically resolves `*.54.123.45.67.nip.io` to `54.123.45.67` — no DNS configuration needed.

---

## 📁 Repository Structure

```
voting-app/
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
│   │   └── redis-service.yaml
│   ├── db/
│   │   ├── db-deployment.yaml
│   │   └── db-service.yaml
│   └── ingress/
│       └── voting-app-ingress.yaml  # Host-based NGINX ingress
├── main.tf                          # AWS infrastructure (ALB, VPC, subnets)
└── README.md
```

---

## ⚙️ Ingress Configuration

Host-based routing is used so each app is served at root `/`, preserving internal asset paths and form submissions:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: voting-app-ingress
  namespace: voting
  annotations:
    kubernetes.io/ingress.class: "nginx"
spec:
  rules:
  - host: vote.<ALB-IP>.nip.io / real domain
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: vote
            port:
              number: 80
  - host: result.<ALB-IP>.nip.io / real domain
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: result
            port:
              number: 80
```

---

## 🛠️ Useful kubectl Commands

```bash
# Check all resources in voting namespace
kubectl get all -n voting

# Check ingress routing
kubectl describe ingress voting-app-ingress -n voting

# Check NGINX ingress controller logs
kubectl logs -n ingress-nginx \
  $(kubectl get pods -n ingress-nginx -o jsonpath='{.items[0].metadata.name}') \
  --tail=50

# Check ArgoCD app sync status
kubectl get applications -n argocd

# Restart a deployment
kubectl rollout restart deployment/vote -n voting
```

---

## 🔗 Key Design Decisions

| Decision | Reason |
|---|---|
| ALB on public subnet | Shields private cluster from direct internet exposure |
| NGINX as NodePort | Simple, no AWS API calls needed — no OIDC/IRSA required |
| App services as ClusterIP | Only ingress needs to be reachable externally |
| Host-based routing | Path-based routing breaks the vote app's internal form POST and static asset loading |
| nip.io for DNS | Zero-config wildcard DNS for testing without a registered domain |
| ArgoCD for GitOps | Declarative, auditable deployments synced from git |