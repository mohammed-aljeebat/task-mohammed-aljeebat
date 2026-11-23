resource "kubernetes_namespace_v1" "ci" {
  metadata {
    name = var.jenkins_namespace
  }
}

resource "kubernetes_namespace_v1" "quest" {
  metadata {
    name = "quest"
  }
}

resource "kubernetes_service_account_v1" "jenkins" {
  metadata {
    name      = "jenkins"
    namespace = kubernetes_namespace_v1.ci.metadata[0].name
  }
}

resource "kubernetes_role_v1" "jenkins_agents" {
  metadata {
    name      = "jenkins-agents"
    namespace = kubernetes_namespace_v1.ci.metadata[0].name
  }
  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log", "pods/exec"]
    verbs      = ["create", "delete", "get", "list", "watch"]
  }
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_role_binding_v1" "jenkins_agents" {
  metadata {
    name      = "jenkins-agents"
    namespace = kubernetes_namespace_v1.ci.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.jenkins_agents.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.jenkins.metadata[0].name
    namespace = var.jenkins_namespace
  }
}

resource "kubernetes_service_account_v1" "jenkins_deployer" {
  metadata {
    name      = "jenkins-deployer"
    namespace = "quest"
  }
  depends_on = [kubernetes_namespace_v1.quest]
}

resource "kubernetes_role_v1" "jenkins_deployer" {
  metadata {
    name      = "jenkins-deployer"
    namespace = "quest"
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["get", "list", "watch", "create", "patch", "update"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = [""]
    resources  = ["services", "configmaps"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }
}

resource "kubernetes_role_binding_v1" "jenkins_deployer" {
  metadata {
    name      = "jenkins-deployer"
    namespace = "quest"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.jenkins_deployer.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.jenkins_deployer.metadata[0].name
    namespace = "quest"
  }
}
