# The Beacon of Release

This project is a Java 17 Spring Boot application and a local DevOps lab. It
combines Docker, Kubernetes, Terraform, Jenkins, and Trivy to demonstrate
building, running, scanning, and deploying a small service. The original
requirements are in [TASK.md](TASK.md).

## Application

The service listens on port `8080` and exposes:

- `GET /` — returns `Hello <name>` as plain text.
- `GET /actuator/health` — returns the application's health status.
- `/actuator/health/readiness` and `/actuator/health/liveness` — used by
  Kubernetes probes.

The `YOUR_NAME` environment variable sets the name. If it is missing or
blank, the application uses `traveler`. The Kubernetes
[ConfigMap](k8s/configmap.yaml) currently sets it to `Mohammed Al Jeebat`.

## Project layout

- [src/](src/) — Spring Boot application and automated tests.
- [pom.xml](pom.xml) — Maven dependencies and build configuration.
- [Dockerfile](Dockerfile) — multi-stage build; Maven compilation and tests
  run in Docker, and the final image runs as a non-root user.
- [k8s/](k8s/) — Deployment, ConfigMap, internal Service, and Ingress.
- [terraform/](terraform/) — Jenkins Helm release, service accounts, and RBAC.
- [Jenkinsfile](Jenkinsfile) — Kubernetes-agent build, test, scan, push, digest deployment, smoke test, and rollback pipeline.
- [scripts/](scripts/) — PowerShell helpers for the local lab.
- [RUNBOOK.md](RUNBOOK.md) — additional operational notes.

## Run and test with Docker

These commands use PowerShell on Windows. Start Docker Desktop with Linux
containers, then run them from this directory. Java and Maven do not need to
be installed on the host.

```powershell
# Run from the repository root.
docker build -t simple-java-app:local .
```

The build runs the Maven tests. Start the resulting image:

```powershell
docker run --rm --name simple-java-app -p 8080:8080 `
  --read-only --tmpfs /tmp:rw,noexec,nosuid,size=64m `
  -e "YOUR_NAME=Mohammed Al Jeebat" simple-java-app:local
```

Leave that window open. After the application starts, use a second PowerShell
window:

```powershell
Invoke-RestMethod http://localhost:8080/
(Invoke-RestMethod http://localhost:8080/actuator/health).status
```

Expected results are `Hello Mohammed Al Jeebat` and `UP`. Press `Ctrl+C` in the
first window to stop the container. If the connection fails, check the Docker
window for startup errors and make sure port `8080` is available.

## Run on local Kubernetes

The local lab uses Docker Desktop, Kind, `kubectl`, and ingress-nginx. The Kind
configuration maps host ports `80` and `443`, so those ports must be free.
From this directory, create the cluster and ingress controller:

```powershell
.\scripts\kind-up.ps1
```

Terraform creates the `quest` namespace. If you are deploying the app locally
without Terraform, create the namespace first:

```powershell
kubectl --context kind-quest create namespace quest
```

Build the image as shown above, then deploy it:

```powershell
.\scripts\deploy-local.ps1
```

The helper loads `simple-java-app:local` into Kind, applies the manifests, and
waits for the rollout. This local tag is mutable; after rebuilding an image
with the same tag, restart the deployment so pods pick up the new image:

```powershell
kubectl --context kind-quest -n quest rollout restart deployment/simple-java-app
kubectl --context kind-quest -n quest rollout status deployment/simple-java-app --timeout=180s
```

Test through Ingress using its hostname:

```powershell
curl.exe -H "Host: quest.local" http://localhost/
curl.exe -H "Host: quest.local" http://localhost/actuator/health
kubectl --context kind-quest -n quest get pods
```

The greeting should be `Hello Mohammed Al Jeebat` and the health status `UP`. To
use `http://quest.local/` directly in a browser, map `quest.local` to
`127.0.0.1` in your hosts file. Port `8080` is the application's container
port; the Kind Ingress is accessed on host port `80`.

To change the Kubernetes greeting, edit `YOUR_NAME` in
[configmap.yaml](k8s/configmap.yaml), apply it, and restart the deployment:

