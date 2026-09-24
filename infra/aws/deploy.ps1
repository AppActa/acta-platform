# para o script se algum comando falhar
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# confirma a conta da AWS antes de criar os recursos
aws sts get-caller-identity

# prepara o terraform e mostra o que será criado
Push-Location .\infra\aws
try {
    terraform init
    terraform validate
    terraform plan

    if ((Read-Host "Digite APLICAR para criar os recursos na AWS") -cne "APLICAR") {
        Write-Host "Implantacao cancelada"
        exit
    }

    terraform apply -auto-approve
    $publicIp = (terraform output -raw public_ip).Trim()
}
finally {
    Pop-Location
}

# espera a ec2 liberar o acesso ssh
$sshDeadline = (Get-Date).AddMinutes(10)
do {
    if (Test-NetConnection $publicIp -Port 22 -InformationLevel Quiet) { break }
    if ((Get-Date) -ge $sshDeadline) { throw "SSH nao ficou disponivel em 10 minutos" }
    Start-Sleep -Seconds 5
} while ($true)

# instala k3s, argocd, cert-manager e infisical
Get-Content .\infra\aws\bootstrap-k3s.sh -Raw |
    ssh -i .\.aws\labsuser.pem -o StrictHostKeyChecking=accept-new "ubuntu@$publicIp" "sudo bash -s"

# baixa o kubeconfig para controlar o cluster pelo computador
$kubeconfigPath = Join-Path $env:USERPROFILE ".kube\acta-aws.yaml"
New-Item (Split-Path $kubeconfigPath) -ItemType Directory -Force | Out-Null

$kubeconfig = ssh -i .\.aws\labsuser.pem "ubuntu@$publicIp" "sudo cat /etc/rancher/k3s/k3s.yaml"
$kubeconfig.Replace("https://127.0.0.1:6443", "https://${publicIp}:6443") |
    Set-Content $kubeconfigPath -Encoding utf8

$env:KUBECONFIG = $kubeconfigPath
kubectl wait --for=condition=Ready node --all --timeout=10m

# recebe as credenciais do Infisical sem salvar em arquivo
$clientId = Read-Host "Client ID do Infisical"
$secureClientSecret = Read-Host "Client Secret do Infisical" -AsSecureString
$credential = [Net.NetworkCredential]::new("", $secureClientSecret)

$secretManifest = @{
    apiVersion = "v1"
    kind = "Secret"
    metadata = @{
        name = "infisical-universal-auth"
        namespace = "acta-prod"
    }
    type = "Opaque"
    stringData = @{
        clientId = $clientId
        clientSecret = $credential.Password
    }
} | ConvertTo-Json -Depth 5

$secretManifest | kubectl apply -f -
$secretManifest = $null
$credential = $null
$secureClientSecret = $null

# entrega os manifests das aplicações para o Argo CD
kubectl apply -f .\argocd\prod.yaml

# cria os endereços sslip.io usando o Elastic IP
$ipHost = $publicIp.Replace(".", "-")
$hosts = @{
    "pg-api" = "pg-api.$ipHost.sslip.io"
    "mongo-api" = "mongo-api.$ipHost.sslip.io"
    "import-api" = "import-api.$ipHost.sslip.io"
}

# troca os hosts genéricos pelos endereços finais
$patches = foreach ($name in $hosts.Keys) {
    @{
        target = @{ kind = "Ingress"; name = $name }
        patch = @"
- op: replace
  path: /spec/rules/0/host
  value: $($hosts[$name])
- op: replace
  path: /spec/tls/0/hosts/0
  value: $($hosts[$name])
"@
    }
}

$applicationPatch = @{
    spec = @{
        source = @{
            kustomize = @{ patches = @($patches) }
        }
    }
} | ConvertTo-Json -Depth 8 -Compress

kubectl patch application acta-prod -n argocd --type merge --patch $applicationPatch
kubectl wait application/acta-prod -n argocd --for=jsonpath='{.status.sync.status}'=Synced --timeout=5m

# espera as apis, o worker e os certificados ficarem prontos
kubectl rollout status deployment/acta-pg-api -n acta-prod --timeout=15m
kubectl rollout status deployment/acta-mongo-api -n acta-prod --timeout=15m
kubectl rollout status deployment/acta-import-api -n acta-prod --timeout=15m
kubectl rollout status deployment/acta-import-worker -n acta-prod --timeout=15m
kubectl wait certificate --all -n acta-prod --for=condition=Ready --timeout=10m

# chama os endereços públicos para confirmar que estão respondendo
Invoke-WebRequest "https://$($hosts['pg-api'])/api/v1/health" -UseBasicParsing
Invoke-WebRequest "https://$($hosts['mongo-api'])/api/v1/health" -UseBasicParsing
Invoke-WebRequest "https://$($hosts['import-api'])/docs" -UseBasicParsing

# mostra o estado final da implantação
kubectl get applications -n argocd
kubectl get pods,secrets,ingress,certificate -n acta-prod

Write-Host "Implantacao concluida"
terraform -chdir=infra/aws output api_urls