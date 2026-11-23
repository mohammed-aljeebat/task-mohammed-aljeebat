resource "helm_release" "jenkins" {
  name       = "jenkins"
  namespace  = kubernetes_namespace_v1.ci.metadata[0].name
  repository = "https://charts.jenkins.io"
  chart      = "jenkins"
  version    = var.jenkins_chart_version
  wait       = true
  timeout    = 600

  values = [
    <<-EOT
    controller:
      image:
        repository: jenkins/jenkins
        tag: "2.541.3-lts-jdk17"
      admin:
        username: admin
        password: ${var.jenkins_admin_password}
      serviceType: NodePort
      servicePort: 8080
      serviceNodePort: 32000
      installPlugins:
        - kubernetes:4560.vc25b_83890c34
        - workflow-aggregator:608.v67378e9d3db_1
        - git:5.11.0
        - job-dsl:3752.vb_199526b_20c3
        - configuration-as-code:2147.v8a_8d38668c72
        - credentials-binding:728.v902a_273b_8947
        - timestamper:1.30
      JCasC:
        defaultConfig: true
        configScripts:
          kubernetes-agents: |
            jenkins:
              clouds:
                - kubernetes:
                    name: "kubernetes"
                    serverUrl: "https://kubernetes.default"
                    namespace: "${var.jenkins_namespace}"
                    jenkinsUrl: "http://jenkins.${var.jenkins_namespace}.svc.cluster.local:8080"
                    jenkinsTunnel: "jenkins-agent.${var.jenkins_namespace}.svc.cluster.local:50000"
                    containerCapStr: "10"
                    templates:
                      - name: "quest-agent"
                        namespace: "${var.jenkins_namespace}"
                        label: "quest-agent"
                        serviceAccount: "jenkins"
                        containers:
                          - name: "jnlp"
                            image: "jenkins/inbound-agent:3198.v03a_401881f3e-1-jdk17"
                            args: "^$${computer.jnlpmac} ^$${computer.name}"
                          - name: "docker"
                            image: "docker:28.5.2-cli"
                            ttyEnabled: true
                            command: "cat"
                            envVars:
                              - envVar:
                                  key: "DOCKER_HOST"
                                  value: "tcp://localhost:2375"
                          - name: "dind"
                            image: "docker:28.5.2-dind"
                            ttyEnabled: true
                            privileged: true
                            envVars:
                              - envVar:
                                  key: "DOCKER_TLS_CERTDIR"
                                  value: ""
                          - name: "trivy"
                            image: "aquasec/trivy:0.76.2"
                            ttyEnabled: true
                            command: "cat"
                            envVars:
                              - envVar:
                                  key: "TRIVY_CACHE_DIR"
                                  value: "/tmp/trivy"
                              - envVar:
                                  key: "DOCKER_HOST"
                                  value: "tcp://localhost:2375"
                          - name: "kubectl"
                            image: "alpine/k8s:1.31.2"
                            ttyEnabled: true
                            command: "cat"
                          - name: "curl"
                            image: "curlimages/curl:8.11.1"
                            ttyEnabled: true
                            command: "cat"
                        volumes:
                          - emptyDirVolume:
                              memory: false
                              mountPath: "/tmp"
          quest-job: |
            jobs:
              - script: >
                  pipelineJob('simple-java-app') {
                    definition {
                      cpsScm {
                        scm {
                          gitSCM {
                            branches {
                              branchSpec {
                                name('*/main')
                              }
                            }
                            userRemoteConfigs {
                              userRemoteConfig {
                                url('${var.jenkins_git_url}')
                                name('origin')
                                refspec('+refs/heads/*:refs/remotes/origin/*')
                                credentialsId('')
                              }
                            }
                            browser(null)
                            gitTool('')
                          }
                        }
                        scriptPath('Jenkinsfile')
                      }
                    }
                  }
    persistence:
      enabled: true
      size: 8Gi
    serviceAccount:
      create: false
      name: jenkins
    rbac:
      create: false
    EOT
  ]

  depends_on = [
    kubernetes_service_account_v1.jenkins,
    kubernetes_role_binding_v1.jenkins_agents
  ]
}
