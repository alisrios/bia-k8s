# Deploy da BIA no EKS com RDS (AWS)

Manifestos Kubernetes para execução da BIA em um cluster EKS com banco de dados PostgreSQL gerenciado pelo Amazon RDS, provisionado via Terraform.

## Estrutura

```
k8s/eks-rds/
├── app/
│   ├── bia-deploy.yml      # Deployment da aplicação BIA
│   └── bia-service.yml     # Service NodePort da BIA
├── ingress.yml             # Ingress ALB com HTTPS (certificado ACM)
└── kustomization.yml       # Kustomize com image override
```

## Pré-requisitos

- Cluster EKS provisionado via Terraform (pasta `terraform/`)
- Instância RDS PostgreSQL provisionada via Terraform
- AWS Load Balancer Controller instalado via Helm (provisionado pelo Terraform)
- `kubectl` configurado para o cluster EKS
- Imagem da BIA publicada no ECR
- Certificado SSL/TLS no AWS Certificate Manager (ACM)

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

### 1. Atualizar a tag da imagem no kustomization.yml

Edite o campo `newTag` em `kustomization.yml` com o commit SHA ou tag da imagem:

```yaml
images:
- name: 976808777516.dkr.ecr.us-east-1.amazonaws.com/bia
  newName: 976808777516.dkr.ecr.us-east-1.amazonaws.com/bia
  newTag: <SEU_COMMIT_SHA>
```

### 2. Aplicar os manifestos

```bash
kubectl apply -k k8s/eks-rds/
```

### 3. Aguardar os pods ficarem prontos

```bash
kubectl get pods -w
```

### 4. Rodar as migrations

```bash
kubectl exec -it deployment/bia -- npx sequelize db:migrate
```

### 5. Obter o endpoint do Load Balancer

```bash
kubectl get ingress bia-ingress
```

O campo `ADDRESS` retorna o DNS do ALB. Aguarde alguns minutos até o ALB ser provisionado.

A aplicação estará disponível via HTTPS na porta 443.

## Arquitetura de rede

```
Internet (HTTPS:443)
    │
    ▼
AWS ALB (internet-facing)
Load Balancer: bia-application-load-balancer
Subnets: subnet-05898e116dba4a044, subnet-033f56e295fa42b82
SSL/TLS: ACM Certificate
    │
    ▼ (target-type: instance)
Service NodePort (bia:8080)
    │
    ▼
Pod BIA (containerPort: 8080)
    │
    ▼
Amazon RDS PostgreSQL
Endpoint: db-bia-eks.cs9w2owgmo8f.us-east-1.rds.amazonaws.com:5432
```

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
| Load Balancer Name | `bia-application-load-balancer` |
| Scheme | `internet-facing` |
| Target Type | `instance` |
| Protocol | HTTPS (porta 443) |
| SSL Policy | `ELBSecurityPolicy-2016-08` |
| Certificate ARN | `arn:aws:acm:us-east-1:976808777516:certificate/a5368b26-d5e7-4606-93bb-b7d764c5575c` |
| Deregistration Delay | 30 segundos |

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
