resource "kubernetes_role" "linkerd_psp" {
  metadata {
    name      = "linkerd-psp"
    namespace = local.linkerd_namespace
    labels    = local.linkerd_label_control_plane_ns
  }
  rule {
    verbs          = ["use"]
    api_groups     = ["policy", "extensions"]
    resources      = ["podsecuritypolicies"]
    resource_names = ["linkerd-linkerd-control-plane"]
  }
}

resource "kubernetes_role_binding" "linkerd_psp" {
  metadata {
    name      = "linkerd-psp"
    namespace = local.linkerd_namespace
    labels    = local.linkerd_label_control_plane_ns
  }
  subject {
    kind      = "ServiceAccount"
    name      = local.linkerd_controller_name
    namespace = local.linkerd_namespace
  }
  subject {
    kind      = "ServiceAccount"
    name      = local.linkerd_destination_name
    namespace = local.linkerd_namespace
  }
  subject {
    kind      = "ServiceAccount"
    name      = local.linkerd_grafana_name
    namespace = local.linkerd_namespace
  }
  subject {
    kind      = "ServiceAccount"
    name      = local.linkerd_heartbeat_name
    namespace = local.linkerd_namespace
  }
  subject {
    kind      = "ServiceAccount"
    name      = local.linkerd_identity_name
    namespace = local.linkerd_namespace
  }
  subject {
    kind      = "ServiceAccount"
    name      = local.linkerd_prometheus_name
    namespace = local.linkerd_namespace
  }
  subject {
    kind      = "ServiceAccount"
    name      = local.linkerd_proxy_injector_name
    namespace = local.linkerd_namespace
  }
  subject {
    kind      = "ServiceAccount"
    name      = local.linkerd_sp_validator_name
    namespace = local.linkerd_namespace
  }
  subject {
    kind      = "ServiceAccount"
    name      = local.linkerd_tap_name
    namespace = local.linkerd_namespace
  }
  subject {
    kind      = "ServiceAccount"
    name      = local.linkerd_web_name
    namespace = local.linkerd_namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "linkerd-psp"
  }
}

resource "kubernetes_cluster_role" "linkerd_controller" {
  metadata {
    name = "linkerd-linkerd-controller"
    labels = merge(local.linkerd_label_control_plane_ns, {
      "linkerd.io/control-plane-component" = local.linkerd_component_controller_name
    })
  }
  rule {
    verbs      = ["list", "get", "watch"]
    api_groups = ["extensions", "apps"]
    resources  = ["daemonsets", "deployments", "replicasets", "statefulsets"]
  }
  rule {
    verbs      = ["list", "get", "watch"]
    api_groups = ["extensions", "batch"]
    resources  = ["cronjobs", "jobs"]
  }
  rule {
    verbs      = ["list", "get", "watch"]
    api_groups = [""]
    resources  = ["pods", "endpoints", "services", "replicationcontrollers", "namespaces"]
  }
  rule {
    verbs      = ["list", "get", "watch"]
    api_groups = ["linkerd.io"]
    resources  = ["serviceprofiles"]
  }
  rule {
    verbs      = ["list", "get", "watch"]
    api_groups = ["split.smi-spec.io"]
    resources  = ["trafficsplits"]
  }
}

resource "kubernetes_cluster_role_binding" "linkerd_controller" {
  metadata {
    name = "linkerd-linkerd-controller"
    labels = merge(local.linkerd_label_control_plane_ns, {
      "linkerd.io/control-plane-component" = local.linkerd_component_controller_name
    })
  }
  subject {
    kind      = "ServiceAccount"
    name      = local.linkerd_controller_name
    namespace = local.linkerd_namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "linkerd-linkerd-controller"
  }
}

resource "kubernetes_service_account" "linkerd_controller" {
  metadata {
    name      = local.linkerd_controller_name
    namespace = local.linkerd_namespace
    labels    = merge(local.linkerd_label_control_plane_ns, {
      "linkerd.io/control-plane-component" = local.linkerd_component_controller_name
    })
  }
}

