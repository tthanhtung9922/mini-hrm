# MiniHRM Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a production-grade HRM backend API demonstrating Clean Architecture, DDD-lite, and CQRS patterns on .NET 10.

**Architecture:** Clean Architecture with 4 layers (Domain → Application → Infrastructure → API), DDD-lite tactical patterns (Value Objects, Aggregates, Domain Events), CQRS via MediatR, EF Core 10 Code First with SQL Server 2025.

**Tech Stack:** .NET 10, EF Core 10, SQL Server 2025, MediatR 14.x, FluentValidation 12.x, Mapster, Asp.Versioning.Mvc, Serilog, xUnit, NSubstitute, FluentAssertions, Bogus, Testcontainers, Docker, GitHub Actions.

**Design doc:** `docs/plans/2026-03-09-mini-hrm-design.md`

---

## Phase 1: Solution Scaffolding & Docker Setup

**Progress:** Task 1.1 ✅ · Task 1.2 ✅ · Task 1.3 ⬜ · Task 1.4 ⬜

---

### Task 1.1: Create Solution and Projects ✅ DONE

> Automated via `00-setup-solution.ps1`. Commit: `6bd6fcd chore: scaffold Clean Architecture solution with test projects`

**⚠️ .NET 10 deviation:** `dotnet new sln` now creates `MiniHRM.slnx` (new XML format), not `MiniHRM.sln`. All `dotnet sln` and `dotnet build` commands must reference `MiniHRM.slnx`.

**Files created:**
- `MiniHRM.slnx` *(not `.sln` — .NET 10 default)*
- `src/MiniHRM.Domain/MiniHRM.Domain.csproj`
- `src/MiniHRM.Application/MiniHRM.Application.csproj`
- `src/MiniHRM.Infrastructure/MiniHRM.Infrastructure.csproj`
- `src/MiniHRM.API/MiniHRM.API.csproj`
- `tests/MiniHRM.Domain.Tests/MiniHRM.Domain.Tests.csproj`
- `tests/MiniHRM.Application.Tests/MiniHRM.Application.Tests.csproj`
- `tests/MiniHRM.API.Tests/MiniHRM.API.Tests.csproj`

**Project references (verified):**
- Application → Domain
- Infrastructure → Application, Domain
- API → Application, Infrastructure
- Domain.Tests → Domain
- Application.Tests → Application, Domain
- API.Tests → API, Infrastructure, Application

**Steps completed:**
1. ✅ Created solution and all source/test projects
2. ✅ Added all projects to `MiniHRM.slnx`
3. ✅ Set up all project references (Clean Architecture dependency direction enforced)
4. ✅ Removed boilerplate (`Class1.cs`, `WeatherForecast*`, `UnitTest1.cs`)
5. ✅ Solution builds successfully
6. ✅ Committed

---

### Task 1.2: Install NuGet Packages ✅ DONE

> Automated via `00-setup-solution.ps1`. Builds clean after all packages installed.

**⚠️ Package correction:** `MapsterMapper` does not exist on NuGet. Replaced with `Mapster.DependencyInjection`.

**Domain:** No packages (intentional — zero external dependencies).

**Application packages installed:**
- `MediatR`
- `FluentValidation`
- `FluentValidation.DependencyInjectionExtensions`
- `Mapster`
- `Mapster.DependencyInjection` *(replaces the incorrect `MapsterMapper`)*
- `Microsoft.Extensions.Logging.Abstractions`

**Infrastructure packages installed:**
- `Microsoft.EntityFrameworkCore`
- `Microsoft.EntityFrameworkCore.SqlServer`
- `Microsoft.EntityFrameworkCore.Tools`
- `Microsoft.AspNetCore.Identity.EntityFrameworkCore`
- `Microsoft.AspNetCore.Authentication.JwtBearer`
- `Microsoft.Extensions.Configuration.Abstractions`

**API packages installed:**
- `Serilog.AspNetCore`
- `Serilog.Sinks.Console`
- `Serilog.Sinks.File`
- `Serilog.Sinks.Seq`
- `Serilog.Enrichers.Environment`
- `Serilog.Enrichers.Process`
- `Serilog.Enrichers.Thread`
- `Asp.Versioning.Mvc`
- `Asp.Versioning.Mvc.ApiExplorer`
- `Swashbuckle.AspNetCore`
- `AspNetCore.HealthChecks.SqlServer`
- ~~`Microsoft.AspNetCore.Diagnostics.HealthChecks`~~ *(removed — deprecated legacy package; `AddHealthChecks()` / `MapHealthChecks()` are built into `Microsoft.AspNetCore.App` since .NET 6)*

**Test packages installed:**
- All test projects: ~~`xunit` 2.9.x~~ → `xunit.v3` 3.2.2 *(xunit v2 is legacy/deprecated; v3 is the current release)*
- Domain.Tests: `FluentAssertions`
- Application.Tests: `FluentAssertions`, `NSubstitute`, `Bogus`
- API.Tests: `FluentAssertions`, `Microsoft.AspNetCore.Mvc.Testing`, `Testcontainers.MsSql`, `Bogus`

**Steps completed:**
1. ✅ Application packages added
2. ✅ Infrastructure packages added
3. ✅ API packages added
4. ✅ Test packages added
5. ✅ Solution builds successfully
6. ✅ Committed & pushed (`d9d05c1 chore: install NuGet packages for all layers`)

---

### Task 1.3: Docker & docker-compose Setup

**Files:**
- Create: `Dockerfile`
- Create: `docker-compose.yml`
- Create: `.dockerignore`

**Step 1: Create Dockerfile**

```dockerfile
# Build stage
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY MiniHRM.slnx .
COPY src/MiniHRM.Domain/MiniHRM.Domain.csproj src/MiniHRM.Domain/
COPY src/MiniHRM.Application/MiniHRM.Application.csproj src/MiniHRM.Application/
COPY src/MiniHRM.Infrastructure/MiniHRM.Infrastructure.csproj src/MiniHRM.Infrastructure/
COPY src/MiniHRM.API/MiniHRM.API.csproj src/MiniHRM.API/
RUN dotnet restore

COPY src/ src/
RUN dotnet publish src/MiniHRM.API/MiniHRM.API.csproj -c Release -o /app/publish --no-restore

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .
EXPOSE 8080
ENTRYPOINT ["dotnet", "MiniHRM.API.dll"]
```

**Step 2: Create docker-compose.yml**

```yaml
services:
  api:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "5000:8080"
    environment:
      - ASPNETCORE_ENVIRONMENT=Development
      - ConnectionStrings__DefaultConnection=Server=sqlserver;Database=MiniHRM;User Id=sa;Password=MiniHrm@2026!;TrustServerCertificate=True
    depends_on:
      sqlserver:
        condition: service_healthy

  sqlserver:
    image: mcr.microsoft.com/mssql/server:2025-latest
    environment:
      - ACCEPT_EULA=Y
      - MSSQL_SA_PASSWORD=MiniHrm@2026!
    ports:
      - "1433:1433"
    volumes:
      - sqlserver-data:/var/opt/mssql
    healthcheck:
      test: /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "MiniHrm@2026!" -Q "SELECT 1" -C -b
      interval: 10s
      timeout: 5s
      retries: 5

  seq:
    image: datalust/seq:latest
    environment:
      - ACCEPT_EULA=Y
    ports:
      - "5341:5341"
      - "8081:80"

volumes:
  sqlserver-data:
```

**Step 3: Create .dockerignore**

```
**/bin/
**/obj/
**/out/
**/.vs/
**/.git/
**/node_modules/
*.md
.gitignore
```

**Step 4: Commit**

```bash
git add Dockerfile docker-compose.yml .dockerignore
git commit -m "chore: add Docker and docker-compose configuration"
```

---

### Task 1.4: Create .gitignore and .editorconfig

**Files:**
- Create: `.gitignore`
- Create: `.editorconfig`

**Step 1: Create .gitignore**

Use the standard Visual Studio / .NET gitignore. Key entries:

```
## .NET
bin/
obj/
*.user
*.suo
*.userosscache
*.sln.docstates
.vs/
[Dd]ebug/
[Rr]elease/

## Rider
.idea/

## User secrets
secrets.json

## Environment
.env
appsettings.*.local.json
```

**Step 2: Create .editorconfig**

Standard C# .editorconfig with:
- `indent_style = space`, `indent_size = 4`
- `csharp_style_namespace_declarations = file_scoped:suggestion`
- `csharp_style_var_for_built_in_types = true:suggestion`
- `dotnet_sort_system_directives_first = true`

**Step 3: Commit**

```bash
git add .gitignore .editorconfig
git commit -m "chore: add .gitignore and .editorconfig"
```

---

## Phase 2: Domain Layer

### Task 2.1: Base Classes (BaseEntity, AggregateRoot)

**Files:**
- Create: `src/MiniHRM.Domain/Common/BaseEntity.cs`
- Create: `src/MiniHRM.Domain/Common/AggregateRoot.cs`
- Create: `src/MiniHRM.Domain/Common/IDomainEvent.cs`

**Step 1: Create IDomainEvent interface**

```csharp
// src/MiniHRM.Domain/Common/IDomainEvent.cs
using MediatR;

namespace MiniHRM.Domain.Common;

public interface IDomainEvent : INotification
{
}
```

