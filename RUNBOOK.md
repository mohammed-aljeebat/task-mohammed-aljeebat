# Beacon of Release Runbook

## Prerequisites

- Windows, Docker Desktop 29.9.3
- Kubernetes kind 0.33.0
- kubectl 1.36.1
- Terraform 1.17.1
- Helm 4.3.2
- Trivy 0.76.2
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

Set the Jenkins administrator password through a protected local environment
variable or protected local tfvars file. The example file contains no secret:

```powershell
$env:TF_VAR_jenkins_admin_password = '<strong-local-password>'
cd terraform
terraform init
terraform validate
terraform plan -out=quest.tfplan
terraform apply quest.tfplan
terraform plan
```

Commit `.terraform.lock.hcl`; never commit `.tfstate`, `terraform.tfvars`, or
credentials. This lab uses local Terraform state, which can contain sensitive
values. Protect the state and its backups; do not attach them to a handover.
Shared environments should use an encrypted remote backend with restricted
access.

Jenkins is exposed as a NodePort service. Determine the assigned port with
`kubectl get svc -n ci jenkins`, then open `http://localhost:<node-port>`.

Jenkins uses Configuration as Code and a pinned plugin list. The `simple-java-app` job is bootstrapped from the checked-out repository. Kubernetes agents use a DinD sidecar. This gives build workers Docker daemon access and is therefore an isolated privileged boundary; replace it with an appropriately isolated builder for shared production use.

Create these Jenkins credentials manually in the Jenkins Credentials UI:

- `dockerhub-credentials`: **Username with password**, using the Docker Hub
  username and access token.
- `quest-kubeconfig`: **Secret file**, containing valid kubeconfig YAML for the
  `jenkins-deployer` service account.

The deployer is limited to the `quest` namespace and is not cluster-admin. It
can manage the app Deployment, ConfigMap, Service, and Ingress, and read the
app's Pods. Terraform does not provision these Jenkins credentials; do not
pass the Docker Hub token through Terraform variables.

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
6. Smoke-tests the Ingress greeting and health endpoint and rolls back if the
   deployment/smoke stage fails.

The pipeline uses `disableConcurrentBuilds()` to prevent overlapping
deployments. The Docker-in-Docker sidecar is privileged; this lab isolates it
to the local CI namespace, but it is not an appropriate shared production
builder without stronger isolation.

## Verified release and handover status

Jenkins Build #10 checked out commit
`b9a1089c09bf175cfbf634d2a6ed7f647c044b9c`. All four Maven tests passed, the
Trivy gate passed, and the commit tag `b9a1089c09bf` was pushed and deployed
by digest:
`mohammedaljeebat/simple-java-app@sha256:4951760e05630c6b723553ff7bd749a7c863836fb1f21cd09de04ef1b0b2684d`.
Ingress returned `Hello Mohammed Al Jeebat` and health `UP`; Kubernetes was
verified with two ready replicas on that digest. A pod deletion recovery
check recreated the pod and the Ingress greeting and health checks still
passed.

The successful Jenkins build archives the test reports, Trivy report and
scanner/database version information, image digest, greeting/health responses,
and deployment result. Download these from the successful build before
teardown. The checked-in `trivy-report.json` is a scan of the local
`simple-java-app:local` image and is not the release report.

Still required for formal sign-off:

- Demonstrate at least one failing delivery gate—a failing test or a Trivy
  finding—and confirm that it prevents publication/deployment. Prefer the
  failing-test check because it also verifies Surefire reports are archived
  when tests fail.
- Exercise a controlled failed rollout and verify recovery to an immutable
  known-good image. A prior smoke-test agent startup failure did trigger
  rollback to the then-current `simple-java-app:local`, but this was not a
  controlled rollout-failure test.
- Re-run and retain a reviewed Terraform plan and post-apply no-change plan
  using protected inputs.
- Rotate the Jenkins administrator password before ownership transfer.

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

This deletes the Kind cluster, including Jenkins and the Jenkins artifact
storage on its persistent volume. Download the required build reports and
release evidence before teardown. Local Terraform state, Docker images, and
files outside the cluster remain; protect or remove them separately as
appropriate.
