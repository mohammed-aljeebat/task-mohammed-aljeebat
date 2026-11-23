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
- [Jenkinsfile](Jenkinsfile) — proposed build, scan, push, and deployment stages.
- [scripts/](scripts/) — PowerShell helpers for the local lab.
- [RUNBOOK.md](RUNBOOK.md) — additional operational notes.

## Run and test with Docker

These commands use PowerShell on Windows. Start Docker Desktop with Linux
containers, then run them from this directory. Java and Maven do not need to
be installed on the host.

```powershell
cd C:\git\remote\task\Task
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

The current Terraform configuration expects the `quest` namespace to already
exist. Create it if it is not present:

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

## Pipeline and security status

The Jenkinsfile describes checkout, Docker build and test, Trivy scan, Docker
Hub push, digest deployment, smoke testing, and attempted rollback. It is
**not yet verified end to end**: Docker Hub credentials and image settings
are required, and the bootstrapped job references the remote repository with
`Jenkinsfile` at its root, whereas this project is under `Task/`. The agent
tooling, deployer permissions, failure handling, and rollback also need
validation before relying on the pipeline. Its current smoke test targets the
internal Service rather than Ingress. Plugin versions are not pinned, and
Docker-in-Docker uses a privileged agent; this is a lab, not a production-ready
security boundary.

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