> **WAIT — Domain should have zero dependencies!** MediatR is an Application concern. Instead, define IDomainEvent as a plain marker interface in Domain, and let Application/Infrastructure handle dispatching.

**Corrected Step 1: Create IDomainEvent as plain marker interface**

```csharp
// src/MiniHRM.Domain/Common/IDomainEvent.cs
namespace MiniHRM.Domain.Common;

public interface IDomainEvent
{
    DateTime OccurredOn { get; }
}
```

**Step 2: Create BaseEntity**

```csharp
// src/MiniHRM.Domain/Common/BaseEntity.cs
namespace MiniHRM.Domain.Common;

public abstract class BaseEntity
{
    public Guid Id { get; protected set; } = Guid.NewGuid();
    public DateTime CreatedAt { get; set; }
    public string? CreatedBy { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public string? UpdatedBy { get; set; }
    public bool IsDeleted { get; set; }
}
```

**Step 3: Create AggregateRoot**

```csharp
// src/MiniHRM.Domain/Common/AggregateRoot.cs
namespace MiniHRM.Domain.Common;

public abstract class AggregateRoot : BaseEntity
{
    private readonly List<IDomainEvent> _domainEvents = [];

    public IReadOnlyCollection<IDomainEvent> DomainEvents => _domainEvents.AsReadOnly();

    public void AddDomainEvent(IDomainEvent domainEvent)
    {
        _domainEvents.Add(domainEvent);
    }

    public void RemoveDomainEvent(IDomainEvent domainEvent)
    {
        _domainEvents.Remove(domainEvent);
    }

    public void ClearDomainEvents()
    {
        _domainEvents.Clear();
    }
}
```

**Step 4: Build and verify**

```bash
dotnet build src/MiniHRM.Domain
```

**Step 5: Commit**

```bash
git add src/MiniHRM.Domain/Common/
git commit -m "feat(domain): add BaseEntity, AggregateRoot, and IDomainEvent base classes"
```

---

### Task 2.2: Enums

**Files:**
- Create: `src/MiniHRM.Domain/Enums/Gender.cs`
- Create: `src/MiniHRM.Domain/Enums/EmploymentStatus.cs`
- Create: `src/MiniHRM.Domain/Enums/LeaveType.cs`
- Create: `src/MiniHRM.Domain/Enums/LeaveRequestStatus.cs`
- Create: `src/MiniHRM.Domain/Enums/AttendanceStatus.cs`

**Step 1: Create all enum files**

```csharp
// src/MiniHRM.Domain/Enums/Gender.cs
namespace MiniHRM.Domain.Enums;

public enum Gender
{
    Male = 0,
    Female = 1,
    Other = 2
}
```

```csharp
// src/MiniHRM.Domain/Enums/EmploymentStatus.cs
namespace MiniHRM.Domain.Enums;

public enum EmploymentStatus
{
    Active = 0,
    OnLeave = 1,
    Resigned = 2,
    Terminated = 3
}
```

```csharp
// src/MiniHRM.Domain/Enums/LeaveType.cs
namespace MiniHRM.Domain.Enums;

public enum LeaveType
{
    Annual = 0,
    Sick = 1,
    Unpaid = 2,
    Maternity = 3,
    Paternity = 4,
    Other = 5
}
```

```csharp
// src/MiniHRM.Domain/Enums/LeaveRequestStatus.cs
namespace MiniHRM.Domain.Enums;

public enum LeaveRequestStatus
{
    Pending = 0,
    Approved = 1,
    Rejected = 2,
    Cancelled = 3
}
```

```csharp
// src/MiniHRM.Domain/Enums/AttendanceStatus.cs
namespace MiniHRM.Domain.Enums;

public enum AttendanceStatus
{
    Present = 0,
    Absent = 1,
    Late = 2,
    HalfDay = 3
}
```

**Step 2: Build and verify**

```bash
dotnet build src/MiniHRM.Domain
```

**Step 3: Commit**

```bash
git add src/MiniHRM.Domain/Enums/
git commit -m "feat(domain): add domain enums"
```

---

### Task 2.3: Value Objects

**Files:**
- Create: `src/MiniHRM.Domain/ValueObjects/ValueObject.cs`
- Create: `src/MiniHRM.Domain/ValueObjects/Email.cs`
- Create: `src/MiniHRM.Domain/ValueObjects/FullName.cs`
- Create: `src/MiniHRM.Domain/ValueObjects/PhoneNumber.cs`
- Test: `tests/MiniHRM.Domain.Tests/ValueObjects/EmailTests.cs`
- Test: `tests/MiniHRM.Domain.Tests/ValueObjects/FullNameTests.cs`
- Test: `tests/MiniHRM.Domain.Tests/ValueObjects/PhoneNumberTests.cs`

**Step 1: Write failing tests for Email value object**

```csharp
// tests/MiniHRM.Domain.Tests/ValueObjects/EmailTests.cs
using FluentAssertions;
using MiniHRM.Domain.ValueObjects;

namespace MiniHRM.Domain.Tests.ValueObjects;

public class EmailTests
{
    [Theory]
    [InlineData("test@example.com")]
    [InlineData("user.name@company.co.uk")]
    public void Create_WithValidEmail_ShouldSucceed(string email)
    {
        var result = Email.Create(email);
        result.Value.Should().Be(email.ToLowerInvariant());
    }

    [Theory]
    [InlineData("")]
    [InlineData(null)]
    [InlineData("invalid")]
    [InlineData("@domain.com")]
    [InlineData("user@")]
    public void Create_WithInvalidEmail_ShouldThrow(string? email)
    {
        var act = () => Email.Create(email!);
        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void TwoEmails_WithSameValue_ShouldBeEqual()
    {
        var email1 = Email.Create("test@example.com");
        var email2 = Email.Create("TEST@EXAMPLE.COM");
        email1.Should().Be(email2);
    }
}
```

**Step 2: Run tests to verify they fail**

```bash
dotnet test tests/MiniHRM.Domain.Tests --filter "EmailTests" -v n
```

Expected: FAIL — `Email` class doesn't exist yet.

**Step 3: Create ValueObject base class**

```csharp
// src/MiniHRM.Domain/ValueObjects/ValueObject.cs
namespace MiniHRM.Domain.ValueObjects;

public abstract class ValueObject
{
    protected abstract IEnumerable<object?> GetEqualityComponents();

    public override bool Equals(object? obj)
    {
        if (obj is null || obj.GetType() != GetType())
            return false;

        var other = (ValueObject)obj;
        return GetEqualityComponents()
            .SequenceEqual(other.GetEqualityComponents());
    }

    public override int GetHashCode()
    {
        return GetEqualityComponents()
            .Select(x => x?.GetHashCode() ?? 0)
            .Aggregate((x, y) => x ^ y);
    }

    public static bool operator ==(ValueObject? left, ValueObject? right)
    {
        return Equals(left, right);
    }

    public static bool operator !=(ValueObject? left, ValueObject? right)
    {
        return !Equals(left, right);
    }
}
```

**Step 4: Create Email value object**

```csharp
// src/MiniHRM.Domain/ValueObjects/Email.cs
using System.Text.RegularExpressions;

namespace MiniHRM.Domain.ValueObjects;

public sealed partial class Email : ValueObject
{
    public string Value { get; }

    private Email(string value)
    {
        Value = value;
    }

    public static Email Create(string email)
    {
        if (string.IsNullOrWhiteSpace(email))
            throw new ArgumentException("Email cannot be empty.", nameof(email));

        email = email.Trim().ToLowerInvariant();

        if (!EmailRegex().IsMatch(email))
            throw new ArgumentException($"Invalid email format: {email}", nameof(email));

        return new Email(email);
    }

    protected override IEnumerable<object?> GetEqualityComponents()
    {
        yield return Value;
    }

    public override string ToString() => Value;

    [GeneratedRegex(@"^[^@\s]+@[^@\s]+\.[^@\s]+$", RegexOptions.Compiled)]
    private static partial Regex EmailRegex();
}
```

**Step 5: Run Email tests**

```bash
dotnet test tests/MiniHRM.Domain.Tests --filter "EmailTests" -v n
```

Expected: All PASS.

**Step 6: Write failing tests for FullName**

```csharp
// tests/MiniHRM.Domain.Tests/ValueObjects/FullNameTests.cs
using FluentAssertions;
using MiniHRM.Domain.ValueObjects;

namespace MiniHRM.Domain.Tests.ValueObjects;

public class FullNameTests
{
    [Fact]
    public void Create_WithValidNames_ShouldSucceed()
    {
        var name = FullName.Create("John", "Doe");
        name.FirstName.Should().Be("John");
        name.LastName.Should().Be("Doe");
    }

    [Theory]
    [InlineData("", "Doe")]
    [InlineData("John", "")]
    [InlineData(null, "Doe")]
    [InlineData("John", null)]
    public void Create_WithEmptyName_ShouldThrow(string? first, string? last)
    {
        var act = () => FullName.Create(first!, last!);
        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void ToString_ShouldReturnFullName()
    {
        var name = FullName.Create("John", "Doe");
        name.ToString().Should().Be("John Doe");
    }

    [Fact]
    public void TwoNames_WithSameValues_ShouldBeEqual()
    {
        var name1 = FullName.Create("John", "Doe");
        var name2 = FullName.Create("John", "Doe");
        name1.Should().Be(name2);
    }
}
```

**Step 7: Implement FullName**

