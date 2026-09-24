#!/usr/bin/env bash

# para o bootstrap se algum comando falhar
set -euo pipefail

# usa o kubectl instalado junto com o k3s
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
export PATH="/snap/bin:${PATH}"

# o ssh pode abrir antes do k3s terminar de iniciar
until kubectl get nodes >/dev/null 2>&1; do
  sleep 5
done

# instala o argocd dentro do cluster
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.2/manifests/install.yaml

# espera os componentes do argocd ficarem disponiveis
kubectl wait --for=condition=Available deployment --all -n argocd --timeout=10m

kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=10m

# instala o cert-manager que emite e renova os certificados https
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.21.2/cert-manager.yaml
kubectl wait --for=condition=Available deployment --all -n cert-manager --timeout=10m

# instala o helm usado pelo operador do infisical
if ! command -v helm >/dev/null 2>&1; then
  snap install helm --classic
fi

helm repo add infisical-helm-charts https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/ --force-update

helm repo update

# instala o infisical para o k8s
helm upgrade --install infisical-operator infisical-helm-charts/secrets-operator --version 0.10.11 -n infisical-operator-system --create-namespace --wait --timeout 10m

# namespace recebe a api e suas credenciais
kubectl create namespace acta-prod --dry-run=client -o yaml | kubectl apply -f -