resource "kubernetes_deployment" "linkerd_controller" {
  depends_on = [
    kubernetes_cluster_role.linkerd_controller,
    kubernetes_cluster_role_binding.linkerd_controller,
    kubernetes_service_account.linkerd_controller,
    kubernetes_role.linkerd_psp,
    kubernetes_role_binding.linkerd_psp
  ]

  metadata {
    name      = local.linkerd_controller_name
    namespace = local.linkerd_namespace
    labels    = merge(
      local.linkerd_label_control_plane_ns,
      local.linkerd_label_partof_version,
      {
        "app.kubernetes.io/name"             = local.linkerd_component_controller_name,
        "linkerd.io/control-plane-component" = local.linkerd_component_controller_name
      }
    )
    annotations = local.linkerd_annotation_created_by
  }
  spec {
    replicas = 1
    selector {
      match_labels = merge(local.linkerd_label_control_plane_ns, {
        "linkerd.io/control-plane-component" = local.linkerd_component_controller_name,
        "linkerd.io/proxy-deployment"        = local.linkerd_controller_name
      })
    }
    template {
      metadata {
        labels = merge(
          local.linkerd_label_control_plane_ns,
          local.linkerd_label_workload_ns,
          {
            "linkerd.io/control-plane-component" = local.linkerd_component_controller_name,
            "linkerd.io/proxy-deployment"        = local.linkerd_controller_name,
          }
        )
        annotations = local.linkerd_annotations_for_deployment
      }
      spec {
        volume {
          name = "config"
          config_map {
            name = "linkerd-config"
          }
        }
        volume {
          name = "linkerd-identity-end-entity"
          empty_dir {
            medium = "Memory"
          }
        }
        automount_service_account_token = var.automount_service_account_token
        init_container {
          name  = "linkerd-init"
          image =  local.linkerd_deployment_proxy_init_image
          args = [
            "--incoming-proxy-port",
            "${local.linkerd_deployment_incoming_proxy_port}",
            "--outgoing-proxy-port",
            "${local.linkerd_deployment_outgoing_proxy_port}",
            "--proxy-uid",
            "${local.linkerd_deployment_proxy_uid}",
            "--inbound-ports-to-ignore",
            "${local.linkerd_deployment_proxy_control_port},${local.linkerd_deployment_admin_port}",
            "--outbound-ports-to-ignore",
            "${local.linkerd_deployment_outbound_port}"
          ]
          resources {
            limits {
              cpu    = "100m"
              memory = "50Mi"
            }
            requests {
              cpu    = "10m"
              memory = "10Mi"
            }
          }
          image_pull_policy = "IfNotPresent"
          security_context {
            capabilities {
              add = ["NET_ADMIN", "NET_RAW"]
            }
            read_only_root_filesystem = true
          }
        }
        container {
          name  = "public-api"
          image =  local.linkerd_deployment_controller_image
          args = [
            "public-api",
            "-prometheus-url=http://linkerd-prometheus.linkerd.svc.cluster.local:9090",
            "-destination-addr=linkerd-dst.linkerd.svc.cluster.local:8086",
            "-controller-namespace=linkerd",
            "-log-level=info"
          ]
          port {
            name           = "http"
            container_port = 8085
          }
          port {
            name           = "admin-http"
            container_port = 9995
          }
          resources {
            limits {
              cpu    = "1"
              memory = "250Mi"
            }
            requests {
              cpu    = "100m"
              memory = "50Mi"
            }
          }
          volume_mount {
            name       = "config"
            mount_path = "/var/run/linkerd/config"
          }
          liveness_probe {
            http_get {
              path = "/ping"
              port = "9995"
            }
            initial_delay_seconds = 10
          }
          readiness_probe {
            http_get {
              path = "/ready"
              port = "9995"
            }
            failure_threshold = 7
          }
          image_pull_policy = "IfNotPresent"
          security_context {
            run_as_user = 2103
          }
        }
        container {
          name  = "linkerd-proxy"
          image = local.linkerd_deployment_proxy_image
          port {
            name           = "linkerd-proxy"
            container_port = local.linkerd_deployment_incoming_proxy_port
          }
          port {
            name           = "linkerd-admin"
            container_port = local.linkerd_deployment_admin_port
          }
          env {
            name  = "LINKERD2_PROXY_LOG"
            value = "warn,linkerd=info"
          }
          env {
            name  = "LINKERD2_PROXY_DESTINATION_SVC_ADDR"
            value = "linkerd-dst.linkerd.svc.cluster.local:8086"
          }
          env {
            name  = "LINKERD2_PROXY_DESTINATION_GET_NETWORKS"
            value = "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
          }
          env {
            name  = "LINKERD2_PROXY_CONTROL_LISTEN_ADDR"
            value = "0.0.0.0:${local.linkerd_deployment_proxy_control_port}"
          }
          env {
            name  = "LINKERD2_PROXY_ADMIN_LISTEN_ADDR"
            value = "0.0.0.0:${local.linkerd_deployment_admin_port}"
          }
          env {
            name  = "LINKERD2_PROXY_OUTBOUND_LISTEN_ADDR"
            value = "127.0.0.1:4140"
          }
          env {
            name  = "LINKERD2_PROXY_INBOUND_LISTEN_ADDR"
            value = "0.0.0.0:${local.linkerd_deployment_incoming_proxy_port}"
          }
          env {
            name  = "LINKERD2_PROXY_DESTINATION_GET_SUFFIXES"
            value = "svc.cluster.local."
          }
          env {
            name  = "LINKERD2_PROXY_DESTINATION_PROFILE_SUFFIXES"
            value = "svc.cluster.local."
          }
          env {
            name  = "LINKERD2_PROXY_INBOUND_ACCEPT_KEEPALIVE"
            value = "10000ms"
          }
          env {
            name  = "LINKERD2_PROXY_OUTBOUND_CONNECT_KEEPALIVE"
            value = "10000ms"
          }
          env {
            name = "_pod_ns"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }
          env {
            name  = "LINKERD2_PROXY_DESTINATION_CONTEXT"
            value = "ns:$(_pod_ns)"
          }
          env {
            name  = "LINKERD2_PROXY_IDENTITY_DIR"
            value = "/var/run/linkerd/identity/end-entity"
          }
          env {
            name  = "LINKERD2_PROXY_IDENTITY_TRUST_ANCHORS"
            value = file("${path.module}/certs/proxy_trust_anchor.pem")
          }
          env {
            name  = "LINKERD2_PROXY_IDENTITY_TOKEN_FILE"
            value = "/var/run/secrets/kubernetes.io/serviceaccount/token"
          }
          env {
            name  = "LINKERD2_PROXY_IDENTITY_SVC_ADDR"
            value = "linkerd-identity.linkerd.svc.cluster.local:8080"
          }
          env {
            name = "_pod_sa"
            value_from {
              field_ref {
                field_path = "spec.serviceAccountName"
              }
            }
          }
          env {
            name  = "_l5d_ns"
            value = "linkerd"
          }
          env {
            name  = "_l5d_trustdomain"
            value = "cluster.local"
          }
          env {
            name  = "LINKERD2_PROXY_IDENTITY_LOCAL_NAME"
            value = "$(_pod_sa).$(_pod_ns).serviceaccount.identity.$(_l5d_ns).$(_l5d_trustdomain)"
          }
          env {
            name  = "LINKERD2_PROXY_IDENTITY_SVC_NAME"
            value = "linkerd-identity.$(_l5d_ns).serviceaccount.identity.$(_l5d_ns).$(_l5d_trustdomain)"
          }
          env {
            name  = "LINKERD2_PROXY_DESTINATION_SVC_NAME"
            value = "linkerd-destination.$(_l5d_ns).serviceaccount.identity.$(_l5d_ns).$(_l5d_trustdomain)"
          }
          env {
            name  = "LINKERD2_PROXY_TAP_SVC_NAME"
            value = "linkerd-tap.$(_l5d_ns).serviceaccount.identity.$(_l5d_ns).$(_l5d_trustdomain)"
          }
          resources {
            limits {
              cpu    = "1"
              memory = "250Mi"
            }
            requests {
              cpu    = "100m"
              memory = "20Mi"
            }
          }
          volume_mount {
            name       = "linkerd-identity-end-entity"
            mount_path = "/var/run/linkerd/identity/end-entity"
          }
          liveness_probe {
            http_get {
              path = "/live"
              port = local.linkerd_deployment_admin_port
            }
            initial_delay_seconds = 10
          }
          readiness_probe {
            http_get {
              path = "/ready"
              port = local.linkerd_deployment_admin_port
            }
            initial_delay_seconds = 2
          }
          image_pull_policy = "IfNotPresent"
          security_context {
            run_as_user               = 2102
            read_only_root_filesystem = true
          }
        }
        node_selector        = { "beta.kubernetes.io/os" = "linux" }
        service_account_name = local.linkerd_controller_name
        dynamic "affinity" {
          for_each = var.high_availability == true ? [map("ha", true)] : []

          content {
            pod_anti_affinity {
              required_during_scheduling_ignored_during_execution {
                label_selector {
                  match_expressions {
                    key      = "linkerd.io/control-plane-component"
                    operator = "In"
                    values   = [local.linkerd_component_controller_name]
                  }
                }
                topology_key = "kubernetes.io/hostname"
              }
              preferred_during_scheduling_ignored_during_execution {
                weight = 100
                pod_affinity_term {
                  label_selector {
                    match_expressions {
                      key      = "linkerd.io/control-plane-component"
                      operator = "In"
                      values   = [local.linkerd_component_controller_name]
                    }
                  }
                  topology_key = "failure-domain.beta.kubernetes.io/zone"
                }
              }
            }
          }
        }
      }
    }
    strategy {
      rolling_update {
        max_unavailable = "1"
      }
    }
  }
}

resource "kubernetes_service" "linkerd_controller_api" {
  depends_on = [
    kubernetes_cluster_role.linkerd_controller,
    kubernetes_cluster_role_binding.linkerd_controller,
    kubernetes_service_account.linkerd_controller,
    kubernetes_role.linkerd_psp,
    kubernetes_role_binding.linkerd_psp
  ]

  metadata {
    name      = "linkerd-controller-api"
    namespace = local.linkerd_namespace
    labels    = merge(local.linkerd_label_control_plane_ns, {
      "linkerd.io/control-plane-component" = local.linkerd_component_controller_name
    })
    annotations = local.linkerd_annotation_created_by
  }
  spec {
    type = "ClusterIP"
    port {
      name        = "http"
      port        = 8085
      target_port = "8085"
    }
    selector = {
      "linkerd.io/control-plane-component" = local.linkerd_component_controller_name
    }
  }
}
