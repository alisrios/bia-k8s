# Deploy da BIA no EKS com RDS e ArgoCD (AWS)

Manifestos Kubernetes para execução da BIA em um cluster EKS com banco de dados PostgreSQL gerenciado pelo Amazon RDS, provisionado via Terraform, e GitOps com ArgoCD.

## Estrutura

```
k8s/eks-rds/
├── app/
│   ├── bia-deploy.yml      # Deployment da aplicação BIA
│   ├── bia-service.yml     # Service NodePort da BIA
│   └── bia-hpa.yml         # HorizontalPodAutoscaler
├── argocd/
│   ├── application.yml     # ArgoCD Application para GitOps
│   ├── ingress.yml         # Ingress ALB para ArgoCD UI
│   ├── configmap-patch.yml # ConfigMap para modo insecure
│   └── kustomization.yml   # Kustomize do ArgoCD
├── ingress.yml             # Ingress ALB com HTTPS (certificado ACM)
└── kustomization.yml       # Kustomize com image override
```

## Pré-requisitos

- Cluster EKS provisionado via Terraform (pasta `terraform/`)
- Instância RDS PostgreSQL provisionada via Terraform
- AWS Load Balancer Controller instalado via Helm (provisionado pelo Terraform)
- Cluster Autoscaler configurado no node group (provisionado pelo Terraform)
- Metrics Server instalado no cluster (para HPA funcionar)
- ArgoCD instalado no namespace `argocd`
- `kubectl` configurado para o cluster EKS
- Imagem da BIA publicada no ECR
- Certificado SSL/TLS no AWS Certificate Manager (ACM)
- Repositório Git para GitOps (ex: `https://github.com/alisrios/bia-k8s-gitops`)

## Infraestrutura provisionada pelo Terraform

O Terraform cria:

| Recurso | Nome/Endpoint |
|---|---|
| Cluster EKS | `bia-eks-cluster` |
| Node Group | `bia-eks-node-group` (2x t3.small) |
| RDS PostgreSQL | `db-bia-eks.cs9w2owgmo8f.us-east-1.rds.amazonaws.com` |
| ECR Repository | `bia` |
| AWS Load Balancer Controller | Helm release no namespace `kube-system` |
| VPC | `bia-eks-vpc` |
| Subnets públicas | `subnet-05898e116dba4a044`, `subnet-033f56e295fa42b82` |
| Certificado ACM | `arn:aws:acm:us-east-1:976808777516:certificate/a5368b26-d5e7-4606-93bb-b7d764c5575c` |

## Configuração do kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name bia-eks-cluster
```

## Build e push da imagem para o ECR

```bash
# Autenticar no ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 976808777516.dkr.ecr.us-east-1.amazonaws.com

# Build e push
docker build -t bia:latest .
docker tag bia:latest 976808777516.dkr.ecr.us-east-1.amazonaws.com/bia:<TAG>
docker push 976808777516.dkr.ecr.us-east-1.amazonaws.com/bia:<TAG>
```

## Deploy

### Opção 1: Deploy Manual com Kustomize

#### 1. Atualizar a tag da imagem no kustomization.yml

Edite o campo `newTag` em `kustomization.yml` com o commit SHA ou tag da imagem:

```yaml
images:
- name: 976808777516.dkr.ecr.us-east-1.amazonaws.com/bia
  newName: 976808777516.dkr.ecr.us-east-1.amazonaws.com/bia
  newTag: <SEU_COMMIT_SHA>
```

#### 2. Aplicar os manifestos

```bash
kubectl apply -k k8s/eks-rds/
```

#### 3. Aguardar os pods ficarem prontos

```bash
kubectl get pods -w
```

#### 4. Rodar as migrations

```bash
kubectl exec -it deployment/bia -- npx sequelize db:migrate
```

#### 5. Obter o endpoint do Load Balancer

```bash
kubectl get ingress bia-ingress
```

O campo `ADDRESS` retorna o DNS do ALB. Aguarde alguns minutos até o ALB ser provisionado.

A aplicação estará disponível via HTTPS na porta 443.

### Opção 2: Deploy com GitOps (ArgoCD)

#### 1. Instalar o ArgoCD

```bash
# Criar namespace
kubectl create namespace argocd