```csharp
// src/MiniHRM.Domain/ValueObjects/FullName.cs
namespace MiniHRM.Domain.ValueObjects;

public sealed class FullName : ValueObject
{
    public string FirstName { get; }
    public string LastName { get; }

    private FullName(string firstName, string lastName)
    {
        FirstName = firstName;
        LastName = lastName;
    }

    public static FullName Create(string firstName, string lastName)
    {
        if (string.IsNullOrWhiteSpace(firstName))
            throw new ArgumentException("First name cannot be empty.", nameof(firstName));

        if (string.IsNullOrWhiteSpace(lastName))
            throw new ArgumentException("Last name cannot be empty.", nameof(lastName));

        return new FullName(firstName.Trim(), lastName.Trim());
    }

    protected override IEnumerable<object?> GetEqualityComponents()
    {
        yield return FirstName;
        yield return LastName;
    }

    public override string ToString() => $"{FirstName} {LastName}";
}
```

**Step 8: Run FullName tests**

```bash
dotnet test tests/MiniHRM.Domain.Tests --filter "FullNameTests" -v n
```

Expected: All PASS.

**Step 9: Write failing tests for PhoneNumber**

```csharp
// tests/MiniHRM.Domain.Tests/ValueObjects/PhoneNumberTests.cs
using FluentAssertions;
using MiniHRM.Domain.ValueObjects;

namespace MiniHRM.Domain.Tests.ValueObjects;

public class PhoneNumberTests
{
    [Theory]
    [InlineData("+1234567890")]
    [InlineData("0901234567")]
    [InlineData("+84 901 234 567")]
    public void Create_WithValidPhone_ShouldSucceed(string phone)
    {
        var result = PhoneNumber.Create(phone);
        result.Value.Should().NotBeEmpty();
    }

    [Theory]
    [InlineData("")]
    [InlineData(null)]
    [InlineData("abc")]
    [InlineData("12")]
    public void Create_WithInvalidPhone_ShouldThrow(string? phone)
    {
        var act = () => PhoneNumber.Create(phone!);
        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void Create_ShouldStripNonDigitCharacters()
    {
        var phone = PhoneNumber.Create("+84 901-234-567");
        phone.Value.Should().Be("84901234567");
    }
}
```

**Step 10: Implement PhoneNumber**

```csharp
// src/MiniHRM.Domain/ValueObjects/PhoneNumber.cs
using System.Text.RegularExpressions;

namespace MiniHRM.Domain.ValueObjects;

public sealed partial class PhoneNumber : ValueObject
{
    public string Value { get; }

    private PhoneNumber(string value)
    {
        Value = value;
    }

    public static PhoneNumber Create(string phoneNumber)
    {
        if (string.IsNullOrWhiteSpace(phoneNumber))
            throw new ArgumentException("Phone number cannot be empty.", nameof(phoneNumber));

        var digitsOnly = NonDigitRegex().Replace(phoneNumber, "");

        if (digitsOnly.Length < 7 || digitsOnly.Length > 15)
            throw new ArgumentException($"Invalid phone number: {phoneNumber}", nameof(phoneNumber));

        return new PhoneNumber(digitsOnly);
    }

    protected override IEnumerable<object?> GetEqualityComponents()
    {
        yield return Value;
    }

    public override string ToString() => Value;

    [GeneratedRegex(@"[^\d]", RegexOptions.Compiled)]
    private static partial Regex NonDigitRegex();
}
```

**Step 11: Run all Domain tests**

```bash
dotnet test tests/MiniHRM.Domain.Tests -v n
```

Expected: All PASS.

**Step 12: Commit**

```bash
git add src/MiniHRM.Domain/ValueObjects/ tests/MiniHRM.Domain.Tests/ValueObjects/
git commit -m "feat(domain): add Value Objects — Email, FullName, PhoneNumber with tests"
```

---

### Task 2.4: Domain Entities

**Files:**
- Create: `src/MiniHRM.Domain/Entities/Department.cs`
- Create: `src/MiniHRM.Domain/Entities/Position.cs`
- Create: `src/MiniHRM.Domain/Entities/Employee.cs`
- Create: `src/MiniHRM.Domain/Entities/LeaveRequest.cs`
- Create: `src/MiniHRM.Domain/Entities/Attendance.cs`
- Create: `src/MiniHRM.Domain/Entities/LeaveBalance.cs`

**Step 1: Create Department entity**

```csharp
// src/MiniHRM.Domain/Entities/Department.cs
using MiniHRM.Domain.Common;

namespace MiniHRM.Domain.Entities;

public class Department : AggregateRoot
{
    public string Name { get; private set; } = null!;
    public string? Description { get; private set; }
    public Guid? ManagerId { get; private set; }

    // Navigation properties
    public Employee? Manager { get; private set; }
    public ICollection<Employee> Employees { get; private set; } = [];
    public ICollection<Position> Positions { get; private set; } = [];

    private Department() { } // EF Core

    public static Department Create(string name, string? description = null)
    {
        if (string.IsNullOrWhiteSpace(name))
            throw new ArgumentException("Department name cannot be empty.", nameof(name));

        return new Department
        {
            Name = name.Trim(),
            Description = description?.Trim()
        };
    }

    public void Update(string name, string? description)
    {
        if (string.IsNullOrWhiteSpace(name))
            throw new ArgumentException("Department name cannot be empty.", nameof(name));

        Name = name.Trim();
        Description = description?.Trim();
    }

    public void AssignManager(Guid? managerId)
    {
        ManagerId = managerId;
    }
}
```

**Step 2: Create Position entity**

```csharp
// src/MiniHRM.Domain/Entities/Position.cs
using MiniHRM.Domain.Common;

namespace MiniHRM.Domain.Entities;

public class Position : AggregateRoot
{
    public string Title { get; private set; } = null!;
    public string? Description { get; private set; }
    public decimal MinSalary { get; private set; }
    public decimal MaxSalary { get; private set; }
    public Guid DepartmentId { get; private set; }

    // Navigation properties
    public Department Department { get; private set; } = null!;
    public ICollection<Employee> Employees { get; private set; } = [];

    private Position() { } // EF Core

    public static Position Create(string title, Guid departmentId, decimal minSalary, decimal maxSalary, string? description = null)
    {
        if (string.IsNullOrWhiteSpace(title))
            throw new ArgumentException("Position title cannot be empty.", nameof(title));

        if (minSalary < 0)
            throw new ArgumentException("Minimum salary cannot be negative.", nameof(minSalary));

        if (maxSalary < minSalary)
            throw new ArgumentException("Maximum salary cannot be less than minimum salary.", nameof(maxSalary));

        return new Position
        {
            Title = title.Trim(),
            Description = description?.Trim(),
            DepartmentId = departmentId,
            MinSalary = minSalary,
            MaxSalary = maxSalary
        };
    }

    public void Update(string title, decimal minSalary, decimal maxSalary, string? description)
    {
        if (string.IsNullOrWhiteSpace(title))
            throw new ArgumentException("Position title cannot be empty.", nameof(title));

        if (minSalary < 0)
            throw new ArgumentException("Minimum salary cannot be negative.", nameof(minSalary));

        if (maxSalary < minSalary)
            throw new ArgumentException("Maximum salary cannot be less than minimum salary.", nameof(maxSalary));

        Title = title.Trim();
        Description = description?.Trim();
        MinSalary = minSalary;
        MaxSalary = maxSalary;
    }
}
```

**Step 3: Create Employee entity**

```csharp
// src/MiniHRM.Domain/Entities/Employee.cs
using MiniHRM.Domain.Common;
using MiniHRM.Domain.Enums;
using MiniHRM.Domain.Events;
using MiniHRM.Domain.ValueObjects;

namespace MiniHRM.Domain.Entities;

public class Employee : AggregateRoot
{
    public FullName FullName { get; private set; } = null!;
    public Email Email { get; private set; } = null!;
    public PhoneNumber PhoneNumber { get; private set; } = null!;
    public DateTime DateOfBirth { get; private set; }
    public DateTime HireDate { get; private set; }
    public Gender Gender { get; private set; }
    public EmploymentStatus Status { get; private set; }
    public Guid DepartmentId { get; private set; }
    public Guid PositionId { get; private set; }

    // Navigation properties
    public Department Department { get; private set; } = null!;
    public Position Position { get; private set; } = null!;
    public ICollection<LeaveRequest> LeaveRequests { get; private set; } = [];
    public ICollection<Attendance> AttendanceRecords { get; private set; } = [];
    public ICollection<LeaveBalance> LeaveBalances { get; private set; } = [];

    private Employee() { } // EF Core

    public static Employee Create(
        FullName fullName,
        Email email,
        PhoneNumber phoneNumber,
        DateTime dateOfBirth,
        DateTime hireDate,
        Gender gender,
        Guid departmentId,
        Guid positionId)
    {
        var employee = new Employee
        {
            FullName = fullName,
            Email = email,
            PhoneNumber = phoneNumber,
            DateOfBirth = dateOfBirth,
            HireDate = hireDate,
            Gender = gender,
            Status = EmploymentStatus.Active,
            DepartmentId = departmentId,
            PositionId = positionId
        };

        employee.AddDomainEvent(new EmployeeCreatedEvent(employee.Id));

        return employee;
    }

    public void Update(
        FullName fullName,
        Email email,
        PhoneNumber phoneNumber,
        DateTime dateOfBirth,
        Gender gender,
        Guid departmentId,
        Guid positionId)
    {
        FullName = fullName;
        Email = email;
        PhoneNumber = phoneNumber;
        DateOfBirth = dateOfBirth;
        Gender = gender;
        DepartmentId = departmentId;
        PositionId = positionId;
    }

    public void UpdateStatus(EmploymentStatus status)
    {
        Status = status;
    }
}
```

