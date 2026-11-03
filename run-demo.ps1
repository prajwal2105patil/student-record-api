# Windows one-click demo for the Student Record API (Windows PowerShell 5.1+).
# - Uses your JDK if it is 17+, otherwise downloads a portable Temurin JDK 21 into .tools\ (no system install)
# - Uses Maven from PATH if present, otherwise downloads Maven 3.9.11 into .tools\
# - Builds the JAR, runs it, executes every required scenario, queries H2, restarts, writes REPORT.md
#
#   .\run-demo.ps1             fresh run (deletes .\data and .\logs first so the evidence is clean)
#   .\run-demo.ps1 -KeepData   keep the existing H2 database file
param([switch]$KeepData, [switch]$Serve)
if ($Serve) { $KeepData = $true }

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Set-Location $PSScriptRoot

$Root     = $PSScriptRoot
$Tools    = Join-Path $Root '.tools'
$Evid     = Join-Path $Root 'evidence'
$Report   = Join-Path $Root 'REPORT.md'
$Base     = 'http://localhost:8080'
$Utf8     = New-Object System.Text.UTF8Encoding($false)
$Fence    = '```'
$Curl     = Join-Path $env:SystemRoot 'System32\curl.exe'
$BodyFile = Join-Path $env:TEMP 'student-api-body.json'
$RespFile = Join-Path $env:TEMP 'student-api-resp.txt'
$script:Failures = 0
$script:App = $null

New-Item -ItemType Directory -Force $Tools | Out-Null
if (-not $Serve) {
    if (Test-Path $Evid) { Remove-Item -Recurse -Force $Evid }
    New-Item -ItemType Directory -Force $Evid | Out-Null
}
$Summary = Join-Path $Evid 'summary.txt'

function Say([string]$msg) { Write-Host $msg; if (-not $Serve) { [IO.File]::AppendAllText($Summary, $msg + "`r`n", $Utf8) } }
function Fail([string]$msg) { Say "FAILED: $msg"; if ($script:App -and -not $script:App.HasExited) { Stop-Process -Id $script:App.Id -Force }; exit 1 }

# ---------------------------------------------------------------- JDK 17+
function Get-JavaMajor([string]$javaExe) {
    if (-not $javaExe -or -not (Test-Path $javaExe)) { return 0 }
    $out = (& $javaExe -version 2>&1 | ForEach-Object { "$_" }) -join "`n"
    if ($out -match 'version "(\d+)(?:\.(\d+))?') {
        $major = [int]$Matches[1]
        if ($major -eq 1) { $major = [int]$Matches[2] }
        return $major
    }
    return 0
}

$JavaHome = $null
$portable = Join-Path $Tools 'jdk'
if ((Get-JavaMajor (Join-Path $portable 'bin\java.exe')) -ge 17) { $JavaHome = $portable }
if (-not $JavaHome -and $env:JAVA_HOME -and (Get-JavaMajor (Join-Path $env:JAVA_HOME 'bin\java.exe')) -ge 17) { $JavaHome = $env:JAVA_HOME }
if (-not $JavaHome) {
    $cmd = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($cmd -and (Get-JavaMajor $cmd.Source) -ge 17) { $JavaHome = Split-Path (Split-Path $cmd.Source) }
}
if (-not $JavaHome) {
    Say '==> No JDK 17+ found. Downloading portable Temurin JDK 21 into .tools\jdk (about 190 MB, one time)...'
    $zip = Join-Path $Tools 'jdk.zip'
    try {
        Invoke-WebRequest -UseBasicParsing -OutFile $zip `
            -Uri 'https://api.adoptium.net/v3/binary/latest/21/ga/windows/x64/jdk/hotspot/normal/eclipse'
    } catch { Fail "JDK download failed: $($_.Exception.Message)" }
    $tmp = Join-Path $Tools 'jdk-tmp'
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
    if (Test-Path $portable) { Remove-Item -Recurse -Force $portable }
    Move-Item $inner.FullName $portable
    Remove-Item -Recurse -Force $tmp, $zip
    $JavaHome = $portable
}
$env:JAVA_HOME = $JavaHome
$env:Path = (Join-Path $JavaHome 'bin') + ';' + $env:Path
$Java = Join-Path $JavaHome 'bin\java.exe'
Say "==> Using JDK at $JavaHome"

# ---------------------------------------------------------------- Maven
$Mvn = $null
$mvnCmd = Get-Command mvn.cmd -ErrorAction SilentlyContinue
if ($mvnCmd) { $Mvn = $mvnCmd.Source }
$portableMvn = Join-Path $Tools 'apache-maven-3.9.11\bin\mvn.cmd'
if (-not $Mvn -and (Test-Path $portableMvn)) { $Mvn = $portableMvn }
if (-not $Mvn) {
    Say '==> Maven not found. Downloading portable Maven 3.9.11 into .tools (about 9 MB, one time)...'
    $zip = Join-Path $Tools 'maven.zip'
    try {
        Invoke-WebRequest -UseBasicParsing -OutFile $zip `
            -Uri 'https://archive.apache.org/dist/maven/maven-3/3.9.11/binaries/apache-maven-3.9.11-bin.zip'
    } catch { Fail "Maven download failed: $($_.Exception.Message)" }
    Expand-Archive -Path $zip -DestinationPath $Tools -Force
    Remove-Item -Force $zip
    $Mvn = $portableMvn
}
Say "==> Using Maven at $Mvn"