# Instalar ArgoCD
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Aguardar pods ficarem prontos
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
```

#### 2. Configurar ArgoCD para aceitar tráfego HTTP (ALB faz terminação SSL)

```bash
kubectl apply -f k8s/eks-rds/argocd/configmap-patch.yml
kubectl rollout restart deployment argocd-server -n argocd
```

#### 3. Aplicar os manifestos do ArgoCD (Ingress + Application)

```bash
kubectl apply -k k8s/eks-rds/
```

#### 4. Obter a senha inicial do ArgoCD

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

#### 5. Configurar DNS

Crie entradas DNS apontando para o ALB:
- `argocd.alisriosti.com.br` → DNS do ALB
- `bia-eks.alisriosti.com.br` → DNS do ALB

```bash
# Obter DNS do ALB
kubectl get ingress -A
```

#### 6. Instalar Metrics Server (necessário para HPA)

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Aguardar ficar pronto
kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=120s

# Verificar
kubectl top nodes
kubectl top pods
```

#### 7. Acessar o ArgoCD

- **URL:** https://argocd.alisriosti.com.br
- **Usuário:** admin
- **Senha:** (obtida no passo 4)

**Importante:** Altere a senha após o primeiro login.

#### 8. Sincronizar a aplicação

O ArgoCD está configurado com `syncPolicy.automated.selfHeal: true`, então qualquer mudança no repositório Git será automaticamente aplicada no cluster.

Para sincronizar manualmente:
```bash
# Via CLI
argocd app sync bia-k8s

# Via UI
Acesse https://argocd.alisriosti.com.br e clique em "Sync"
```

## Arquitetura de rede

```
Internet (HTTPS:443)
    │
    ▼
AWS ALB (internet-facing) - Compartilhado
Load Balancer: k8s-biaalb-fa7f1b247b
Group Name: bia-alb
Subnets: subnet-06006850eabb7dba0, subnet-017091556fa6401ef
SSL/TLS: ACM Certificate
    │
    ├─────────────────────────────────┬──────────────────────────────────┐
    │                                 │                                  │
    ▼ Host: bia-eks.alisriosti.com.br│  Host: argocd.alisriosti.com.br  │
Service NodePort (bia:8080)          │  Service ClusterIP (argocd:80)   │
target-type: instance                │  target-type: ip                 │
    │                                 │                                  │
    ▼                                 ▼                                  │
Pod BIA (containerPort: 8080)    Pod ArgoCD (containerPort: 8080)      │
    │                                                                    │
    ▼                                                                    │
Amazon RDS PostgreSQL                                                   │
Endpoint: db-bia-eks.cs9w2owgmo8f.us-east-1.rds.amazonaws.com:5432     │
```

### ALB Compartilhado (group.name: bia-alb)

Ambos os Ingress usam `alb.ingress.kubernetes.io/group.name: bia-alb` para compartilhar o mesmo ALB, economizando custos e simplificando o gerenciamento.

**Regras de roteamento:**
- `argocd.alisriosti.com.br` → ArgoCD Server (porta 80)
- `bia-eks.alisriosti.com.br` → Aplicação BIA (porta 8080)

## Configuração

### Variáveis de ambiente da BIA

| Variável | Valor |
|---|---|
| `DB_USER` | `postgres` |
| `DB_PWD` | `postgres` |
| `DB_HOST` | `db-bia-eks.cs9w2owgmo8f.us-east-1.rds.amazonaws.com` |
| `DB_PORT` | `5432` |

> **Importante:** As credenciais do banco estão hardcoded no manifesto. Para produção, use Kubernetes Secrets ou AWS Secrets Manager.

### Amazon RDS PostgreSQL

