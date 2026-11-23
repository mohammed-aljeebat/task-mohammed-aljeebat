# Beacon of Release Runbook

## Prerequisites

- Windows 11, Docker Desktop 29.9 or newer
- Kubernetes kind 0.33.0
- kubectl 1.34 or newer
- Terraform 1.17.2 or newer
- Helm 4.3.2 or newer
- Trivy 0.76.2 or newer
- Docker Hub account and access token for pipeline publication

Docker Desktop must run Linux containers. Java and Maven are not required on the host.

## Build and verify locally

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-and-verify.ps1
```

The script builds with Docker, runs Maven tests in the Docker build, starts the image read-only as UID 10001, verifies the greeting and health endpoint, and writes Trivy output.

Fix every vulnerability reported by Trivy before publishing. The scan is fail closed: any finding in the selected severities or any scanner error fails delivery.

## Create the Kind lab

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\kind-up.ps1
```

The cluster publishes ports 80 and 443. Add `127.0.0.1 quest.local` to the hosts file if you need hostname resolution outside Kind. The ingress controller is installed before Jenkins.

## Provision Jenkins

Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and inject real credentials only through environment variables or a protected local file:

```powershell
$env:TF_VAR_jenkins_admin_password = '<strong-local-password>'
$env:TF_VAR_dockerhub_username = '<username>'
$env:TF_VAR_dockerhub_token = '<token>'
cd terraform
terraform init
terraform validate
terraform plan -out=quest.tfplan
terraform apply quest.tfplan
terraform plan
```

Commit `.terraform.lock.hcl`; never commit `.tfstate`, `terraform.tfvars`, or credentials. Production state must use an encrypted remote backend and restricted access. This lab stores state locally and can contain sensitive values.

Jenkins is exposed as a NodePort service. Determine the assigned port with
`kubectl get svc -n ci jenkins`, then open `http://localhost:<node-port>`.

Jenkins uses Configuration as Code and a pinned plugin list. The `simple-java-app` job is bootstrapped from the checked-out repository. Kubernetes agents use a DinD sidecar. This gives build workers Docker daemon access and is therefore an isolated privileged boundary; replace it with an appropriately isolated builder for shared production use.

Create Jenkins credentials:

- `dockerhub-credentials`: Docker Hub username/token
- `quest-kubeconfig`: kubeconfig for the Jenkins deployer service account

The kubeconfig must use `jenkins-deployer`, which has update/patch only in the `quest` namespace and cannot act as cluster-admin.

## Deploy locally

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\deploy-local.ps1
```

This applies Kubernetes configuration and verifies the Ingress route and health.

## Pipeline gates

The root `Jenkinsfile`:

1. Checks out the requested revision and records the commit.
2. Builds and tests in Docker; test reports are archived.
3. Scans the final image and database timestamp and fails on findings or scanner errors.
4. Pushes only the passing commit tag and captures the registry digest.
5. Applies the exact digest to Kubernetes and waits for rollout.
6. Smoke-tests Ingress and rolls back if deployment fails.

Set `IMAGE_NAME` in the `Jenkinsfile` to `dockerhub-user/simple-java-app`.

Overlapping deployments are prevented with Jenkins locks.

## Rollback

```powershell
kubectl -n quest rollout undo deployment/simple-java-app
kubectl -n quest rollout status deployment/simple-java-app --timeout=180s
```

For an exact known-good image:

```powershell
kubectl -n quest set image deployment/simple-java-app app=docker.io/<user>/simple-java-app@sha256:<digest>
kubectl -n quest rollout status deployment/simple-java-app --timeout=180s
```

## Verify failed gates

- Test gate: make a test assertion fail and run the pipeline; no image is pushed.
- Vulnerability gate: introduce or upgrade to a package with a Trivy finding; no push or deployment follows.
- Rollout gate: deploy an invalid digest or port and confirm Jenkins records failure and restores `PREVIOUS_IMAGE`.

## Teardown

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\teardown.ps1
```

This deletes the Kind cluster and all local data. Terraform state, Jenkins reports, Docker images, and local evidence outside the cluster are not deleted. Remove them separately if needed.
