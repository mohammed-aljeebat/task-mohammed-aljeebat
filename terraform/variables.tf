variable "kubeconfig" {
  description = "Path to the kubeconfig for the target cluster"
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Optional kubeconfig context"
  type        = string
  default     = null
}

variable "jenkins_namespace" {
  description = "Namespace for Jenkins"
  type        = string
  default     = "ci"
}

variable "jenkins_chart_version" {
  description = "Pinned Jenkins Helm chart version"
  type        = string
  default     = "5.8.58"
}

variable "jenkins_admin_password" {
  description = "Jenkins local admin password"
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition     = trimspace(var.jenkins_admin_password) != ""
    error_message = "Set a non-empty Jenkins administrator password through a protected input."
  }
}

variable "jenkins_git_url" {
  description = "Git remote containing the Jenkinsfile"
  type        = string
  default     = "https://github.com/mohammed-aljeebat/task-mohammed-aljeebat.git"
}
