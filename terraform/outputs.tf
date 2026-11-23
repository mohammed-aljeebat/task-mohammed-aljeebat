output "jenkins_namespace" {
  value = helm_release.jenkins.namespace
}

output "jenkins_service" {
  value = "jenkins.${helm_release.jenkins.namespace}.svc.cluster.local:8080"
}

output "jenkins_nodeport" {
  value = "32000"
}
