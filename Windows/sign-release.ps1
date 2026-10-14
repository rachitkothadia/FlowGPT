param([Parameter(Mandatory=$true)][string]$Artifact)
$ErrorActionPreference = 'Stop'
if (-not $env:FLOW_WINDOWS_CERT_THUMBPRINT) { throw 'A trusted code-signing certificate is required. Set FLOW_WINDOWS_CERT_THUMBPRINT.' }
$certificate = Get-Item "Cert:\CurrentUser\My\$($env:FLOW_WINDOWS_CERT_THUMBPRINT)"
if (-not $certificate.HasPrivateKey -or $certificate.NotAfter -le [DateTime]::Now -or $certificate.Subject -eq $certificate.Issuer) { throw 'The publisher certificate must have its private key, be unexpired, and not be self-signed.' }
$vs = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -property installationPath
$tools = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe" | Sort-Object FullName -Descending
if (-not $tools) { throw 'Windows SDK SignTool was not found.' }
& $tools[0].FullName sign /fd SHA256 /td SHA256 /tr http://timestamp.digicert.com /sha1 $env:FLOW_WINDOWS_CERT_THUMBPRINT $Artifact
if ($LASTEXITCODE -ne 0) { throw 'Publisher signing failed.' }
& $tools[0].FullName verify /pa /all $Artifact
if ($LASTEXITCODE -ne 0 -or (Get-AuthenticodeSignature $Artifact).Status -ne 'Valid') { throw 'The signed artifact is not trusted by Windows.' }
