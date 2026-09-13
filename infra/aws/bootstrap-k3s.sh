#!/usr/bin/env bash

# para o bootstrap se algum comando falhar
set -e

# usa o kubectl instalado junto com o k3s
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
export PATH="/snap/bin:${PATH}"

# o ssh pode abrir antes do k3s terminar de iniciar
until kubectl get nodes >/dev/null 2>&1; do
  sleep 5
done

# instala o argocd dentro do cluster
kubectl create namespace argocd

kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.2/manifests/install.yaml

# espera os componentes do argocd ficarem disponiveis
kubectl wait --for=condition=Available deployment --all -n argocd --timeout=10m

kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=10m

# instala o helm usado pelo operador do infisical
snap install helm --classic

helm repo add infisical-helm-charts https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/ --force-update

helm repo update

# instala o infisical para o k8s
helm install infisical-operator infisical-helm-charts/secrets-operator --version 0.10.11 -n infisical-operator-system --create-namespace  --wait --timeout 10m

# namespace recebe a api e suas credenciais
kubectl create namespace acta-prod