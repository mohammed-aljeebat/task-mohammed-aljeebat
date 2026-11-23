$ErrorActionPreference = 'Stop'

$kind = Get-Command kind -ErrorAction SilentlyContinue
if (-not $kind) {
  $kind = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Filter kind.exe -Recurse -ErrorAction SilentlyContinue |
    Select-Object -First 1
}
if (-not $kind) { throw "Kind is not installed" }
$kindPath = if ($kind.Source) { $kind.Source } else { $kind.FullName }
& $kindPath create cluster --name quest --config "$PSScriptRoot\kind-cluster.yaml"
kubectl config use-context kind-quest

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.13.3/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx `
  --for=condition=available deployment/ingress-nginx-controller `
  --timeout=180s

Write-Host "Kind cluster quest is ready."