| Parâmetro | Valor |
|---|---|
| Engine | PostgreSQL |
| Endpoint | `db-bia-eks.cs9w2owgmo8f.us-east-1.rds.amazonaws.com` |
| Porta | `5432` |
| Usuário | `postgres` |
| Senha | `postgres` |
| Banco | `bia` |
| Backup | Gerenciado pelo RDS |
| Multi-AZ | Configurado via Terraform |

### Ingress (ALB)

| Configuração | Valor |
|---|---|
| Group Name | `bia-alb` (compartilhado entre BIA e ArgoCD) |
| Load Balancer Name | `k8s-biaalb-fa7f1b247b` |
| Scheme | `internet-facing` |
| Protocol | HTTPS (porta 443) |
| SSL Policy | `ELBSecurityPolicy-2016-08` |
| Certificate ARN | `arn:aws:acm:us-east-1:976808777516:certificate/a5368b26-d5e7-4606-93bb-b7d764c5575c` |
| Deregistration Delay | 30 segundos |

**Ingress da BIA:**
- Target Type: `instance` (NodePort)
- Host: `bia-eks.alisriosti.com.br`
- Backend: Service `bia` porta 8080

**Ingress do ArgoCD:**
- Target Type: `ip` (ClusterIP)
- Host: `argocd.alisriosti.com.br`
- Backend: Service `argocd-server` porta 80
- Healthcheck: `/healthz`

### Auto-scaling

#### HPA (Horizontal Pod Autoscaler)

Escala automaticamente os **pods** da aplicação BIA baseado em métricas de CPU e memória.

| Configuração | Valor |
|---|---|
| Min Replicas | 2 |
| Max Replicas | 10 |
| CPU Target | 70% de utilização |
| Memory Target | 80% de utilização |
| Scale Up | Rápido (até 100% ou +2 pods a cada 30s) |
| Scale Down | Conservador (até 50% a cada 60s, aguarda 5 min) |

**Resource Requests/Limits:**
```yaml
requests:
  cpu: 100m      # 0.1 CPU
  memory: 128Mi
limits:
  cpu: 500m      # 0.5 CPU
  memory: 512Mi
```

**Como funciona:**
1. HPA monitora uso de CPU/memória dos pods
2. Se uso > 70% CPU ou 80% memória → aumenta pods (até 10)
3. Se uso normaliza → reduz pods (até 2) após 5 minutos

#### Cluster Autoscaler

Escala automaticamente as **instâncias EC2** do node group baseado em pods pendentes.

| Configuração | Valor |
|---|---|
| Min Size | 2 nodes |
| Max Size | 10 nodes |
| Desired Size | 2 nodes (inicial) |
| Scale Up | Quando há pods pendentes (sem recursos) |
| Scale Down | Após 10 min de node ocioso (< 50% utilização) |

**Como funciona:**
1. HPA cria novos pods mas não há recursos → pods ficam "Pending"
2. Cluster Autoscaler detecta pods pendentes → adiciona nodes
3. Novos nodes ficam prontos → pods são agendados
4. Quando carga normaliza → HPA remove pods → nodes ficam ociosos
5. Após 10 min → Cluster Autoscaler remove nodes ociosos (até min: 2)

**Fluxo completo de auto-scaling:**
```
Alta carga:
1. HPA: 2 pods → 10 pods (imediato)
2. Cluster Autoscaler: 2 nodes → 5 nodes (2-3 min)

Carga normaliza:
1. HPA: 10 pods → 2 pods (após 5 min)
2. Cluster Autoscaler: 5 nodes → 2 nodes (após 10 min)
```

## Vantagens do RDS vs PostgreSQL em Pod

| Aspecto | RDS | PostgreSQL em Pod |
|---|---|---|
| Persistência | Dados persistentes e seguros | Requer PVC (dados podem ser perdidos) |
| Backup | Automático e gerenciado | Manual |
| Alta disponibilidade | Multi-AZ nativo | Requer configuração complexa |
| Manutenção | Gerenciada pela AWS | Manual |
| Escalabilidade | Vertical e read replicas | Limitada |
| Monitoramento | CloudWatch integrado | Requer configuração |
| Custo | Mais alto | Mais baixo |

