$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path "$PSScriptRoot\..")

$image = 'simple-java-app:local'
docker build --tag $image .

docker rm -f simple-java-app-verify 2>$null | Out-Null
docker run --detach --name simple-java-app-verify `
  --user 10001:10001 `
  --read-only `
  --tmpfs /tmp:rw,noexec,nosuid,size=64m `
  --env YOUR_NAME=Explorer `
  --publish 18080:8080 `
  $image | Out-Null

try {
  Start-Sleep -Seconds 8
  $greeting = Invoke-RestMethod -Uri 'http://127.0.0.1:18080/' -UseBasicParsing
  $health = Invoke-RestMethod -Uri 'http://127.0.0.1:18080/actuator/health' -UseBasicParsing
  $greeting | Set-Content -Encoding utf8 'greeting-verification.txt'
  $health | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 'health-verification.json'
  if ($greeting -ne 'Hello Explorer') { throw "Unexpected greeting: $greeting" }
  if ($health.status -ne 'UP') { throw "Unexpected health: $($health.status)" }
} finally {
  docker rm -f simple-java-app-verify 2>$null | Out-Null
}

$imageId = docker inspect --format '{{.Id}}' $image
$trivy = Get-Command trivy -ErrorAction SilentlyContinue
if (-not $trivy) {
  $trivy = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Filter trivy.exe -Recurse -ErrorAction SilentlyContinue |
    Select-Object -First 1
}
if (-not $trivy) { throw "Trivy is not installed" }
$trivyPath = if ($trivy.Source) { $trivy.Source } else { $trivy.FullName }
& $trivyPath image --scanners vuln --format json --output trivy-report.json --severity UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL --exit-code 1 $image
& $trivyPath --version | Set-Content -Encoding utf8 trivy-version.txt

Write-Host "Greeting: Hello Explorer"
Write-Host "Health: UP"
Write-Host "Image ID: $imageId"