**Step 4: Create LeaveRequest entity**

```csharp
// src/MiniHRM.Domain/Entities/LeaveRequest.cs
using MiniHRM.Domain.Common;
using MiniHRM.Domain.Enums;
using MiniHRM.Domain.Events;

namespace MiniHRM.Domain.Entities;

public class LeaveRequest : AggregateRoot
{
    public Guid EmployeeId { get; private set; }
    public LeaveType LeaveType { get; private set; }
    public DateTime StartDate { get; private set; }
    public DateTime EndDate { get; private set; }
    public string Reason { get; private set; } = null!;
    public LeaveRequestStatus Status { get; private set; }
    public Guid? ReviewedBy { get; private set; }
    public DateTime? ReviewedDate { get; private set; }
    public string? ReviewNote { get; private set; }

    // Navigation properties
    public Employee Employee { get; private set; } = null!;
    public Employee? Reviewer { get; private set; }

    private LeaveRequest() { } // EF Core

    public static LeaveRequest Create(
        Guid employeeId,
        LeaveType leaveType,
        DateTime startDate,
        DateTime endDate,
        string reason)
    {
        if (endDate < startDate)
            throw new ArgumentException("End date cannot be before start date.");

        if (string.IsNullOrWhiteSpace(reason))
            throw new ArgumentException("Reason is required.", nameof(reason));

        return new LeaveRequest
        {
            EmployeeId = employeeId,
            LeaveType = leaveType,
            StartDate = startDate.Date,
            EndDate = endDate.Date,
            Reason = reason.Trim(),
            Status = LeaveRequestStatus.Pending
        };
    }

    public int GetTotalDays()
    {
        return (EndDate - StartDate).Days + 1;
    }

    public void Approve(Guid reviewerId, string? note = null)
    {
        if (reviewerId == EmployeeId)
            throw new InvalidOperationException("Employee cannot approve their own leave request.");

        if (Status != LeaveRequestStatus.Pending)
            throw new InvalidOperationException($"Cannot approve a leave request with status: {Status}.");

        Status = LeaveRequestStatus.Approved;
        ReviewedBy = reviewerId;
        ReviewedDate = DateTime.UtcNow;
        ReviewNote = note?.Trim();

        AddDomainEvent(new LeaveRequestApprovedEvent(Id, EmployeeId, LeaveType, GetTotalDays()));
    }

    public void Reject(Guid reviewerId, string? note = null)
    {
        if (reviewerId == EmployeeId)
            throw new InvalidOperationException("Employee cannot reject their own leave request.");

        if (Status != LeaveRequestStatus.Pending)
            throw new InvalidOperationException($"Cannot reject a leave request with status: {Status}.");

        Status = LeaveRequestStatus.Rejected;
        ReviewedBy = reviewerId;
        ReviewedDate = DateTime.UtcNow;
        ReviewNote = note?.Trim();

        AddDomainEvent(new LeaveRequestRejectedEvent(Id, EmployeeId));
    }

    public void Cancel()
    {
        if (Status != LeaveRequestStatus.Pending && Status != LeaveRequestStatus.Approved)
            throw new InvalidOperationException($"Cannot cancel a leave request with status: {Status}.");

        Status = LeaveRequestStatus.Cancelled;
    }
}
```

**Step 5: Create Attendance entity**

```csharp
// src/MiniHRM.Domain/Entities/Attendance.cs
using MiniHRM.Domain.Common;
using MiniHRM.Domain.Enums;

namespace MiniHRM.Domain.Entities;

public class Attendance : BaseEntity
{
    public Guid EmployeeId { get; private set; }
    public DateOnly Date { get; private set; }
    public TimeOnly? CheckIn { get; private set; }
    public TimeOnly? CheckOut { get; private set; }
    public AttendanceStatus Status { get; private set; }
    public string? Note { get; private set; }

    // Navigation properties
    public Employee Employee { get; private set; } = null!;

    private Attendance() { } // EF Core

    public static Attendance Create(Guid employeeId, DateOnly date, AttendanceStatus status, string? note = null)
    {
        return new Attendance
        {
            EmployeeId = employeeId,
            Date = date,
            Status = status,
            Note = note?.Trim()
        };
    }

    public void RecordCheckIn(TimeOnly time)
    {
        CheckIn = time;
    }

    public void RecordCheckOut(TimeOnly time)
    {
        if (CheckIn.HasValue && time < CheckIn.Value)
            throw new InvalidOperationException("Check-out time cannot be before check-in time.");

        CheckOut = time;
    }

    public void UpdateStatus(AttendanceStatus status, string? note = null)
    {
        Status = status;
        Note = note?.Trim();
    }
}
```

**Step 6: Create LeaveBalance entity**

```csharp
// src/MiniHRM.Domain/Entities/LeaveBalance.cs
using MiniHRM.Domain.Common;
using MiniHRM.Domain.Enums;

namespace MiniHRM.Domain.Entities;

public class LeaveBalance : BaseEntity
{
    public Guid EmployeeId { get; private set; }
    public LeaveType LeaveType { get; private set; }
    public int Year { get; private set; }
    public decimal TotalDays { get; private set; }
    public decimal UsedDays { get; private set; }
    public decimal RemainingDays => TotalDays - UsedDays;

    // Navigation properties
    public Employee Employee { get; private set; } = null!;

    private LeaveBalance() { } // EF Core

    public static LeaveBalance Create(Guid employeeId, LeaveType leaveType, int year, decimal totalDays)
    {
        if (totalDays < 0)
            throw new ArgumentException("Total days cannot be negative.", nameof(totalDays));

        return new LeaveBalance
        {
            EmployeeId = employeeId,
            LeaveType = leaveType,
            Year = year,
            TotalDays = totalDays,
            UsedDays = 0
        };
    }

    public void Deduct(decimal days)
    {
        if (days <= 0)
            throw new ArgumentException("Days to deduct must be positive.", nameof(days));

        if (days > RemainingDays)
            throw new InvalidOperationException($"Insufficient leave balance. Remaining: {RemainingDays}, Requested: {days}.");

        UsedDays += days;
    }

    public void Restore(decimal days)
    {
        if (days <= 0)
            throw new ArgumentException("Days to restore must be positive.", nameof(days));

        UsedDays = Math.Max(0, UsedDays - days);
    }

    public void AdjustTotalDays(decimal totalDays)
    {
        if (totalDays < 0)
            throw new ArgumentException("Total days cannot be negative.", nameof(totalDays));

        TotalDays = totalDays;
    }
}
```

**Step 7: Build and verify**

```bash
dotnet build src/MiniHRM.Domain
```

Expected: FAIL — Domain Events referenced in Employee and LeaveRequest don't exist yet. That's Task 2.5.

---

### Task 2.5: Domain Events

**Files:**
- Create: `src/MiniHRM.Domain/Events/EmployeeCreatedEvent.cs`
- Create: `src/MiniHRM.Domain/Events/LeaveRequestApprovedEvent.cs`
- Create: `src/MiniHRM.Domain/Events/LeaveRequestRejectedEvent.cs`

**Step 1: Create domain event classes**

```csharp
// src/MiniHRM.Domain/Events/EmployeeCreatedEvent.cs
using MiniHRM.Domain.Common;

namespace MiniHRM.Domain.Events;

public sealed class EmployeeCreatedEvent : IDomainEvent
{
    public Guid EmployeeId { get; }
    public DateTime OccurredOn { get; } = DateTime.UtcNow;

    public EmployeeCreatedEvent(Guid employeeId)
    {
        EmployeeId = employeeId;
    }
}
```

```csharp
// src/MiniHRM.Domain/Events/LeaveRequestApprovedEvent.cs
using MiniHRM.Domain.Common;
using MiniHRM.Domain.Enums;

namespace MiniHRM.Domain.Events;

public sealed class LeaveRequestApprovedEvent : IDomainEvent
{
    public Guid LeaveRequestId { get; }
    public Guid EmployeeId { get; }
    public LeaveType LeaveType { get; }
    public int TotalDays { get; }
    public DateTime OccurredOn { get; } = DateTime.UtcNow;

    public LeaveRequestApprovedEvent(Guid leaveRequestId, Guid employeeId, LeaveType leaveType, int totalDays)
    {
        LeaveRequestId = leaveRequestId;
        EmployeeId = employeeId;
        LeaveType = leaveType;
        TotalDays = totalDays;
    }
}
```

```csharp
// src/MiniHRM.Domain/Events/LeaveRequestRejectedEvent.cs
using MiniHRM.Domain.Common;

namespace MiniHRM.Domain.Events;

public sealed class LeaveRequestRejectedEvent : IDomainEvent
{
    public Guid LeaveRequestId { get; }
    public Guid EmployeeId { get; }
    public DateTime OccurredOn { get; } = DateTime.UtcNow;

    public LeaveRequestRejectedEvent(Guid leaveRequestId, Guid employeeId)
    {
        LeaveRequestId = leaveRequestId;
        EmployeeId = employeeId;
    }
}
```

**Step 2: Build entire Domain**