## Comandos Úteis

### Aplicação BIA

```bash
# Status dos recursos
kubectl get pods
kubectl get ingress
kubectl get svc

# Logs
kubectl logs -f deployment/bia

# Testar conexão com o RDS
kubectl exec -it deployment/bia -- sh
# Dentro do pod:
psql -h db-bia-eks.cs9w2owgmo8f.us-east-1.rds.amazonaws.com -U postgres -d bia

# Rebuild e redeploy
docker build -t bia:latest .
docker tag bia:latest 976808777516.dkr.ecr.us-east-1.amazonaws.com/bia:<NOVA_TAG>
docker push 976808777516.dkr.ecr.us-east-1.amazonaws.com/bia:<NOVA_TAG>
# Atualizar newTag no kustomization.yml e aplicar:
kubectl apply -k k8s/eks-rds/

# Forçar restart dos pods
kubectl rollout restart deployment/bia

# Verificar conectividade com RDS
kubectl run -it --rm debug --image=postgres:17.1 --restart=Never -- psql -h db-bia-eks.cs9w2owgmo8f.us-east-1.rds.amazonaws.com -U postgres -d bia
```

### HPA e Auto-scaling

```bash
# Ver status do HPA
kubectl get hpa
kubectl describe hpa bia-hpa

# Ver métricas dos pods
kubectl top pods -l app=bia
kubectl top nodes

# Testar auto-scaling (gerar carga)
kubectl run -it --rm load-generator --image=busybox --restart=Never -- /bin/sh -c "while sleep 0.01; do wget -q -O- http://bia:8080/api/versao; done"

# Monitorar scaling em tempo real
watch kubectl get hpa,pods

# Ver eventos de scaling
kubectl get events --sort-by='.lastTimestamp' | grep -i "horizontal\|scaled"

# Ver histórico de replicas
kubectl describe hpa bia-hpa | grep -A 10 "Events:"

# Desabilitar HPA temporariamente
kubectl scale deployment bia --replicas=2
kubectl delete hpa bia-hpa

# Reabilitar HPA
kubectl apply -f k8s/eks-rds/app/bia-hpa.yml
```

### ArgoCD

```bash
# Status do ArgoCD
kubectl get pods -n argocd
kubectl get ingress -n argocd

# Logs do ArgoCD
kubectl logs -n argocd deployment/argocd-server -f

# Obter senha inicial
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

# Listar aplicações
kubectl get applications -n argocd

# Ver status da aplicação BIA
kubectl get application bia-k8s -n argocd -o yaml

# Sincronizar manualmente
kubectl patch application bia-k8s -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'

# Pausar sync automático
kubectl patch application bia-k8s -n argocd --type=json -p='[{"op": "remove", "path": "/spec/syncPolicy/automated"}]'

# Reabilitar sync automático
kubectl patch application bia-k8s -n argocd --type merge -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":true,"prune":true}}}}'

# Port-forward para acessar localmente (alternativa ao Ingress)
kubectl port-forward svc/argocd-server -n argocd 8080:80
```

### ALB

```bash
# Listar todos os ALBs
aws elbv2 describe-load-balancers --region us-east-1 --query "LoadBalancers[?Type=='application'].[LoadBalancerName,DNSName,State.Code]" --output table

# Ver regras do listener HTTPS
ALB_ARN=$(kubectl get ingress bia-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' | xargs -I {} aws elbv2 describe-load-balancers --region us-east-1 --query "LoadBalancers[?DNSName=='{}'].LoadBalancerArn" --output text)
LISTENER_ARN=$(aws elbv2 describe-listeners --load-balancer-arn $ALB_ARN --region us-east-1 --query "Listeners[?Port==\`443\`].ListenerArn" --output text)
aws elbv2 describe-rules --listener-arn $LISTENER_ARN --region us-east-1 --query "Rules[].{Priority:Priority,Host:Conditions[?Field=='host-header'].Values}" --output table

# Ver target groups
aws elbv2 describe-target-groups --load-balancer-arn $ALB_ARN --region us-east-1 --query "TargetGroups[].[TargetGroupName,Port,Protocol,HealthCheckPath]" --output table
```

