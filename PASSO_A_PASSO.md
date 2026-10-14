# ☁️ ACTA Platform — guia de implantação

## 📌 Objetivo e escopo

Este guia acompanha o [README](README.md): use o README para conhecer a plataforma e este arquivo para preparar e executar uma implantação do zero. As instruções abaixo refletem os scripts e manifests versionados neste repositório.

O processo cria recursos cobrados na AWS e publica serviços acessíveis pela internet. Uma instância EC2 executa K3s em nó único; não há alta disponibilidade. Para produção crítica, avalie redundância, backups, recuperação, observabilidade e armazenamento remoto do estado Terraform antes de usar este desenho.

## 🧭 Fluxo

1. Preparar ferramentas, credenciais e configurações.
2. Validar o repositório e revisar o plano Terraform.
3. Provisionar a infraestrutura e instalar o cluster.
4. Configurar acesso ao GHCR e autenticação do Infisical.
5. Sincronizar os manifests pelo Argo CD.
6. Verificar workloads, certificados e URLs.

## ✅ Preparar o ambiente

Este procedimento usa **Windows PowerShell**. As ferramentas abaixo atendem a partes diferentes do fluxo; instale o conjunto necessário à tarefa que vai executar. Para provisionar e implantar a plataforma, são necessários todos os itens marcados como implantação.

| Ferramenta | Necessária para | Como confirmar |
| --- | --- | --- |
| AWS CLI | Confirmar a conta AWS antes do Terraform. | `aws --version` |
| Terraform | Validar e criar a VPC, EC2, Security Group e Elastic IP. A CI fixa a versão 1.13.3. | `terraform version` |
| kubectl | Renderizar manifests, configurar o cluster e acompanhar workloads. O Docker Desktop também pode instalá-lo. | `kubectl version --client` |
| OpenSSH Client | Conectar à EC2 e enviar o bootstrap do K3s. | `ssh -V` |
| GitHub CLI | Confirmar acesso ao GHCR e gerar a credencial temporária de pull usada no cluster. | `gh --version` e `gh auth status` |
| yq | Necessária apenas para reproduzir localmente a checagem estrutural da Application Argo CD feita pela CI. | `yq --version` |
| kubeconform | Necessária apenas para validar localmente os schemas dos manifests Kubernetes. | `kubeconform -v` |
| Git | Clonar o repositório e trabalhar com branches e Pull Requests. | `git --version` |

Terraform deve ser versão 1.5 ou superior, conforme `required_version`; para reproduzir a CI, use Terraform 1.13.3. As versões de ferramentas e actions usadas na CI estão em [`.github/workflows/teste-infra.yml`](.github/workflows/teste-infra.yml). Docker não é necessário para implantar imagens que já estão publicadas; ele só é necessário se você for construir imagens localmente.

### Instalar ferramentas no Windows

Abra o PowerShell como seu usuário. O `winget` instala os pacotes disponíveis na fonte configurada no Windows:

```powershell
winget install --id Git.Git --exact
winget install --id Amazon.AWSCLI --exact
winget install --id Hashicorp.Terraform --exact
winget install --id Kubernetes.kubectl --exact
winget install --id GitHub.cli --exact
winget install --id MikeFarah.yq --exact
winget install --id YannHamon.kubeconform --exact
```

O OpenSSH Client pode ser instalado em **Configurações > Sistema > Recursos opcionais > Exibir recursos**. Em seguida, procure **OpenSSH Client** e instale. Se o comando `ssh` já existir, essa etapa está concluída. Feche e abra o PowerShell para atualizar o `PATH`, depois execute os comandos da tabela para confirmar cada instalação.

### Acessos e recursos necessários para implantar

Antes do provisionamento, prepare:

