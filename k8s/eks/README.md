# Deploy da BIA no EKS (AWS)

Manifestos Kubernetes para execução da BIA em um cluster EKS provisionado via Terraform.

## Estrutura

```
k8s/eks/
├── app/
│   ├── bia-deploy.yml           # Deployment da aplicação BIA
│   ├── bia-service.yml          # Service NodePort da BIA
│   ├── postgres-deployment.yml  # Deployment do PostgreSQL 17.1
│   └── postgres-service.yml     # Service ClusterIP do PostgreSQL
├── ingress.yml                  # Ingress ALB com HTTPS (certificado ACM)
└── kustomization.yml            # Kustomize com image override
```

## Pré-requisitos

- Cluster EKS provisionado via Terraform (pasta `terraform/`)
- AWS Load Balancer Controller instalado via Helm (provisionado pelo Terraform)
- `kubectl` configurado para o cluster EKS
- Imagem da BIA publicada no ECR
- Certificado SSL/TLS no AWS Certificate Manager (ACM)

## Infraestrutura provisionada pelo Terraform

O Terraform cria:

| Recurso | Nome |
|---|---|
| Cluster EKS | `bia-eks-cluster` |
| Node Group | `bia-eks-node-group` (2x t3.small) |
| ECR Repository | `bia` |
| AWS Load Balancer Controller | Helm release no namespace `kube-system` |
| VPC | `bia-eks-vpc` |
| Subnets públicas | `subnet-066b0291f4ec82a10`, `subnet-063554b73bfa8a081` |
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
kubectl apply -k k8s/eks/
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
Subnets: subnet-066b0291f4ec82a10, subnet-063554b73bfa8a081
SSL/TLS: ACM Certificate
    │
    ▼ (target-type: instance)
Service NodePort (bia:8080)
    │
    ▼
Pod BIA (containerPort: 8080)
    │
    ▼
Service ClusterIP (postgres:5432)
    │
    ▼
Pod PostgreSQL (emptyDir storage)
```

## Configuração

### Variáveis de ambiente da BIA

| Variável | Valor |
|---|---|
| `DB_USER` | `postgres` |
| `DB_PWD` | `postgres` |
| `DB_HOST` | `postgres` |
| `DB_PORT` | `5432` |

### PostgreSQL

| Parâmetro | Valor |
|---|---|
| Imagem | `postgres:17.1` |
| Usuário | `postgres` |
| Senha | `postgres` |
| Banco | `bia` |
| Storage | `emptyDir` (dados não persistentes) |
| PGDATA | `/var/lib/postgresql/data/pgdata` |

> **Atenção:** O PostgreSQL está usando `emptyDir` como volume, o que significa que os dados serão perdidos se o pod for reiniciado. Para produção, considere usar um PersistentVolumeClaim (PVC) com EBS.

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

## Comandos Úteis

```bash
# Status dos recursos
kubectl get pods
kubectl get ingress
kubectl get svc

# Logs
kubectl logs -f deployment/bia
kubectl logs -f deployment/postgres

# Acessar o banco diretamente
kubectl exec -it deployment/postgres -- psql -U postgres -d bia

# Rebuild e redeploy
docker build -t bia:latest .
docker tag bia:latest 976808777516.dkr.ecr.us-east-1.amazonaws.com/bia:<NOVA_TAG>
docker push 976808777516.dkr.ecr.us-east-1.amazonaws.com/bia:<NOVA_TAG>
# Atualizar newTag no kustomization.yml e aplicar:
kubectl apply -k k8s/eks/

# Forçar restart dos pods
kubectl rollout restart deployment/bia
kubectl rollout restart deployment/postgres
```

## Limpar recursos

```bash
# Remove todos os recursos Kubernetes (o ALB é destruído automaticamente)
kubectl delete -k k8s/eks/
```

> Para destruir a infraestrutura completa (EKS, VPC, ECR), use `terraform destroy` nas stacks do Terraform.

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

**Erro de conexão com o banco**

```bash
kubectl get pods
kubectl logs deployment/postgres
kubectl exec -it deployment/postgres -- psql -U postgres -d bia -c "\l"
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

**Dados do PostgreSQL perdidos após restart**

O volume `emptyDir` não persiste dados. Para produção, crie um PVC:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: gp2
```

E atualize o `postgres-deployment.yml` para usar o PVC ao invés de `emptyDir`.

## Melhorias recomendadas para produção

1. **Persistência de dados:** Substituir `emptyDir` por PersistentVolumeClaim (PVC)
2. **Secrets:** Mover credenciais do banco para Kubernetes Secrets
3. **Health checks:** Adicionar `livenessProbe` e `readinessProbe` nos deployments
4. **Resource limits:** Definir `requests` e `limits` de CPU/memória
5. **Horizontal Pod Autoscaler:** Configurar HPA para escalar automaticamente
6. **Backup:** Implementar estratégia de backup do PostgreSQL
7. **Monitoring:** Integrar com CloudWatch Container Insights ou Prometheus
