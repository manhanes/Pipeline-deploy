# PNETLab Kubernetes Deployment

## 📋 Visão Geral

Este repositório contém os manifestos Kubernetes para deploy do **PNETLab** - uma plataforma de laboratório de redes virtuais.

## 🏗️ Arquitetura

```
┌─────────────────────────────────────────────────────────────────┐
│                        KUBERNETES CLUSTER                       │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    Namespace: pnetlab                     │  │
│  │                                                           │  │
│  │  ┌──────────────┐     ┌──────────────┐     ┌─────────────┐│  │
│  │  │   Ingress    │───▶│  Service      │───▶│     Pod     ││  │
│  │  │   (nginx)    │     │ (NodePort/   │     │  (PNETLab)  ││  │
│  │  └──────────────┘     │ LoadBalancer)│     └──────┬──────┘│  │
│  │                       └──────────────┘           │        │  │
│  │                                                  │        │  │
│  │  ┌─────────────────────────────────────────────▼────────┐ │  │
│  │  │              Persistent Volumes                      │ │  │
│  │  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────────┐ │ │  │
│  │  │  │  data   │ │  labs   │ │ config  │ │     tmp     │ │ │  │
│  │  │  │ (100Gi) │ │ (50Gi)  │ │  (1Gi)  │ │   (20Gi)    │ │ │  │
│  │  │  └─────────┘ └─────────┘ └─────────┘ └─────────────┘ │ │  │
│  │  └──────────────────────────────────────────────────────┘ │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## 📁 Estrutura de Arquivos

```
pnetlab-k8s/
├── 00-namespace.yaml          # Namespace isolado
├── 01-storage.yaml            # PersistentVolumeClaims
├── 02-configmap.yaml          # Configurações
├── 03-secrets.yaml            # Credenciais (ALTERE!)
├── 04-rbac.yaml               # ServiceAccount e permissões
├── 05-deployment.yaml         # Deployment principal
├── 06-services.yaml           # Services (NodePort, LoadBalancer)
├── 07-ingress.yaml            # Ingress (acesso via hostname)
├── 08-network-policy.yaml     # Políticas de rede
├── 09-resource-management.yaml # Quotas e limites
├── deploy.sh                  # Script de deploy interativo
├── kustomization.yaml         # Kustomize config
└── README.md                  # Esta documentação
```

## ⚡ Requisitos

### Hardware (Node Workers)
- **CPU**: Intel/AMD com suporte a VT-x/AMD-V e EPT/NPT
- **RAM**: Mínimo 8GB (recomendado 16GB+)
- **Storage**: SSD recomendado, 200GB+ livres
- **Nested Virtualization**: OBRIGATÓRIO

### Software
- Kubernetes 1.25+
- kubectl configurado
- StorageClass provisionado (local-path, longhorn, etc.)
- Ingress Controller (opcional, para acesso via hostname)

### Verificar Nested Virtualization

No node worker, execute:
```bash
# Para Intel
cat /sys/module/kvm_intel/parameters/nested
# Deve retornar: Y

# Para AMD
cat /sys/module/kvm_amd/parameters/nested
# Deve retornar: 1
```

Habilitar nested virtualization:
```bash
# Intel
sudo modprobe -r kvm_intel
sudo modprobe kvm_intel nested=1
echo "options kvm-intel nested=1" | sudo tee /etc/modprobe.d/kvm-intel.conf

# AMD
sudo modprobe -r kvm_amd
sudo modprobe kvm_amd nested=1
echo "options kvm-amd nested=1" | sudo tee /etc/modprobe.d/kvm-amd.conf
```

## 🚀 Deploy

### Opção 1: Script Interativo
```bash
chmod +x deploy.sh
./deploy.sh
```

### Opção 2: Kustomize
```bash
kubectl apply -k .
```

### Opção 3: Kubectl Direto
```bash
kubectl apply -f 00-namespace.yaml
kubectl apply -f 01-storage.yaml
kubectl apply -f 02-configmap.yaml
kubectl apply -f 03-secrets.yaml
kubectl apply -f 04-rbac.yaml
kubectl apply -f 05-deployment.yaml
kubectl apply -f 06-services.yaml
kubectl apply -f 07-ingress.yaml
kubectl apply -f 08-network-policy.yaml
kubectl apply -f 09-resource-management.yaml
```

## 🌐 Acesso

### NodePort (mais simples)
```
HTTP:  http://<NODE_IP>:30080
HTTPS: https://<NODE_IP>:30443
```

### LoadBalancer (cloud/MetalLB)
```
HTTP:  http://<EXTERNAL_IP>
HTTPS: https://<EXTERNAL_IP>
```

### Ingress (com hostname)
```
# Adicione ao /etc/hosts:
<NODE_IP> pnetlab.local

