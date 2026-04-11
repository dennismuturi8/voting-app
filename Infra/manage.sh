#!/bin/bash
set -e

TF_DIR="./Terraform"
ANSIBLE_DIR="./Ansible"

usage() {
    echo "Usage: $0 {up|down|ansible}"
    echo "  up      - Provision infrastructure and run Ansible"
    echo "  down    - Destroy all infrastructure"
    echo "  ansible - Re-run Ansible only"
    exit 1
}

[[ -z "$1" ]] && usage

case "$1" in
    up)
        echo "=== Starting Deployment ==="

        # ---------------------------------
        # 1. Terraform Apply
        # ---------------------------------
        echo "[1/5] Running Terraform..."
        cd "$TF_DIR"
        terraform init -input=false
        terraform apply -auto-approve

        echo "[2/5] Extracting Outputs..."
        BASTION_IP=$(terraform output -raw bastion_ip)
        CONTROL_PLANE=$(terraform output -raw control_plane_ip)
        WORKERS=$(terraform output -json worker_ips | jq -r '.[]')
        USER=$(terraform output -raw ssh_user)
        KEY=$(terraform output -raw ssh_key_path)

        cd ..

        # ---------------------------------
        # 2. Start SSH Agent
        # ---------------------------------
        echo "[3/5] Starting SSH Agent..."
        eval "$(ssh-agent -s)"
        ssh-add "$KEY"

        # ---------------------------------
        # 3. Generate Inventory
        # ---------------------------------
        echo "[4/5] Preparing inventory..."
        cd "$ANSIBLE_DIR"

        cat > inventory.ini <<EOF
[control_plane]
$CONTROL_PLANE ansible_user=$USER

[workers]
$(for ip in $WORKERS; do echo "$ip"; done)

[all:vars]
ansible_user=$USER
ansible_python_interpreter=/usr/bin/python3
EOF

        cd ..

        # ---------------------------------
        # 4. Copy Ansible Directory to Bastion
        # ---------------------------------
        echo "[5/5] Copying Ansible to Bastion..."
        scp -r -o StrictHostKeyChecking=no "$ANSIBLE_DIR" "$USER@$BASTION_IP:/home/$USER/"

        echo "Running Ansible from Bastion..."

        echo "Running Ansible via Bastion → Control Plane..."

        ssh -A -o StrictHostKeyChecking=no "$USER@$BASTION_IP" <<EOF

           echo "Inside Bastion Host"

          # Go to Ansible directory
           cd Ansible

           echo "Testing Control Plane Connectivity..."

         # Explicit SSH to Control Plane
          ssh -o StrictHostKeyChecking=no $USER@$CONTROL_PLANE <<INNER_EOF

          echo "Inside Control Plane Node"

         # Run your playbook tasks or bootstrap commands
          ansible-playbook -i inventory.ini plybk.yaml

          INNER_EOF

EOF

        echo "=== Deployment Complete ==="
        ;;

    down)
        echo "=== Destroying Infrastructure ==="
        cd "$TF_DIR"
        terraform destroy -auto-approve
        echo "=== Destroy Complete ==="
        ;;

    ansible)
        echo "=== Re-running Ansible Only ==="

        cd "$TF_DIR"
        BASTION_IP=$(terraform output -raw bastion_ip)
        USER=$(terraform output -raw ssh_user)
        KEY=$(terraform output -raw ssh_key_path)
        cd ..

        eval "$(ssh-agent -s)"
        ssh-add "$KEY"

        scp -r "$ANSIBLE_DIR" "$USER@$BASTION_IP:/home/$USER/"

        ssh -A "$USER@$BASTION_IP" <<EOF
            cd Ansible
            ansible-playbook -i inventory.ini plybk.yaml
EOF

        echo "=== Ansible Complete ==="
        ;;

    *)
        usage
        ;;
esac