- credenciais AWS com permissão para criar os recursos declarados em `infra/aws/main.tf`;
- um EC2 Key Pair existente na região de destino e sua chave privada local;
- o IPv4 público de quem administrará o cluster, em formato `/32` para restringir SSH e API Kubernetes;
- credenciais Universal Auth do Infisical e os segredos exigidos pelos manifests em `apps/config/`;
- imagens das APIs e do worker atualmente declarados, publicadas nos registros configurados;
- GitHub CLI autenticado com permissão `read:packages` no pacote privado `ghcr.io/appacta/acta-import-api`.

Não inclua tokens, segredos, arquivos de estado ou chave privada nos comandos, no Git ou neste guia. Para validar Terraform e manifests sem criar recursos, não é necessário autenticar na AWS nem configurar os segredos das aplicações.

## 1. Baixar e validar o repositório

Clone o repositório e entre na pasta:

```powershell
git clone https://github.com/AppActa/acta-platform.git
Set-Location acta-platform
```

Confirme as ferramentas necessárias ao fluxo que você executará. Para implantação completa, verifique todas as linhas da tabela acima:

```powershell
aws --version
terraform version
kubectl version --client
ssh -V
gh --version
```

Selecione o perfil AWS nomeado desta execução e confira o alvo antes de criar recursos. Defina `AWS_PROFILE` na sessão para que o script e o provider do Terraform usem a mesma identidade:

```powershell
$AwsProfile = "<perfil-aws>"
$env:AWS_PROFILE = $AwsProfile
aws sts get-caller-identity --profile $AwsProfile
aws configure get region --profile $AwsProfile
gh auth status
```

A conta e região retornadas devem ser as pretendidas. Mantenha o perfil selecionado nessa mesma sessão ao executar `deploy.ps1`. Não prossiga se não puder confirmar o alvo.

Valide o código sem provisionar:

```powershell
terraform -chdir=infra/aws fmt -check
terraform -chdir=infra/aws init -backend=false -input=false
terraform -chdir=infra/aws validate
kubectl kustomize apps
```

Para validar os schemas Kubernetes, instale `kubeconform` e execute:

```powershell
kubectl kustomize apps | kubeconform -strict -summary -skip InfisicalSecret,ClusterIssuer -
```

Para reproduzir a validação estrutural da Application Argo CD, instale `yq` e execute a mesma expressão usada pela CI:

```powershell
yq -e '.apiVersion == "argoproj.io/v1alpha1" and .kind == "Application" and .metadata.namespace == "argocd" and .spec.source.repoURL == "https://github.com/AppActa/acta-platform.git" and .spec.source.targetRevision == "main" and .spec.source.path == "apps" and .spec.destination.server == "https://kubernetes.default.svc" and .spec.destination.namespace == "acta-prod" and .spec.syncPolicy.automated.prune == true and .spec.syncPolicy.automated.selfHeal == true' argocd/prod.yaml
```

Essas verificações são estáticas: não criam recursos e não comprovam conectividade AWS, disponibilidade de serviços ou funcionamento de integrações externas.

## 2. Configurar Terraform

Crie `infra/aws/terraform.tfvars` localmente. Substitua todos os placeholders antes de continuar:

```hcl
aws_region    = "<regiao-aws>"
key_name      = "<nome-do-key-pair>"
admin_cidr    = "<seu-ip-publico>/32"
instance_type = "t3.medium"
```

O Key Pair precisa existir na mesma região. Coloque a chave privada correspondente em `.aws/labsuser.pem`, caminho esperado pelo script de deploy. Restrinja permissões do arquivo à sua conta de usuário. `terraform.tfvars`, estado e chave são arquivos locais ignorados pelo Git.

Confira seu IP público por um meio confiável e use somente esse endereço com sufixo `/32`; não libere SSH ou API Kubernetes para `0.0.0.0/0`.

## 3. Revisar e aplicar a infraestrutura

