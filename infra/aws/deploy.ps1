# faz o script parar se algum comando falhar
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# confirma a conta da aws e prepara o terraform
aws sts get-caller-identity
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Set-Location .\infra\aws

terraform init
terraform validate
terraform plan -out acta.tfplan
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$confirmation = Read-Host "Digite APLICAR para criar os recursos na AWS"

if ($confirmation -cne "APLICAR") {
    Set-Location ..\..
    Write-Host "Implantacao cancelada"
    exit
}

terraform apply acta.tfplan
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$publicIp = (terraform output -raw public_ip).Trim()

Set-Location ..\..

# espera a ec2 liberar o acesso ssh
while (-not (Test-NetConnection $publicIp -Port 22 -InformationLevel Quiet)) {
    Start-Sleep -Seconds 10
}

# instala o argocd e o infisical dentro da ec2
Get-Content .\infra\aws\bootstrap-k3s.sh -Raw |
    ssh -i .\.aws\labsuser.pem -o StrictHostKeyChecking=accept-new "ubuntu@$publicIp" "tr -d '\r' | sudo bash -s"

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# baixa o kubeconfig do k3s
$kubeconfigPath = "$env:USERPROFILE\.kube\acta-aws.yaml"

New-Item "$env:USERPROFILE\.kube" -ItemType Directory -Force | Out-Null

$kubeconfig = ssh -i .\.aws\labsuser.pem "ubuntu@$publicIp" "sudo cat /etc/rancher/k3s/k3s.yaml"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$kubeconfig | Set-Content $kubeconfigPath -Encoding utf8

(Get-Content $kubeconfigPath -Raw).Replace(
    "https://127.0.0.1:6443",
    "https://${publicIp}:6443"
) | Set-Content $kubeconfigPath -Encoding utf8

$env:KUBECONFIG = $kubeconfigPath
kubectl get nodes

# cria a credencial usada pelo infisical
$clientId = Read-Host "Client ID do Infisical"
$clientSecret = Read-Host "Client Secret do Infisical" -AsSecureString
$clientSecret = [Net.NetworkCredential]::new("", $clientSecret).Password

kubectl create secret generic infisical-universal-auth `
    -n acta-prod `
    --from-literal="clientId=$clientId" `
    --from-literal="clientSecret=$clientSecret"

$clientSecret = $null

# entrega a aplicacao para o argocd
kubectl apply -f .\argocd\prod.yaml

Write-Host "Aguardando o Argo CD e o Infisical..."
Start-Sleep -Seconds 90

kubectl rollout status deployment/acta-pg-api -n acta-prod --timeout=15m
kubectl get applications -n argocd
kubectl get pods -n acta-prod

Write-Host "Implantação concluída"
Write-Host "Para abrir o Argo CD:"
Write-Host "kubectl port-forward svc/argocd-server -n argocd 9000:443"
