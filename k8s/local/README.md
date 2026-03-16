# Deploy da BIA no Minikube (Local)

Manifestos Kubernetes para execução local da BIA em um cluster Minikube.

## Estrutura

| Arquivo | Descrição |
|---|---|
| `bia-deployment.yaml` | Deployment da aplicação BIA |
| `bia-service.yml` | Service NodePort da BIA (porta 30001) |
| `postgres-deployment.yml` | Deployment do PostgreSQL 17.1 |
| `postgres-service.yml` | Service ClusterIP do PostgreSQL |
| `postgres-pvc.yml` | PersistentVolumeClaim de 1Gi para o banco |

## Pré-requisitos

- [Minikube](https://minikube.sigs.k8s.io/docs/start/) instalado e rodando
- [kubectl](https://kubernetes.io/docs/tasks/tools/) configurado
- Docker disponível

## Deploy

### 1. Iniciar o Minikube

```bash
minikube start
```

### 2. Build da imagem no contexto do Minikube

```bash
eval $(minikube docker-env)
docker build -t bia:latest .
```

> O `imagePullPolicy: Never` no deployment garante que o Kubernetes use a imagem local em vez de tentar baixar do registry.

### 3. Aplicar os manifestos

```bash
kubectl apply -f k8s/local/
```

### 4. Aguardar os pods ficarem prontos

```bash
kubectl get pods -w
```

Aguarde até ambos os pods (`bia` e `postgres`) estarem com status `Running`.

### 5. Rodar as migrations

```bash
kubectl exec -it deployment/bia -- npx sequelize db:migrate
```

### 6. Acessar a aplicação

A BIA fica exposta via NodePort na porta `30001`. Para acessar:

```bash
minikube service bia --url
```

Ou via port-forward:

```bash
kubectl port-forward svc/bia 3001:8080
```

Acesse em: **http://localhost:3001**

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
| Storage | PVC de 1Gi |

## Persistência de Dados

Os dados do PostgreSQL ficam em um PVC (`postgres-pvc`) de 1Gi. Os dados sobrevivem a restarts e recriações de pods. Para limpar completamente:

```bash
kubectl delete pvc postgres-pvc
```

## Comandos Úteis

```bash
# Status dos recursos
kubectl get pods
kubectl get pvc
kubectl get svc

# Logs
kubectl logs -f deployment/bia
kubectl logs -f deployment/postgres

# Acessar o banco diretamente
kubectl exec -it deployment/postgres -- psql -U postgres -d bia

# Rebuild após alterações no código
eval $(minikube docker-env)
docker build -t bia:latest .
kubectl rollout restart deployment/bia
kubectl rollout status deployment/bia
```

## Limpar recursos

```bash
# Remove tudo (mantém o PVC)
kubectl delete deployment bia postgres
kubectl delete svc bia postgres

# Remove tudo incluindo os dados persistidos
kubectl delete -f k8s/local/
```

## Troubleshooting

**Pod não inicia**
```bash
kubectl describe pod <nome-do-pod>
kubectl logs <nome-do-pod>
```

**Erro de conexão com o banco**
```bash
kubectl get pods
kubectl logs deployment/postgres
```

**Port-forward desconecta**

Basta executar novamente:
```bash
kubectl port-forward svc/bia 3001:8080
```

**Imagem não encontrada**

Certifique-se de ter feito o build no contexto do Minikube:
```bash
eval $(minikube docker-env)
docker build -t bia:latest .
```