O script executa `aws sts get-caller-identity`, inicializa e valida Terraform, mostra o plano e pede a confirmação literal `APLICAR`. Antes de iniciar, confirme que a chave privada está em `.aws/labsuser.pem`, pois este caminho está fixo no script. Na raiz do repositório:

```powershell
.\infra\aws\deploy.ps1
```

Leia o plano antes de confirmar. Confira conta, região, quantidade de recursos, ações de substituição ou remoção e custos estimados. O script aplica o Terraform somente após a confirmação.

Para inspecionar o estado e os outputs depois da criação:

```powershell
terraform -chdir=infra/aws output
terraform -chdir=infra/aws output api_urls
```

Guarde o arquivo de estado Terraform em local persistente e seguro. Este repositório usa estado local em `infra/aws/terraform.tfstate`; perder o estado pode impedir atualizações seguras da infraestrutura. Não compartilhe o estado: ele pode conter dados sensíveis. O `.gitignore` exclui o estado e os planos Terraform do Git; ainda assim, confira `git status` antes de publicar alterações.

## 4. Acompanhar bootstrap do cluster

Durante a execução, o script aguarda a porta SSH, executa `infra/aws/bootstrap-k3s.sh` e configura K3s, Argo CD, cert-manager, Helm, Infisical Secrets Operator e o namespace `acta-prod`. Em seguida, salva o kubeconfig em `~/.kube/acta-aws.yaml` e configura `KUBECONFIG` para a sessão atual. O script continua diretamente às etapas de GHCR, Infisical, GitOps e rollout; não o interrompa após o bootstrap.

Se o script terminar antes das etapas posteriores, defina o kubeconfig na sessão e confira o cluster:

```powershell
$env:KUBECONFIG = Join-Path $env:USERPROFILE ".kube\acta-aws.yaml"
kubectl get nodes
kubectl get pods -n argocd
kubectl get pods -n cert-manager
kubectl get pods -n infisical-operator-system
```

O nó precisa estar `Ready`; os componentes precisam estar disponíveis antes de avançar.

## 5. Configurar acesso ao GHCR e Infisical

O script usa GitHub CLI para validar acesso ao pacote privado `ghcr.io/appacta/acta-import-api` e cria o Secret `ghcr-pull` no cluster. Verifique antes:

```powershell
gh auth status
gh api /orgs/AppActa/packages/container/acta-import-api --jq .name
```

A autenticação deve ter permissão de leitura de pacotes. Não copie nem registre o token retornado por `gh auth token`.

O script solicita o Client ID e Client Secret do Infisical. Insira-os somente nos prompts interativos quando solicitados; o campo do segredo é oculto. O valor é enviado ao Kubernetes como Secret `infisical-universal-auth`. Configure previamente no Infisical os segredos exigidos pelos manifests existentes em `apps/config/`, nos caminhos e ambiente referenciados neles. Obtenha cada valor diretamente no projeto Infisical autorizado para o ambiente de destino; use placeholders em exemplos locais e nunca copie os valores para o Git ou para este guia. Para conferir a sincronização, execute `kubectl get infisicalsecret -n acta-prod` e confirme que os Secrets referenciados pelos Deployments foram criados.

### Estado de AI e MCP neste checkout

Os manifests `apps/ai.yaml`, `apps/mcp.yaml`, `apps/config/ai-secrets.yaml` e `apps/config/mcp-secrets.yaml` estão listados em `apps/kustomization.yaml`. Antes de sincronizá-los, confirme que a imagem MCP está publicada no GHCR e que os caminhos e nomes referenciados existem no Infisical. O script de implantação aguarda os seis Deployments e os certificados, verifica `/health` do AI e do MCP e imprime as URLs públicas.

Para preparar essa integração, os caminhos planejados nos manifests são `/ai` e `/mcp`, no ambiente `prod`; confirme que existem no projeto autorizado e que contêm os nomes exigidos pelo código antes de sincronizar os Secrets. Não registre valores reais em arquivos, comandos ou documentação. A chave compartilhada `ACTA_MCP_API_KEY` precisa ser a mesma nos dois serviços, pois o AI a envia como Bearer e o MCP a valida; confirme essa igualdade diretamente no ambiente antes de habilitar a integração.

