$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path "$PSScriptRoot\..")

$image = 'simple-java-app:local'
$kind = Get-Command kind -ErrorAction SilentlyContinue
if (-not $kind) {
  $kind = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Filter kind.exe -Recurse -ErrorAction SilentlyContinue |
    Select-Object -First 1
}
if ($kind) {
  $kindPath = if ($kind.Source) { $kind.Source } else { $kind.FullName }
  & $kindPath load docker-image $image --name quest
}
kubectl -n quest apply -f k8s/configmap.yaml
kubectl -n quest apply -f k8s/service.yaml
kubectl -n quest apply -f k8s/ingress.yaml
$deployment = Get-Content k8s/deployment.yaml -Raw
$deployment = $deployment.Replace('IMAGE_PLACEHOLDER', $image)
$deployment | kubectl -n quest apply -f -
kubectl -n quest rollout status deployment/simple-java-app --timeout=180s

$headers = @{ Host = 'quest.local' }
$greeting = Invoke-RestMethod -Uri 'http://127.0.0.1/' -Headers $headers -UseBasicParsing
$health = Invoke-RestMethod -Uri 'http://127.0.0.1/actuator/health' -Headers $headers -UseBasicParsing
if ($greeting -ne 'Hello Mohammed Al Jeebat') { throw "Unexpected greeting: $greeting" }
if ($health.status -ne 'UP') { throw "Unexpected health: $($health.status)" }
Write-Host $greeting
Write-Host $($health.status)
