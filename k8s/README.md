# Deploy BIA no Minikube

## Pré-requisitos

1. Minikube instalado e rodando
2. kubectl configurado

## Deploy

### 1. Build da imagem no contexto do Minikube

```bash
eval $(minikube docker-env)
docker build -t bia:latest .
```

### 2. Aplicar os manifestos Kubernetes

```bash
kubectl apply -f k8s/
```

### 3. Aguardar os pods ficarem prontos

```bash
kubectl get pods -w
```

Aguarde até ambos os pods (bia e postgres) estarem com status `Running`.

### 4. Rodar migrations do banco de dados

```bash
kubectl exec -it deployment/bia -- npx sequelize db:migrate
```

### 5. Criar port-forward para acessar a aplicação

```bash
kubectl port-forward svc/bia 3001:8080
```

**Importante:** Mantenha este terminal aberto. O port-forward precisa estar ativo para acessar a aplicação.

### 6. Acessar a aplicação

Abra o navegador em: **http://localhost:3001**

## Persistência de Dados

Os dados do PostgreSQL são armazenados em um PersistentVolumeClaim (PVC) de 1Gi. Isso significa que:

- Os dados permanecem mesmo se você deletar e recriar os pods
- Para limpar completamente os dados, você precisa deletar o PVC

## Comandos Úteis

### Verificar status dos recursos

```bash
kubectl get pods
kubectl get pvc
kubectl get svc
```

### Ver logs

```bash
kubectl logs -f deployment/bia
kubectl logs -f deployment/postgres
```

### Acessar o banco de dados diretamente

```bash
kubectl exec -it deployment/postgres -- psql -U postgres -d bia
```

### Rebuild após alterações no código

```bash
eval $(minikube docker-env)
docker build -t bia:latest .
kubectl rollout restart deployment/bia
kubectl rollout status deployment/bia
```

## Limpar recursos

### Deletar apenas os deployments e services (mantém os dados)

```bash
kubectl delete deployment bia postgres
kubectl delete svc bia postgres
```

### Deletar tudo incluindo dados persistidos

```bash
kubectl delete -f k8s/
```

## Troubleshooting

### Port-forward desconecta

Se o port-forward cair, basta executar novamente:

```bash
kubectl port-forward svc/bia 3001:8080
```

### Pod não inicia

Verifique os logs:

```bash
kubectl describe pod <nome-do-pod>
kubectl logs <nome-do-pod>
```

### Erro de conexão com banco

Verifique se o pod do postgres está rodando:

```bash
kubectl get pods
kubectl logs deployment/postgres
```