```bash
dotnet build src/MiniHRM.Domain
```

Expected: Build succeeded.

**Step 3: Commit**

```bash
git add src/MiniHRM.Domain/Entities/ src/MiniHRM.Domain/Events/
git commit -m "feat(domain): add entities (Department, Position, Employee, LeaveRequest, Attendance, LeaveBalance) and domain events"
```

---

### Task 2.6: Domain Entity Tests

**Files:**
- Create: `tests/MiniHRM.Domain.Tests/Entities/LeaveRequestTests.cs`
- Create: `tests/MiniHRM.Domain.Tests/Entities/LeaveBalanceTests.cs`
- Create: `tests/MiniHRM.Domain.Tests/Entities/AttendanceTests.cs`
- Create: `tests/MiniHRM.Domain.Tests/Entities/DepartmentTests.cs`

**Step 1: Write LeaveRequest tests**

```csharp
// tests/MiniHRM.Domain.Tests/Entities/LeaveRequestTests.cs
using FluentAssertions;
using MiniHRM.Domain.Entities;
using MiniHRM.Domain.Enums;
using MiniHRM.Domain.Events;

namespace MiniHRM.Domain.Tests.Entities;

public class LeaveRequestTests
{
    private readonly Guid _employeeId = Guid.NewGuid();
    private readonly Guid _reviewerId = Guid.NewGuid();

    private LeaveRequest CreatePendingRequest()
    {
        return LeaveRequest.Create(
            _employeeId,
            LeaveType.Annual,
            DateTime.Today.AddDays(1),
            DateTime.Today.AddDays(3),
            "Vacation");
    }

    [Fact]
    public void Create_ShouldSetStatusToPending()
    {
        var request = CreatePendingRequest();
        request.Status.Should().Be(LeaveRequestStatus.Pending);
    }

    [Fact]
    public void Create_WithEndDateBeforeStartDate_ShouldThrow()
    {
        var act = () => LeaveRequest.Create(
            _employeeId, LeaveType.Annual,
            DateTime.Today.AddDays(3), DateTime.Today.AddDays(1), "Test");

        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void GetTotalDays_ShouldReturnInclusiveDayCount()
    {
        var request = CreatePendingRequest(); // 3 days: day1, day2, day3
        request.GetTotalDays().Should().Be(3);
    }

    [Fact]
    public void Approve_ShouldChangeStatusAndRaiseDomainEvent()
    {
        var request = CreatePendingRequest();

        request.Approve(_reviewerId, "Looks good");

        request.Status.Should().Be(LeaveRequestStatus.Approved);
        request.ReviewedBy.Should().Be(_reviewerId);
        request.ReviewNote.Should().Be("Looks good");
        request.DomainEvents.Should().ContainSingle(e => e is LeaveRequestApprovedEvent);
    }

    [Fact]
    public void Approve_BySameEmployee_ShouldThrow()
    {
        var request = CreatePendingRequest();

        var act = () => request.Approve(_employeeId);

        act.Should().Throw<InvalidOperationException>()
            .WithMessage("*cannot approve their own*");
    }

    [Fact]
    public void Approve_WhenNotPending_ShouldThrow()
    {
        var request = CreatePendingRequest();
        request.Approve(_reviewerId);

        var act = () => request.Approve(_reviewerId);

        act.Should().Throw<InvalidOperationException>();
    }

    [Fact]
    public void Reject_ShouldChangeStatusAndRaiseDomainEvent()
    {
        var request = CreatePendingRequest();

        request.Reject(_reviewerId, "Not enough notice");

        request.Status.Should().Be(LeaveRequestStatus.Rejected);
        request.DomainEvents.Should().ContainSingle(e => e is LeaveRequestRejectedEvent);
    }

    [Fact]
    public void Cancel_WhenPending_ShouldSucceed()
    {
        var request = CreatePendingRequest();
        request.Cancel();
        request.Status.Should().Be(LeaveRequestStatus.Cancelled);
    }

    [Fact]
    public void Cancel_WhenRejected_ShouldThrow()
    {
        var request = CreatePendingRequest();
        request.Reject(_reviewerId);

        var act = () => request.Cancel();

        act.Should().Throw<InvalidOperationException>();
    }
}
```

**Step 2: Write LeaveBalance tests**

```csharp
// tests/MiniHRM.Domain.Tests/Entities/LeaveBalanceTests.cs
using FluentAssertions;
using MiniHRM.Domain.Entities;
using MiniHRM.Domain.Enums;

namespace MiniHRM.Domain.Tests.Entities;

public class LeaveBalanceTests
{
    [Fact]
    public void Create_ShouldInitializeWithZeroUsedDays()
    {
        var balance = LeaveBalance.Create(Guid.NewGuid(), LeaveType.Annual, 2026, 12);

        balance.TotalDays.Should().Be(12);
        balance.UsedDays.Should().Be(0);
        balance.RemainingDays.Should().Be(12);
    }

    [Fact]
    public void Deduct_ShouldReduceRemainingDays()
    {
        var balance = LeaveBalance.Create(Guid.NewGuid(), LeaveType.Annual, 2026, 12);

        balance.Deduct(3);

        balance.UsedDays.Should().Be(3);
        balance.RemainingDays.Should().Be(9);
    }

    [Fact]
    public void Deduct_ExceedingBalance_ShouldThrow()
    {
        var balance = LeaveBalance.Create(Guid.NewGuid(), LeaveType.Annual, 2026, 5);

        var act = () => balance.Deduct(6);

        act.Should().Throw<InvalidOperationException>()
            .WithMessage("*Insufficient*");
    }

    [Fact]
    public void Restore_ShouldIncreaseRemainingDays()
    {
        var balance = LeaveBalance.Create(Guid.NewGuid(), LeaveType.Annual, 2026, 12);
        balance.Deduct(5);

        balance.Restore(3);

        balance.UsedDays.Should().Be(2);
        balance.RemainingDays.Should().Be(10);
    }
}
```

**Step 3: Run all Domain tests**

```bash
dotnet test tests/MiniHRM.Domain.Tests -v n
```

Expected: All PASS.

**Step 4: Commit**

```bash
git add tests/MiniHRM.Domain.Tests/Entities/
git commit -m "test(domain): add unit tests for LeaveRequest and LeaveBalance entities"
```

---

### Task 2.7: Domain Repository Interfaces

**Files:**
- Create: `src/MiniHRM.Domain/Interfaces/IGenericRepository.cs`
- Create: `src/MiniHRM.Domain/Interfaces/IEmployeeRepository.cs`
- Create: `src/MiniHRM.Domain/Interfaces/ILeaveRequestRepository.cs`
- Create: `src/MiniHRM.Domain/Interfaces/IAttendanceRepository.cs`
- Create: `src/MiniHRM.Domain/Interfaces/IUnitOfWork.cs`

**Step 1: Create interfaces**

```csharp
// src/MiniHRM.Domain/Interfaces/IGenericRepository.cs
using System.Linq.Expressions;
using MiniHRM.Domain.Common;

namespace MiniHRM.Domain.Interfaces;

public interface IGenericRepository<T> where T : BaseEntity
{
    Task<T?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<T>> GetAllAsync(CancellationToken cancellationToken = default);
    Task<IReadOnlyList<T>> FindAsync(Expression<Func<T, bool>> predicate, CancellationToken cancellationToken = default);
    IQueryable<T> Query();
    Task AddAsync(T entity, CancellationToken cancellationToken = default);
    void Update(T entity);
    void Delete(T entity);
    Task<bool> ExistsAsync(Guid id, CancellationToken cancellationToken = default);
}
```

```csharp
// src/MiniHRM.Domain/Interfaces/IEmployeeRepository.cs
using MiniHRM.Domain.Entities;

namespace MiniHRM.Domain.Interfaces;

public interface IEmployeeRepository : IGenericRepository<Employee>
{
    Task<Employee?> GetByEmailAsync(string email, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<Employee>> GetByDepartmentAsync(Guid departmentId, CancellationToken cancellationToken = default);
}
```

```csharp
// src/MiniHRM.Domain/Interfaces/ILeaveRequestRepository.cs
using MiniHRM.Domain.Entities;
using MiniHRM.Domain.Enums;

namespace MiniHRM.Domain.Interfaces;

public interface ILeaveRequestRepository : IGenericRepository<LeaveRequest>
{
    Task<IReadOnlyList<LeaveRequest>> GetByEmployeeIdAsync(Guid employeeId, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<LeaveRequest>> GetByStatusAsync(LeaveRequestStatus status, CancellationToken cancellationToken = default);
    Task<bool> HasOverlappingRequestAsync(Guid employeeId, DateTime startDate, DateTime endDate, Guid? excludeId = null, CancellationToken cancellationToken = default);
}
```

```csharp
// src/MiniHRM.Domain/Interfaces/IAttendanceRepository.cs
using MiniHRM.Domain.Entities;

namespace MiniHRM.Domain.Interfaces;

public interface IAttendanceRepository : IGenericRepository<Attendance>
{
    Task<Attendance?> GetByEmployeeDateAsync(Guid employeeId, DateOnly date, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<Attendance>> GetByEmployeeRangeAsync(Guid employeeId, DateOnly startDate, DateOnly endDate, CancellationToken cancellationToken = default);
}
```

```csharp
// src/MiniHRM.Domain/Interfaces/IUnitOfWork.cs
namespace MiniHRM.Domain.Interfaces;

public interface IUnitOfWork : IDisposable
{
    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
```

