#!/usr/bin/env ruby
# Kubernetes Microservices Architecture
# Demonstrates deploying microservices on Kubernetes with service mesh and monitoring

require 'terraform-synthesizer'
require 'json'

synth = TerraformSynthesizer.new

synth.synthesize do
  terraform do
    required_version ">= 1.0"
    required_providers do
      kubernetes do
        source "hashicorp/kubernetes"
        version "~> 2.16"
      end
      helm do
        source "hashicorp/helm"
        version "~> 2.8"
      end
      aws do
        source "hashicorp/aws"
        version "~> 5.0"
      end
    end
  end
  
  # Variables
  variable :cluster_name do
    description "Name of the Kubernetes cluster"
    type "string"
    default "microservices-cluster"
  end
  
  variable :environment do
    description "Environment (dev, staging, prod)"
    type "string"
    default "production"
  end
  
  variable :namespace do
    description "Kubernetes namespace for applications"
    type "string"
    default "microservices"
  end
  
  variable :enable_istio do
    description "Enable Istio service mesh"
    type "bool"
    default true
  end
  
  # Local values
  locals do
    common_labels do
      environment "${var.environment}"
      managed_by "terraform-synthesizer"
      cluster "${var.cluster_name}"
    end
    
    microservices [
      {
        name = "user-service"
        port = 8080
        replicas = 3
        image = "microservices/user-service:v1.0.0"
        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits = { cpu = "500m", memory = "512Mi" }
        }
      },
      {
        name = "product-service" 
        port = 8081
        replicas = 3
        image = "microservices/product-service:v1.0.0"
        resources = {
          requests = { cpu = "200m", memory = "256Mi" }
          limits = { cpu = "1000m", memory = "1Gi" }
        }
      },
      {
        name = "order-service"
        port = 8082
        replicas = 2
        image = "microservices/order-service:v1.0.0"
        resources = {
          requests = { cpu = "150m", memory = "192Mi" }
          limits = { cpu = "750m", memory = "768Mi" }
        }
      },
      {
        name = "notification-service"
        port = 8083
        replicas = 2
        image = "microservices/notification-service:v1.0.0"
        resources = {
          requests = { cpu = "50m", memory = "64Mi" }
          limits = { cpu = "200m", memory = "256Mi" }
        }
      }
    ]
  }
  
  provider :kubernetes do
    config_path "~/.kube/config"
  end
  
  provider :helm do
    kubernetes do
      config_path "~/.kube/config"
    end
  end
  
  provider :aws do
    region "us-west-2"
  end
  
  # Namespaces
  resource :kubernetes_namespace, :microservices do
    metadata do
      name "${var.namespace}"
      labels "${merge(local.common_labels, {
        name = var.namespace
        istio-injection = var.enable_istio ? \"enabled\" : \"disabled\"
      })}"
    end
  end
  
  resource :kubernetes_namespace, :monitoring do
    metadata do
      name "monitoring"
      labels local.common_labels
    end
  end
  
  resource :kubernetes_namespace, :istio_system do
    count "${var.enable_istio ? 1 : 0}"
    metadata do
      name "istio-system"
      labels local.common_labels
    end
  end
  
  # Config Maps
  resource :kubernetes_config_map, :app_config do
    metadata do
      name "app-config"
      namespace "${kubernetes_namespace.microservices.metadata.0.name}"
    end
    
    data do
      database_host "postgresql.${kubernetes_namespace.microservices.metadata.0.name}.svc.cluster.local"
      database_port "5432"
      redis_host "redis.${kubernetes_namespace.microservices.metadata.0.name}.svc.cluster.local"
      redis_port "6379"
      log_level "${var.environment == \"production\" ? \"INFO\" : \"DEBUG\"}"
      jaeger_agent_host "jaeger-agent.monitoring.svc.cluster.local"
    end
  end
  
  # Secrets
  resource :kubernetes_secret, :app_secrets do
    metadata do
      name "app-secrets"
      namespace "${kubernetes_namespace.microservices.metadata.0.name}"
    end
    
    type "Opaque"
    
    data do
      database_username "YXBwdXNlcg==" # base64 encoded "appuser"
      database_password "c3VwZXJzZWNyZXQ=" # base64 encoded "supersecret"
      jwt_secret "bXlqd3RzZWNyZXQ=" # base64 encoded "myjwtsecret"
      redis_password "cmVkaXNwYXNz=" # base64 encoded "redispass"
    end
  end
  
  # PostgreSQL Database
  resource :kubernetes_deployment, :postgresql do
    metadata do
      name "postgresql"
      namespace "${kubernetes_namespace.microservices.metadata.0.name}"
      labels "${merge(local.common_labels, { app = \"postgresql\" })}"
    end
    
    spec do
      replicas 1
      selector do
        match_labels do
          app "postgresql"
        end
      end
      
      template do
        metadata do
          labels "${merge(local.common_labels, { app = \"postgresql\" })}"
        end
        
        spec do
          container do
            image "postgres:13"
            name "postgresql"
            
            env do
              name "POSTGRES_DB"
              value "microservices"
            end
            
            env do
              name "POSTGRES_USER"
              value_from do
                secret_key_ref do
                  name "app-secrets"
                  key "database_username"
                end
              end
            end
            
            env do
              name "POSTGRES_PASSWORD"
              value_from do
                secret_key_ref do
                  name "app-secrets"
                  key "database_password"
                end
              end
            end
            
            port do
              container_port 5432
            end
            
            volume_mount do
              name "postgresql-data"
              mount_path "/var/lib/postgresql/data"
            end
            
            resources do
              requests do
                cpu "200m"
                memory "256Mi"
              end
              limits do
                cpu "500m"
                memory "512Mi"
              end
            end
          end
          
          volume do
            name "postgresql-data"
            persistent_volume_claim do
              claim_name "postgresql-pvc"
            end
          end
        end
      end
    end
  end
  
  resource :kubernetes_service, :postgresql do
    metadata do
      name "postgresql"
      namespace "${kubernetes_namespace.microservices.metadata.0.name}"
      labels "${merge(local.common_labels, { app = \"postgresql\" })}"
    end
    
    spec do
      selector do
        app "postgresql"
      end
      
      port do
        name "postgresql"
        port 5432
        target_port 5432
      end
      
      type "ClusterIP"
    end
  end
  
  # Redis Cache
  resource :kubernetes_deployment, :redis do
    metadata do
      name "redis"
      namespace "${kubernetes_namespace.microservices.metadata.0.name}"
      labels "${merge(local.common_labels, { app = \"redis\" })}"
    end
    
    spec do
      replicas 1
      selector do
        match_labels do
          app "redis"
        end
      end
      
      template do
        metadata do
          labels "${merge(local.common_labels, { app = \"redis\" })}"
        end
        
        spec do
          container do
            image "redis:7-alpine"
            name "redis"
            
            port do
              container_port 6379
            end
            
            resources do
              requests do
                cpu "100m"
                memory "128Mi"
              end
              limits do
                cpu "200m"
                memory "256Mi"
              end
            end
          end
        end
      end
    end
  end
  
  resource :kubernetes_service, :redis do
    metadata do
      name "redis"
      namespace "${kubernetes_namespace.microservices.metadata.0.name}"
      labels "${merge(local.common_labels, { app = \"redis\" })}"
    end
    
    spec do
      selector do
        app "redis"
      end
      
      port do
        name "redis"
        port 6379
        target_port 6379
      end
      
      type "ClusterIP"
    end
  end
  
  # Microservices Deployments and Services
  resource :kubernetes_deployment, :microservice do
    count "${length(local.microservices)}"
    
    metadata do
      name "${local.microservices[count.index].name}"
      namespace "${kubernetes_namespace.microservices.metadata.0.name}"
      labels "${merge(local.common_labels, { 
        app = local.microservices[count.index].name
        version = \"v1\"
      })}"
    end
    
    spec do
      replicas "${local.microservices[count.index].replicas}"
      selector do
        match_labels do
          app "${local.microservices[count.index].name}"
          version "v1"
        end
      end
      
      template do
        metadata do
          labels "${merge(local.common_labels, { 
            app = local.microservices[count.index].name
            version = \"v1\"
          })}"
          annotations "${var.enable_istio ? {
            \"sidecar.istio.io/inject\" = \"true\"
          } : {}}"
        end
        
        spec do
          container do
            name "${local.microservices[count.index].name}"
            image "${local.microservices[count.index].image}"
            
            port do
              container_port "${local.microservices[count.index].port}"
              name "http"
            end
            
            env_from do
              config_map_ref do
                name "app-config"
              end
            end
            
            env do
              name "SERVICE_NAME"
              value "${local.microservices[count.index].name}"
            end
            
            env do
              name "SERVICE_PORT"
              value "${local.microservices[count.index].port}"
            end
            
            resources do
              requests do
                cpu "${local.microservices[count.index].resources.requests.cpu}"
                memory "${local.microservices[count.index].resources.requests.memory}"
              end
              limits do
                cpu "${local.microservices[count.index].resources.limits.cpu}"
                memory "${local.microservices[count.index].resources.limits.memory}"
              end
            end
            
            liveness_probe do
              http_get do
                path "/health"
                port "http"
              end
              initial_delay_seconds 30
              period_seconds 10
            end
            
            readiness_probe do
              http_get do
                path "/ready"
                port "http"
              end
              initial_delay_seconds 5
              period_seconds 5
            end
          end
        end
      end
    end
  end
  
  resource :kubernetes_service, :microservice do
    count "${length(local.microservices)}"
    
    metadata do
      name "${local.microservices[count.index].name}"
      namespace "${kubernetes_namespace.microservices.metadata.0.name}"
      labels "${merge(local.common_labels, { 
        app = local.microservices[count.index].name
      })}"
    end
    
    spec do
      selector do
        app "${local.microservices[count.index].name}"
      end
      
      port do
        name "http"
        port 80
        target_port "${local.microservices[count.index].port}"
      end
      
      type "ClusterIP"
    end
  end
  
  # Horizontal Pod Autoscalers
  resource :kubernetes_horizontal_pod_autoscaler_v2, :microservice_hpa do
    count "${length(local.microservices)}"
    
    metadata do
      name "${local.microservices[count.index].name}-hpa"
      namespace "${kubernetes_namespace.microservices.metadata.0.name}"
    end
    
    spec do
      scale_target_ref do
        api_version "apps/v1"
        kind "Deployment"
        name "${local.microservices[count.index].name}"
      end
      
      min_replicas "${local.microservices[count.index].replicas}"
      max_replicas "${local.microservices[count.index].replicas * 3}"
      
      metric do
        type "Resource"
        resource do
          name "cpu"
          target do
            type "Utilization"
            average_utilization 70
          end
        end
      end
      
      metric do
        type "Resource"
        resource do
          name "memory"
          target do
            type "Utilization"
            average_utilization 80
          end
        end
      end
    end
  end
  
  # API Gateway Service
  resource :kubernetes_deployment, :api_gateway do
    metadata do
      name "api-gateway"
      namespace "${kubernetes_namespace.microservices.metadata.0.name}"
      labels "${merge(local.common_labels, { 
        app = \"api-gateway\"
        version = \"v1\"
      })}"
    end
    
    spec do
      replicas 2
      selector do
        match_labels do
          app "api-gateway"
          version "v1"
        end
      end
      
      template do
        metadata do
          labels "${merge(local.common_labels, { 
            app = \"api-gateway\"
            version = \"v1\"
          })}"
          annotations "${var.enable_istio ? {
            \"sidecar.istio.io/inject\" = \"true\"
          } : {}}"
        end
        
        spec do
          container do
            name "api-gateway"
            image "microservices/api-gateway:v1.0.0"
            
            port do
              container_port 8080
              name "http"
            end
            
            env_from do
              config_map_ref do
                name "app-config"
              end
            end
            
            env do
              name "USER_SERVICE_URL"
              value "http://user-service.${kubernetes_namespace.microservices.metadata.0.name}.svc.cluster.local"
            end
            
            env do
              name "PRODUCT_SERVICE_URL"
              value "http://product-service.${kubernetes_namespace.microservices.metadata.0.name}.svc.cluster.local"
            end
            
            env do
              name "ORDER_SERVICE_URL"
              value "http://order-service.${kubernetes_namespace.microservices.metadata.0.name}.svc.cluster.local"
            end
            
            resources do
              requests do
                cpu "200m"
                memory "256Mi"
              end
              limits do
                cpu "500m"
                memory "512Mi"
              end
            end
            
            liveness_probe do
              http_get do
                path "/health"
                port "http"
              end
              initial_delay_seconds 30
              period_seconds 10
            end
            
            readiness_probe do
              http_get do
                path "/ready"
                port "http"
              end
              initial_delay_seconds 5
              period_seconds 5
            end
          end
        end
      end
    end
  end
  
  resource :kubernetes_service, :api_gateway do
    metadata do
      name "api-gateway"
      namespace "${kubernetes_namespace.microservices.metadata.0.name}"
      labels "${merge(local.common_labels, { app = \"api-gateway\" })}"
    end
    
    spec do
      selector do
        app "api-gateway"
      end
      
      port do
        name "http"
        port 80
        target_port 8080
      end
      
      type "LoadBalancer"
    end
  end
  
  # Ingress
  resource :kubernetes_ingress_v1, :api_gateway do
    count "${var.enable_istio ? 0 : 1}"
    
    metadata do
      name "api-gateway-ingress"
      namespace "${kubernetes_namespace.microservices.metadata.0.name}"
      annotations do
        "kubernetes.io/ingress.class" "nginx"
        "cert-manager.io/cluster-issuer" "letsencrypt-prod"
      end
    end
    
    spec do
      tls do
        hosts ["api.${var.cluster_name}.example.com"]
        secret_name "api-gateway-tls"
      end
      
      rule do
        host "api.${var.cluster_name}.example.com"
        http do
          path do
            path "/"
            path_type "Prefix"
            backend do
              service do
                name "api-gateway"
                port do
                  number 80
                end
              end
            end
          end
        end
      end
    end
  end
  
  # Istio Service Mesh (if enabled)
  resource :helm_release, :istio_base do
    count "${var.enable_istio ? 1 : 0}"
    name "istio-base"
    repository "https://istio-release.storage.googleapis.com/charts"
    chart "base"
    namespace "${kubernetes_namespace.istio_system[0].metadata.0.name}"
    version "1.19.3"
    
    set do
      name "global.istioNamespace"
      value "${kubernetes_namespace.istio_system[0].metadata.0.name}"
    end
  end
  
  resource :helm_release, :istiod do
    count "${var.enable_istio ? 1 : 0}"
    name "istiod"
    repository "https://istio-release.storage.googleapis.com/charts"
    chart "istiod"
    namespace "${kubernetes_namespace.istio_system[0].metadata.0.name}"
    version "1.19.3"
    
    depends_on ["helm_release.istio_base"]
  end
  
  # Monitoring Stack
  resource :helm_release, :prometheus do
    name "prometheus"
    repository "https://prometheus-community.github.io/helm-charts"
    chart "kube-prometheus-stack"
    namespace "${kubernetes_namespace.monitoring.metadata.0.name}"
    version "51.2.0"
    
    values [<<-EOF
      grafana:
        enabled: true
        adminPassword: admin123
        service:
          type: LoadBalancer
        datasources:
          datasources.yaml:
            apiVersion: 1
            datasources:
              - name: Prometheus
                type: prometheus
                url: http://prometheus-server:80
                access: proxy
                isDefault: true
              - name: Jaeger
                type: jaeger
                url: http://jaeger-query.monitoring:16686
                access: proxy
      
      prometheus:
        prometheusSpec:
          retention: 30d
          storageSpec:
            volumeClaimTemplate:
              spec:
                accessModes: ["ReadWriteOnce"]
                resources:
                  requests:
                    storage: 50Gi
    EOF
    ]
  end
  
  # Jaeger for distributed tracing
  resource :helm_release, :jaeger do
    name "jaeger"
    repository "https://jaegertracing.github.io/helm-charts"
    chart "jaeger"
    namespace "${kubernetes_namespace.monitoring.metadata.0.name}"
    version "0.71.2"
    
    values [<<-EOF
      provisionDataStore:
        cassandra: false
        elasticsearch: true
      
      elasticsearch:
        replicas: 1
        minimumMasterNodes: 1
        resources:
          requests:
            cpu: 100m
            memory: 512Mi
          limits:
            cpu: 500m
            memory: 1Gi
      
      agent:
        service:
          type: ClusterIP
      
      query:
        service:
          type: LoadBalancer
    EOF
    ]
  end
  
  # Network Policies for security
  resource :kubernetes_network_policy, :microservices_network_policy do
    metadata do
      name "microservices-network-policy"
      namespace "${kubernetes_namespace.microservices.metadata.0.name}"
    end
    
    spec do
      pod_selector do
        match_labels do
          environment "${var.environment}"
        end
      end
      
      policy_types ["Ingress", "Egress"]
      
      ingress do
        from do
          namespace_selector do
            match_labels do
              name "${kubernetes_namespace.microservices.metadata.0.name}"
            end
          end
        end
        
        ports do
          protocol "TCP"
          port "8080"
        end
        ports do
          protocol "TCP"
          port "8081"
        end
        ports do
          protocol "TCP"
          port "8082"
        end
        ports do
          protocol "TCP"
          port "8083"
        end
      end
      
      egress do
        to do
          namespace_selector do
            match_labels do
              name "${kubernetes_namespace.microservices.metadata.0.name}"
            end
          end
        end
        
        # Allow DNS
        ports do
          protocol "UDP"
          port "53"
        end
        ports do
          protocol "TCP"
          port "53"
        end
      end
    end
  end
  
  # Outputs
  output :namespace do
    description "Microservices namespace"
    value "${kubernetes_namespace.microservices.metadata.0.name}"
  end
  
  output :api_gateway_service do
    description "API Gateway service name"
    value "${kubernetes_service.api_gateway.metadata.0.name}"
  end
  
  output :microservices do
    description "List of deployed microservices"
    value "${local.microservices[*].name}"
  end
  
  output :database_service do
    description "PostgreSQL database service"
    value "${kubernetes_service.postgresql.metadata.0.name}"
  end
  
  output :redis_service do
    description "Redis cache service"
    value "${kubernetes_service.redis.metadata.0.name}"
  end
  
  output :monitoring_namespace do
    description "Monitoring namespace"
    value "${kubernetes_namespace.monitoring.metadata.0.name}"
  end
end

# Output the generated Terraform configuration
puts JSON.pretty_generate(synth.synthesis)