## Limpar recursos

```bash
# Remove todos os recursos Kubernetes (o ALB é destruído automaticamente)
kubectl delete -k k8s/eks-rds/
```

> Para destruir a infraestrutura completa (EKS, RDS, VPC, ECR), use `terraform destroy` nas stacks do Terraform.

## Troubleshooting

**ALB não é provisionado**

Verifique se o AWS Load Balancer Controller está rodando:
```bash
kubectl get pods -n kube-system | grep aws-load-balancer
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

**Dois ALBs foram criados em vez de um compartilhado**

Isso acontece quando os Ingress não têm o mesmo `group.name`. Verifique:
```bash
kubectl get ingress -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.alb\.ingress\.kubernetes\.io/group\.name}{"\n"}{end}'
```

Ambos devem ter `bia-alb`. Se não tiverem, corrija os manifestos e reaplique. O ALB antigo será deletado automaticamente.

**ArgoCD sobrescreve configurações locais**

Se o ArgoCD está com `syncPolicy.automated.selfHeal: true`, ele vai reverter qualquer mudança manual. Para fazer mudanças temporárias:
```bash
# Pausar sync automático
kubectl patch application bia-k8s -n argocd --type=json -p='[{"op": "remove", "path": "/spec/syncPolicy/automated"}]'

# Fazer suas mudanças...

# Reabilitar sync automático
kubectl patch application bia-k8s -n argocd --type merge -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":true}}}}'
```

**ArgoCD mostra "ImagePullBackOff"**

O ArgoCD está tentando usar uma imagem que não existe no ECR. Verifique:
```bash
# Ver qual imagem o ArgoCD está tentando usar
kubectl get deployment bia -o jsonpath='{.spec.template.spec.containers[0].image}'

# Listar imagens disponíveis no ECR
aws ecr describe-images --repository-name bia --region us-east-1 --query 'imageDetails[*].imageTags'
```

Atualize o repositório GitOps com a tag correta ou faça push da imagem faltante.

**ArgoCD UI não carrega (erro de certificado ou redirect loop)**

O ArgoCD precisa estar em modo insecure quando atrás de um ALB que faz terminação SSL:
```bash
kubectl get configmap argocd-cmd-params-cm -n argocd -o yaml | grep insecure
```

Deve mostrar `server.insecure: "true"`. Se não, aplique:
```bash
kubectl apply -f k8s/eks-rds/argocd/configmap-patch.yml
kubectl rollout restart deployment argocd-server -n argocd
```bash
kubectl apply -f k8s/eks-rds/argocd/configmap-patch.yml
kubectl rollout restart deployment argocd-server -n argocd
```

**HPA mostra `<unknown>` nas métricas**

O Metrics Server não está instalado ou não está funcionando:
```bash
# Verificar se está instalado
kubectl get deployment metrics-server -n kube-system

# Se não estiver, instalar
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Aguardar ficar pronto
kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=120s

# Verificar logs se houver erro
kubectl logs -n kube-system deployment/metrics-server

# Testar
kubectl top nodes
kubectl top pods
```

Após instalar, aguarde 1-2 minutos para o HPA começar a coletar métricas.

**HPA não escala os pods**

Verifique se o Deployment tem resource requests configurados:
```bash
kubectl get deployment bia -o yaml | grep -A 5 "resources:"
```

Deve mostrar `requests.cpu` e `requests.memory`. O HPA precisa desses valores para calcular a utilização percentual.

**Pods ficam "Pending" após HPA escalar**

O Cluster Autoscaler vai adicionar nodes automaticamente. Aguarde 2-3 minutos:
```bash
# Ver pods pendentes
kubectl get pods -l app=bia | grep Pending

# Ver eventos do pod
kubectl describe pod <pod-name>

# Ver se Cluster Autoscaler está adicionando nodes
kubectl get nodes -w
```

