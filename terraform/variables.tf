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
}

variable "dockerhub_username" {
  description = "Docker Hub username"
  type        = string
  sensitive   = true
  default     = ""
}

variable "dockerhub_token" {
  description = "Docker Hub access token"
  type        = string
  sensitive   = true
  default     = ""
}

variable "jenkins_git_url" {
  description = "Git remote containing the Jenkinsfile"
  type        = string
  default     = "https://github.com/mohammed-aljeebat/task-mohammed-aljeebat.git"
}

variable "dockerhub_image" {
  description = "Docker Hub repository, for example username/simple-java-app"
  type        = string
  default     = "CHANGE_ME/simple-java-app"
}