## 6. Sincronizar aplicações com Argo CD

O script aplica `argocd/prod.yaml`, constrói os hosts com prefixo `acta-` a partir do Elastic IP e os configura na Application `acta-prod`. Para o MCP, ele usa `https://acta-mcp.<ip-com-hifens>.sslip.io/mcp` em `ACTA_MCP_URL`; o sufixo `/mcp` corresponde ao endpoint Streamable HTTP. O AI fica disponível em `https://acta-ai.<ip-com-hifens>.sslip.io`. `/health` é somente a rota de disponibilidade. O Argo CD acompanha a branch `main` e reconcilia os manifests de `apps/`.

Confira o estado:

```powershell
kubectl get application acta-prod -n argocd
kubectl get applications -n argocd
```

A sincronização automatizada usa `prune` e `selfHeal`: recursos removidos do Git podem ser removidos do cluster, e alterações manuais podem ser revertidas.

### Retomar uma instância existente

Use este procedimento quando a EC2 que já hospeda o cluster estiver parada. Ele retoma a instância existente; não recria recursos, altera o estado Terraform, executa bootstrap ou sincroniza o Argo CD.

Confirme a conta, região e o único alvo pelas tags do projeto antes de iniciar:

```powershell
$AwsProfile = $env:AWS_PROFILE
$AwsRegion = aws configure get region --profile $AwsProfile
aws sts get-caller-identity --profile $AwsProfile
aws ec2 describe-instances --profile $AwsProfile --region $AwsRegion `
  --filters "Name=tag:Project,Values=ACTA" "Name=tag:Name,Values=acta-prod-k3s" `
  --query 'Reservations[].Instances[].{Id:InstanceId,State:State.Name,PublicIp:PublicIpAddress,Key:KeyName}' --output table
```

Confira a conta e selecione o ID exato da instância esperada. Se a consulta não retornar exatamente um alvo esperado, pare. Inicie somente quando o estado for `stopped`:

```powershell
$InstanceId = "<id-confirmado>"
aws ec2 start-instances --profile $AwsProfile --region $AwsRegion --instance-ids $InstanceId
aws ec2 wait instance-running --profile $AwsProfile --region $AwsRegion --instance-ids $InstanceId
aws ec2 wait instance-status-ok --profile $AwsProfile --region $AwsRegion --instance-ids $InstanceId
```

Depois, use o IP atual mostrado pela consulta e a chave privada correspondente ao Key Pair confirmado para verificar o cluster por SSH:

```powershell
$PrivateKey = "<caminho-da-chave-privada>"
$PublicIp = "<ip-atual-da-instancia>"
ssh -i $PrivateKey "ubuntu@$PublicIp" "sudo kubectl get nodes"
ssh -i $PrivateKey "ubuntu@$PublicIp" "sudo kubectl get deployments,pods -n acta-prod"
```

Confirme o nó `Ready` e os seis Deployments declarados no Kustomize conforme a seção 7. Se probes, Pods ou eventos indicarem falha, registre o estado e siga o diagnóstico da etapa ativa; não repita bootstrap, aplique Terraform nem force sincronização GitOps como tentativa genérica de recuperação.

## 7. Verificar serviços e certificados

O script aguarda os Deployments e certificados e faz requisições HTTPS às APIs. Se estiver verificando manualmente:

```powershell
kubectl rollout status deployment/acta-pg-api -n acta-prod --timeout=15m
kubectl rollout status deployment/acta-mongo-api -n acta-prod --timeout=15m
kubectl rollout status deployment/acta-import-api -n acta-prod --timeout=15m
kubectl rollout status deployment/acta-import-worker -n acta-prod --timeout=15m
kubectl rollout status deployment/acta-ai -n acta-prod --timeout=15m
kubectl rollout status deployment/acta-mcp -n acta-prod --timeout=15m
kubectl get certificates -n acta-prod
kubectl get pods,services,ingress -n acta-prod
terraform -chdir=infra/aws output api_urls
```

