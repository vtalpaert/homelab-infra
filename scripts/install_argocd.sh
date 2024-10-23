#!/bin/bash

# Set variables
DISPLAY_ARGOCD_PASSWORD=false
SSH_URL=$(git config --get remote.origin.url)

while getopts ":pu:" option; do
    case $option in
    p) # Display ArgoCD password
        DISPLAY_ARGOCD_PASSWORD=true ;;
    u) # Git SSH url
        SSH_URL=$OPTARG ;;
    \?) # Invalid option
        echo "Error: Invalid option"
        exit
        ;;
    esac
done

# Create ArgoCD namespace
microk8s kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
 name: argocd
spec: {}
status: {}
EOF

microk8s kubectl describe ns

# Create ArgoCD defaults
microk8s kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

ARGOCD_PASSWORD=$(microk8s kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 --decode; echo)
# Display ArgoCD initial password
if [ $DISPLAY_ARGOCD_PASSWORD = "true" ] ; then
    echo Your ArgoCD password is: $ARGOCD_PASSWORD
fi

microk8s kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: local-access-argocd
  namespace: argocd
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: argocd-server
  ports:
    - port: 8080
      nodePort: 30000
EOF

# Install argocd CLI
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

argocd login localhost:30000 --insecure --name argocd --username admin --password $ARGOCD_PASSWORD
argocd repo add $SSH_URL --ssh-private-key-path ~/.ssh/id_ed25519

argocd app create base --repo $SSH_URL --path manifests/base --allow-empty --auto-prune --self-heal --sync-policy auto --dest-server https://kubernetes.default.svc --dest-namespace default