**Step 2: Build and verify**

```bash
dotnet build src/MiniHRM.Domain
```

**Step 3: Commit**

```bash
git add src/MiniHRM.Domain/Interfaces/
git commit -m "feat(domain): add repository interfaces and IUnitOfWork"
```

---

## Phase 3: Infrastructure Layer

### Task 3.1: ApplicationDbContext and Entity Configurations

**Files:**
- Create: `src/MiniHRM.Infrastructure/Data/ApplicationDbContext.cs`
- Create: `src/MiniHRM.Infrastructure/Data/Configurations/DepartmentConfiguration.cs`
- Create: `src/MiniHRM.Infrastructure/Data/Configurations/PositionConfiguration.cs`
- Create: `src/MiniHRM.Infrastructure/Data/Configurations/EmployeeConfiguration.cs`
- Create: `src/MiniHRM.Infrastructure/Data/Configurations/LeaveRequestConfiguration.cs`
- Create: `src/MiniHRM.Infrastructure/Data/Configurations/AttendanceConfiguration.cs`
- Create: `src/MiniHRM.Infrastructure/Data/Configurations/LeaveBalanceConfiguration.cs`

**Step 1: Create ApplicationDbContext**

```csharp
// src/MiniHRM.Infrastructure/Data/ApplicationDbContext.cs
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using MiniHRM.Domain.Entities;

namespace MiniHRM.Infrastructure.Data;

public class ApplicationDbContext : IdentityDbContext<IdentityUser>
{
    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options)
        : base(options)
    {
    }

    public DbSet<Department> Departments => Set<Department>();
    public DbSet<Position> Positions => Set<Position>();
    public DbSet<Employee> Employees => Set<Employee>();
    public DbSet<LeaveRequest> LeaveRequests => Set<LeaveRequest>();
    public DbSet<Attendance> AttendanceRecords => Set<Attendance>();
    public DbSet<LeaveBalance> LeaveBalances => Set<LeaveBalance>();

    protected override void OnModelCreating(ModelBuilder builder)
    {
        base.OnModelCreating(builder);
        builder.ApplyConfigurationsFromAssembly(typeof(ApplicationDbContext).Assembly);

        // Global query filter for soft delete
        foreach (var entityType in builder.Model.GetEntityTypes())
        {
            if (typeof(Domain.Common.BaseEntity).IsAssignableFrom(entityType.ClrType))
            {
                var method = typeof(ApplicationDbContext)
                    .GetMethod(nameof(SetSoftDeleteFilter),
                        System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static)!
                    .MakeGenericMethod(entityType.ClrType);

                method.Invoke(null, [builder]);
            }
        }
    }

    private static void SetSoftDeleteFilter<T>(ModelBuilder builder) where T : Domain.Common.BaseEntity
    {
        builder.Entity<T>().HasQueryFilter(e => !e.IsDeleted);
    }
}
```

**Step 2: Create DepartmentConfiguration**

```csharp
// src/MiniHRM.Infrastructure/Data/Configurations/DepartmentConfiguration.cs
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using MiniHRM.Domain.Entities;

namespace MiniHRM.Infrastructure.Data.Configurations;

public class DepartmentConfiguration : IEntityTypeConfiguration<Department>
{
    public void Configure(EntityTypeBuilder<Department> builder)
    {
        builder.ToTable("Departments");

        builder.HasKey(d => d.Id);

        builder.Property(d => d.Name)
            .IsRequired()
            .HasMaxLength(100);

        builder.Property(d => d.Description)
            .HasMaxLength(500);

        builder.HasOne(d => d.Manager)
            .WithMany()
            .HasForeignKey(d => d.ManagerId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.HasIndex(d => d.Name).IsUnique();
    }
}
```

**Step 3: Create PositionConfiguration**

```csharp
// src/MiniHRM.Infrastructure/Data/Configurations/PositionConfiguration.cs
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using MiniHRM.Domain.Entities;

namespace MiniHRM.Infrastructure.Data.Configurations;

public class PositionConfiguration : IEntityTypeConfiguration<Position>
{
    public void Configure(EntityTypeBuilder<Position> builder)
    {
        builder.ToTable("Positions");

        builder.HasKey(p => p.Id);

        builder.Property(p => p.Title)
            .IsRequired()
            .HasMaxLength(100);

        builder.Property(p => p.Description)
            .HasMaxLength(500);

        builder.Property(p => p.MinSalary)
            .HasColumnType("decimal(18,2)");

        builder.Property(p => p.MaxSalary)
            .HasColumnType("decimal(18,2)");

        builder.HasOne(p => p.Department)
            .WithMany(d => d.Positions)
            .HasForeignKey(p => p.DepartmentId)
            .OnDelete(DeleteBehavior.Restrict);
    }
}
```

**Step 4: Create EmployeeConfiguration**

```csharp
// src/MiniHRM.Infrastructure/Data/Configurations/EmployeeConfiguration.cs
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using MiniHRM.Domain.Entities;
using MiniHRM.Domain.ValueObjects;

namespace MiniHRM.Infrastructure.Data.Configurations;

public class EmployeeConfiguration : IEntityTypeConfiguration<Employee>
{
    public void Configure(EntityTypeBuilder<Employee> builder)
    {
        builder.ToTable("Employees");

        builder.HasKey(e => e.Id);

        // Value Object: FullName
        builder.OwnsOne(e => e.FullName, fn =>
        {
            fn.Property(f => f.FirstName)
                .HasColumnName("FirstName")
                .IsRequired()
                .HasMaxLength(100);

            fn.Property(f => f.LastName)
                .HasColumnName("LastName")
                .IsRequired()
                .HasMaxLength(100);
        });

        // Value Object: Email
        builder.OwnsOne(e => e.Email, em =>
        {
            em.Property(e => e.Value)
                .HasColumnName("Email")
                .IsRequired()
                .HasMaxLength(256);

            em.HasIndex(e => e.Value).IsUnique();
        });

        // Value Object: PhoneNumber
        builder.OwnsOne(e => e.PhoneNumber, ph =>
        {
            ph.Property(p => p.Value)
                .HasColumnName("PhoneNumber")
                .IsRequired()
                .HasMaxLength(20);
        });

        builder.Property(e => e.DateOfBirth).IsRequired();
        builder.Property(e => e.HireDate).IsRequired();
        builder.Property(e => e.Gender).IsRequired();
        builder.Property(e => e.Status).IsRequired();

        builder.HasOne(e => e.Department)
            .WithMany(d => d.Employees)
            .HasForeignKey(e => e.DepartmentId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(e => e.Position)
            .WithMany(p => p.Employees)
            .HasForeignKey(e => e.PositionId)
            .OnDelete(DeleteBehavior.Restrict);
    }
}
```

**Step 5: Create LeaveRequestConfiguration**

```csharp
// src/MiniHRM.Infrastructure/Data/Configurations/LeaveRequestConfiguration.cs
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using MiniHRM.Domain.Entities;

namespace MiniHRM.Infrastructure.Data.Configurations;

public class LeaveRequestConfiguration : IEntityTypeConfiguration<LeaveRequest>
{
    public void Configure(EntityTypeBuilder<LeaveRequest> builder)
    {
        builder.ToTable("LeaveRequests");

        builder.HasKey(lr => lr.Id);

        builder.Property(lr => lr.LeaveType).IsRequired();
        builder.Property(lr => lr.StartDate).IsRequired();
        builder.Property(lr => lr.EndDate).IsRequired();
        builder.Property(lr => lr.Reason).IsRequired().HasMaxLength(1000);
        builder.Property(lr => lr.Status).IsRequired();
        builder.Property(lr => lr.ReviewNote).HasMaxLength(1000);

        builder.HasOne(lr => lr.Employee)
            .WithMany(e => e.LeaveRequests)
            .HasForeignKey(lr => lr.EmployeeId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(lr => lr.Reviewer)
            .WithMany()
            .HasForeignKey(lr => lr.ReviewedBy)
            .OnDelete(DeleteBehavior.SetNull);
    }
}
```

**Step 6: Create AttendanceConfiguration**

```csharp
// src/MiniHRM.Infrastructure/Data/Configurations/AttendanceConfiguration.cs
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using MiniHRM.Domain.Entities;

namespace MiniHRM.Infrastructure.Data.Configurations;

public class AttendanceConfiguration : IEntityTypeConfiguration<Attendance>
{
    public void Configure(EntityTypeBuilder<Attendance> builder)
    {
        builder.ToTable("Attendance");

        builder.HasKey(a => a.Id);

        builder.Property(a => a.Date).IsRequired();
        builder.Property(a => a.Status).IsRequired();
        builder.Property(a => a.Note).HasMaxLength(500);

        builder.HasOne(a => a.Employee)
            .WithMany(e => e.AttendanceRecords)
            .HasForeignKey(a => a.EmployeeId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(a => new { a.EmployeeId, a.Date }).IsUnique();
    }
}
```

**Step 7: Create LeaveBalanceConfiguration**

