resource "null_resource" "cluster_bootstrap" {
  # This ensures the resource only runs AFTER the control plane VM is fully created
  depends_on = [var.control_plane_ip] 

  connection {
    type                = "ssh"
    host                = var.control_plane_ip
    user                = "ubuntu"
    private_key         = file(var.private_key_path)
    bastion_host        = var.bastion_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(var.private_key_path)
    agent               = false
  }

  provisioner "remote-exec" {
    inline = [
      # 1. Wait for System/Apt locks to clear (Common on fresh VMs)
      "echo 'Waiting for cloud-init/apt locks...'",
      "while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 5; done",
      
      # 2. Update Apt (Standard procedure)
      "sudo apt-get update -y",

      # 3. The "Wait for K8s" Loop (Crucial)
      # Terraform connects the moment SSH is up, but the API server takes longer to start.
      "echo 'Waiting for Kubernetes API to respond...'",
      "timeout 300 bash -c 'until sudo kubectl --kubeconfig /etc/kubernetes/admin.conf cluster-info; do sleep 10; done'",

      # 4. Create Namespace (Idempotent style)
      "echo 'Creating ArgoCD Namespace...'",
      "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf create namespace argocd --dry-run=client -o yaml | sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f -",

      # 5. Apply ArgoCD Manifests
      "echo 'Installing ArgoCD...'",
      "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml",
      
      # 6. Create NGINX Ingress Namespace 
      "echo 'Creating NGINX Ingress Namespace...'",
      "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf create namespace ingress-nginx --dry-run=client -o yaml | sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f -",

      # 7. Install NGINX Ingress Controller
      "echo 'Installing NGINX Ingress Controller...'",
      "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml"
    ]
  }
}

variable "bastion_ip" {
  type = string
}

variable "control_plane_ip" {
  type = string
}

variable "worker_ips" {
  type = list(string)
}

variable "private_key_path" {
  type = string
}



