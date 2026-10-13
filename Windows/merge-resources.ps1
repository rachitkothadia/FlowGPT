param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$outputPath = (Resolve-Path $OutputDirectory).Path
$makepri = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Filter makepri.exe -Recurse |
    Where-Object FullName -match '\\x64\\makepri\.exe$' | Sort-Object FullName -Descending | Select-Object -First 1
if (-not $makepri) { throw 'Windows SDK resource indexer not found' }
if (-not (Get-ChildItem $outputPath -Filter '*.pri' -Recurse | Where-Object Name -ne 'resources.pri')) {
    throw 'Self-contained framework resource indexes are missing from the output'
}
# A programmatic unpackaged app has no App.xaml compiler pass to merge the
# framework PRI. Merge it explicitly so the runtime can resolve theme resources.
$configuration = Join-Path $env:TEMP ([guid]::NewGuid().ToString() + '.priconfig.xml')
try {
    & $makepri.FullName createconfig /cf $configuration /dq en-US /o
    if ($LASTEXITCODE -ne 0) { throw 'Could not create resource configuration' }
    [xml]$xml = Get-Content $configuration
    foreach ($node in @($xml.SelectNodes('//packaging'))) { $null = $node.ParentNode.RemoveChild($node) }
    $xml.Save($configuration)
    Remove-Item "$outputPath/resources.pri" -ErrorAction SilentlyContinue
    & $makepri.FullName new /pr $outputPath /cf $configuration /of "$outputPath/resources.pri" /o
    if ($LASTEXITCODE -ne 0) { throw 'Could not merge WinUI resources' }
    if (-not (Test-Path "$outputPath/resources.pri")) { throw 'Merged resource index was not created' }
} finally { Remove-Item $configuration -ErrorAction SilentlyContinue }
