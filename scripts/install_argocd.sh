#!/bin/bash

# Set variables
DISPLAY_ARGOCD_PASSWORD=false
SSH_URL=$(git config --get remote.origin.url)

while getopts ":puasc:" option; do
    case $option in
    p) # Display ArgoCD password
        DISPLAY_ARGOCD_PASSWORD=true ;;
    u) # Git SSH url
        SSH_URL=$OPTARG ;;
    a) # OVH API credentials
        APPLICATION_KEY=$OPTARG ;;
    s) # OVH API credentials
        APPLICATION_SECRET=$OPTARG ;;
    c) # OVH API credentials
        CONSUMER_KEY=$OPTARG ;;
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

# Add a NodePort service to access ArgoCd on my-ip:30000
# Anyone that can view this IP can access the port !!
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

# Create secrets for OVH API key
# https://aureq.github.io/cert-manager-webhook-ovh/
if [ "$APPLICATION_KEY" = "" ] || [ "$APPLICATION_SECRET" = "" ] || [ "$CONSUMER_KEY" = "" ] ; then
    echo Create an API key at https://api.ovh.com/console/
    echo Enter ApplicationKey
    read APPLICATION_KEY
    echo Enter ApplicationSecret
    read APPLICATION_SECRET
    echo Enter ConsumerKey
    read CONSUMER_KEY
fi
if [ "$APPLICATION_KEY" = "" ] || [ "$APPLICATION_SECRET" = "" ] || [ "$CONSUMER_KEY" = "" ] ; then
    echo Skip ovh-credentials secret
else
    microk8s kubectl create secret generic ovh-credentials --from-literal=applicationKey=$APPLICATION_KEY --from-literal=applicationSecret=$APPLICATION_SECRET --from-literal=consumerKey=$CONSUMER_KEY
fi

# Install argocd CLI
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

# Login to local API server and ignore self signed certificate
argocd login localhost:30000 --insecure --name argocd --username admin --password $ARGOCD_PASSWORD

# Add a repository, by default the one where this script lives
argocd repo add $SSH_URL --ssh-private-key-path ~/.ssh/id_ed25519

# Create the base app
# Will essentially enable SSL certificates
argocd app create base --repo $SSH_URL --path manifests/base --allow-empty --auto-prune --self-heal --sync-policy auto --dest-server https://kubernetes.default.svc --dest-namespace default

# Create VPN app
# TODO

# Remove public and NodePort access to ArgoCD
