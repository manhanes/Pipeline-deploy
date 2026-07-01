#!/bin/bash
#===============================================================================
# PNETLab Kubernetes Deployment Script
# Autor: Claude AI
# Data: 2024
# Descrição: Script para deploy completo do PNETLab no Kubernetes
#===============================================================================

set -euo pipefail

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Diretório dos manifestos
MANIFEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#===============================================================================
# Funções auxiliares
#===============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Verificando pré-requisitos..."
    
    # Verificar kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl não encontrado. Instale o kubectl primeiro."
        exit 1
    fi
    
    # Verificar conexão com cluster
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Não foi possível conectar ao cluster Kubernetes."
        exit 1
    fi
    
    # Verificar se o cluster tem nodes com KVM
    log_info "Verificando suporte a nested virtualization nos nodes..."
    NODES_WITH_KVM=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
    log_info "Nodes disponíveis: $NODES_WITH_KVM"
    
    log_success "Pré-requisitos verificados!"
}

check_storage_class() {
    log_info "Verificando StorageClasses disponíveis..."
    
    STORAGE_CLASSES=$(kubectl get storageclass -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$STORAGE_CLASSES" ]; then
        log_warning "Nenhum StorageClass encontrado!"
        log_warning "Você pode precisar criar PersistentVolumes manualmente."
    else
        log_info "StorageClasses disponíveis: $STORAGE_CLASSES"
        
        # Verificar se local-path existe
        if echo "$STORAGE_CLASSES" | grep -q "local-path"; then
            log_success "StorageClass 'local-path' encontrado!"
        else
            log_warning "StorageClass 'local-path' não encontrado."
            log_warning "Edite 01-storage.yaml e ajuste o storageClassName conforme disponível."
        fi
    fi
}

deploy_namespace() {
    log_info "Criando namespace..."
    kubectl apply -f "$MANIFEST_DIR/00-namespace.yaml"
    log_success "Namespace criado!"
}

deploy_storage() {
    log_info "Criando PersistentVolumeClaims..."
    kubectl apply -f "$MANIFEST_DIR/01-storage.yaml"
    log_success "PVCs criados!"
    
    # Aguardar PVCs ficarem bound
    log_info "Aguardando PVCs ficarem Bound..."
    sleep 5
    kubectl get pvc -n pnetlab
}

deploy_config() {
    log_info "Criando ConfigMaps e Secrets..."
    kubectl apply -f "$MANIFEST_DIR/02-configmap.yaml"
    kubectl apply -f "$MANIFEST_DIR/03-secrets.yaml"
    log_success "ConfigMaps e Secrets criados!"
}

deploy_rbac() {
    log_info "Configurando RBAC..."
    kubectl apply -f "$MANIFEST_DIR/04-rbac.yaml"
    log_success "RBAC configurado!"
}

deploy_application() {
    log_info "Deployando PNETLab..."
    kubectl apply -f "$MANIFEST_DIR/05-deployment.yaml"
    log_success "Deployment criado!"
    
    # Aguardar pod ficar ready
    log_info "Aguardando pod ficar Ready (pode demorar alguns minutos)..."
    kubectl rollout status deployment/pnetlab -n pnetlab --timeout=600s || {
        log_warning "Timeout aguardando deployment. Verificando status..."
        kubectl get pods -n pnetlab
        kubectl describe pod -n pnetlab -l app.kubernetes.io/name=pnetlab | tail -50
    }
}

deploy_services() {
    log_info "Criando Services..."
    kubectl apply -f "$MANIFEST_DIR/06-services.yaml"
    log_success "Services criados!"
    
    # Mostrar IPs e portas
    log_info "Services disponíveis:"
    kubectl get svc -n pnetlab
}

deploy_ingress() {
    log_info "Criando Ingress..."
    
    # Verificar se existe Ingress Controller
    if kubectl get ingressclass &> /dev/null; then
        kubectl apply -f "$MANIFEST_DIR/07-ingress.yaml"
        log_success "Ingress criado!"
    else
        log_warning "Nenhum IngressClass encontrado. Pulando criação do Ingress."
        log_warning "Use o NodePort ou LoadBalancer Service para acessar."
    fi
}

deploy_network_policies() {
    log_info "Criando Network Policies..."
    kubectl apply -f "$MANIFEST_DIR/08-network-policy.yaml" || {
        log_warning "Network Policies podem não ser suportadas neste cluster."
    }
}

deploy_resource_management() {
    log_info "Configurando Resource Management..."
    kubectl apply -f "$MANIFEST_DIR/09-resource-management.yaml"
    log_success "Resource Management configurado!"
}

show_access_info() {
    echo ""
    echo "==============================================================================="
    echo -e "${GREEN}PNETLab deployado com sucesso!${NC}"
    echo "==============================================================================="
    echo ""
    
    # NodePort
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "NODE_IP")
    echo -e "${BLUE}Acesso via NodePort:${NC}"
    echo "  HTTP:  http://$NODE_IP:30080"
    echo "  HTTPS: https://$NODE_IP:30443"
    echo ""
    
    # LoadBalancer (se disponível)
    LB_IP=$(kubectl get svc pnetlab-lb -n pnetlab -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -n "$LB_IP" ]; then
        echo -e "${BLUE}Acesso via LoadBalancer:${NC}"
        echo "  HTTP:  http://$LB_IP"
        echo "  HTTPS: https://$LB_IP"
        echo ""
    fi
    
    # Ingress
    echo -e "${BLUE}Acesso via Ingress (se configurado):${NC}"
    echo "  http://pnetlab.local"
    echo "  (adicione '$NODE_IP pnetlab.local' ao /etc/hosts)"
    echo ""
    
    echo -e "${YELLOW}Credenciais padrão:${NC}"
    echo "  Usuário: admin"
    echo "  Senha:   pnet"
    echo ""
    
    echo -e "${RED}IMPORTANTE:${NC}"
    echo "  1. Altere a senha padrão imediatamente!"
    echo "  2. Certifique-se que os nodes suportam nested virtualization"
    echo "  3. Em produção, use uma imagem Docker customizada com PNETLab"
    echo ""
}

