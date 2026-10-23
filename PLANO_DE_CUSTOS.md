# 💵 Plano de custos — ACTA Platform

Este documento apresenta a arquitetura planejada e as premissas de orçamento do ACTA para apoiar quem vai implementar a plataforma e permitir que professores acompanhem como os custos foram estimados. O teto de referência é **US$ 50 por mês** para a conta AWS Education. Os serviços externos abaixo são considerados nos planos gratuitos, dentro de suas cotas.

## 📌 Premissas e situação atual

O repositório mantém serviços do ACTA em Kubernetes/K3s na AWS, com configuração GitOps pelo Argo CD e referências de segredos ao Infisical. Os manifests já apontam PostgreSQL para `DB_URL`, MongoDB para `MONGODB_URI`, Qdrant para `QDRANT_CLUSTER_ENDPOINT`/`QDRANT_API_KEY` e Redis para `REDIS_HOST`, `REDIS_PORT`, `REDIS_DB` e `REDIS_PASSWORD`.

| Componente | Uso esperado | Serviços que precisam dele |
| --- | --- | --- |
| PostgreSQL no Neon | Dados relacionais e notificações | `acta-pg-api`, `acta-import-api`, `acta-fcm-api` e job de lembretes |
| MongoDB Atlas | Documentos | `acta-mongo-api`, `acta-ai` e `acta-mcp` |
| Redis no Upstash | Cache/fila usada pelo fluxo de importação | `acta-import-api` e worker correspondente, conforme o código do serviço |
| Qdrant Cloud | Busca vetorial | `acta-ai` e `acta-mcp` |

Confirme cada relação nos repositórios das aplicações antes de alterar contratos ou configurações. Os nomes de variáveis acima foram observados nos manifests deste repositório; não são prova de que cada serviço esteja usando o banco em produção.

