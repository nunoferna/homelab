locals {
  # renovate: datasource=github-releases depName=kubernetes-sigs/gateway-api
  gateway_api_version = "v1.2.1"
}

resource "null_resource" "gateway_api_crds" {
  triggers = {
    version = local.gateway_api_version
  }

  provisioner "local-exec" {
    command = "kubectl --kubeconfig='${pathexpand(var.kubeconfig_path)}' apply -f 'https://github.com/kubernetes-sigs/gateway-api/releases/download/${local.gateway_api_version}/standard-install.yaml'"
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
  version          = "9.5.18"
  namespace        = "argocd"
  create_namespace = true

  wait    = true
  timeout = 600

  values = [
    file("${path.module}/values/argocd.yaml"),
    yamlencode({
      extraObjects = [
        {
          apiVersion = "argoproj.io/v1alpha1"
          kind       = "Application"
          metadata = {
            name      = "root"
            namespace = "argocd"
          }
          spec = {
            project = "default"
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
        }
      ]
    })
  ]

  depends_on = [helm_release.cilium]
}