```csharp
// src/MiniHRM.Infrastructure/Data/Configurations/LeaveBalanceConfiguration.cs
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using MiniHRM.Domain.Entities;

namespace MiniHRM.Infrastructure.Data.Configurations;

public class LeaveBalanceConfiguration : IEntityTypeConfiguration<LeaveBalance>
{
    public void Configure(EntityTypeBuilder<LeaveBalance> builder)
    {
        builder.ToTable("LeaveBalances");

        builder.HasKey(lb => lb.Id);

        builder.Property(lb => lb.LeaveType).IsRequired();
        builder.Property(lb => lb.Year).IsRequired();
        builder.Property(lb => lb.TotalDays).HasColumnType("decimal(5,1)");
        builder.Property(lb => lb.UsedDays).HasColumnType("decimal(5,1)");
        builder.Ignore(lb => lb.RemainingDays); // Computed property

        builder.HasOne(lb => lb.Employee)
            .WithMany(e => e.LeaveBalances)
            .HasForeignKey(lb => lb.EmployeeId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(lb => new { lb.EmployeeId, lb.LeaveType, lb.Year }).IsUnique();
    }
}
```

**Step 8: Build and verify**

```bash
dotnet build src/MiniHRM.Infrastructure
```

**Step 9: Commit**

```bash
git add src/MiniHRM.Infrastructure/Data/
git commit -m "feat(infra): add ApplicationDbContext and Fluent API entity configurations"
```

---

### Task 3.2: AuditableEntityInterceptor

**Files:**
- Create: `src/MiniHRM.Infrastructure/Data/Interceptors/AuditableEntityInterceptor.cs`
- Modify: `src/MiniHRM.Application/Common/Interfaces/ICurrentUserService.cs`
- Modify: `src/MiniHRM.Application/Common/Interfaces/IDateTimeService.cs`

**Step 1: Create Application interfaces first**

```csharp
// src/MiniHRM.Application/Common/Interfaces/ICurrentUserService.cs
namespace MiniHRM.Application.Common.Interfaces;

public interface ICurrentUserService
{
    string? UserId { get; }
}
```

```csharp
// src/MiniHRM.Application/Common/Interfaces/IDateTimeService.cs
namespace MiniHRM.Application.Common.Interfaces;

public interface IDateTimeService
{
    DateTime UtcNow { get; }
}
```

**Step 2: Create interceptor**

```csharp
// src/MiniHRM.Infrastructure/Data/Interceptors/AuditableEntityInterceptor.cs
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using MiniHRM.Application.Common.Interfaces;
using MiniHRM.Domain.Common;

namespace MiniHRM.Infrastructure.Data.Interceptors;

public class AuditableEntityInterceptor : SaveChangesInterceptor
{
    private readonly ICurrentUserService _currentUserService;
    private readonly IDateTimeService _dateTimeService;

    public AuditableEntityInterceptor(
        ICurrentUserService currentUserService,
        IDateTimeService dateTimeService)
    {
        _currentUserService = currentUserService;
        _dateTimeService = dateTimeService;
    }

    public override InterceptionResult<int> SavingChanges(
        DbContextEventData eventData, InterceptionResult<int> result)
    {
        UpdateEntities(eventData.Context);
        return base.SavingChanges(eventData, result);
    }

    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData, InterceptionResult<int> result,
        CancellationToken cancellationToken = default)
    {
        UpdateEntities(eventData.Context);
        return base.SavingChangesAsync(eventData, result, cancellationToken);
    }

    private void UpdateEntities(DbContext? context)
    {
        if (context is null) return;

        var now = _dateTimeService.UtcNow;
        var userId = _currentUserService.UserId;

        foreach (var entry in context.ChangeTracker.Entries<BaseEntity>())
        {
            if (entry.State == EntityState.Added)
            {
                entry.Entity.CreatedAt = now;
                entry.Entity.CreatedBy = userId;
            }

            if (entry.State == EntityState.Modified)
            {
                entry.Entity.UpdatedAt = now;
                entry.Entity.UpdatedBy = userId;
            }

            if (entry.State == EntityState.Deleted)
            {
                // Soft delete instead of hard delete
                entry.State = EntityState.Modified;
                entry.Entity.IsDeleted = true;
                entry.Entity.UpdatedAt = now;
                entry.Entity.UpdatedBy = userId;
            }
        }
    }
}
```

**Step 3: Build and verify**

```bash
dotnet build MiniHRM.sln
```

**Step 4: Commit**

```bash
git add src/MiniHRM.Application/Common/Interfaces/ src/MiniHRM.Infrastructure/Data/Interceptors/
git commit -m "feat(infra): add AuditableEntityInterceptor for auto audit fields and soft delete"
```

---

### Task 3.3: Repository Implementations

**Files:**
- Create: `src/MiniHRM.Infrastructure/Repositories/GenericRepository.cs`
- Create: `src/MiniHRM.Infrastructure/Repositories/EmployeeRepository.cs`
- Create: `src/MiniHRM.Infrastructure/Repositories/LeaveRequestRepository.cs`
- Create: `src/MiniHRM.Infrastructure/Repositories/AttendanceRepository.cs`
- Create: `src/MiniHRM.Infrastructure/Repositories/UnitOfWork.cs`

**Step 1: Create GenericRepository**

```csharp
// src/MiniHRM.Infrastructure/Repositories/GenericRepository.cs
using System.Linq.Expressions;
using Microsoft.EntityFrameworkCore;
using MiniHRM.Domain.Common;
using MiniHRM.Domain.Interfaces;
using MiniHRM.Infrastructure.Data;

namespace MiniHRM.Infrastructure.Repositories;

public class GenericRepository<T> : IGenericRepository<T> where T : BaseEntity
{
    protected readonly ApplicationDbContext Context;
    protected readonly DbSet<T> DbSet;

    public GenericRepository(ApplicationDbContext context)
    {
        Context = context;
        DbSet = context.Set<T>();
    }

    public async Task<T?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default)
    {
        return await DbSet.FindAsync([id], cancellationToken);
    }

    public async Task<IReadOnlyList<T>> GetAllAsync(CancellationToken cancellationToken = default)
    {
        return await DbSet.ToListAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<T>> FindAsync(
        Expression<Func<T, bool>> predicate, CancellationToken cancellationToken = default)
    {
        return await DbSet.Where(predicate).ToListAsync(cancellationToken);
    }

    public IQueryable<T> Query()
    {
        return DbSet.AsQueryable();
    }

    public async Task AddAsync(T entity, CancellationToken cancellationToken = default)
    {
        await DbSet.AddAsync(entity, cancellationToken);
    }

    public void Update(T entity)
    {
        DbSet.Update(entity);
    }

    public void Delete(T entity)
    {
        DbSet.Remove(entity);
    }

    public async Task<bool> ExistsAsync(Guid id, CancellationToken cancellationToken = default)
    {
        return await DbSet.AnyAsync(e => e.Id == id, cancellationToken);
    }
}
```

**Step 2: Create specific repositories**

```csharp
// src/MiniHRM.Infrastructure/Repositories/EmployeeRepository.cs
using Microsoft.EntityFrameworkCore;
using MiniHRM.Domain.Entities;
using MiniHRM.Domain.Interfaces;
using MiniHRM.Infrastructure.Data;

namespace MiniHRM.Infrastructure.Repositories;

public class EmployeeRepository : GenericRepository<Employee>, IEmployeeRepository
{
    public EmployeeRepository(ApplicationDbContext context) : base(context) { }

    public async Task<Employee?> GetByEmailAsync(string email, CancellationToken cancellationToken = default)
    {
        return await DbSet
            .FirstOrDefaultAsync(e => e.Email.Value == email.ToLowerInvariant(), cancellationToken);
    }

    public async Task<IReadOnlyList<Employee>> GetByDepartmentAsync(
        Guid departmentId, CancellationToken cancellationToken = default)
    {
        return await DbSet
            .Where(e => e.DepartmentId == departmentId)
            .ToListAsync(cancellationToken);
    }
}
```

```csharp
// src/MiniHRM.Infrastructure/Repositories/LeaveRequestRepository.cs
using Microsoft.EntityFrameworkCore;
using MiniHRM.Domain.Entities;
using MiniHRM.Domain.Enums;
using MiniHRM.Domain.Interfaces;
using MiniHRM.Infrastructure.Data;

namespace MiniHRM.Infrastructure.Repositories;

public class LeaveRequestRepository : GenericRepository<LeaveRequest>, ILeaveRequestRepository
{
    public LeaveRequestRepository(ApplicationDbContext context) : base(context) { }

    public async Task<IReadOnlyList<LeaveRequest>> GetByEmployeeIdAsync(
        Guid employeeId, CancellationToken cancellationToken = default)
    {
        return await DbSet
            .Where(lr => lr.EmployeeId == employeeId)
            .OrderByDescending(lr => lr.CreatedAt)
            .ToListAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<LeaveRequest>> GetByStatusAsync(
        LeaveRequestStatus status, CancellationToken cancellationToken = default)
    {
        return await DbSet
            .Where(lr => lr.Status == status)
            .Include(lr => lr.Employee)
            .OrderByDescending(lr => lr.CreatedAt)
            .ToListAsync(cancellationToken);
    }

    public async Task<bool> HasOverlappingRequestAsync(
        Guid employeeId, DateTime startDate, DateTime endDate,
        Guid? excludeId = null, CancellationToken cancellationToken = default)
    {
        var query = DbSet
            .Where(lr => lr.EmployeeId == employeeId)
            .Where(lr => lr.Status != LeaveRequestStatus.Rejected && lr.Status != LeaveRequestStatus.Cancelled)
            .Where(lr => lr.StartDate <= endDate && lr.EndDate >= startDate);

        if (excludeId.HasValue)
            query = query.Where(lr => lr.Id != excludeId.Value);

        return await query.AnyAsync(cancellationToken);
    }
}
```