O [Firebase Cloud Messaging](https://firebase.google.com/pricing) não tem cobrança pelo serviço de mensagens, conforme consulta em 15/10/2026. Isso não elimina o consumo da EC2, do banco ou do tráfego de saída associado à API e aos lembretes.

## 🧾 Cotas gratuitas consideradas

Valores consultados em **14/10/2026**. Planos, disponibilidade regional e regras podem mudar; confirme as cotas no painel do provedor antes de provisionar ou alterar o plano.

| Provedor | Custo planejado | Cota gratuita relevante | Limites e cuidados |
| --- | ---: | --- | --- |
| [Neon — Free](https://neon.com/pricing) | US$ 0/mês | 1 GB de armazenamento e 100 CU-horas por projeto/mês; compute suspende após inatividade | A cota vale por projeto. Monitorar compute, armazenamento, tráfego e cold starts. O plano Free não deve ser tratado como SLA de produção. |
| [MongoDB Atlas — Free](https://www.mongodb.com/docs/atlas/reference/free-shared-limitations/) | US$ 0/mês | 512 MB, até 100 operações/s e 10 GB de entrada e 10 GB de saída por período móvel de 7 dias | Sem backups gerenciados no Free; clusters ociosos podem pausar após 30 dias. Planejar exportação/restauração e limitar conexões. |
| [Upstash Redis — Free](https://upstash.com/pricing/redis) | US$ 0/mês | 250 MB, 500 mil comandos/mês e 10 GB de tráfego/mês | Ultrapassar a cota exige interromper/reduzir uso ou optar conscientemente por plano pago. Não cadastrar forma de pagamento nem habilitar upgrade automático sem decisão explícita. |
| [Qdrant Cloud — Free](https://qdrant.tech/documentation/cloud/create-cluster/) | US$ 0/mês | Nó único, 0,5 vCPU, 1 GB RAM e 4 GB de disco; cerca de 1 milhão de vetores de 768 dimensões | Adequado a protótipo e carga pequena, sem alta disponibilidade. Suspende após uma semana sem uso e pode ser excluído após quatro semanas de inatividade. |

Se todos permanecerem dentro dessas cotas, os quatro bancos custam **US$ 0/mês**. Isso não inclui a aplicação na AWS, tráfego de saída, snapshots, domínios, monitoramento pago, impostos ou excedentes.

## 🚧 Orçamento AWS Education: teto de US$ 50/mês

A estimativa usa o [AWS Pricing Calculator](https://calculator.aws/#/) com a região e a instância definidas para o ambiente `aws-education`. Os valores são preços públicos, sem aplicar créditos, descontos educacionais, regras de laboratório ou limites da conta. O Calculator fornece uma estimativa; o valor real depende do uso e da configuração efetivamente ativa na conta.

### Premissas usadas no cálculo

| Variável | Valor usado | Origem ou observação |
| --- | --- | --- |
| Data de consulta | 23/10/2026 | Data da atualização do cenário EC2 e conferência da referência pública de preço em `us-east-1`; as demais premissas permanecem as estimadas em 14/10/2026. |
| Conta | `aws-education` (AWS Education) | Conta informada pelo responsável pelo projeto; cota/créditos disponíveis não foram consultados. |
| Região AWS | `us-east-1` (Leste dos EUA — N. da Virgínia) | Valor informado para `aws_region`. |
| Tipo de instância | `t3.large`, Linux, compartilhada, sob demanda (configuração desejada) | Configurada no Terraform e no `terraform.tfvars` local em relação à `t3.medium` anteriormente usada; mantém 2 vCPU e amplia a memória de 4 para 8 GiB. A alteração na EC2 ainda não foi aplicada. |
| Quantidade de instâncias | 1 | Uma EC2 K3s conforme a infraestrutura Terraform. |
| Horas ligadas | 730 horas/mês (100% de utilização) | Mês de referência de 30 dias, sem desligamento programado. |
| Volume | 30 GiB, SSD de uso geral `gp3` | Volume raiz padrão definido no Terraform; o Calculator incluiu o EBS na estimativa EC2. |
| IOPS e throughput do volume | Padrões do `gp3` | Não foi solicitado desempenho adicional; confirmar valores no Terraform e no Console antes de mudar. |
| Snapshots | 0 GiB-mês | Nenhuma retenção recorrente foi informada. Snapshots reais devem ser medidos e adicionados ao cálculo. |
| Tráfego de entrada | 0 GB estimados | Não foi fornecido volume; entrada não foi adicionada como consumo pago. |
| Tráfego de saída para a Internet | 10 GB/mês | Premissa inicial para cálculo; trocar por medição de tráfego/CloudWatch quando houver histórico. |
| IP público | 1 IPv4 público associado ao Elastic IP por 730 h/mês | Um `aws_eip` aparece na infraestrutura. Tarifa pública consultada: US$ 0,005 por hora, total estimado de US$ 3,65/mês; a eventual cota/crédito Education não está descontada. |
| Serviços AWS do ACTA | EC2, EBS, VPC, sub-rede, tabela de rotas, Internet Gateway, grupo de segurança e Elastic IP | Recursos vistos no Terraform. VPC, sub-rede, rotas, Internet Gateway e grupos de segurança não receberam itens pagos próprios nesta estimativa; tráfego e IPv4 público foram considerados separadamente. |

### Resultado mensal de referência

| Item | Estimativa mensal (USD) | Como foi calculado |
| --- | ---: | --- |
| EC2 `t3.large` sob demanda | 60,74 | US$ 0,0832/h × 730 h; preço público de referência para Linux sob demanda em `us-east-1`. |
| EBS `gp3`, 30 GiB | 2,40 | Resultado incluído pelo Calculator após configurar o volume raiz de 30 GiB. |
| Saída para Internet, 10 GB | 0,90 | Resultado do Calculator ao inserir 10 GB/mês como transferência de saída. |
| IPv4 público do Elastic IP, 730 h | 3,65 | 730 h × US$ 0,005/h, conforme [preços da Amazon VPC](https://aws.amazon.com/vpc/pricing/). |
| **Total AWS estimado** | **67,69** | Soma dos itens acima; cenário com `t3.large`, antes de créditos/descontos. |
| **Diferença para o teto de US$ 50** | **−17,69** | O cenário excede o teto de referência antes de considerar outros serviços ativos, tráfego acima da premissa, snapshots, impostos ou taxas. |
| Neon, Atlas, Upstash e Qdrant Free | 0,00 | Condicionado à permanência dentro das cotas gratuitas de cada serviço. |

O cenário com `t3.large` eleva a estimativa para **US$ 67,69/mês**, incluindo EC2, EBS, saída estimada e IPv4 público. A EC2 custa aproximadamente **US$ 30,37/mês a mais** que `t3.medium` (diferença de US$ 0,0416/h × 730 h), e o total ultrapassa o teto de referência de US$ 50. São preços públicos antes de créditos/descontos; confirme os créditos disponíveis e a cobrança aplicável no ambiente AWS Education. O total real também depende dos demais serviços ativos.

### Capacidade e réplicas dos serviços

Uma leitura pontual do nó K3s em 23/10/2026 mostrou `t3.medium` com CPU em 7% e memória em 78% (3.016 MiB usados). A leitura embasou a configuração de `t3.large` (2 vCPU e 8 GiB), antes de considerar `t3.xlarge`; ela não substitui o acompanhamento de métricas ao longo do tempo.

`acta-auth-api`, `acta-pg-api`, `acta-mongo-api` e `acta-fcm-api` estão configurados com duas réplicas. Elas compartilham o mesmo nó, não acrescentam custo de instância EC2 e não fornecem alta disponibilidade contra falha da máquina. Mantenha `acta-import-worker` em uma réplica até confirmar que o processamento evita duplicidade. Os manifests de `acta-ai` e `acta-mcp` definem requests de `100m` CPU e `256Mi` de memória, com limits de `500m` e `512Mi`; continuam com uma réplica até que o consumo seja acompanhado e a capacidade disponível confirmada.

### Como reproduzir e manter o orçamento

1. Abra o [AWS Pricing Calculator](https://calculator.aws/#/) e escolha região **US East (N. Virginia) / `us-east-1`**.
2. Adicione **Amazon EC2**: Linux, instância compartilhada, `t3.large`, uma instância, uso constante e 100%/730 h por mês, preço sob demanda.
3. Inclua o armazenamento EBS no EC2: SSD de uso geral `gp3`, 30 GiB, sem snapshots recorrentes.
4. No bloco de transferência de dados do EC2, registre 10 GB por mês de saída para Internet. Atualize esse volume com medições reais quando existirem.
5. Considere um IPv4 público/Elastic IP por 730 horas usando a tarifa da Amazon VPC indicada na tabela; mantenha os demais IPs públicos e recursos de rede em zero somente se o inventário confirmar isso.
6. Registre no documento a data da consulta, os valores informados e o total exibido. Repita o cálculo quando mudar a região, instância, horas, disco, tráfego, snapshots, IPs ou serviços ativos.
7. Compare a estimativa com faturamento e créditos disponíveis no AWS Education. Revise também recursos em todas as regiões; o Calculator público não verifica a conta nem interrompe recursos que gerem cobrança.

O AWS Education pode oferecer créditos, cotas ou limites próprios do curso/laboratório. Eles não foram presumidos como saldo mensal de US$ 50 e não são refletidos no preço público calculado. Confirme o saldo, validade, serviços permitidos, duração das sessões e regras de cobrança no portal da conta antes de usar a estimativa como previsão de pagamento.

## 🔗 Fontes de preços e limites

- [Neon Pricing](https://neon.com/pricing) e [atualização do plano gratuito em 02/10/2026](https://neon.com/blog/neon-free-plan-1-gb-per-project).
- [MongoDB Atlas Free Cluster Limits](https://www.mongodb.com/docs/atlas/reference/free-shared-limitations/).
- [Upstash Redis Pricing](https://upstash.com/pricing/redis).
- [Qdrant Cloud — criação e limites de clusters](https://qdrant.tech/documentation/cloud/create-cluster/).
- [AWS Pricing Calculator](https://calculator.aws/#/), [EC2 On-Demand](https://aws.amazon.com/ec2/pricing/on-demand/), [referência de preço T3 em `us-east-1`](https://docs.aws.amazon.com/prescriptive-guidance/latest/optimize-costs-microsoft-workloads/right-size-selection.html), [EBS Pricing](https://aws.amazon.com/ebs/pricing/) e [Amazon VPC Pricing — IPv4 público](https://aws.amazon.com/vpc/pricing/).