# ---------------------------------------------------------------- Build
if (-not $KeepData) {
    foreach ($d in 'data', 'logs') { if (Test-Path $d) { Remove-Item -Recurse -Force $d } }
}
Say '==> Building (first build downloads dependencies, give it a few minutes)...'
$buildLog = Join-Path $Evid 'build.log'
if ($Serve) { $buildLog = Join-Path $env:TEMP 'student-api-build.log' }
& $Mvn -B clean package -DskipTests 2>&1 | ForEach-Object { "$_" } | Out-File -FilePath $buildLog -Encoding utf8
if ($LASTEXITCODE -ne 0) {
    Get-Content $buildLog -Tail 60 | ForEach-Object { Write-Host $_ }
    Fail "Maven build failed (exit $LASTEXITCODE). Full log: evidence\build.log"
}
$Jar = Get-ChildItem (Join-Path $Root 'target') -Filter 'student-api-*.jar' | Where-Object { $_.Name -notlike '*.original' } | Select-Object -First 1
if (-not $Jar) { Fail 'No JAR produced in target\' }
$JarRel = "target\$($Jar.Name)"
Say "==> Built $JarRel"

if ($Serve) {
    Say ''
    Say "==> Serving: java -jar $JarRel"
    Say '    API console: http://localhost:8080/api-console.html    H2 console: http://localhost:8080/h2-console'
    Say '    Press Ctrl+C or close this window to stop.'
    Say ''
    & $Java -jar $Jar.FullName
    exit 0
}

$H2Jar = Get-ChildItem (Join-Path $env:USERPROFILE '.m2\repository\com\h2database\h2') -Recurse -Filter 'h2-*.jar' -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -notmatch 'sources|javadoc' } | Select-Object -Last 1

# ---------------------------------------------------------------- helpers
function Add-Report([string[]]$lines) { foreach ($l in $lines) { [IO.File]::AppendAllText($Report, $l + "`n", $Utf8) } }