# Acesse:
http://pnetlab.local
```

### Credenciais Padrão
```
Usuário: admin
Senha:   pnet
```

⚠️ **ALTERE A SENHA IMEDIATAMENTE APÓS O PRIMEIRO ACESSO!**

## 🔧 Customização

### Alterar StorageClass
Edite `01-storage.yaml` e substitua `local-path` pela sua StorageClass:
```yaml
storageClassName: seu-storage-class
```

### Ajustar Recursos
Edite `05-deployment.yaml`:
```yaml
resources:
  requests:
    cpu: "4"        # Ajuste conforme necessário
    memory: "8Gi"
  limits:
    cpu: "16"
    memory: "32Gi"
```

### Configurar MetalLB (LoadBalancer local)
Edite `06-services.yaml` e descomente:
```yaml
annotations:
  metallb.universe.tf/loadBalancerIPs: 192.168.1.100
```

### Usar Imagem Docker Customizada
Para produção, crie uma imagem com PNETLab pré-instalado e altere em `05-deployment.yaml`:
```yaml
image: seu-registry/pnetlab:latest
```

## 📊 Monitoramento

### Ver Status
```bash
kubectl get all -n pnetlab
```

### Ver Logs
```bash
kubectl logs -n pnetlab -l app.kubernetes.io/name=pnetlab -f
```

### Acessar Shell do Container
```bash
kubectl exec -it -n pnetlab deploy/pnetlab -- bash
```

### Verificar KVM
```bash
kubectl exec -n pnetlab deploy/pnetlab -- ls -la /dev/kvm
```

## 🔄 Atualizações

### Atualizar Configurações
```bash
kubectl apply -f 02-configmap.yaml
kubectl rollout restart deployment/pnetlab -n pnetlab
```

### Escalar Recursos
```bash
kubectl set resources deployment/pnetlab -n pnetlab \
  --limits=cpu=8,memory=32Gi \
  --requests=cpu=4,memory=16Gi
```

## 🗑️ Remoção

### Remover Todos os Recursos
```bash
kubectl delete namespace pnetlab
```

### Remover Mantendo PVCs (dados)
```bash
kubectl delete -f 05-deployment.yaml
kubectl delete -f 06-services.yaml
kubectl delete -f 07-ingress.yaml
# PVCs mantidos em 01-storage.yaml
```

## ⚠️ Troubleshooting

### Pod em CrashLoopBackOff
```bash
kubectl describe pod -n pnetlab -l app.kubernetes.io/name=pnetlab
kubectl logs -n pnetlab -l app.kubernetes.io/name=pnetlab --previous
```

### KVM não Disponível
1. Verifique nested virtualization no node
2. Verifique se o node tem `/dev/kvm`
3. Certifique-se que o pod está em modo privilegiado

### PVC Pendente
```bash
kubectl get pvc -n pnetlab
kubectl describe pvc pnetlab-data -n pnetlab
```
Verifique se o StorageClass existe e pode provisionar volumes.

### Sem Acesso Externo
1. Verifique se o Service está UP: `kubectl get svc -n pnetlab`
2. Verifique NetworkPolicies
3. Teste conectividade ao NodePort

## 📚 Referências

- [PNETLab Official](https://pnetlab.com/)
- [PNETLab Documentation](https://pnetlab.com/pages/documentation)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [KVM Nested Virtualization](https://www.linux-kvm.org/page/Nested_Guests)

## 📝 Notas de Segurança

1. **Secrets**: Altere todas as senhas padrão em `03-secrets.yaml`
2. **RBAC**: O pod roda como privilegiado (necessário para KVM)
3. **Network Policies**: Revise e ajuste conforme seu ambiente
4. **TLS**: Configure certificados para produção

## 📄 Licença

Este deployment é fornecido "as is" para uso educacional e laboratorial.
PNETLab é um produto independente com sua própria licença.