Se os nodes não forem adicionados, verifique os logs do Cluster Autoscaler (se instalado).

**Pod não inicia (ImagePullBackOff)**

Verifique se a imagem existe no ECR e se o node group tem permissão de pull:
```bash
kubectl describe pod <nome-do-pod>
```

**Erro de conexão com o RDS**

Verifique se:
1. O security group do RDS permite conexões do security group do EKS
2. O endpoint do RDS está correto no manifesto
3. As credenciais estão corretas

```bash
kubectl get pods
kubectl logs deployment/bia
kubectl describe pod <nome-do-pod>

# Testar conectividade de rede
kubectl run -it --rm debug --image=busybox --restart=Never -- nc -zv db-bia-eks.cs9w2owgmo8f.us-east-1.rds.amazonaws.com 5432
```

**Ingress sem ADDRESS**

O ALB pode levar 2-5 minutos para ser provisionado. Verifique os eventos:
```bash
kubectl describe ingress bia-ingress
kubectl describe ingress argocd-ingress -n argocd
```

**Erro de certificado SSL**

Verifique se o certificado ACM está válido e associado ao domínio correto:
```bash
aws acm describe-certificate --certificate-arn arn:aws:acm:us-east-1:976808777516:certificate/a5368b26-d5e7-4606-93bb-b7d764c5575c --region us-east-1
```

**Timeout ao conectar no RDS**

Verifique os security groups:
```bash
# Obter o security group do RDS
aws rds describe-db-instances --db-instance-identifier <rds-instance-id> --query 'DBInstances[0].VpcSecurityGroups' --region us-east-1

# Obter o security group dos nodes do EKS
kubectl get nodes -o wide
aws ec2 describe-instances --instance-ids <node-instance-id> --query 'Reservations[0].Instances[0].SecurityGroups' --region us-east-1
```

O security group do RDS deve permitir tráfego na porta 5432 do security group dos nodes do EKS.

## Melhorias recomendadas para produção

1. **Secrets:** Mover credenciais do RDS para Kubernetes Secrets ou AWS Secrets Manager
2. **Connection pooling:** Configurar PgBouncer para gerenciar conexões
3. **Health checks:** Adicionar `livenessProbe` e `readinessProbe` nos deployments
4. **Resource limits:** Definir `requests` e `limits` de CPU/memória
5. **Horizontal Pod Autoscaler:** Configurar HPA para escalar automaticamente
6. **RDS Proxy:** Usar RDS Proxy para melhor gerenciamento de conexões
7. **Monitoring:** Integrar com CloudWatch Container Insights ou Prometheus
8. **Read Replicas:** Configurar read replicas do RDS para queries de leitura
9. **Backup strategy:** Configurar snapshots automáticos e retenção adequada
10. **Network policies:** Implementar network policies para restringir tráfego
11. **ArgoCD RBAC:** Configurar controle de acesso baseado em roles no ArgoCD
12. **ArgoCD SSO:** Integrar com provedor de identidade (GitHub, Google, SAML)
13. **ArgoCD Notifications:** Configurar notificações de deploy (Slack, email)
14. **Multi-environment:** Separar ambientes (dev, staging, prod) com diferentes Applications
15. **Image promotion:** Usar tags específicas em vez de `latest` para rastreabilidade

## Migração de dados

Se estiver migrando de PostgreSQL em pod para RDS:

```bash
# 1. Fazer dump do banco no pod
kubectl exec deployment/postgres -- pg_dump -U postgres bia > bia_backup.sql

# 2. Restaurar no RDS
psql -h db-bia-eks.cs9w2owgmo8f.us-east-1.rds.amazonaws.com -U postgres -d bia < bia_backup.sql

# 3. Atualizar o deployment da BIA para apontar para o RDS
kubectl apply -k k8s/eks-rds/

# 4. Verificar se a aplicação está funcionando
kubectl logs -f deployment/bia
```
