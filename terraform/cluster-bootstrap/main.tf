locals {
  gateway_api_version = "v1.4.1"
}

resource "null_resource" "gateway_api_crds" {
  triggers = {
    version = local.gateway_api_version
  }

  provisioner "local-exec" {
    command = "kubectl --kubeconfig='${pathexpand(var.kubeconfig_path)}' apply --server-side --force-conflicts -f 'https://github.com/kubernetes-sigs/gateway-api/releases/download/${local.gateway_api_version}/experimental-install.yaml'"
  }
}

resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "oci://quay.io/cilium/charts"
  chart      = "cilium"
  version    = "1.19.4"
  namespace  = "kube-system"

  wait    = true
  timeout = 600

  values = [
    file("${path.module}/values/cilium.yaml"),
    yamlencode({
      k8sServiceHost = var.cilium_k8s_service_host
      k8sServicePort = var.cilium_k8s_service_port
    })
  ]

  depends_on = [null_resource.gateway_api_crds]
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "oci://ghcr.io/argoproj/argo-helm"
  chart            = "argo-cd"
  version          = "9.5.19"
  namespace        = "argocd"
  create_namespace = true

  wait    = true
  timeout = 600

  values = [
    file("${path.module}/values/argocd.yaml")
  ]

  depends_on = [helm_release.cilium]
}

resource "helm_release" "argocd_bootstrap" {
  name       = "argocd-bootstrap"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.5"
  namespace  = "argocd"

  wait    = true
  timeout = 300

  values = [
    yamlencode({
      projects = [
        {
          name        = "bootstrap"
          namespace   = "argocd"
          description = "Argo CD bootstrap resources"
          sourceRepos = [var.repo_url]
          destinations = [
            {
              namespace = "argocd"
              server    = "https://kubernetes.default.svc"
            }
          ]
          namespaceResourceWhitelist = [
            {
              group = "argoproj.io"
              kind  = "Application"
            },
            {
              group = "argoproj.io"
              kind  = "ApplicationSet"
            },
            {
              group = "argoproj.io"
              kind  = "AppProject"
            }
          ]
          orphanedResources = {
            warn = true
          }
        }
      ]
      applications = [
        {
          name      = "root"
          namespace = "argocd"
          project   = "bootstrap"
          source = {
            repoURL        = var.repo_url
            targetRevision = var.repo_revision
            path           = "gitops/bootstrap"
          }
          destination = {
            server    = "https://kubernetes.default.svc"
            namespace = "argocd"
          }
          syncPolicy = {
            automated = {
              prune    = true
              selfHeal = true
            }
            syncOptions = ["CreateNamespace=true"]
          }
        }
      ]
    })
  ]

  depends_on = [helm_release.argocd]
}