```powershell
kubectl --context kind-quest apply -f .\k8s\configmap.yaml
kubectl --context kind-quest -n quest rollout restart deployment/simple-java-app
kubectl --context kind-quest -n quest rollout status deployment/simple-java-app --timeout=180s
```

Environment variables are read when pods start, so changing the ConfigMap
alone does not update running pods.

## How the infrastructure fits together

External HTTP traffic reaches the nginx Ingress for `quest.local`, which
routes it to the internal `simple-java-app` Service. The Service forwards
requests to two application pods. The pods use readiness and liveness probes,
resource limits, a non-root user, a read-only root filesystem, and writable
temporary storage.

Terraform uses an existing Kubernetes cluster to install Jenkins in the `ci`
namespace, including persistent storage and a Kubernetes agent configuration.
It also defines a deployer service account and namespace-scoped RBAC in
`quest`. Initialize and review changes before applying them:

```powershell
$env:TF_VAR_kube_context = "kind-quest"
$env:TF_VAR_jenkins_admin_password = "<choose-a-strong-password>"
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan
```

After reviewing the plan, run `terraform -chdir=terraform apply`, then run
`plan` again to check for unexpected changes. Terraform state can contain
secrets: protect it, do not commit it, and use an encrypted, access-controlled
remote backend for shared environments. Do not commit credentials or local
`.tfvars` files. For local Jenkins access, use port forwarding in a separate
window:

```powershell
kubectl --context kind-quest -n ci port-forward svc/jenkins 8081:8080
```

Open `http://localhost:8081/` while that command is running.

## Pipeline and handover status

The Jenkins job is bootstrapped from the root `Jenkinsfile` in the configured
Git repository. Jenkins uses Configuration as Code, pinned chart/plugin and
provider versions, temporary Kubernetes agents, and
`disableConcurrentBuilds()` to prevent overlapping builds. The pipeline uses a
privileged Docker-in-Docker sidecar; isolate these build workers and do not
treat this local lab as a production security boundary.

Jenkins Build #10 checked out commit
`b9a1089c09bf175cfbf634d2a6ed7f647c044b9c`, passed all four Maven tests and
the Trivy gate, pushed tag `b9a1089c09bf`, and deployed digest
`sha256:4951760e05630c6b723553ff7bd749a7c863836fb1f21cd09de04ef1b0b2684d`.
The Jenkins smoke checks passed for the Ingress greeting and health endpoint.
The live Deployment was verified with two ready replicas using that digest.
A pod deletion recovery check also passed: Kubernetes recreated the pod,
returned to two ready replicas, and the Ingress greeting and health checks
remained successful.
Jenkins archives the scan report, scanner/database version information, test
reports, image digest, and deployment/smoke-test results; download those
artifacts from the successful build before tearing down the cluster.

The checked-in [trivy-report.json](trivy-report.json) is a local scan of
`simple-java-app:local`, not the image digest listed above. Use the report
archived by the successful Jenkins run as the release scan evidence.

The happy path and pod recovery are verified. Before final handover, still
demonstrate that a failing test and a Trivy finding both stop
publication/deployment, and verify a controlled failed rollout restores a
known-good image. The earlier smoke-test agent failure did trigger rollback,
but it was not a controlled failed-rollout test.

Terraform state is stored locally and can contain secrets. Keep
`terraform/terraform.tfstate` and backups out of Git and do not send them with
the handover. Rotate the Jenkins administrator password before transferring
ownership; use protected inputs and an encrypted, access-controlled remote
backend for shared environments.

Trivy can scan the final local image with:

```powershell
trivy image --scanners vuln --severity UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL `
  --exit-code 1 --format json --output trivy-report.json simple-java-app:local
```

Run a fresh scan for each image and preserve its image digest and database
timestamp. Existing reports describe the image scanned at the time, not
necessarily a subsequent build. A clean scan is only a snapshot, not a
permanent security guarantee.

## Teardown

`.\scripts\teardown.ps1` deletes the `quest` Kind cluster and its cluster
data. Docker images, local reports, and Terraform state outside the cluster
remain. Review the [runbook](RUNBOOK.md) and Terraform state before removing
the lab; do not delete data you need to keep.
