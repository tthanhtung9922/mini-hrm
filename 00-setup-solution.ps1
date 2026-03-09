# ─────────────────────────────────────────────
#  MiniHRM – Clean Architecture Setup Script
#  Requires: .NET 10 SDK
# ─────────────────────────────────────────────
param (
    [string]$Solution  = "MiniHRM",
    [string]$Framework = "net10.0"
)

$ErrorActionPreference = "Stop"

# ── Logging setup ─────────────────────────────
$LogFile = "setup-minihrm_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$script:LogBuffer = [System.Collections.Generic.List[string]]::new()

function Write-Log {
    param([string]$Level, [string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $script:LogBuffer.Add("[$timestamp] [$Level] $Message")
}

function Flush-Log {
    $script:LogBuffer | Set-Content -Path $LogFile
}

function Write-Info { param([string]$msg) Write-Host $msg -ForegroundColor DarkGray;   Write-Log "INFO"  $msg }
function Write-Step { param([string]$msg) Write-Host $msg -ForegroundColor Yellow;     Write-Log "STEP"  $msg }
function Write-Ok   { param([string]$msg) Write-Host $msg -ForegroundColor Green;      Write-Log "OK"    $msg }
function Write-Warn { param([string]$msg) Write-Host $msg -ForegroundColor DarkYellow; Write-Log "WARN"  $msg }
function Write-Err  { param([string]$msg) Write-Host $msg -ForegroundColor Red;        Write-Log "ERROR" $msg }

function Invoke-Cmd {
    param([string]$Description, [scriptblock]$Command)
    Write-Info "  >> $Description"
    Write-Log "CMD" $Description

    $output = & $Command 2>&1
    $output | ForEach-Object { Write-Log "OUT" "$_" }

    if ($LASTEXITCODE -ne 0) {
        Write-Err "[ERROR] Failed: $Description"
        Write-Log "ERROR" "Exit code: $LASTEXITCODE"
        Write-Log "ERROR" "Output: $($output -join ' | ')"
        Flush-Log
        Write-Host ""
        Write-Err "  Log saved to: $LogFile"
        exit 1
    }
}

# ── Prerequisites check ───────────────────────
Write-Log "INFO" "===== Setup started: $Solution ====="
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Setting up $Solution solution"         -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Err "[ERROR] .NET SDK not found. Please install .NET 10 SDK first."
    Flush-Log
    Write-Host "  Log saved to: $LogFile" -ForegroundColor Red
    exit 1
}

$dotnetVersion = dotnet --version
Write-Ok "[OK] .NET SDK found: $dotnetVersion"
Write-Log "INFO" "OS: $([System.Environment]::OSVersion.VersionString)"
Write-Log "INFO" "PowerShell: $($PSVersionTable.PSVersion)"
Write-Log "INFO" "Working dir: $(Get-Location)"
Write-Host ""

# ── [1/7] Create solution ─────────────────────
Write-Step "[1/7] Creating solution..."
Invoke-Cmd "Create solution" { dotnet new sln -n $Solution }
Write-Host ""

# ── [2/7] Source projects ─────────────────────
Write-Step "[2/7] Creating source projects..."
Invoke-Cmd "Domain"         { dotnet new classlib -n "$Solution.Domain"         -o "src/$Solution.Domain"         --framework $Framework }
Invoke-Cmd "Application"    { dotnet new classlib -n "$Solution.Application"    -o "src/$Solution.Application"    --framework $Framework }
Invoke-Cmd "Infrastructure" { dotnet new classlib -n "$Solution.Infrastructure" -o "src/$Solution.Infrastructure" --framework $Framework }
Invoke-Cmd "API"            { dotnet new webapi   -n "$Solution.API"            -o "src/$Solution.API"            --framework $Framework --use-controllers }
Write-Host ""

# ── [3/7] Test projects ───────────────────────
Write-Step "[3/7] Creating test projects..."
Invoke-Cmd "Domain.Tests"       { dotnet new xunit -n "$Solution.Domain.Tests"       -o "tests/$Solution.Domain.Tests"       --framework $Framework }
Invoke-Cmd "Application.Tests"  { dotnet new xunit -n "$Solution.Application.Tests"  -o "tests/$Solution.Application.Tests"  --framework $Framework }
Invoke-Cmd "API.Tests"          { dotnet new xunit -n "$Solution.API.Tests"          -o "tests/$Solution.API.Tests"          --framework $Framework }
Write-Host ""

# ── [4/7] Add projects to solution ───────────
Write-Step "[4/7] Adding projects to solution..."
$projects = @(
    "src/$Solution.Domain/$Solution.Domain.csproj",
    "src/$Solution.Application/$Solution.Application.csproj",
    "src/$Solution.Infrastructure/$Solution.Infrastructure.csproj",
    "src/$Solution.API/$Solution.API.csproj",
    "tests/$Solution.Domain.Tests/$Solution.Domain.Tests.csproj",
    "tests/$Solution.Application.Tests/$Solution.Application.Tests.csproj",
    "tests/$Solution.API.Tests/$Solution.API.Tests.csproj"
)
foreach ($proj in $projects) {
    Invoke-Cmd "Add $proj" { dotnet sln "$Solution.slnx" add $proj }
}
Write-Host ""

# ── [5/7] Project references ──────────────────
Write-Step "[5/7] Setting up project references..."

Invoke-Cmd "Application -> Domain" {
    dotnet add "src/$Solution.Application/$Solution.Application.csproj" reference "src/$Solution.Domain/$Solution.Domain.csproj"
}
Invoke-Cmd "Infrastructure -> Application" {
    dotnet add "src/$Solution.Infrastructure/$Solution.Infrastructure.csproj" reference "src/$Solution.Application/$Solution.Application.csproj"
}
Invoke-Cmd "Infrastructure -> Domain" {
    dotnet add "src/$Solution.Infrastructure/$Solution.Infrastructure.csproj" reference "src/$Solution.Domain/$Solution.Domain.csproj"
}
Invoke-Cmd "API -> Application" {
    dotnet add "src/$Solution.API/$Solution.API.csproj" reference "src/$Solution.Application/$Solution.Application.csproj"
}
Invoke-Cmd "API -> Infrastructure" {
    dotnet add "src/$Solution.API/$Solution.API.csproj" reference "src/$Solution.Infrastructure/$Solution.Infrastructure.csproj"
}
Invoke-Cmd "Domain.Tests -> Domain" {
    dotnet add "tests/$Solution.Domain.Tests/$Solution.Domain.Tests.csproj" reference "src/$Solution.Domain/$Solution.Domain.csproj"
}
Invoke-Cmd "Application.Tests -> Application" {
    dotnet add "tests/$Solution.Application.Tests/$Solution.Application.Tests.csproj" reference "src/$Solution.Application/$Solution.Application.csproj"
}
Invoke-Cmd "Application.Tests -> Domain" {
    dotnet add "tests/$Solution.Application.Tests/$Solution.Application.Tests.csproj" reference "src/$Solution.Domain/$Solution.Domain.csproj"
}
Invoke-Cmd "API.Tests -> API" {
    dotnet add "tests/$Solution.API.Tests/$Solution.API.Tests.csproj" reference "src/$Solution.API/$Solution.API.csproj"
}
Invoke-Cmd "API.Tests -> Infrastructure" {
    dotnet add "tests/$Solution.API.Tests/$Solution.API.Tests.csproj" reference "src/$Solution.Infrastructure/$Solution.Infrastructure.csproj"
}
Invoke-Cmd "API.Tests -> Application" {
    dotnet add "tests/$Solution.API.Tests/$Solution.API.Tests.csproj" reference "src/$Solution.Application/$Solution.Application.csproj"
}
Write-Host ""

# ── [6/7] Remove default generated files ─────
Write-Step "[6/7] Removing default generated files..."

$filesToDelete = @(
    "src/$Solution.Domain/Class1.cs",
    "src/$Solution.Application/Class1.cs",
    "src/$Solution.Infrastructure/Class1.cs",
    "src/$Solution.API/WeatherForecast.cs",
    "src/$Solution.API/Controllers/WeatherForecastController.cs",
    "tests/$Solution.Domain.Tests/UnitTest1.cs",
    "tests/$Solution.Application.Tests/UnitTest1.cs",
    "tests/$Solution.API.Tests/UnitTest1.cs"
)

foreach ($file in $filesToDelete) {
    if (Test-Path $file) {
        Remove-Item $file -Force
        Write-Info "  >> Deleted: $file"
    } else {
        Write-Warn "  >> Skipped (not found): $file"
    }
}
Write-Host ""

# ── [7/7] Install NuGet packages ─────────────
Write-Step "[7/7] Installing NuGet packages..."

# Domain: intentionally no packages (zero dependencies)
Write-Info "  >> Domain: no packages (pure domain model)"

# Application
$appPkg = @(
    "MediatR",
    "FluentValidation",
    "FluentValidation.DependencyInjectionExtensions",
    "Mapster",
    "Mapster.DependencyInjection",
    "Microsoft.Extensions.Logging.Abstractions"
)
foreach ($pkg in $appPkg) {
    Invoke-Cmd "Application: $pkg" { dotnet add "src/$Solution.Application/$Solution.Application.csproj" package $pkg }
}

# Infrastructure
$infraPkg = @(
    "Microsoft.EntityFrameworkCore",
    "Microsoft.EntityFrameworkCore.SqlServer",
    "Microsoft.EntityFrameworkCore.Tools",
    "Microsoft.AspNetCore.Identity.EntityFrameworkCore",
    "Microsoft.AspNetCore.Authentication.JwtBearer",
    "Microsoft.Extensions.Configuration.Abstractions"
)
foreach ($pkg in $infraPkg) {
    Invoke-Cmd "Infrastructure: $pkg" { dotnet add "src/$Solution.Infrastructure/$Solution.Infrastructure.csproj" package $pkg }
}

# API
$apiPkg = @(
    "Serilog.AspNetCore",
    "Serilog.Sinks.Console",
    "Serilog.Sinks.File",
    "Serilog.Sinks.Seq",
    "Serilog.Enrichers.Environment",
    "Serilog.Enrichers.Process",
    "Serilog.Enrichers.Thread",
    "Asp.Versioning.Mvc",
    "Asp.Versioning.Mvc.ApiExplorer",
    "Swashbuckle.AspNetCore",
    "Microsoft.AspNetCore.Diagnostics.HealthChecks",
    "AspNetCore.HealthChecks.SqlServer"
)
foreach ($pkg in $apiPkg) {
    Invoke-Cmd "API: $pkg" { dotnet add "src/$Solution.API/$Solution.API.csproj" package $pkg }
}

# Domain.Tests
$domainTestPkg = @("FluentAssertions")
foreach ($pkg in $domainTestPkg) {
    Invoke-Cmd "Domain.Tests: $pkg" { dotnet add "tests/$Solution.Domain.Tests/$Solution.Domain.Tests.csproj" package $pkg }
}

# Application.Tests
$appTestPkg = @("FluentAssertions", "NSubstitute", "Bogus")
foreach ($pkg in $appTestPkg) {
    Invoke-Cmd "Application.Tests: $pkg" { dotnet add "tests/$Solution.Application.Tests/$Solution.Application.Tests.csproj" package $pkg }
}

# API.Tests (integration)
$apiTestPkg = @(
    "FluentAssertions",
    "Microsoft.AspNetCore.Mvc.Testing",
    "Testcontainers.MsSql",
    "Bogus"
)
foreach ($pkg in $apiTestPkg) {
    Invoke-Cmd "API.Tests: $pkg" { dotnet add "tests/$Solution.API.Tests/$Solution.API.Tests.csproj" package $pkg }
}
Write-Host ""

# ── Build ─────────────────────────────────────
Write-Step "Building solution..."
Invoke-Cmd "dotnet build" { dotnet build "$Solution.slnx" }

# ── Done ──────────────────────────────────────
Write-Log "INFO" "===== Setup completed successfully ====="
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  [OK] $Solution setup complete!"        -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Project structure:" -ForegroundColor Cyan
Write-Host "  src/"
Write-Host "    $Solution.Domain"
Write-Host "    $Solution.Application       -> Domain"
Write-Host "    $Solution.Infrastructure    -> Application, Domain"
Write-Host "    $Solution.API               -> Application, Infrastructure"
Write-Host "  tests/"
Write-Host "    $Solution.Domain.Tests      -> Domain"
Write-Host "    $Solution.Application.Tests -> Application, Domain"
Write-Host "    $Solution.API.Tests         -> API, Infrastructure, Application"
Write-Host ""