# Indents compact JSON exactly as the API returned it (PowerShell 5.1's ConvertTo-Json rewrites arrays
# as {"value":[...],"Count":n} and escapes quotes, which would misrepresent the response bodies).
function Pretty([string]$json) {
    $t = $json.Trim()
    if (-not ($t.StartsWith('{') -or $t.StartsWith('['))) { return $json }
    $sb = New-Object System.Text.StringBuilder
    $indent = 0; $inStr = $false; $esc = $false
    $chars = $t.ToCharArray()
    for ($i = 0; $i -lt $chars.Length; $i++) {
        $c = [string]$chars[$i]
        if ($inStr) {
            [void]$sb.Append($c)
            if ($esc) { $esc = $false } elseif ($c -eq '\') { $esc = $true } elseif ($c -eq '"') { $inStr = $false }
            continue
        }
        if ($c -eq '"') { $inStr = $true; [void]$sb.Append($c) }
        elseif ($c -eq '{' -or $c -eq '[') {
            $close = '}'; if ($c -eq '[') { $close = ']' }
            if ($i + 1 -lt $chars.Length -and [string]$chars[$i + 1] -eq $close) { [void]$sb.Append($c + $close); $i++ }
            else { $indent++; [void]$sb.Append($c + "`n" + ('  ' * $indent)) }
        }
        elseif ($c -eq '}' -or $c -eq ']') { $indent--; [void]$sb.Append("`n" + ('  ' * $indent) + $c) }
        elseif ($c -eq ',') { [void]$sb.Append(",`n" + ('  ' * $indent)) }
        elseif ($c -eq ':') { [void]$sb.Append(': ') }
        elseif ($c.Trim().Length -gt 0) { [void]$sb.Append($c) }
    }
    return $sb.ToString()
}

function Api([string]$title, [string]$method, [string]$path, [string]$body) {
    if (Test-Path $RespFile) { Remove-Item $RespFile -Force }
    $cargs = @('-s', '-X', $method, "$Base$path", '-o', $RespFile, '-w', '%{http_code}')
    if ($body) {
        [IO.File]::WriteAllText($BodyFile, $body, $Utf8)
        $cargs += @('-H', 'Content-Type: application/json', '--data-binary', "@$BodyFile")
    }
    $status = (& $Curl @cargs | Out-String).Trim()
    $resp = ''
    if (Test-Path $RespFile) { $resp = [IO.File]::ReadAllText($RespFile, $Utf8) }
    $script:LastStatus = $status
    $script:LastBody = $resp

    Add-Report @("### $title", '', ($Fence + 'http'), "$method $path")
    if ($body) { Add-Report @('Content-Type: application/json', '', $body) }
    Add-Report @($Fence, '', "**Status:** ``$status``", '')
    if ($resp) { Add-Report @(($Fence + 'json'), (Pretty $resp), $Fence) } else { Add-Report @('_(empty body)_') }
    Add-Report @('')
    Say ('  {0,-62} {1}' -f $title, $status)
}

function Expect([string]$code) {
    if ($script:LastStatus -ne $code) { Say "  !! expected $code, got $($script:LastStatus)"; $script:Failures++ }
}

function Is-Up { $c = (& $Curl -s -o NUL -w '%{http_code}' "$Base/students" | Out-String).Trim(); return ($c -eq '200') }

function Start-App([string]$logName) {
    $out = Join-Path $Evid $logName
    $script:App = Start-Process -FilePath $Java -ArgumentList @('-jar', "`"$($Jar.FullName)`"") `
        -WorkingDirectory $Root -RedirectStandardOutput $out -RedirectStandardError ($out + '.err') -WindowStyle Hidden -PassThru
    # Wait for the app's own "ready" line (logged after the seeder ran), not just the first HTTP 200
    for ($i = 0; $i -lt 120; $i++) {
        if ((Test-Path $out) -and (Select-String -Path $out -Pattern 'Student API ready' -Quiet) -and (Is-Up)) { return }
        if ($script:App.HasExited) { break }
        Start-Sleep -Seconds 1
    }
    Get-Content $out -Tail 40 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
    Fail "App did not start. See evidence\$logName"
}

function Stop-App {
    if ($script:App -and -not $script:App.HasExited) { Stop-Process -Id $script:App.Id -Force; $script:App.WaitForExit() }
    for ($i = 0; $i -lt 20; $i++) { if (-not (Is-Up)) { return }; Start-Sleep -Seconds 1 }
}

function Grep-Log([string]$file, [string]$pattern) {
    if (Test-Path $file) { Select-String -Path $file -Pattern $pattern | ForEach-Object { $_.Line } }
}

# ---------------------------------------------------------------- Report header
if (Is-Up) { Fail 'Something is already running on port 8080. Stop it and run again.' }

$JavaVer = (& $Java -version 2>&1 | ForEach-Object { "$_" } | Select-Object -First 1)
$MvnVer  = (& $Mvn -v 2>&1 | ForEach-Object { "$_" } | Select-Object -First 1)
$BootVer = ([xml](Get-Content (Join-Path $Root 'pom.xml') -Raw)).project.parent.version
$OsVer   = [Environment]::OSVersion.VersionString

if (Test-Path $Report) { Remove-Item $Report -Force }
Add-Report @('# Student Record Management API: Test Report', '')
Add-Report @("Generated by ``run-demo.ps1`` on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ($OsVer). Every request, status code and response body below was captured live from the running JAR.", '')
Add-Report @('| Item | Value |', '|---|---|',
     "| Java | ``$JavaVer`` |", "| Build tool | ``$MvnVer`` |", "| Spring Boot | ``$BootVer`` |",
     "| Artifact | ``$JarRel`` |",
     '| H2 mode | **File-based**: `jdbc:h2:file:./data/studentdb` (stored in `data/studentdb.mv.db`) |', '')

# ---------------------------------------------------------------- Run 1
Say "==> Run 1: java -jar $JarRel"
Start-App 'run1-console.log'
$run1 = Join-Path $Evid 'run1-console.log'

Add-Report @('## 1. Startup log (run 1)', '', "Command: ``java -jar $JarRel``", '', ($Fence + 'text'))
Add-Report (Grep-Log $run1 'Starting StudentApiApplication|Tomcat started|Started StudentApiApplication|DataSeeder|Student API ready')
Add-Report @($Fence, '')

Add-Report @('## 2. Create, retrieve, update, delete, with error cases', '')
Say '==> Scenarios'
Api '2.1 List all students (3 seeded records)' GET '/students'; Expect 200

Api '2.2 Valid creation' POST '/students' '{"usn":"1JS23CS101","name":"Mahantesh R. Patted","department":"CSE","semester":5}'; Expect 201
$NewId = $null
try { $NewId = (ConvertFrom-Json $script:LastBody).id } catch { }
if (-not $NewId) { Fail 'Create did not return an id; cannot continue' }

Api '2.3 Retrieve the created student' GET "/students/$NewId"; Expect 200
Api '2.4 Duplicate USN on create (lower-case USN still collides)' POST '/students' '{"usn":"1js23cs101","name":"Someone Else","department":"ISE","semester":3}'; Expect 409
Api '2.5 Invalid semester (9)' POST '/students' '{"usn":"1JS23CS102","name":"Test User","department":"CSE","semester":9}'; Expect 400
Api '2.6 Blank USN, blank name and semester 0' POST '/students' '{"usn":"  ","name":"","department":"CSE","semester":0}'; Expect 400
Api '2.7 Department filtering (?department=CSE)' GET '/students?department=CSE'; Expect 200
Api '2.8 Update (PUT) the created student' PUT "/students/$NewId" '{"usn":"1JS23CS101","name":"Mahantesh R. Patted","department":"AIML","semester":6}'; Expect 200
Api '2.9 Update with a USN owned by another student' PUT "/students/$NewId" '{"usn":"1JS23CS001","name":"Mahantesh R. Patted","department":"AIML","semester":6}'; Expect 409
Api '2.10 PUT on a missing id does not create it' PUT '/students/99999' '{"usn":"1JS23CS999","name":"Ghost","department":"CSE","semester":1}'; Expect 404
Api '2.11 Retrieve after failed updates (2.9 and 2.10 changed nothing)' GET "/students/$NewId"; Expect 200
Api '2.12 Delete the created student' DELETE "/students/$NewId"; Expect 204
Api '2.13 Lookup after deletion' GET "/students/$NewId"; Expect 404
Api '2.14 Non-numeric id' GET '/students/abc'; Expect 400
Api '2.15 Final list: only the seeds remain, no invalid request changed data' GET '/students'; Expect 200

# ---------------------------------------------------------------- H2 query
Add-Report @('## 3. H2 query result', '')
$Sql = 'SELECT ID, USN, NAME, DEPARTMENT, SEMESTER FROM STUDENTS ORDER BY ID'
if ($H2Jar) {
    $h2Out = & $Java -cp $H2Jar.FullName org.h2.tools.Shell -url 'jdbc:h2:file:./data/studentdb;AUTO_SERVER=TRUE' -user sa -sql $Sql 2>&1 | ForEach-Object { "$_" }
    Add-Report @('Run with the H2 Shell against the same database file while the app is running (`AUTO_SERVER=TRUE` allows a second connection):', '', ($Fence + 'text'))
    Add-Report @("> java -cp $($H2Jar.Name) org.h2.tools.Shell -url `"jdbc:h2:file:./data/studentdb;AUTO_SERVER=TRUE`" -user sa -sql `"$Sql`"", '')
    Add-Report ([string[]]$h2Out)
    Add-Report @($Fence, '')
    Say '  H2 query captured'
} else {
    Add-Report @('_H2 jar not found in the local Maven repository; use the H2 console instead (see README)._', '')
}

# ---------------------------------------------------------------- Restart
Add-Report @('## 4. Restart observation', '')
Api '4.1 Create a marker record before restarting' POST '/students' '{"usn":"1JS23CS555","name":"Restart Marker","department":"ISE","semester":2}'; Expect 201
$MarkerId = (ConvertFrom-Json $script:LastBody).id
$Before = (& $Curl -s "$Base/students" | Out-String).Trim()

Say '==> Stopping and restarting the JAR'
Stop-App
Start-App 'run2-console.log'
$run2 = Join-Path $Evid 'run2-console.log'

Add-Report @('The JAR was stopped with a forced kill (Stop-Process -Force, no graceful shutdown) and started again with the same command. Startup log of run 2:', '', ($Fence + 'text'))
Add-Report (Grep-Log $run2 'Started StudentApiApplication|DataSeeder|Student API ready')
Add-Report @($Fence, '')
Api '4.2 Marker record after restart' GET "/students/$MarkerId"; Expect 200
Api '4.3 Full list after restart' GET '/students'; Expect 200
$After = $script:LastBody.Trim()

Add-Report @("**Observation:** H2 is file-based, so every record survives the restart, including the marker created at runtime (id $MarkerId). The seeder found its three USNs already present, logged ``inserted=0, skipped(already present)=3``, and created no duplicates.")
if ($Before -eq $After) { Add-Report @('The list before and after the restart is identical.', '') }
else { Add-Report @('**Warning:** the list differed before and after the restart.', ''); $script:Failures++ }
Add-Report @('With an in-memory URL (`jdbc:h2:mem:studentdb`) the database would be dropped when the JVM exits: only the three seeds would come back, with new ids, and the marker would be gone.', '')

Api '4.4 Cleanup: delete the marker' DELETE "/students/$MarkerId"; Expect 204

# ---------------------------------------------------------------- Logging + explanation
Add-Report @('## 5. Logging sample', '', 'From `logs/student-api.log`: successful mutations at INFO and failed requests at WARN, each with timestamp, level, thread and class name. No full student records are logged.', '', ($Fence + 'text'))
Add-Report ([string[]](Grep-Log (Join-Path $Root 'logs\student-api.log') 'StudentService|GlobalExceptionHandler|DataSeeder' | Select-Object -First 25))
Add-Report @($Fence, '')

Add-Report @('## 6. Why the service layer is separate from the controller', '')
Add-Report @('The controller only handles HTTP: it maps URLs, reads JSON, triggers bean validation and picks status codes. The service owns the business rules: USN normalisation and uniqueness, "PUT never creates", transactions and mutation logging. Keeping them apart means the same rules apply whether a request comes from REST, the startup seeder or a future batch job, and each layer can be tested on its own (the service with a mocked repository, the controller with a mocked service). It also lets the transport change, for example to GraphQL or messaging, without touching the logic that protects the data.', '')

Stop-App

Add-Report @('---', '', "Result: **$($script:Failures) unexpected status code(s)**. Full console output: ``evidence/run1-console.log``, ``evidence/run2-console.log``.")
Say ''
if ($script:Failures -eq 0) { Say 'RESULT: PASS - all scenarios returned the expected status codes. Report: REPORT.md' }
else { Say "RESULT: $($script:Failures) scenario(s) returned unexpected codes. See REPORT.md" }