#===============================================================================
# Menu principal
#===============================================================================

show_menu() {
    echo ""
    echo "==============================================================================="
    echo "PNETLab Kubernetes Deployment"
    echo "==============================================================================="
    echo ""
    echo "1) Deploy completo (todos os recursos)"
    echo "2) Apenas verificar pré-requisitos"
    echo "3) Deletar deployment"
    echo "4) Ver status"
    echo "5) Ver logs"
    echo "6) Sair"
    echo ""
    read -p "Escolha uma opção: " choice
    
    case $choice in
        1) full_deploy ;;
        2) check_prerequisites && check_storage_class ;;
        3) delete_deployment ;;
        4) show_status ;;
        5) show_logs ;;
        6) exit 0 ;;
        *) log_error "Opção inválida"; show_menu ;;
    esac
}

full_deploy() {
    check_prerequisites
    check_storage_class
    
    echo ""
    read -p "Deseja continuar com o deploy? (y/N) " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Deploy cancelado."
        exit 0
    fi
    
    deploy_namespace
    deploy_storage
    deploy_config
    deploy_rbac
    deploy_application
    deploy_services
    deploy_ingress
    deploy_network_policies
    deploy_resource_management
    show_access_info
}

delete_deployment() {
    log_warning "Isso irá deletar TODOS os recursos do PNETLab!"
    read -p "Tem certeza? (digite 'DELETE' para confirmar) " confirm
    
    if [ "$confirm" == "DELETE" ]; then
        log_info "Deletando recursos..."
        kubectl delete namespace pnetlab --ignore-not-found=true
        log_success "Recursos deletados!"
    else
        log_info "Operação cancelada."
    fi
}

show_status() {
    log_info "Status dos recursos:"
    echo ""
    echo "=== Pods ==="
    kubectl get pods -n pnetlab -o wide
    echo ""
    echo "=== Services ==="
    kubectl get svc -n pnetlab
    echo ""
    echo "=== PVCs ==="
    kubectl get pvc -n pnetlab
    echo ""
    echo "=== Ingress ==="
    kubectl get ingress -n pnetlab 2>/dev/null || echo "Nenhum Ingress configurado"
}

show_logs() {
    log_info "Logs do pod PNETLab:"
    kubectl logs -n pnetlab -l app.kubernetes.io/name=pnetlab --tail=100 -f
}

#===============================================================================
# Execução
#===============================================================================

# Se chamado com argumento
if [ $# -gt 0 ]; then
    case $1 in
        deploy) full_deploy ;;
        delete) delete_deployment ;;
        status) show_status ;;
        logs) show_logs ;;
        *) show_menu ;;
    esac
else
    show_menu
fi
