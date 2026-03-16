# Deploy da BIA no EKS (AWS)

Manifestos Kubernetes para execução da BIA em um cluster EKS provisionado via Terraform.

## Estrutura

```
k8s/eks/
├── app/
│   ├── bia-deploy.yml           # Deployment da aplicação BIA
│   ├── bia-service.yml          # Service ClusterIP da BIA
│   ├── postgres-deployment.yml  # Deployment do PostgreSQL 17.1
│   ├── postgres-service.yml     # Service ClusterIP do PostgreSQL
│   └── postgres-pvc.yml         # PersistentVolumeClaim de 1Gi
├── ingress.yml                  # Ingress ALB (AWS Load Balancer Controller)
└── kustomization.yml            # Kustomize com image override
```

## Pré-requisitos

- Cluster EKS provisionado via Terraform (pasta `terraform/`)
- AWS Load Balancer Controller instalado via Helm (provisionado pelo Terraform)
- `kubectl` configurado para o cluster EKS
- Imagem da BIA publicada no ECR

## Infraestrutura provisionada pelo Terraform

O Terraform cria:

| Recurso | Nome |
|---|---|
| Cluster EKS | `bia-eks-cluster` |
| Node Group | `bia-eks-node-group` (2x t3.small) |
| ECR Repository | `bia` |
| AWS Load Balancer Controller | Helm release no namespace `kube-system` |
| VPC | `bia-eks-vpc` |
| Subnets públicas | `bia-eks-vpc-public-subnet-1a`, `bia-eks-vpc-public-subnet-1b` |

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

## Arquitetura de rede

```
Internet
    │
    ▼
AWS ALB (internet-facing)
bia-eks-vpc-public-subnet-1a / 1b
    │
    ▼ (target-type: ip)
Service ClusterIP (bia:8080)
    │
    ▼
Pod BIA (containerPort: 8080)
    │
    ▼
Service ClusterIP (postgres:5432)
    │
    ▼
Pod PostgreSQL + PVC 1Gi
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
| Storage | PVC de 1Gi (EBS gp2) |

## Comandos Úteis

```bash
# Status dos recursos
kubectl get pods
kubectl get ingress
kubectl get pvc
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
```

**Ingress sem ADDRESS**

O ALB pode levar 2-5 minutos para ser provisionado. Verifique os eventos:
```bash
kubectl describe ingress bia-ingress
```