Aguarde os certificados ficarem `Ready` e os seis Deployments declarados concluírem o rollout. Use as URLs reportadas pelos outputs do Terraform para testar as APIs públicas. O script também imprime a URL do MCP; para chamadas de protocolo, use o endereço terminado em `/mcp`, e reserve `/health` para a verificação de disponibilidade:

- PostgreSQL API: `<pg_api>/api/v1/health`
- Mongo API: `<mongo_api>/api/v1/health`
- Import API: `<import_api>/docs`
- AI: `<ai>/health`
- MCP: `<mcp>` (termina em `/mcp`)

Exemplo para verificar uma URL:

```powershell
$urls = terraform -chdir=infra/aws output -json api_urls | ConvertFrom-Json
Invoke-WebRequest "$($urls.pg_api)/api/v1/health"
Invoke-WebRequest "$($urls.mongo_api)/api/v1/health"
Invoke-WebRequest "$($urls.import_api)/docs"
Invoke-WebRequest "$($urls.ai)/health"
Invoke-WebRequest "$($urls.mcp.Replace('/mcp', '/health'))"
```

Uma resposta HTTP de sucesso confirma apenas a disponibilidade do endpoint consultado. Ela não valida o fluxo completo de importação. Faça um teste funcional controlado apenas com dados e arquivos autorizados, avaliando os efeitos no banco e no armazenamento de arquivos.

## 🩺 Diagnóstico rápido

| Sintoma | Verificação inicial |
| --- | --- |
| AWS aponta para conta ou região inesperada | Confira `aws sts get-caller-identity`, perfil ativo e `aws_region` em `terraform.tfvars`. |
| Terraform informa recurso existente ou divergência | Preserve o estado original e revise `terraform plan`; não apague o estado nem recursos manualmente. |
| SSH não conecta | Confirme o IP administrativo em `admin_cidr`, a chave privada e o Key Pair da região. |
| Pods ficam em `ImagePullBackOff` | Confirme acesso GHCR, validade do login da CLI e presença do Secret `ghcr-pull` na ServiceAccount. |
| `InfisicalSecret` não fica pronto | Confira credenciais Universal Auth, projeto, ambiente, caminho e nomes dos segredos referenciados nos manifests. |
| Certificado não fica `Ready` | Confira DNS/host gerado, portas públicas 80/443 e Ingress; consulte `kubectl describe certificate <nome> -n acta-prod` e `kubectl get events -n cert-manager`. |
| API retorna erro de dependência | Confira os Secrets sincronizados e os logs do Deployment afetado com `kubectl logs -n acta-prod deployment/<deployment>`. |

## 🧹 Encerrar o ambiente

Recursos AWS continuam gerando custos após o fim de credenciais temporárias ou da sessão de laboratório. Para remover recursos, consulte o plano Terraform no mesmo workspace e só aplique a destruição quando houver autorização explícita. A remoção da EC2 não apaga automaticamente bancos ou serviços gerenciados fora desta configuração.

## 📚 Referências

- [README do ACTA Platform](README.md): visão geral, arquitetura, tecnologias e fluxo GitOps.
- [Workflow de validação da infraestrutura](.github/workflows/teste-infra.yml).
- [Script de provisionamento e implantação](infra/aws/deploy.ps1).
- [Bootstrap do cluster](infra/aws/bootstrap-k3s.sh).
- [Variáveis Terraform](infra/aws/variables.tf) e [recursos AWS](infra/aws/main.tf).
- [Application Argo CD](argocd/prod.yaml) e [manifests Kubernetes](apps/).