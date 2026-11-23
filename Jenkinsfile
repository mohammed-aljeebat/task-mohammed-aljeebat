pipeline {
  agent {
    label 'quest-agent'
  }
  options {
    timestamps()
    disableConcurrentBuilds()
  }
  environment {
    IMAGE_NAME = 'mohammedaljeebat/simple-java-app'
    KUBECONFIG_CREDENTIAL = 'quest-kubeconfig'
    DOCKERHUB_CREDENTIAL = 'dockerhub-credentials'
  }
  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.GIT_COMMIT_ID = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
          env.IMAGE = "${env.IMAGE_NAME}:${env.GIT_COMMIT_ID}"
          env.SHORT_COMMIT = env.GIT_COMMIT_ID.take(12)
        }
      }
    }

    stage('Build and Test') {
      steps {
        script {
          try {
            container('docker') {
              sh '''
                remaining=60
                until docker info >/dev/null 2>&1; do
                  if [ "$remaining" -le 0 ]; then
                    echo "Docker daemon did not become ready within 120 seconds" >&2
                    exit 1
                  fi
                  remaining=$((remaining - 1))
                  sleep 2
                done
                docker info
                mkdir -p test-results
                docker build --target build --tag simple-java-app:test .
                docker build --tag ${IMAGE_NAME}:${SHORT_COMMIT} .
              '''
            }
            container('docker') {
              sh '''
                mkdir -p test-results
                docker run --rm \
                  -v "$WORKSPACE:/workspace" \
                  -w /workspace \
                  maven:3.9.11-eclipse-temurin-17 \
                  mvn -B -ntp test
              '''
            }
          } finally {
            archiveArtifacts allowEmptyArchive: true, artifacts: 'target/surefire-reports/**,test-results/**'
          }
        }
      }
    }

    stage('Trivy Scan') {
      steps {
        script {
          container('trivy') {
            sh '''
              trivy image --download-db-only
              trivy image --download-java-db-only
              trivy image \
                --scanners vuln \
                --format json \
                --output trivy-report.json \
                --severity UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL \
                --exit-code 1 \
                ${IMAGE_NAME}:${SHORT_COMMIT}
            '''
          }
        }
      }
      post {
        always {
          container('trivy') {
            sh '''
              trivy --version > trivy-version.txt
              trivy image --download-db-only
              trivy image --format json --output trivy-report.json ${IMAGE_NAME}:${SHORT_COMMIT} || true
            '''
          }
          archiveArtifacts allowEmptyArchive: true,
            artifacts: 'trivy-report.json,trivy-version.txt'
        }
      }
    }

    stage('Push Digest') {
      steps {
        withCredentials([usernamePassword(
            credentialsId: "${env.DOCKERHUB_CREDENTIAL}",
            usernameVariable: 'DOCKERHUB_USERNAME',
            passwordVariable: 'DOCKERHUB_TOKEN'
          )]) {
            container('docker') {
              sh 'echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin'
              sh '''
                set -o pipefail
                docker push ${IMAGE_NAME}:${SHORT_COMMIT} | tee docker-push.txt
              '''
              script {
                def pushedDigest = sh(
                  script: "grep -Eo 'sha256:[0-9a-f]{64}' docker-push.txt | tail -n 1",
                  returnStdout: true
                ).trim()
                if (!pushedDigest.startsWith('sha256:') || pushedDigest.length() != 71) {
                  error "Docker push did not produce an immutable digest"
                }
                env.IMAGE_DIGEST = "${env.IMAGE_NAME}@${pushedDigest}"
                writeFile file: 'image-digest.txt', text: env.IMAGE_DIGEST
              }
            }
          }
      }
    }

    stage('Deploy and Smoke Test') {
      steps {
        withCredentials([file(credentialsId: "${env.KUBECONFIG_CREDENTIAL}", variable: 'KUBECONFIG')]) {
          script {
            container('kubectl') {
              env.PREVIOUS_IMAGE = sh(
                script: 'kubectl --kubeconfig "$KUBECONFIG" -n quest get deploy simple-java-app -o jsonpath="{.spec.template.spec.containers[0].image}"',
                returnStdout: true
              ).trim()
              sh '''
                kubectl --kubeconfig "$KUBECONFIG" -n quest apply -f k8s/configmap.yaml
                kubectl --kubeconfig "$KUBECONFIG" -n quest apply -f k8s/service.yaml
                kubectl --kubeconfig "$KUBECONFIG" -n quest apply -f k8s/ingress.yaml
                sed "s#IMAGE_PLACEHOLDER#${IMAGE_DIGEST}#g" k8s/deployment.yaml |
                  kubectl --kubeconfig "$KUBECONFIG" -n quest apply -f -
                kubectl --kubeconfig "$KUBECONFIG" -n quest set image deployment/simple-java-app \
                  app=${IMAGE_DIGEST} -n quest
                kubectl --kubeconfig "$KUBECONFIG" -n quest rollout status deployment/simple-java-app --timeout=180s
              '''
            }
          }
          container('curl') {
            sh '''
              curl --fail --retry 12 --retry-delay 5 --retry-all-errors \
                -H 'Host: quest.local' \
                http://ingress-nginx-controller.ingress-nginx.svc.cluster.local/ \
                | tee smoke-greeting.txt
              grep -Fxq 'Hello Mohammed Al Jeebat' smoke-greeting.txt
              curl --fail --retry 12 --retry-delay 5 --retry-all-errors \
                -H 'Host: quest.local' \
                http://ingress-nginx-controller.ingress-nginx.svc.cluster.local/actuator/health \
                > smoke-health.json
              grep -Fq '"status":"UP"' smoke-health.json
            '''
          }
        }
      }
      post {
        failure {
          withCredentials([file(credentialsId: "${env.KUBECONFIG_CREDENTIAL}", variable: 'KUBECONFIG')]) {
            container('kubectl') {
              sh '''
                if [ -n "$PREVIOUS_IMAGE" ]; then
                  kubectl --kubeconfig "$KUBECONFIG" -n quest set image deployment/simple-java-app app="$PREVIOUS_IMAGE"
                  kubectl --kubeconfig "$KUBECONFIG" -n quest rollout status deployment/simple-java-app --timeout=180s
                fi
              '''
            }
          }
          echo "Deployment failed; attempted rollback to ${env.PREVIOUS_IMAGE}"
        }
      }
    }

    stage('Record Result') {
      steps {
        sh '''
          printf 'commit=%s\nimage_digest=%s\ndeployment=healthy\n' \
            "$GIT_COMMIT_ID" "$IMAGE_DIGEST" > deployment-result.txt
        '''
        archiveArtifacts artifacts: 'deployment-result.txt,smoke-greeting.txt,smoke-health.json,image-digest.txt'
      }
    }
  }
  post {
    success {
      echo "Published and deployed ${env.IMAGE_DIGEST}"
    }
  }
}