```csharp
// src/MiniHRM.Infrastructure/Repositories/AttendanceRepository.cs
using Microsoft.EntityFrameworkCore;
using MiniHRM.Domain.Entities;
using MiniHRM.Domain.Interfaces;
using MiniHRM.Infrastructure.Data;

namespace MiniHRM.Infrastructure.Repositories;

public class AttendanceRepository : GenericRepository<Attendance>, IAttendanceRepository
{
    public AttendanceRepository(ApplicationDbContext context) : base(context) { }

    public async Task<Attendance?> GetByEmployeeDateAsync(
        Guid employeeId, DateOnly date, CancellationToken cancellationToken = default)
    {
        return await DbSet
            .FirstOrDefaultAsync(a => a.EmployeeId == employeeId && a.Date == date, cancellationToken);
    }

    public async Task<IReadOnlyList<Attendance>> GetByEmployeeRangeAsync(
        Guid employeeId, DateOnly startDate, DateOnly endDate, CancellationToken cancellationToken = default)
    {
        return await DbSet
            .Where(a => a.EmployeeId == employeeId && a.Date >= startDate && a.Date <= endDate)
            .OrderBy(a => a.Date)
            .ToListAsync(cancellationToken);
    }
}
```

```csharp
// src/MiniHRM.Infrastructure/Repositories/UnitOfWork.cs
using MiniHRM.Domain.Interfaces;
using MiniHRM.Infrastructure.Data;

namespace MiniHRM.Infrastructure.Repositories;

public class UnitOfWork : IUnitOfWork
{
    private readonly ApplicationDbContext _context;

    public UnitOfWork(ApplicationDbContext context)
    {
        _context = context;
    }

    public async Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
    {
        return await _context.SaveChangesAsync(cancellationToken);
    }

    public void Dispose()
    {
        _context.Dispose();
    }
}
```

**Step 3: Build and verify**

```bash
dotnet build MiniHRM.sln
```

**Step 4: Commit**

```bash
git add src/MiniHRM.Infrastructure/Repositories/
git commit -m "feat(infra): add Generic and specific repository implementations with UnitOfWork"
```

---

### Task 3.4: Infrastructure Services & DI Registration

**Files:**
- Create: `src/MiniHRM.Infrastructure/Services/DateTimeService.cs`
- Create: `src/MiniHRM.Infrastructure/DependencyInjection.cs`

**Step 1: Create DateTimeService**

```csharp
// src/MiniHRM.Infrastructure/Services/DateTimeService.cs
using MiniHRM.Application.Common.Interfaces;

namespace MiniHRM.Infrastructure.Services;

public class DateTimeService : IDateTimeService
{
    public DateTime UtcNow => DateTime.UtcNow;
}
```

**Step 2: Create DependencyInjection registration**

```csharp
// src/MiniHRM.Infrastructure/DependencyInjection.cs
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using MiniHRM.Application.Common.Interfaces;
using MiniHRM.Domain.Interfaces;
using MiniHRM.Infrastructure.Data;
using MiniHRM.Infrastructure.Data.Interceptors;
using MiniHRM.Infrastructure.Repositories;
using MiniHRM.Infrastructure.Services;

namespace MiniHRM.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services, IConfiguration configuration)
    {
        // Interceptors
        services.AddScoped<AuditableEntityInterceptor>();

        // Database
        services.AddDbContext<ApplicationDbContext>((sp, options) =>
        {
            var interceptor = sp.GetRequiredService<AuditableEntityInterceptor>();
            options.UseSqlServer(
                configuration.GetConnectionString("DefaultConnection"),
                b => b.MigrationsAssembly(typeof(ApplicationDbContext).Assembly.FullName))
                .AddInterceptors(interceptor);
        });

        // Repositories
        services.AddScoped(typeof(IGenericRepository<>), typeof(GenericRepository<>));
        services.AddScoped<IEmployeeRepository, EmployeeRepository>();
        services.AddScoped<ILeaveRequestRepository, LeaveRequestRepository>();
        services.AddScoped<IAttendanceRepository, AttendanceRepository>();
        services.AddScoped<IUnitOfWork, UnitOfWork>();

        // Services
        services.AddScoped<IDateTimeService, DateTimeService>();

        return services;
    }
}
```

**Step 3: Build and verify**

```bash
dotnet build MiniHRM.sln
```

**Step 4: Commit**

```bash
git add src/MiniHRM.Infrastructure/Services/ src/MiniHRM.Infrastructure/DependencyInjection.cs
git commit -m "feat(infra): add DateTimeService and Infrastructure DI registration"
```

---

### Task 3.5: Seed Data

**Files:**
- Create: `src/MiniHRM.Infrastructure/Data/Seeds/ApplicationDbContextSeed.cs`

**Step 1: Create seed data class**

```csharp
// src/MiniHRM.Infrastructure/Data/Seeds/ApplicationDbContextSeed.cs
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using MiniHRM.Domain.Entities;

namespace MiniHRM.Infrastructure.Data.Seeds;

public static class ApplicationDbContextSeed
{
    public static async Task SeedDefaultDataAsync(
        ApplicationDbContext context,
        UserManager<IdentityUser> userManager,
        RoleManager<IdentityRole> roleManager)
    {
        // Seed Roles
        string[] roles = ["Admin", "HRManager", "Manager", "Employee"];
        foreach (var role in roles)
        {
            if (!await roleManager.RoleExistsAsync(role))
            {
                await roleManager.CreateAsync(new IdentityRole(role));
            }
        }

        // Seed Admin User
        const string adminEmail = "admin@minihrm.com";
        if (await userManager.FindByEmailAsync(adminEmail) is null)
        {
            var adminUser = new IdentityUser
            {
                UserName = adminEmail,
                Email = adminEmail,
                EmailConfirmed = true
            };
            await userManager.CreateAsync(adminUser, "Admin@123456");
            await userManager.AddToRoleAsync(adminUser, "Admin");
        }

        // Seed Departments
        if (!await context.Departments.AnyAsync())
        {
            var departments = new[]
            {
                Department.Create("Engineering", "Software development and engineering"),
                Department.Create("Human Resources", "HR and people operations"),
                Department.Create("Finance", "Finance and accounting"),
                Department.Create("Marketing", "Marketing and communications")
            };

            await context.Departments.AddRangeAsync(departments);
            await context.SaveChangesAsync();
        }
    }
}
```

**Step 2: Build and verify**

```bash
dotnet build src/MiniHRM.Infrastructure
```

**Step 3: Commit**

```bash
git add src/MiniHRM.Infrastructure/Data/Seeds/
git commit -m "feat(infra): add seed data for roles, admin user, and departments"
```

---

## Phase 4: Application Layer — Common Infrastructure

> **This phase is documented in Part 2:** `docs/plans/2026-03-09-implementation-plan-part2.md`
>
> Covers:
> - Task 4.1: Application Exceptions
> - Task 4.2: Result & PaginatedList models
> - Task 4.3: MediatR Pipeline Behaviors (Validation, Logging, UnhandledException)
> - Task 4.4: Mapster Configuration
> - Task 4.5: Application DependencyInjection
> - Task 4.6: IApplicationDbContext interface

## Phase 5: Application Layer — Department Feature (CQRS)

> Covers: CreateDepartment, UpdateDepartment, DeleteDepartment, GetDepartmentById, GetDepartmentsList — full CQRS pattern with validators

## Phase 6: Application Layer — Position Feature (CQRS)

> Same CQRS pattern as Department

## Phase 7: Application Layer — Employee Feature (CQRS)

> Same pattern + Value Object mapping

## Phase 8: Identity & Authentication

> ASP.NET Identity setup, JWT token generation, Login/Register commands, RefreshToken

## Phase 9: API Layer

> Controllers, middleware, Swagger, versioning, Program.cs configuration, health checks

## Phase 10: Leave Management Feature

> LeaveRequest CQRS, LeaveBalance CQRS, domain event handlers, approval workflow

## Phase 11: Attendance Feature

> CheckIn/CheckOut commands, attendance queries, monthly reports

## Phase 12: Testing — Application & Integration

> Application handler tests with NSubstitute, API integration tests with WebApplicationFactory + Testcontainers

## Phase 13: DevOps

> GitHub Actions CI pipeline, Serilog configuration, health check endpoints

---

## Implementation Order Summary

| Phase | Description | Estimated Tasks |
|-------|-------------|-----------------|
| 1 | Solution Scaffolding & Docker | 4 tasks |
| 2 | Domain Layer | 7 tasks |
| 3 | Infrastructure Layer | 5 tasks |
| 4 | Application Common | 6 tasks |
| 5 | Department Feature | 5 tasks |
| 6 | Position Feature | 5 tasks |
| 7 | Employee Feature | 5 tasks |
| 8 | Identity & Auth | 4 tasks |
| 9 | API Layer | 6 tasks |
| 10 | Leave Management | 6 tasks |
| 11 | Attendance | 4 tasks |
| 12 | Testing | 4 tasks |
| 13 | DevOps | 3 tasks |

**Total: ~62 bite-sized tasks across 13 phases**

Each subsequent phase document will follow the same detailed format as Phases 1-3 above, with exact file paths, complete code, test commands, and commit messages.
