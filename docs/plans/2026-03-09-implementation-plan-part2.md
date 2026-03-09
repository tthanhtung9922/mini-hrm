# MiniHRM Implementation Plan — Part 2 (Phases 4–13)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> **Part 1:** `docs/plans/2026-03-09-implementation-plan.md` (Phases 1–3)

---

## Phase 4: Application Layer — Common Infrastructure

### Task 4.1: Application Exceptions

**Files:**
- Create: `src/MiniHRM.Application/Common/Exceptions/NotFoundException.cs`
- Create: `src/MiniHRM.Application/Common/Exceptions/ForbiddenException.cs`
- Create: `src/MiniHRM.Application/Common/Exceptions/ValidationException.cs`
- Create: `src/MiniHRM.Application/Common/Exceptions/ConflictException.cs`

**Step 1: Create all exception classes**

```csharp
// src/MiniHRM.Application/Common/Exceptions/NotFoundException.cs
namespace MiniHRM.Application.Common.Exceptions;

public class NotFoundException : Exception
{
    public NotFoundException(string name, object key)
        : base($"Entity '{name}' ({key}) was not found.")
    {
    }

    public NotFoundException(string message)
        : base(message)
    {
    }
}
```

```csharp
// src/MiniHRM.Application/Common/Exceptions/ForbiddenException.cs
namespace MiniHRM.Application.Common.Exceptions;

public class ForbiddenException : Exception
{
    public ForbiddenException()
        : base("You do not have permission to perform this action.")
    {
    }

    public ForbiddenException(string message)
        : base(message)
    {
    }
}
```

```csharp
// src/MiniHRM.Application/Common/Exceptions/ValidationException.cs
using FluentValidation.Results;

namespace MiniHRM.Application.Common.Exceptions;

public class ValidationException : Exception
{
    public IDictionary<string, string[]> Errors { get; }

    public ValidationException()
        : base("One or more validation failures have occurred.")
    {
        Errors = new Dictionary<string, string[]>();
    }

    public ValidationException(IEnumerable<ValidationFailure> failures)
        : this()
    {
        Errors = failures
            .GroupBy(e => e.PropertyName, e => e.ErrorMessage)
            .ToDictionary(failureGroup => failureGroup.Key, failureGroup => failureGroup.ToArray());
    }
}
```

```csharp
// src/MiniHRM.Application/Common/Exceptions/ConflictException.cs
namespace MiniHRM.Application.Common.Exceptions;

public class ConflictException : Exception
{
    public ConflictException(string message)
        : base(message)
    {
    }
}
```

**Step 2: Build and verify**

```bash
dotnet build src/MiniHRM.Application
```

**Step 3: Commit**

```bash
git add src/MiniHRM.Application/Common/Exceptions/
git commit -m "feat(app): add application exception types"
```

---

### Task 4.2: Result and PaginatedList Models

**Files:**
- Create: `src/MiniHRM.Application/Common/Models/PaginatedList.cs`

**Step 1: Create PaginatedList**

```csharp
// src/MiniHRM.Application/Common/Models/PaginatedList.cs
namespace MiniHRM.Application.Common.Models;

public class PaginatedList<T>
{
    public IReadOnlyList<T> Items { get; }
    public int PageNumber { get; }
    public int TotalPages { get; }
    public int TotalCount { get; }
    public bool HasPreviousPage => PageNumber > 1;
    public bool HasNextPage => PageNumber < TotalPages;

    public PaginatedList(IReadOnlyList<T> items, int count, int pageNumber, int pageSize)
    {
        PageNumber = pageNumber;
        TotalPages = (int)Math.Ceiling(count / (double)pageSize);
        TotalCount = count;
        Items = items;
    }

    public static async Task<PaginatedList<T>> CreateAsync(
        IQueryable<T> source, int pageNumber, int pageSize,
        CancellationToken cancellationToken = default)
    {
        var count = source.Count();
        var items = source
            .Skip((pageNumber - 1) * pageSize)
            .Take(pageSize)
            .ToList();

        return new PaginatedList<T>(items, count, pageNumber, pageSize);
    }
}
```

> **Note:** For async `CreateAsync` with EF Core, add an overload that takes `IQueryable<T>` and uses `CountAsync`/`ToListAsync`. However, to avoid an EF Core dependency in Application layer, use the sync version here or create an extension method in Infrastructure.

**Step 2: Commit**

```bash
git add src/MiniHRM.Application/Common/Models/
git commit -m "feat(app): add PaginatedList model"
```

---

### Task 4.3: MediatR Pipeline Behaviors

**Files:**
- Create: `src/MiniHRM.Application/Common/Behaviors/LoggingBehavior.cs`
- Create: `src/MiniHRM.Application/Common/Behaviors/ValidationBehavior.cs`
- Create: `src/MiniHRM.Application/Common/Behaviors/UnhandledExceptionBehavior.cs`

**Step 1: Create LoggingBehavior**

```csharp
// src/MiniHRM.Application/Common/Behaviors/LoggingBehavior.cs
using MediatR;
using Microsoft.Extensions.Logging;

namespace MiniHRM.Application.Common.Behaviors;

public class LoggingBehavior<TRequest, TResponse> : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    private readonly ILogger<LoggingBehavior<TRequest, TResponse>> _logger;

    public LoggingBehavior(ILogger<LoggingBehavior<TRequest, TResponse>> logger)
    {
        _logger = logger;
    }

    public async Task<TResponse> Handle(
        TRequest request, RequestHandlerDelegate<TResponse> next,
        CancellationToken cancellationToken)
    {
        var requestName = typeof(TRequest).Name;

        _logger.LogInformation("Handling {RequestName}: {@Request}", requestName, request);

        var stopwatch = System.Diagnostics.Stopwatch.StartNew();
        var response = await next();
        stopwatch.Stop();

        _logger.LogInformation(
            "Handled {RequestName} in {ElapsedMilliseconds}ms",
            requestName, stopwatch.ElapsedMilliseconds);

        return response;
    }
}
```

**Step 2: Create ValidationBehavior**

```csharp
// src/MiniHRM.Application/Common/Behaviors/ValidationBehavior.cs
using FluentValidation;
using MediatR;
using ValidationException = MiniHRM.Application.Common.Exceptions.ValidationException;

namespace MiniHRM.Application.Common.Behaviors;

public class ValidationBehavior<TRequest, TResponse> : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    private readonly IEnumerable<IValidator<TRequest>> _validators;

    public ValidationBehavior(IEnumerable<IValidator<TRequest>> validators)
    {
        _validators = validators;
    }

    public async Task<TResponse> Handle(
        TRequest request, RequestHandlerDelegate<TResponse> next,
        CancellationToken cancellationToken)
    {
        if (!_validators.Any())
            return await next();

        var context = new ValidationContext<TRequest>(request);

        var validationResults = await Task.WhenAll(
            _validators.Select(v => v.ValidateAsync(context, cancellationToken)));

        var failures = validationResults
            .Where(r => r.Errors.Count > 0)
            .SelectMany(r => r.Errors)
            .ToList();

        if (failures.Count > 0)
            throw new ValidationException(failures);

        return await next();
    }
}
```

**Step 3: Create UnhandledExceptionBehavior**

```csharp
// src/MiniHRM.Application/Common/Behaviors/UnhandledExceptionBehavior.cs
using MediatR;
using Microsoft.Extensions.Logging;

namespace MiniHRM.Application.Common.Behaviors;

public class UnhandledExceptionBehavior<TRequest, TResponse> : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    private readonly ILogger<UnhandledExceptionBehavior<TRequest, TResponse>> _logger;

    public UnhandledExceptionBehavior(
        ILogger<UnhandledExceptionBehavior<TRequest, TResponse>> logger)
    {
        _logger = logger;
    }

    public async Task<TResponse> Handle(
        TRequest request, RequestHandlerDelegate<TResponse> next,
        CancellationToken cancellationToken)
    {
        try
        {
            return await next();
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            var requestName = typeof(TRequest).Name;
            _logger.LogError(ex, "Unhandled exception for request {RequestName}: {@Request}",
                requestName, request);
            throw;
        }
    }
}
```

**Step 4: Build and verify**

```bash
dotnet build src/MiniHRM.Application
```

**Step 5: Commit**

```bash
git add src/MiniHRM.Application/Common/Behaviors/
git commit -m "feat(app): add MediatR pipeline behaviors — Logging, Validation, UnhandledException"
```

---

### Task 4.4: Mapster Configuration

**Files:**
- Create: `src/MiniHRM.Application/Common/Mappings/MapsterConfig.cs`
- Create: `src/MiniHRM.Application/Common/Mappings/IMapFrom.cs`

**Step 1: Create IMapFrom marker interface**

```csharp
// src/MiniHRM.Application/Common/Mappings/IMapFrom.cs
using Mapster;

namespace MiniHRM.Application.Common.Mappings;

public interface IMapFrom<T>
{
    void Mapping(TypeAdapterConfig config) { }
}
```

**Step 2: Create MapsterConfig**

```csharp
// src/MiniHRM.Application/Common/Mappings/MapsterConfig.cs
using System.Reflection;
using Mapster;
using MapsterMapper;

namespace MiniHRM.Application.Common.Mappings;

public static class MapsterConfig
{
    public static void RegisterMappings(TypeAdapterConfig config, Assembly assembly)
    {
        // Scan assembly for types implementing IMapFrom<T> and apply their custom mappings
        var types = assembly.GetExportedTypes()
            .Where(t => t.GetInterfaces()
                .Any(i => i.IsGenericType && i.GetGenericTypeDefinition() == typeof(IMapFrom<>)));

        foreach (var type in types)
        {
            var instance = Activator.CreateInstance(type);
            var methodInfo = type.GetMethod("Mapping") ??
                             type.GetInterfaces()
                                 .Where(i => i.IsGenericType && i.GetGenericTypeDefinition() == typeof(IMapFrom<>))
                                 .Select(i => i.GetMethod("Mapping"))
                                 .First(m => m is not null);

            methodInfo?.Invoke(instance, [config]);
        }
    }
}
```

**Step 3: Build and verify**

```bash
dotnet build src/MiniHRM.Application
```

**Step 4: Commit**

```bash
git add src/MiniHRM.Application/Common/Mappings/
git commit -m "feat(app): add Mapster configuration and IMapFrom interface"
```

---

### Task 4.5: IApplicationDbContext Interface

**Files:**
- Create: `src/MiniHRM.Application/Common/Interfaces/IApplicationDbContext.cs`

**Step 1: Create interface**

```csharp
// src/MiniHRM.Application/Common/Interfaces/IApplicationDbContext.cs
using Microsoft.EntityFrameworkCore;
using MiniHRM.Domain.Entities;

namespace MiniHRM.Application.Common.Interfaces;

public interface IApplicationDbContext
{
    DbSet<Department> Departments { get; }
    DbSet<Position> Positions { get; }
    DbSet<Employee> Employees { get; }
    DbSet<LeaveRequest> LeaveRequests { get; }
    DbSet<Attendance> AttendanceRecords { get; }
    DbSet<LeaveBalance> LeaveBalances { get; }

    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
```

**Step 2: Implement interface on ApplicationDbContext**

Modify `src/MiniHRM.Infrastructure/Data/ApplicationDbContext.cs` to implement `IApplicationDbContext`:

```csharp
public class ApplicationDbContext : IdentityDbContext<IdentityUser>, IApplicationDbContext
{
    // ... rest of existing code unchanged
}
```

**Step 3: Register in DI**

In `src/MiniHRM.Infrastructure/DependencyInjection.cs`, add after `AddDbContext`:

```csharp
services.AddScoped<IApplicationDbContext>(provider =>
    provider.GetRequiredService<ApplicationDbContext>());
```

**Step 4: Build and verify**

```bash
dotnet build MiniHRM.sln
```

**Step 5: Commit**

```bash
git add src/MiniHRM.Application/Common/Interfaces/IApplicationDbContext.cs src/MiniHRM.Infrastructure/
git commit -m "feat(app): add IApplicationDbContext interface and register in DI"
```

---

### Task 4.6: Application DependencyInjection

**Files:**
- Create: `src/MiniHRM.Application/DependencyInjection.cs`

**Step 1: Create Application DI registration**

```csharp
// src/MiniHRM.Application/DependencyInjection.cs
using System.Reflection;
using FluentValidation;
using Mapster;
using MapsterMapper;
using MediatR;
using Microsoft.Extensions.DependencyInjection;
using MiniHRM.Application.Common.Behaviors;
using MiniHRM.Application.Common.Mappings;

namespace MiniHRM.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        var assembly = typeof(DependencyInjection).Assembly;

        // MediatR
        services.AddMediatR(cfg =>
        {
            cfg.RegisterServicesFromAssembly(assembly);
            cfg.AddBehavior(typeof(IPipelineBehavior<,>), typeof(UnhandledExceptionBehavior<,>));
            cfg.AddBehavior(typeof(IPipelineBehavior<,>), typeof(LoggingBehavior<,>));
            cfg.AddBehavior(typeof(IPipelineBehavior<,>), typeof(ValidationBehavior<,>));
        });

        // FluentValidation
        services.AddValidatorsFromAssembly(assembly);

        // Mapster
        var config = TypeAdapterConfig.GlobalSettings;
        MapsterConfig.RegisterMappings(config, assembly);
        services.AddSingleton(config);
        services.AddScoped<IMapper, ServiceMapper>();

        return services;
    }
}
```

**Step 2: Build and verify**

```bash
dotnet build MiniHRM.sln
```

**Step 3: Commit**

```bash
git add src/MiniHRM.Application/DependencyInjection.cs
git commit -m "feat(app): add Application DI registration with MediatR, FluentValidation, Mapster"
```

---

## Phase 5: Department Feature (CQRS)

### Task 5.1: Department DTOs

**Files:**
- Create: `src/MiniHRM.Application/Departments/DTOs/DepartmentDto.cs`
- Create: `src/MiniHRM.Application/Departments/DTOs/DepartmentBriefDto.cs`

**Step 1: Create DTOs**

```csharp
// src/MiniHRM.Application/Departments/DTOs/DepartmentDto.cs
using MiniHRM.Application.Common.Mappings;
using MiniHRM.Domain.Entities;
using Mapster;

namespace MiniHRM.Application.Departments.DTOs;

public class DepartmentDto : IMapFrom<Department>
{
    public Guid Id { get; set; }
    public string Name { get; set; } = null!;
    public string? Description { get; set; }
    public Guid? ManagerId { get; set; }
    public string? ManagerName { get; set; }
    public int EmployeeCount { get; set; }
    public DateTime CreatedAt { get; set; }
}
```

```csharp
// src/MiniHRM.Application/Departments/DTOs/DepartmentBriefDto.cs
namespace MiniHRM.Application.Departments.DTOs;

public class DepartmentBriefDto
{
    public Guid Id { get; set; }
    public string Name { get; set; } = null!;
}
```

**Step 2: Commit**

```bash
git add src/MiniHRM.Application/Departments/DTOs/
git commit -m "feat(app): add Department DTOs"
```

---

### Task 5.2: Department Queries

**Files:**
- Create: `src/MiniHRM.Application/Departments/Queries/GetDepartmentById/GetDepartmentByIdQuery.cs`
- Create: `src/MiniHRM.Application/Departments/Queries/GetDepartmentById/GetDepartmentByIdQueryHandler.cs`
- Create: `src/MiniHRM.Application/Departments/Queries/GetDepartmentsList/GetDepartmentsListQuery.cs`
- Create: `src/MiniHRM.Application/Departments/Queries/GetDepartmentsList/GetDepartmentsListQueryHandler.cs`
- Test: `tests/MiniHRM.Application.Tests/Departments/GetDepartmentByIdQueryHandlerTests.cs`

**Step 1: Write failing test**

```csharp
// tests/MiniHRM.Application.Tests/Departments/GetDepartmentByIdQueryHandlerTests.cs
using FluentAssertions;
using MiniHRM.Application.Common.Exceptions;
using MiniHRM.Application.Common.Interfaces;
using MiniHRM.Application.Departments.Queries.GetDepartmentById;
using MiniHRM.Domain.Entities;
using NSubstitute;
using NSubstitute.ReturnsExtensions;

namespace MiniHRM.Application.Tests.Departments;

public class GetDepartmentByIdQueryHandlerTests
{
    private readonly IApplicationDbContext _context;
    private readonly GetDepartmentByIdQueryHandler _handler;

    public GetDepartmentByIdQueryHandlerTests()
    {
        _context = Substitute.For<IApplicationDbContext>();
        _handler = new GetDepartmentByIdQueryHandler(_context);
    }

    [Fact]
    public async Task Handle_WithExistingId_ShouldReturnDepartmentDto()
    {
        var dept = Department.Create("Engineering", "Dev team");
        _context.Departments.FindAsync(Arg.Any<object[]>(), Arg.Any<CancellationToken>())
            .Returns(dept);

        var result = await _handler.Handle(
            new GetDepartmentByIdQuery(dept.Id), CancellationToken.None);

        result.Name.Should().Be("Engineering");
    }

    [Fact]
    public async Task Handle_WithNonExistingId_ShouldThrowNotFoundException()
    {
        _context.Departments.FindAsync(Arg.Any<object[]>(), Arg.Any<CancellationToken>())
            .ReturnsNull();

        var act = () => _handler.Handle(
            new GetDepartmentByIdQuery(Guid.NewGuid()), CancellationToken.None);

        await act.Should().ThrowAsync<NotFoundException>();
    }
}
```

**Step 2: Run test to verify fail**

```bash
dotnet test tests/MiniHRM.Application.Tests --filter "GetDepartmentByIdQueryHandlerTests" -v n
```

Expected: FAIL — Handler not found.

**Step 3: Implement query and handler**

```csharp
// src/MiniHRM.Application/Departments/Queries/GetDepartmentById/GetDepartmentByIdQuery.cs
using MediatR;
using MiniHRM.Application.Departments.DTOs;

namespace MiniHRM.Application.Departments.Queries.GetDepartmentById;

public record GetDepartmentByIdQuery(Guid Id) : IRequest<DepartmentDto>;
```

```csharp
// src/MiniHRM.Application/Departments/Queries/GetDepartmentById/GetDepartmentByIdQueryHandler.cs
using Mapster;
using MediatR;
using Microsoft.EntityFrameworkCore;
using MiniHRM.Application.Common.Exceptions;
using MiniHRM.Application.Common.Interfaces;
using MiniHRM.Application.Departments.DTOs;

namespace MiniHRM.Application.Departments.Queries.GetDepartmentById;

public class GetDepartmentByIdQueryHandler : IRequestHandler<GetDepartmentByIdQuery, DepartmentDto>
{
    private readonly IApplicationDbContext _context;

    public GetDepartmentByIdQueryHandler(IApplicationDbContext context)
    {
        _context = context;
    }

    public async Task<DepartmentDto> Handle(
        GetDepartmentByIdQuery request, CancellationToken cancellationToken)
    {
        var department = await _context.Departments
            .Include(d => d.Manager)
            .Include(d => d.Employees)
            .FirstOrDefaultAsync(d => d.Id == request.Id, cancellationToken)
            ?? throw new NotFoundException(nameof(Domain.Entities.Department), request.Id);

        var dto = department.Adapt<DepartmentDto>();
        dto.ManagerName = department.Manager?.FullName.ToString();
        dto.EmployeeCount = department.Employees.Count;

        return dto;
    }
}
```

```csharp
// src/MiniHRM.Application/Departments/Queries/GetDepartmentsList/GetDepartmentsListQuery.cs
using MediatR;
using MiniHRM.Application.Departments.DTOs;

namespace MiniHRM.Application.Departments.Queries.GetDepartmentsList;

public record GetDepartmentsListQuery : IRequest<List<DepartmentDto>>;
```

```csharp
// src/MiniHRM.Application/Departments/Queries/GetDepartmentsList/GetDepartmentsListQueryHandler.cs
using Mapster;
using MediatR;
using Microsoft.EntityFrameworkCore;
using MiniHRM.Application.Common.Interfaces;
using MiniHRM.Application.Departments.DTOs;

namespace MiniHRM.Application.Departments.Queries.GetDepartmentsList;

public class GetDepartmentsListQueryHandler : IRequestHandler<GetDepartmentsListQuery, List<DepartmentDto>>
{
    private readonly IApplicationDbContext _context;

    public GetDepartmentsListQueryHandler(IApplicationDbContext context)
    {
        _context = context;
    }

    public async Task<List<DepartmentDto>> Handle(
        GetDepartmentsListQuery request, CancellationToken cancellationToken)
    {
        return await _context.Departments
            .Include(d => d.Manager)
            .Include(d => d.Employees)
            .AsNoTracking()
            .ProjectToType<DepartmentDto>()
            .ToListAsync(cancellationToken);
    }
}
```

**Step 4: Run tests**

```bash
dotnet test tests/MiniHRM.Application.Tests --filter "GetDepartmentByIdQueryHandlerTests" -v n
```

Expected: All PASS.

**Step 5: Commit**

```bash
git add src/MiniHRM.Application/Departments/Queries/ tests/MiniHRM.Application.Tests/Departments/
git commit -m "feat(app): add GetDepartmentById and GetDepartmentsList queries with tests"
```

---

### Task 5.3: Department Commands

**Files:**
- Create: `src/MiniHRM.Application/Departments/Commands/CreateDepartment/CreateDepartmentCommand.cs`
- Create: `src/MiniHRM.Application/Departments/Commands/CreateDepartment/CreateDepartmentCommandHandler.cs`
- Create: `src/MiniHRM.Application/Departments/Commands/CreateDepartment/CreateDepartmentCommandValidator.cs`
- Create: `src/MiniHRM.Application/Departments/Commands/UpdateDepartment/` (same pattern)
- Create: `src/MiniHRM.Application/Departments/Commands/DeleteDepartment/` (same pattern)
- Test: `tests/MiniHRM.Application.Tests/Departments/CreateDepartmentCommandHandlerTests.cs`

**Step 1: Write failing test**

```csharp
// tests/MiniHRM.Application.Tests/Departments/CreateDepartmentCommandHandlerTests.cs
using FluentAssertions;
using MiniHRM.Application.Common.Interfaces;
using MiniHRM.Application.Departments.Commands.CreateDepartment;
using MiniHRM.Domain.Interfaces;
using NSubstitute;

namespace MiniHRM.Application.Tests.Departments;

public class CreateDepartmentCommandHandlerTests
{
    private readonly IApplicationDbContext _context;
    private readonly IUnitOfWork _unitOfWork;
    private readonly CreateDepartmentCommandHandler _handler;

    public CreateDepartmentCommandHandlerTests()
    {
        _context = Substitute.For<IApplicationDbContext>();
        _unitOfWork = Substitute.For<IUnitOfWork>();
        _handler = new CreateDepartmentCommandHandler(_context, _unitOfWork);
    }

    [Fact]
    public async Task Handle_WithValidCommand_ShouldCreateDepartment()
    {
        var departments = new List<Domain.Entities.Department>();
        _context.Departments.Returns(MockDbSet(departments));

        var command = new CreateDepartmentCommand("IT", "Information Technology");

        var result = await _handler.Handle(command, CancellationToken.None);

        result.Should().NotBeEmpty();
        await _unitOfWork.Received(1).SaveChangesAsync(Arg.Any<CancellationToken>());
    }

    // Helper to mock DbSet — use InMemory or a MockDbSet helper in real tests
    private static Microsoft.EntityFrameworkCore.DbSet<T> MockDbSet<T>(List<T> data)
        where T : class
    {
        var queryable = data.AsQueryable();
        var dbSet = Substitute.For<Microsoft.EntityFrameworkCore.DbSet<T>,
            IQueryable<T>>();
        ((IQueryable<T>)dbSet).Provider.Returns(queryable.Provider);
        ((IQueryable<T>)dbSet).Expression.Returns(queryable.Expression);
        ((IQueryable<T>)dbSet).ElementType.Returns(queryable.ElementType);
        ((IQueryable<T>)dbSet).GetEnumerator().Returns(queryable.GetEnumerator());
        return dbSet;
    }
}
```

**Step 2: Implement CreateDepartment**

```csharp
// src/MiniHRM.Application/Departments/Commands/CreateDepartment/CreateDepartmentCommand.cs
using MediatR;

namespace MiniHRM.Application.Departments.Commands.CreateDepartment;

public record CreateDepartmentCommand(string Name, string? Description) : IRequest<Guid>;
```

```csharp
// src/MiniHRM.Application/Departments/Commands/CreateDepartment/CreateDepartmentCommandValidator.cs
using FluentValidation;

namespace MiniHRM.Application.Departments.Commands.CreateDepartment;

public class CreateDepartmentCommandValidator : AbstractValidator<CreateDepartmentCommand>
{
    public CreateDepartmentCommandValidator()
    {
        RuleFor(v => v.Name)
            .NotEmpty().WithMessage("Name is required.")
            .MaximumLength(100).WithMessage("Name must not exceed 100 characters.");

        RuleFor(v => v.Description)
            .MaximumLength(500).WithMessage("Description must not exceed 500 characters.")
            .When(v => v.Description is not null);
    }
}
```

```csharp
// src/MiniHRM.Application/Departments/Commands/CreateDepartment/CreateDepartmentCommandHandler.cs
using MediatR;
using MiniHRM.Application.Common.Interfaces;
using MiniHRM.Domain.Entities;
using MiniHRM.Domain.Interfaces;

namespace MiniHRM.Application.Departments.Commands.CreateDepartment;

public class CreateDepartmentCommandHandler : IRequestHandler<CreateDepartmentCommand, Guid>
{
    private readonly IApplicationDbContext _context;
    private readonly IUnitOfWork _unitOfWork;

    public CreateDepartmentCommandHandler(
        IApplicationDbContext context, IUnitOfWork unitOfWork)
    {
        _context = context;
        _unitOfWork = unitOfWork;
    }

    public async Task<Guid> Handle(
        CreateDepartmentCommand request, CancellationToken cancellationToken)
    {
        var department = Department.Create(request.Name, request.Description);
        await _context.Departments.AddAsync(department, cancellationToken);
        await _unitOfWork.SaveChangesAsync(cancellationToken);
        return department.Id;
    }
}
```

**Step 3: Create UpdateDepartment command (same pattern)**

```csharp
// src/MiniHRM.Application/Departments/Commands/UpdateDepartment/UpdateDepartmentCommand.cs
using MediatR;

namespace MiniHRM.Application.Departments.Commands.UpdateDepartment;

public record UpdateDepartmentCommand(Guid Id, string Name, string? Description) : IRequest;
```

```csharp
// src/MiniHRM.Application/Departments/Commands/UpdateDepartment/UpdateDepartmentCommandValidator.cs
using FluentValidation;

namespace MiniHRM.Application.Departments.Commands.UpdateDepartment;

public class UpdateDepartmentCommandValidator : AbstractValidator<UpdateDepartmentCommand>
{
    public UpdateDepartmentCommandValidator()
    {
        RuleFor(v => v.Id).NotEmpty();
        RuleFor(v => v.Name).NotEmpty().MaximumLength(100);
        RuleFor(v => v.Description).MaximumLength(500).When(v => v.Description is not null);
    }
}
```

```csharp
// src/MiniHRM.Application/Departments/Commands/UpdateDepartment/UpdateDepartmentCommandHandler.cs
using MediatR;
using MiniHRM.Application.Common.Exceptions;
using MiniHRM.Application.Common.Interfaces;
using MiniHRM.Domain.Interfaces;

namespace MiniHRM.Application.Departments.Commands.UpdateDepartment;

public class UpdateDepartmentCommandHandler : IRequestHandler<UpdateDepartmentCommand>
{
    private readonly IApplicationDbContext _context;
    private readonly IUnitOfWork _unitOfWork;

    public UpdateDepartmentCommandHandler(
        IApplicationDbContext context, IUnitOfWork unitOfWork)
    {
        _context = context;
        _unitOfWork = unitOfWork;
    }

    public async Task Handle(UpdateDepartmentCommand request, CancellationToken cancellationToken)
    {
        var department = await _context.Departments
            .FindAsync([request.Id], cancellationToken)
            ?? throw new NotFoundException(nameof(Domain.Entities.Department), request.Id);

        department.Update(request.Name, request.Description);
        await _unitOfWork.SaveChangesAsync(cancellationToken);
    }
}
```

**Step 4: Create DeleteDepartment command**

```csharp
// src/MiniHRM.Application/Departments/Commands/DeleteDepartment/DeleteDepartmentCommand.cs
using MediatR;

namespace MiniHRM.Application.Departments.Commands.DeleteDepartment;

public record DeleteDepartmentCommand(Guid Id) : IRequest;
```

```csharp
// src/MiniHRM.Application/Departments/Commands/DeleteDepartment/DeleteDepartmentCommandHandler.cs
using MediatR;
using MiniHRM.Application.Common.Exceptions;
using MiniHRM.Application.Common.Interfaces;
using MiniHRM.Domain.Interfaces;

namespace MiniHRM.Application.Departments.Commands.DeleteDepartment;

public class DeleteDepartmentCommandHandler : IRequestHandler<DeleteDepartmentCommand>
{
    private readonly IApplicationDbContext _context;
    private readonly IUnitOfWork _unitOfWork;

    public DeleteDepartmentCommandHandler(
        IApplicationDbContext context, IUnitOfWork unitOfWork)
    {
        _context = context;
        _unitOfWork = unitOfWork;
    }

    public async Task Handle(DeleteDepartmentCommand request, CancellationToken cancellationToken)
    {
        var department = await _context.Departments
            .FindAsync([request.Id], cancellationToken)
            ?? throw new NotFoundException(nameof(Domain.Entities.Department), request.Id);

        _context.Departments.Remove(department);
        await _unitOfWork.SaveChangesAsync(cancellationToken);
    }
}
```

**Step 5: Build and run tests**

```bash
dotnet build MiniHRM.sln
dotnet test tests/MiniHRM.Application.Tests -v n
```

**Step 6: Commit**

```bash
git add src/MiniHRM.Application/Departments/ tests/MiniHRM.Application.Tests/Departments/
git commit -m "feat(app): add Department CQRS commands (Create, Update, Delete) with validators and tests"
```

---

## Phase 6: Position Feature (CQRS)

> **Follow the exact same pattern as Phase 5 (Department).**

**Files to create:**
- `src/MiniHRM.Application/Positions/DTOs/PositionDto.cs`
- `src/MiniHRM.Application/Positions/DTOs/PositionBriefDto.cs`
- `src/MiniHRM.Application/Positions/Queries/GetPositionById/`
- `src/MiniHRM.Application/Positions/Queries/GetPositionsList/`
- `src/MiniHRM.Application/Positions/Queries/GetPositionsByDepartment/`
- `src/MiniHRM.Application/Positions/Commands/CreatePosition/`
- `src/MiniHRM.Application/Positions/Commands/UpdatePosition/`
- `src/MiniHRM.Application/Positions/Commands/DeletePosition/`

**PositionDto:**

```csharp
// src/MiniHRM.Application/Positions/DTOs/PositionDto.cs
namespace MiniHRM.Application.Positions.DTOs;

public class PositionDto
{
    public Guid Id { get; set; }
    public string Title { get; set; } = null!;
    public string? Description { get; set; }
    public decimal MinSalary { get; set; }
    public decimal MaxSalary { get; set; }
    public Guid DepartmentId { get; set; }
    public string DepartmentName { get; set; } = null!;
    public int EmployeeCount { get; set; }
}
```

**CreatePositionCommand:**

```csharp
// src/MiniHRM.Application/Positions/Commands/CreatePosition/CreatePositionCommand.cs
using MediatR;

namespace MiniHRM.Application.Positions.Commands.CreatePosition;

public record CreatePositionCommand(
    string Title,
    Guid DepartmentId,
    decimal MinSalary,
    decimal MaxSalary,
    string? Description) : IRequest<Guid>;
```

**CreatePositionCommandValidator:**

```csharp
using FluentValidation;

namespace MiniHRM.Application.Positions.Commands.CreatePosition;

public class CreatePositionCommandValidator : AbstractValidator<CreatePositionCommand>
{
    public CreatePositionCommandValidator()
    {
        RuleFor(v => v.Title).NotEmpty().MaximumLength(100);
        RuleFor(v => v.DepartmentId).NotEmpty();
        RuleFor(v => v.MinSalary).GreaterThanOrEqualTo(0);
        RuleFor(v => v.MaxSalary).GreaterThanOrEqualTo(v => v.MinSalary)
            .WithMessage("MaxSalary must be >= MinSalary");
        RuleFor(v => v.Description).MaximumLength(500).When(v => v.Description is not null);
    }
}
```

The handler pattern is identical to Department. Repeat for Update/Delete/GetById/GetList.

**Step: Commit**

```bash
git add src/MiniHRM.Application/Positions/ tests/MiniHRM.Application.Tests/Positions/
git commit -m "feat(app): add Position CQRS feature (CRUD + queries) with validators"
```

---

## Phase 7: Employee Feature (CQRS)

### Task 7.1: Employee DTOs

```csharp
// src/MiniHRM.Application/Employees/DTOs/EmployeeDto.cs
using MiniHRM.Domain.Enums;

namespace MiniHRM.Application.Employees.DTOs;

public class EmployeeDto
{
    public Guid Id { get; set; }
    public string FirstName { get; set; } = null!;
    public string LastName { get; set; } = null!;
    public string Email { get; set; } = null!;
    public string PhoneNumber { get; set; } = null!;
    public DateTime DateOfBirth { get; set; }
    public DateTime HireDate { get; set; }
    public Gender Gender { get; set; }
    public EmploymentStatus Status { get; set; }
    public Guid DepartmentId { get; set; }
    public string DepartmentName { get; set; } = null!;
    public Guid PositionId { get; set; }
    public string PositionTitle { get; set; } = null!;
}
```

```csharp
// src/MiniHRM.Application/Employees/DTOs/EmployeeBriefDto.cs
namespace MiniHRM.Application.Employees.DTOs;

public class EmployeeBriefDto
{
    public Guid Id { get; set; }
    public string FullName { get; set; } = null!;
    public string Email { get; set; } = null!;
    public string DepartmentName { get; set; } = null!;
    public string PositionTitle { get; set; } = null!;
}
```

```csharp
// src/MiniHRM.Application/Employees/DTOs/EmployeeListQuery.cs
namespace MiniHRM.Application.Employees.DTOs;

public class EmployeeListQuery
{
    public int PageNumber { get; set; } = 1;
    public int PageSize { get; set; } = 10;
    public string? SearchTerm { get; set; }
    public Guid? DepartmentId { get; set; }
    public string? SortBy { get; set; }
    public string? SortOrder { get; set; }
}
```

### Task 7.2: Employee Commands

```csharp
// src/MiniHRM.Application/Employees/Commands/CreateEmployee/CreateEmployeeCommand.cs
using MediatR;
using MiniHRM.Domain.Enums;

namespace MiniHRM.Application.Employees.Commands.CreateEmployee;

public record CreateEmployeeCommand(
    string FirstName,
    string LastName,
    string Email,
    string PhoneNumber,
    DateTime DateOfBirth,
    DateTime HireDate,
    Gender Gender,
    Guid DepartmentId,
    Guid PositionId) : IRequest<Guid>;
```

```csharp
// src/MiniHRM.Application/Employees/Commands/CreateEmployee/CreateEmployeeCommandValidator.cs
using FluentValidation;

namespace MiniHRM.Application.Employees.Commands.CreateEmployee;

public class CreateEmployeeCommandValidator : AbstractValidator<CreateEmployeeCommand>
{
    public CreateEmployeeCommandValidator()
    {
        RuleFor(v => v.FirstName).NotEmpty().MaximumLength(100);
        RuleFor(v => v.LastName).NotEmpty().MaximumLength(100);
        RuleFor(v => v.Email).NotEmpty().EmailAddress().MaximumLength(256);
        RuleFor(v => v.PhoneNumber).NotEmpty().MaximumLength(20);
        RuleFor(v => v.DateOfBirth)
            .NotEmpty()
            .LessThan(DateTime.Today)
            .WithMessage("Date of birth must be in the past.");
        RuleFor(v => v.HireDate).NotEmpty();
        RuleFor(v => v.DepartmentId).NotEmpty();
        RuleFor(v => v.PositionId).NotEmpty();
    }
}
```

```csharp
// src/MiniHRM.Application/Employees/Commands/CreateEmployee/CreateEmployeeCommandHandler.cs
using MediatR;
using Microsoft.EntityFrameworkCore;
using MiniHRM.Application.Common.Exceptions;
using MiniHRM.Application.Common.Interfaces;
using MiniHRM.Domain.Entities;
using MiniHRM.Domain.Interfaces;
using MiniHRM.Domain.ValueObjects;

namespace MiniHRM.Application.Employees.Commands.CreateEmployee;

public class CreateEmployeeCommandHandler : IRequestHandler<CreateEmployeeCommand, Guid>
{
    private readonly IApplicationDbContext _context;
    private readonly IUnitOfWork _unitOfWork;

    public CreateEmployeeCommandHandler(
        IApplicationDbContext context, IUnitOfWork unitOfWork)
    {
        _context = context;
        _unitOfWork = unitOfWork;
    }

    public async Task<Guid> Handle(
        CreateEmployeeCommand request, CancellationToken cancellationToken)
    {
        // Check email uniqueness
        var emailExists = await _context.Employees
            .AnyAsync(e => e.Email.Value == request.Email.ToLowerInvariant(), cancellationToken);

        if (emailExists)
            throw new ConflictException($"Employee with email '{request.Email}' already exists.");

        // Validate department and position exist
        var departmentExists = await _context.Departments
            .AnyAsync(d => d.Id == request.DepartmentId, cancellationToken);

        if (!departmentExists)
            throw new NotFoundException(nameof(Department), request.DepartmentId);

        var positionExists = await _context.Positions
            .AnyAsync(p => p.Id == request.PositionId, cancellationToken);

        if (!positionExists)
            throw new NotFoundException(nameof(Position), request.PositionId);

        var employee = Employee.Create(
            FullName.Create(request.FirstName, request.LastName),
            Email.Create(request.Email),
            PhoneNumber.Create(request.PhoneNumber),
            request.DateOfBirth,
            request.HireDate,
            request.Gender,
            request.DepartmentId,
            request.PositionId);

        await _context.Employees.AddAsync(employee, cancellationToken);
        await _unitOfWork.SaveChangesAsync(cancellationToken);

        return employee.Id;
    }
}
```

### Task 7.3: Employee Queries (with pagination)

```csharp
// src/MiniHRM.Application/Employees/Queries/GetEmployeesList/GetEmployeesListQuery.cs
using MediatR;
using MiniHRM.Application.Common.Models;
using MiniHRM.Application.Employees.DTOs;

namespace MiniHRM.Application.Employees.Queries.GetEmployeesList;

public record GetEmployeesListQuery(
    int PageNumber = 1,
    int PageSize = 10,
    string? SearchTerm = null,
    Guid? DepartmentId = null,
    string? SortBy = null,
    string? SortOrder = null) : IRequest<PaginatedList<EmployeeBriefDto>>;
```

```csharp
// src/MiniHRM.Application/Employees/Queries/GetEmployeesList/GetEmployeesListQueryHandler.cs
using Mapster;
using MediatR;
using Microsoft.EntityFrameworkCore;
using MiniHRM.Application.Common.Interfaces;
using MiniHRM.Application.Common.Models;
using MiniHRM.Application.Employees.DTOs;

namespace MiniHRM.Application.Employees.Queries.GetEmployeesList;

public class GetEmployeesListQueryHandler
    : IRequestHandler<GetEmployeesListQuery, PaginatedList<EmployeeBriefDto>>
{
    private readonly IApplicationDbContext _context;

    public GetEmployeesListQueryHandler(IApplicationDbContext context)
    {
        _context = context;
    }

    public async Task<PaginatedList<EmployeeBriefDto>> Handle(
        GetEmployeesListQuery request, CancellationToken cancellationToken)
    {
        var query = _context.Employees
            .Include(e => e.Department)
            .Include(e => e.Position)
            .AsNoTracking()
            .AsQueryable();

        // Filtering
        if (request.DepartmentId.HasValue)
            query = query.Where(e => e.DepartmentId == request.DepartmentId.Value);

        if (!string.IsNullOrWhiteSpace(request.SearchTerm))
        {
            var term = request.SearchTerm.ToLower();
            query = query.Where(e =>
                e.FullName.FirstName.ToLower().Contains(term) ||
                e.FullName.LastName.ToLower().Contains(term) ||
                e.Email.Value.Contains(term));
        }

        // Sorting
        query = request.SortBy?.ToLower() switch
        {
            "hiredate" => request.SortOrder == "desc"
                ? query.OrderByDescending(e => e.HireDate)
                : query.OrderBy(e => e.HireDate),
            "name" => request.SortOrder == "desc"
                ? query.OrderByDescending(e => e.FullName.LastName)
                : query.OrderBy(e => e.FullName.LastName),
            _ => query.OrderBy(e => e.FullName.LastName)
        };

        var totalCount = await query.CountAsync(cancellationToken);

        var items = await query
            .Skip((request.PageNumber - 1) * request.PageSize)
            .Take(request.PageSize)
            .Select(e => new EmployeeBriefDto
            {
                Id = e.Id,
                FullName = $"{e.FullName.FirstName} {e.FullName.LastName}",
                Email = e.Email.Value,
                DepartmentName = e.Department.Name,
                PositionTitle = e.Position.Title
            })
            .ToListAsync(cancellationToken);

        return new PaginatedList<EmployeeBriefDto>(items, totalCount, request.PageNumber, request.PageSize);
    }
}
```

**Step: Commit**

```bash
git add src/MiniHRM.Application/Employees/ tests/MiniHRM.Application.Tests/Employees/
git commit -m "feat(app): add Employee CQRS feature (CRUD + paginated list) with validators"
```

---

## Phase 8: Identity & Authentication

### Task 8.1: Identity Setup

**Files:**
- Create: `src/MiniHRM.Infrastructure/Identity/IdentityService.cs`
- Create: `src/MiniHRM.Infrastructure/Identity/JwtTokenGenerator.cs`
- Create: `src/MiniHRM.Infrastructure/Identity/CurrentUserService.cs`
- Create: `src/MiniHRM.Application/Identity/Commands/Login/LoginCommand.cs`
- Create: `src/MiniHRM.Application/Identity/Commands/Login/LoginCommandHandler.cs`
- Create: `src/MiniHRM.Application/Identity/Commands/Register/RegisterCommand.cs`
- Create: `src/MiniHRM.Application/Identity/DTOs/AuthResponseDto.cs`

**Step 1: Create AuthResponseDto**

```csharp
// src/MiniHRM.Application/Identity/DTOs/AuthResponseDto.cs
namespace MiniHRM.Application.Identity.DTOs;

public class AuthResponseDto
{
    public string AccessToken { get; set; } = null!;
    public string RefreshToken { get; set; } = null!;
    public DateTime ExpiresAt { get; set; }
    public string UserId { get; set; } = null!;
    public string Email { get; set; } = null!;
    public IList<string> Roles { get; set; } = [];
}
```

**Step 2: Create IIdentityService interface (in Application)**

```csharp
// src/MiniHRM.Application/Common/Interfaces/IIdentityService.cs
using MiniHRM.Application.Identity.DTOs;

namespace MiniHRM.Application.Common.Interfaces;

public interface IIdentityService
{
    Task<AuthResponseDto> LoginAsync(string email, string password, CancellationToken cancellationToken = default);
    Task<string> RegisterAsync(string email, string password, string role = "Employee", CancellationToken cancellationToken = default);
    Task<AuthResponseDto> RefreshTokenAsync(string refreshToken, CancellationToken cancellationToken = default);
}
```

**Step 3: Create JwtTokenGenerator**

```csharp
// src/MiniHRM.Infrastructure/Identity/JwtTokenGenerator.cs
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Tokens;

namespace MiniHRM.Infrastructure.Identity;

public class JwtTokenGenerator
{
    private readonly IConfiguration _configuration;
    private readonly UserManager<IdentityUser> _userManager;

    public JwtTokenGenerator(IConfiguration configuration, UserManager<IdentityUser> userManager)
    {
        _configuration = configuration;
        _userManager = userManager;
    }

    public async Task<(string accessToken, string refreshToken, DateTime expiresAt)>
        GenerateTokensAsync(IdentityUser user)
    {
        var roles = await _userManager.GetRolesAsync(user);

        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, user.Id),
            new(JwtRegisteredClaimNames.Email, user.Email!),
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
        };

        foreach (var role in roles)
            claims.Add(new Claim(ClaimTypes.Role, role));

        var key = new SymmetricSecurityKey(
            Encoding.UTF8.GetBytes(_configuration["Jwt:Secret"]!));
        var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
        var expiresAt = DateTime.UtcNow.AddMinutes(
            int.Parse(_configuration["Jwt:ExpiryMinutes"] ?? "60"));

        var token = new JwtSecurityToken(
            issuer: _configuration["Jwt:Issuer"],
            audience: _configuration["Jwt:Audience"],
            claims: claims,
            expires: expiresAt,
            signingCredentials: credentials);

        var accessToken = new JwtSecurityTokenHandler().WriteToken(token);
        var refreshToken = GenerateRefreshToken();

        return (accessToken, refreshToken, expiresAt);
    }

    private static string GenerateRefreshToken()
    {
        var randomNumber = new byte[64];
        using var rng = RandomNumberGenerator.Create();
        rng.GetBytes(randomNumber);
        return Convert.ToBase64String(randomNumber);
    }
}
```

**Step 4: Create IdentityService**

```csharp
// src/MiniHRM.Infrastructure/Identity/IdentityService.cs
using Microsoft.AspNetCore.Identity;
using MiniHRM.Application.Common.Exceptions;
using MiniHRM.Application.Common.Interfaces;
using MiniHRM.Application.Identity.DTOs;

namespace MiniHRM.Infrastructure.Identity;

public class IdentityService : IIdentityService
{
    private readonly UserManager<IdentityUser> _userManager;
    private readonly SignInManager<IdentityUser> _signInManager;
    private readonly JwtTokenGenerator _jwtTokenGenerator;

    public IdentityService(
        UserManager<IdentityUser> userManager,
        SignInManager<IdentityUser> signInManager,
        JwtTokenGenerator jwtTokenGenerator)
    {
        _userManager = userManager;
        _signInManager = signInManager;
        _jwtTokenGenerator = jwtTokenGenerator;
    }

    public async Task<AuthResponseDto> LoginAsync(
        string email, string password, CancellationToken cancellationToken = default)
    {
        var user = await _userManager.FindByEmailAsync(email)
            ?? throw new NotFoundException("User not found.");

        var result = await _signInManager.CheckPasswordSignInAsync(user, password, false);

        if (!result.Succeeded)
            throw new ForbiddenException("Invalid credentials.");

        var (accessToken, refreshToken, expiresAt) =
            await _jwtTokenGenerator.GenerateTokensAsync(user);

        var roles = await _userManager.GetRolesAsync(user);

        // Store refresh token
        await _userManager.SetAuthenticationTokenAsync(user, "MiniHRM", "RefreshToken", refreshToken);

        return new AuthResponseDto
        {
            AccessToken = accessToken,
            RefreshToken = refreshToken,
            ExpiresAt = expiresAt,
            UserId = user.Id,
            Email = user.Email!,
            Roles = roles
        };
    }

    public async Task<string> RegisterAsync(
        string email, string password, string role = "Employee",
        CancellationToken cancellationToken = default)
    {
        var user = new IdentityUser { UserName = email, Email = email, EmailConfirmed = true };
        var result = await _userManager.CreateAsync(user, password);

        if (!result.Succeeded)
            throw new ValidationException(
                result.Errors.Select(e => new FluentValidation.Results.ValidationFailure("", e.Description)));

        await _userManager.AddToRoleAsync(user, role);
        return user.Id;
    }

    public async Task<AuthResponseDto> RefreshTokenAsync(
        string refreshToken, CancellationToken cancellationToken = default)
    {
        // Find user with this refresh token
        // Note: In production, store refresh tokens in a dedicated table
        throw new NotImplementedException("Implement with refresh token store.");
    }
}
```

**Step 5: Create CurrentUserService**

```csharp
// src/MiniHRM.Infrastructure/Identity/CurrentUserService.cs
using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using MiniHRM.Application.Common.Interfaces;

namespace MiniHRM.Infrastructure.Identity;

public class CurrentUserService : ICurrentUserService
{
    private readonly IHttpContextAccessor _httpContextAccessor;

    public CurrentUserService(IHttpContextAccessor httpContextAccessor)
    {
        _httpContextAccessor = httpContextAccessor;
    }

    public string? UserId => _httpContextAccessor.HttpContext?.User
        .FindFirstValue(ClaimTypes.NameIdentifier);
}
```

**Step 6: Create Login and Register commands**

```csharp
// src/MiniHRM.Application/Identity/Commands/Login/LoginCommand.cs
using MediatR;
using MiniHRM.Application.Identity.DTOs;

namespace MiniHRM.Application.Identity.Commands.Login;

public record LoginCommand(string Email, string Password) : IRequest<AuthResponseDto>;
```

```csharp
// src/MiniHRM.Application/Identity/Commands/Login/LoginCommandValidator.cs
using FluentValidation;

namespace MiniHRM.Application.Identity.Commands.Login;

public class LoginCommandValidator : AbstractValidator<LoginCommand>
{
    public LoginCommandValidator()
    {
        RuleFor(v => v.Email).NotEmpty().EmailAddress();
        RuleFor(v => v.Password).NotEmpty();
    }
}
```

```csharp
// src/MiniHRM.Application/Identity/Commands/Login/LoginCommandHandler.cs
using MediatR;
using MiniHRM.Application.Common.Interfaces;
using MiniHRM.Application.Identity.DTOs;

namespace MiniHRM.Application.Identity.Commands.Login;

public class LoginCommandHandler : IRequestHandler<LoginCommand, AuthResponseDto>
{
    private readonly IIdentityService _identityService;

    public LoginCommandHandler(IIdentityService identityService)
    {
        _identityService = identityService;
    }

    public async Task<AuthResponseDto> Handle(
        LoginCommand request, CancellationToken cancellationToken)
    {
        return await _identityService.LoginAsync(request.Email, request.Password, cancellationToken);
    }
}
```

**Step 7: Update Infrastructure DI to register Identity**

In `DependencyInjection.cs`, add:

```csharp
// Add Identity
services.AddIdentity<IdentityUser, IdentityRole>(options =>
{
    options.Password.RequiredLength = 8;
    options.Password.RequireDigit = true;
    options.Password.RequireUppercase = true;
    options.User.RequireUniqueEmail = true;
})
.AddEntityFrameworkStores<ApplicationDbContext>()
.AddDefaultTokenProviders();

// Add JWT Authentication
var jwtSection = configuration.GetSection("Jwt");
services.AddAuthentication(options =>
{
    options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
})
.AddJwtBearer(options =>
{
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuer = true,
        ValidateAudience = true,
        ValidateLifetime = true,
        ValidateIssuerSigningKey = true,
        ValidIssuer = jwtSection["Issuer"],
        ValidAudience = jwtSection["Audience"],
        IssuerSigningKey = new SymmetricSecurityKey(
            Encoding.UTF8.GetBytes(jwtSection["Secret"]!))
    };
});

// Register Identity services
services.AddScoped<JwtTokenGenerator>();
services.AddScoped<IIdentityService, IdentityService>();
services.AddScoped<ICurrentUserService, CurrentUserService>();
services.AddHttpContextAccessor();
```

**Step 8: Build and verify**

```bash
dotnet build MiniHRM.sln
```

**Step 9: Commit**

```bash
git add src/MiniHRM.Infrastructure/Identity/ src/MiniHRM.Application/Identity/ src/MiniHRM.Infrastructure/DependencyInjection.cs
git commit -m "feat: add ASP.NET Identity, JWT authentication, Login/Register commands"
```

---

## Phase 9: API Layer

### Task 9.1: Program.cs and appsettings

**Files:**
- Modify: `src/MiniHRM.API/Program.cs`
- Modify: `src/MiniHRM.API/appsettings.json`
- Modify: `src/MiniHRM.API/appsettings.Development.json`

**Step 1: Configure appsettings.json**

```json
{
  "Serilog": {
    "MinimumLevel": {
      "Default": "Information",
      "Override": {
        "Microsoft": "Warning",
        "System": "Warning"
      }
    }
  },
  "ConnectionStrings": {
    "DefaultConnection": "Server=localhost,1433;Database=MiniHRM;User Id=sa;Password=MiniHrm@2026!;TrustServerCertificate=True"
  },
  "Jwt": {
    "Secret": "your-super-secret-key-at-least-32-characters-long!",
    "Issuer": "MiniHRM",
    "Audience": "MiniHRM",
    "ExpiryMinutes": "60"
  }
}
```

**Step 2: Configure Program.cs**

```csharp
// src/MiniHRM.API/Program.cs
using Asp.Versioning;
using MiniHRM.API.Middleware;
using MiniHRM.Application;
using MiniHRM.Infrastructure;
using Serilog;

Log.Logger = new LoggerConfiguration()
    .WriteTo.Console()
    .CreateBootstrapLogger();

try
{
    var builder = WebApplication.CreateBuilder(args);

    // Serilog
    builder.Host.UseSerilog((context, services, configuration) =>
    {
        configuration
            .ReadFrom.Configuration(context.Configuration)
            .ReadFrom.Services(services)
            .Enrich.FromLogContext()
            .Enrich.WithMachineName()
            .Enrich.WithEnvironmentName()
            .WriteTo.Console()
            .WriteTo.File("logs/minihrm-.log", rollingInterval: RollingInterval.Day);

        if (context.HostingEnvironment.IsDevelopment())
            configuration.WriteTo.Seq(context.Configuration["Seq:ServerUrl"] ?? "http://localhost:5341");
    });

    // DI Registrations
    builder.Services.AddApplication();
    builder.Services.AddInfrastructure(builder.Configuration);

    // Controllers
    builder.Services.AddControllers();

    // API Versioning
    builder.Services.AddApiVersioning(options =>
    {
        options.DefaultApiVersion = new ApiVersion(1, 0);
        options.AssumeDefaultVersionWhenUnspecified = true;
        options.ReportApiVersions = true;
    })
    .AddMvc()
    .AddApiExplorer(options =>
    {
        options.GroupNameFormat = "'v'VVV";
        options.SubstituteApiVersionInUrl = true;
    });

    // Swagger
    builder.Services.AddEndpointsApiExplorer();
    builder.Services.AddSwaggerGen(options =>
    {
        options.SwaggerDoc("v1", new() { Title = "MiniHRM API", Version = "v1" });
        options.AddSecurityDefinition("Bearer", new Microsoft.OpenApi.Models.OpenApiSecurityScheme
        {
            Name = "Authorization",
            Type = Microsoft.OpenApi.Models.SecuritySchemeType.Http,
            Scheme = "Bearer",
            BearerFormat = "JWT",
            In = Microsoft.OpenApi.Models.ParameterLocation.Header,
            Description = "Enter: Bearer {token}"
        });
        options.AddSecurityRequirement(new Microsoft.OpenApi.Models.OpenApiSecurityRequirement
        {
            {
                new Microsoft.OpenApi.Models.OpenApiSecurityScheme
                {
                    Reference = new Microsoft.OpenApi.Models.OpenApiReference
                    {
                        Type = Microsoft.OpenApi.Models.ReferenceType.SecurityScheme,
                        Id = "Bearer"
                    }
                },
                []
            }
        });
    });

    // Health Checks
    builder.Services.AddHealthChecks()
        .AddSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")!,
            name: "database", tags: ["db", "ready"]);

    var app = builder.Build();

    // Middleware Pipeline (ORDER MATTERS)
    app.UseMiddleware<GlobalExceptionHandlerMiddleware>();
    app.UseSerilogRequestLogging();

    if (app.Environment.IsDevelopment())
    {
        app.UseSwagger();
        app.UseSwaggerUI(options =>
        {
            options.SwaggerEndpoint("/swagger/v1/swagger.json", "MiniHRM API v1");
        });
    }

    app.UseAuthentication();
    app.UseAuthorization();

    app.MapControllers();
    app.MapHealthChecks("/health");
    app.MapHealthChecks("/health/db", new()
    {
        Predicate = check => check.Tags.Contains("db")
    });

    // Apply migrations and seed on startup (dev only)
    if (app.Environment.IsDevelopment())
        await app.Services.InitialiseDatabaseAsync();

    app.Run();
}
catch (Exception ex) when (ex is not HostAbortedException)
{
    Log.Fatal(ex, "Application terminated unexpectedly");
}
finally
{
    Log.CloseAndFlush();
}

public partial class Program { } // Required for WebApplicationFactory in tests
```

**Step 3: Create GlobalExceptionHandlerMiddleware**

```csharp
// src/MiniHRM.API/Middleware/GlobalExceptionHandlerMiddleware.cs
using System.Net;
using System.Text.Json;
using MiniHRM.Application.Common.Exceptions;
using ValidationException = MiniHRM.Application.Common.Exceptions.ValidationException;

namespace MiniHRM.API.Middleware;

public class GlobalExceptionHandlerMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<GlobalExceptionHandlerMiddleware> _logger;

    public GlobalExceptionHandlerMiddleware(
        RequestDelegate next, ILogger<GlobalExceptionHandlerMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await _next(context);
        }
        catch (Exception ex)
        {
            await HandleExceptionAsync(context, ex);
        }
    }

    private async Task HandleExceptionAsync(HttpContext context, Exception exception)
    {
        var (statusCode, title, errors) = exception switch
        {
            NotFoundException => (HttpStatusCode.NotFound, "Not Found", (object?)null),
            ForbiddenException => (HttpStatusCode.Forbidden, "Forbidden", null),
            ValidationException ve => (HttpStatusCode.UnprocessableEntity, "Validation Failed", ve.Errors),
            ConflictException => (HttpStatusCode.Conflict, "Conflict", null),
            _ => (HttpStatusCode.InternalServerError, "Internal Server Error", null)
        };

        if (statusCode == HttpStatusCode.InternalServerError)
            _logger.LogError(exception, "Unhandled exception: {Message}", exception.Message);

        var problem = new
        {
            type = $"https://httpstatuses.com/{(int)statusCode}",
            title,
            status = (int)statusCode,
            detail = exception.Message,
            errors
        };

        context.Response.StatusCode = (int)statusCode;
        context.Response.ContentType = "application/problem+json";

        await context.Response.WriteAsync(JsonSerializer.Serialize(problem,
            new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase }));
    }
}
```

**Step 4: Create HostExtensions for DB initialization**

```csharp
// src/MiniHRM.API/Extensions/HostExtensions.cs
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using MiniHRM.Infrastructure.Data;
using MiniHRM.Infrastructure.Data.Seeds;

namespace MiniHRM.API.Extensions;

public static class HostExtensions
{
    public static async Task InitialiseDatabaseAsync(this IServiceProvider services)
    {
        using var scope = services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();

        await context.Database.MigrateAsync();

        var userManager = scope.ServiceProvider.GetRequiredService<UserManager<IdentityUser>>();
        var roleManager = scope.ServiceProvider.GetRequiredService<RoleManager<IdentityRole>>();

        await ApplicationDbContextSeed.SeedDefaultDataAsync(context, userManager, roleManager);
    }
}
```

**Step 5: Build and verify**

```bash
dotnet build MiniHRM.sln
```

**Step 6: Commit**

```bash
git add src/MiniHRM.API/
git commit -m "feat(api): configure Program.cs, Serilog, Swagger, versioning, global exception middleware"
```

---

### Task 9.2: API Controllers

**Files:**
- Create: `src/MiniHRM.API/Controllers/v1/AuthController.cs`
- Create: `src/MiniHRM.API/Controllers/v1/DepartmentsController.cs`
- Create: `src/MiniHRM.API/Controllers/v1/PositionsController.cs`
- Create: `src/MiniHRM.API/Controllers/v1/EmployeesController.cs`
- Create: `src/MiniHRM.API/Controllers/v1/LeaveRequestsController.cs`
- Create: `src/MiniHRM.API/Controllers/v1/AttendanceController.cs`
- Create: `src/MiniHRM.API/Controllers/v1/LeaveBalancesController.cs`

**Step 1: Create base ApiController**

```csharp
// src/MiniHRM.API/Controllers/ApiController.cs
using Asp.Versioning;
using MediatR;
using Microsoft.AspNetCore.Mvc;

namespace MiniHRM.API.Controllers;

[ApiController]
[ApiVersion("1.0")]
[Route("api/v{version:apiVersion}/[controller]")]
public abstract class ApiController : ControllerBase
{
    private ISender? _mediator;
    protected ISender Mediator => _mediator ??= HttpContext.RequestServices.GetRequiredService<ISender>();
}
```

**Step 2: Create AuthController**

```csharp
// src/MiniHRM.API/Controllers/v1/AuthController.cs
using Microsoft.AspNetCore.Mvc;
using MiniHRM.Application.Identity.Commands.Login;

namespace MiniHRM.API.Controllers.v1;

public class AuthController : ApiController
{
    /// <summary>Login and receive JWT token</summary>
    [HttpPost("login")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<IActionResult> Login(LoginCommand command, CancellationToken ct)
    {
        var result = await Mediator.Send(command, ct);
        return Ok(result);
    }
}
```

**Step 3: Create DepartmentsController**

```csharp
// src/MiniHRM.API/Controllers/v1/DepartmentsController.cs
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MiniHRM.Application.Departments.Commands.CreateDepartment;
using MiniHRM.Application.Departments.Commands.DeleteDepartment;
using MiniHRM.Application.Departments.Commands.UpdateDepartment;
using MiniHRM.Application.Departments.Queries.GetDepartmentById;
using MiniHRM.Application.Departments.Queries.GetDepartmentsList;

namespace MiniHRM.API.Controllers.v1;

[Authorize]
public class DepartmentsController : ApiController
{
    /// <summary>Get all departments</summary>
    [HttpGet]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IActionResult> GetAll(CancellationToken ct)
        => Ok(await Mediator.Send(new GetDepartmentsListQuery(), ct));

    /// <summary>Get department by ID</summary>
    [HttpGet("{id:guid}")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetById(Guid id, CancellationToken ct)
        => Ok(await Mediator.Send(new GetDepartmentByIdQuery(id), ct));

    /// <summary>Create a new department</summary>
    [HttpPost]
    [Authorize(Roles = "Admin,HRManager")]
    [ProducesResponseType(StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status422UnprocessableEntity)]
    public async Task<IActionResult> Create(CreateDepartmentCommand command, CancellationToken ct)
    {
        var id = await Mediator.Send(command, ct);
        return CreatedAtAction(nameof(GetById), new { id }, id);
    }

    /// <summary>Update a department</summary>
    [HttpPut("{id:guid}")]
    [Authorize(Roles = "Admin,HRManager")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Update(Guid id, UpdateDepartmentCommand command, CancellationToken ct)
    {
        await Mediator.Send(command with { Id = id }, ct);
        return NoContent();
    }

    /// <summary>Delete a department (soft delete)</summary>
    [HttpDelete("{id:guid}")]
    [Authorize(Roles = "Admin")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct)
    {
        await Mediator.Send(new DeleteDepartmentCommand(id), ct);
        return NoContent();
    }
}
```

**Step 4: Create EmployeesController (with pagination)**

```csharp
// src/MiniHRM.API/Controllers/v1/EmployeesController.cs
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MiniHRM.Application.Employees.Commands.CreateEmployee;
using MiniHRM.Application.Employees.Queries.GetEmployeesList;

namespace MiniHRM.API.Controllers.v1;

[Authorize]
public class EmployeesController : ApiController
{
    /// <summary>Get paginated employee list with optional filtering and sorting</summary>
    [HttpGet]
    public async Task<IActionResult> GetList(
        [FromQuery] int pageNumber = 1,
        [FromQuery] int pageSize = 10,
        [FromQuery] string? searchTerm = null,
        [FromQuery] Guid? departmentId = null,
        [FromQuery] string? sortBy = null,
        [FromQuery] string? sortOrder = null,
        CancellationToken ct = default)
    {
        var result = await Mediator.Send(
            new GetEmployeesListQuery(pageNumber, pageSize, searchTerm, departmentId, sortBy, sortOrder), ct);
        return Ok(result);
    }

    /// <summary>Create a new employee</summary>
    [HttpPost]
    [Authorize(Roles = "Admin,HRManager")]
    [ProducesResponseType(StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status422UnprocessableEntity)]
    public async Task<IActionResult> Create(CreateEmployeeCommand command, CancellationToken ct)
    {
        var id = await Mediator.Send(command, ct);
        return CreatedAtAction(nameof(GetById), new { id }, id);
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById(Guid id, CancellationToken ct)
        => Ok(await Mediator.Send(new Application.Employees.Queries.GetEmployeeById.GetEmployeeByIdQuery(id), ct));
}
```

> Follow the same pattern for Positions, LeaveRequests, Attendance, LeaveBalances controllers.

**Step 5: Build and verify**

```bash
dotnet build MiniHRM.sln
```

**Step 6: Create initial EF Core migration**

```bash
cd D:/Projects/mini-hrm
dotnet ef migrations add InitialCreate -p src/MiniHRM.Infrastructure -s src/MiniHRM.API
```

Expected: Migration files created in `src/MiniHRM.Infrastructure/Data/Migrations/`.

**Step 7: Commit**

```bash
git add src/MiniHRM.API/Controllers/ src/MiniHRM.Infrastructure/Data/Migrations/
git commit -m "feat(api): add API controllers (Auth, Departments, Positions, Employees) and initial EF migration"
```

---

## Phase 10: Leave Management Feature

### Task 10.1: Leave Request CQRS

**Files:**
- `src/MiniHRM.Application/LeaveRequests/DTOs/LeaveRequestDto.cs`
- `src/MiniHRM.Application/LeaveRequests/Commands/CreateLeaveRequest/`
- `src/MiniHRM.Application/LeaveRequests/Commands/ApproveLeaveRequest/`
- `src/MiniHRM.Application/LeaveRequests/Commands/RejectLeaveRequest/`
- `src/MiniHRM.Application/LeaveRequests/Commands/CancelLeaveRequest/`
- `src/MiniHRM.Application/LeaveRequests/Queries/GetLeaveRequestById/`
- `src/MiniHRM.Application/LeaveRequests/Queries/GetMyLeaveRequests/`
- `src/MiniHRM.Application/LeaveRequests/Queries/GetPendingLeaveRequests/`

**Step 1: Create LeaveRequestDto**

```csharp
// src/MiniHRM.Application/LeaveRequests/DTOs/LeaveRequestDto.cs
using MiniHRM.Domain.Enums;

namespace MiniHRM.Application.LeaveRequests.DTOs;

public class LeaveRequestDto
{
    public Guid Id { get; set; }
    public Guid EmployeeId { get; set; }
    public string EmployeeName { get; set; } = null!;
    public LeaveType LeaveType { get; set; }
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
    public int TotalDays { get; set; }
    public string Reason { get; set; } = null!;
    public LeaveRequestStatus Status { get; set; }
    public string? ReviewerName { get; set; }
    public DateTime? ReviewedDate { get; set; }
    public string? ReviewNote { get; set; }
    public DateTime CreatedAt { get; set; }
}
```

**Step 2: Create CreateLeaveRequest command (with overlap check)**

```csharp
// src/MiniHRM.Application/LeaveRequests/Commands/CreateLeaveRequest/CreateLeaveRequestCommand.cs
using MediatR;
using MiniHRM.Domain.Enums;

namespace MiniHRM.Application.LeaveRequests.Commands.CreateLeaveRequest;

public record CreateLeaveRequestCommand(
    LeaveType LeaveType,
    DateTime StartDate,
    DateTime EndDate,
    string Reason) : IRequest<Guid>;
```

```csharp
// CreateLeaveRequestCommandHandler.cs
using MediatR;
using MiniHRM.Application.Common.Exceptions;
using MiniHRM.Application.Common.Interfaces;
using MiniHRM.Domain.Entities;
using MiniHRM.Domain.Interfaces;

namespace MiniHRM.Application.LeaveRequests.Commands.CreateLeaveRequest;

public class CreateLeaveRequestCommandHandler : IRequestHandler<CreateLeaveRequestCommand, Guid>
{
    private readonly IApplicationDbContext _context;
    private readonly ILeaveRequestRepository _leaveRequestRepository;
    private readonly ICurrentUserService _currentUserService;
    private readonly IUnitOfWork _unitOfWork;

    public CreateLeaveRequestCommandHandler(
        IApplicationDbContext context,
        ILeaveRequestRepository leaveRequestRepository,
        ICurrentUserService currentUserService,
        IUnitOfWork unitOfWork)
    {
        _context = context;
        _leaveRequestRepository = leaveRequestRepository;
        _currentUserService = currentUserService;
        _unitOfWork = unitOfWork;
    }

    public async Task<Guid> Handle(
        CreateLeaveRequestCommand request, CancellationToken cancellationToken)
    {
        // Get employee linked to current user (simplified — assumes 1:1 user:employee)
        var employee = await _context.Employees
            .FirstOrDefaultAsync(e => e.UserId == _currentUserService.UserId, cancellationToken)
            ?? throw new NotFoundException("Employee profile not found for current user.");

        // Check for overlapping requests
        var hasOverlap = await _leaveRequestRepository.HasOverlappingRequestAsync(
            employee.Id, request.StartDate, request.EndDate,
            cancellationToken: cancellationToken);

        if (hasOverlap)
            throw new ConflictException("You already have a leave request overlapping these dates.");

        // Check leave balance
        var balance = await _context.LeaveBalances
            .FirstOrDefaultAsync(lb =>
                lb.EmployeeId == employee.Id &&
                lb.LeaveType == request.LeaveType &&
                lb.Year == request.StartDate.Year, cancellationToken);

        var totalDays = (request.EndDate.Date - request.StartDate.Date).Days + 1;

        if (balance is not null && balance.RemainingDays < totalDays)
            throw new ConflictException(
                $"Insufficient leave balance. Remaining: {balance.RemainingDays} days, Requested: {totalDays} days.");

        var leaveRequest = LeaveRequest.Create(
            employee.Id,
            request.LeaveType,
            request.StartDate,
            request.EndDate,
            request.Reason);

        await _context.LeaveRequests.AddAsync(leaveRequest, cancellationToken);
        await _unitOfWork.SaveChangesAsync(cancellationToken);

        return leaveRequest.Id;
    }
}
```

> **Note:** `Employee.UserId` field needs to be added to Employee entity to link identity user with employee profile. Add this in the Employee entity and configuration.

**Step 3: Create ApproveLeaveRequest command**

```csharp
// src/MiniHRM.Application/LeaveRequests/Commands/ApproveLeaveRequest/ApproveLeaveRequestCommand.cs
using MediatR;

namespace MiniHRM.Application.LeaveRequests.Commands.ApproveLeaveRequest;

public record ApproveLeaveRequestCommand(Guid LeaveRequestId, string? Note) : IRequest;
```

```csharp
// ApproveLeaveRequestCommandHandler.cs
using MediatR;
using MiniHRM.Application.Common.Exceptions;
using MiniHRM.Application.Common.Interfaces;
using MiniHRM.Domain.Interfaces;
using Microsoft.EntityFrameworkCore;

namespace MiniHRM.Application.LeaveRequests.Commands.ApproveLeaveRequest;

public class ApproveLeaveRequestCommandHandler : IRequestHandler<ApproveLeaveRequestCommand>
{
    private readonly IApplicationDbContext _context;
    private readonly ICurrentUserService _currentUserService;
    private readonly IUnitOfWork _unitOfWork;

    public ApproveLeaveRequestCommandHandler(
        IApplicationDbContext context,
        ICurrentUserService currentUserService,
        IUnitOfWork unitOfWork)
    {
        _context = context;
        _currentUserService = currentUserService;
        _unitOfWork = unitOfWork;
    }

    public async Task Handle(ApproveLeaveRequestCommand request, CancellationToken cancellationToken)
    {
        var leaveRequest = await _context.LeaveRequests
            .FindAsync([request.LeaveRequestId], cancellationToken)
            ?? throw new NotFoundException(nameof(Domain.Entities.LeaveRequest), request.LeaveRequestId);

        var reviewer = await _context.Employees
            .FirstOrDefaultAsync(e => e.UserId == _currentUserService.UserId, cancellationToken)
            ?? throw new NotFoundException("Reviewer employee profile not found.");

        // Domain rule enforced — employee cannot approve own request
        leaveRequest.Approve(reviewer.Id, request.Note);

        // Domain event LeaveRequestApprovedEvent will trigger LeaveBalance deduction
        await _unitOfWork.SaveChangesAsync(cancellationToken);
    }
}
```

**Step 4: Create domain event handler for balance deduction**

```csharp
// src/MiniHRM.Application/LeaveRequests/EventHandlers/LeaveRequestApprovedEventHandler.cs
using MediatR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using MiniHRM.Application.Common.Interfaces;
using MiniHRM.Domain.Events;

namespace MiniHRM.Application.LeaveRequests.EventHandlers;

public class LeaveRequestApprovedEventHandler : INotificationHandler<LeaveRequestApprovedEvent>
{
    private readonly IApplicationDbContext _context;
    private readonly ILogger<LeaveRequestApprovedEventHandler> _logger;

    public LeaveRequestApprovedEventHandler(
        IApplicationDbContext context,
        ILogger<LeaveRequestApprovedEventHandler> logger)
    {
        _context = context;
        _logger = logger;
    }

    public async Task Handle(
        LeaveRequestApprovedEvent notification, CancellationToken cancellationToken)
    {
        var balance = await _context.LeaveBalances
            .FirstOrDefaultAsync(lb =>
                lb.EmployeeId == notification.EmployeeId &&
                lb.LeaveType == notification.LeaveType &&
                lb.Year == DateTime.UtcNow.Year, cancellationToken);

        if (balance is null)
        {
            _logger.LogWarning(
                "No leave balance found for employee {EmployeeId} and type {LeaveType}",
                notification.EmployeeId, notification.LeaveType);
            return;
        }

        balance.Deduct(notification.TotalDays);

        _logger.LogInformation(
            "Deducted {Days} days from leave balance for employee {EmployeeId}",
            notification.TotalDays, notification.EmployeeId);
    }
}
```

> **Important:** For domain events to work with MediatR, you need to dispatch them after SaveChanges. Add domain event dispatching in a `DomainEventDispatcher` service that runs after `SaveChangesAsync`. Update `UnitOfWork.SaveChangesAsync` to dispatch domain events using MediatR before or after saving.

**Step 5: Update UnitOfWork to dispatch domain events**

```csharp
// Modify UnitOfWork.cs
using MediatR;
using MiniHRM.Domain.Common;
using MiniHRM.Domain.Interfaces;
using MiniHRM.Infrastructure.Data;

public class UnitOfWork : IUnitOfWork
{
    private readonly ApplicationDbContext _context;
    private readonly IPublisher _publisher;

    public UnitOfWork(ApplicationDbContext context, IPublisher publisher)
    {
        _context = context;
        _publisher = publisher;
    }

    public async Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
    {
        // Collect domain events before saving
        var domainEvents = _context.ChangeTracker
            .Entries<AggregateRoot>()
            .Select(e => e.Entity)
            .Where(e => e.DomainEvents.Any())
            .SelectMany(e => e.DomainEvents)
            .ToList();

        // Clear domain events from entities
        _context.ChangeTracker
            .Entries<AggregateRoot>()
            .Select(e => e.Entity)
            .ToList()
            .ForEach(e => e.ClearDomainEvents());

        var result = await _context.SaveChangesAsync(cancellationToken);

        // Dispatch domain events AFTER saving
        foreach (var domainEvent in domainEvents)
        {
            // Wrap IDomainEvent in INotification wrapper for MediatR
            await _publisher.Publish(new DomainEventNotification(domainEvent), cancellationToken);
        }

        return result;
    }

    public void Dispose() => _context.Dispose();
}
```

> **Note:** You need a `DomainEventNotification` wrapper since `IDomainEvent` is a plain interface (not MediatR's `INotification`). Create:

```csharp
// src/MiniHRM.Infrastructure/Events/DomainEventNotification.cs
using MediatR;
using MiniHRM.Domain.Common;

namespace MiniHRM.Infrastructure.Events;

public class DomainEventNotification : INotification
{
    public IDomainEvent DomainEvent { get; }

    public DomainEventNotification(IDomainEvent domainEvent)
    {
        DomainEvent = domainEvent;
    }
}
```

> Then update the event handlers to handle `DomainEventNotification` and route based on the inner event type, or alternatively, make `IDomainEvent` extend `INotification` in Application layer. The cleanest approach for this portfolio project: **move IDomainEvent to Application layer and have it extend INotification directly.**

**Step 6: Commit**

```bash
git add src/MiniHRM.Application/LeaveRequests/ src/MiniHRM.Infrastructure/
git commit -m "feat: add Leave Request CQRS with approval workflow and domain event handlers for balance deduction"
```

---

## Phase 11: Attendance Feature

### Task 11.1: Attendance CQRS

**Files:**
- `src/MiniHRM.Application/Attendance/DTOs/AttendanceDto.cs`
- `src/MiniHRM.Application/Attendance/Commands/CheckIn/CheckInCommand.cs`
- `src/MiniHRM.Application/Attendance/Commands/CheckOut/CheckOutCommand.cs`
- `src/MiniHRM.Application/Attendance/Queries/GetByEmployee/`
- `src/MiniHRM.Application/Attendance/Queries/GetMonthlyReport/`

**CheckInCommand:**

```csharp
// src/MiniHRM.Application/Attendance/Commands/CheckIn/CheckInCommand.cs
using MediatR;

namespace MiniHRM.Application.Attendance.Commands.CheckIn;

public record CheckInCommand(TimeOnly? Time = null) : IRequest<Guid>;
```

```csharp
// CheckInCommandHandler.cs
using MediatR;
using MiniHRM.Application.Common.Exceptions;
using MiniHRM.Application.Common.Interfaces;
using MiniHRM.Domain.Enums;
using MiniHRM.Domain.Interfaces;
using Microsoft.EntityFrameworkCore;

namespace MiniHRM.Application.Attendance.Commands.CheckIn;

public class CheckInCommandHandler : IRequestHandler<CheckInCommand, Guid>
{
    private readonly IApplicationDbContext _context;
    private readonly ICurrentUserService _currentUserService;
    private readonly IDateTimeService _dateTimeService;
    private readonly IUnitOfWork _unitOfWork;

    public CheckInCommandHandler(
        IApplicationDbContext context,
        ICurrentUserService currentUserService,
        IDateTimeService dateTimeService,
        IUnitOfWork unitOfWork)
    {
        _context = context;
        _currentUserService = currentUserService;
        _dateTimeService = dateTimeService;
        _unitOfWork = unitOfWork;
    }

    public async Task<Guid> Handle(CheckInCommand request, CancellationToken cancellationToken)
    {
        var employee = await _context.Employees
            .FirstOrDefaultAsync(e => e.UserId == _currentUserService.UserId, cancellationToken)
            ?? throw new NotFoundException("Employee profile not found.");

        var today = DateOnly.FromDateTime(_dateTimeService.UtcNow);

        var existing = await _context.AttendanceRecords
            .FirstOrDefaultAsync(a => a.EmployeeId == employee.Id && a.Date == today, cancellationToken);

        if (existing is not null)
            throw new ConflictException("Already checked in today.");

        var checkInTime = request.Time ?? TimeOnly.FromDateTime(_dateTimeService.UtcNow);

        // Determine status (late if after 09:00)
        var status = checkInTime > new TimeOnly(9, 0)
            ? AttendanceStatus.Late
            : AttendanceStatus.Present;

        var attendance = Domain.Entities.Attendance.Create(employee.Id, today, status);
        attendance.RecordCheckIn(checkInTime);

        await _context.AttendanceRecords.AddAsync(attendance, cancellationToken);
        await _unitOfWork.SaveChangesAsync(cancellationToken);

        return attendance.Id;
    }
}
```

**Monthly Report Query:**

```csharp
// src/MiniHRM.Application/Attendance/Queries/GetMonthlyReport/GetMonthlyReportQuery.cs
using MediatR;
using MiniHRM.Application.Attendance.DTOs;

namespace MiniHRM.Application.Attendance.Queries.GetMonthlyReport;

public record GetMonthlyReportQuery(Guid EmployeeId, int Year, int Month)
    : IRequest<MonthlyAttendanceReportDto>;
```

```csharp
// src/MiniHRM.Application/Attendance/DTOs/MonthlyAttendanceReportDto.cs
using MiniHRM.Domain.Enums;

namespace MiniHRM.Application.Attendance.DTOs;

public class MonthlyAttendanceReportDto
{
    public Guid EmployeeId { get; set; }
    public string EmployeeName { get; set; } = null!;
    public int Year { get; set; }
    public int Month { get; set; }
    public int TotalWorkingDays { get; set; }
    public int PresentDays { get; set; }
    public int AbsentDays { get; set; }
    public int LateDays { get; set; }
    public int HalfDays { get; set; }
    public List<AttendanceDto> Records { get; set; } = [];
}
```

**Step: Commit**

```bash
git add src/MiniHRM.Application/Attendance/
git commit -m "feat(app): add Attendance CheckIn/CheckOut commands and monthly report query"
```

---

## Phase 12: Testing

### Task 12.1: Application Handler Tests

**Files:**
- `tests/MiniHRM.Application.Tests/LeaveRequests/ApproveLeaveRequestCommandHandlerTests.cs`
- `tests/MiniHRM.Application.Tests/Employees/CreateEmployeeCommandHandlerTests.cs`
- `tests/MiniHRM.Application.Tests/Common/ValidationBehaviorTests.cs`

**ApproveLeaveRequest test:**

```csharp
// tests/MiniHRM.Application.Tests/LeaveRequests/ApproveLeaveRequestCommandHandlerTests.cs
using FluentAssertions;
using MiniHRM.Application.Common.Exceptions;
using MiniHRM.Application.Common.Interfaces;
using MiniHRM.Application.LeaveRequests.Commands.ApproveLeaveRequest;
using MiniHRM.Domain.Entities;
using MiniHRM.Domain.Enums;
using NSubstitute;
using NSubstitute.ReturnsExtensions;

namespace MiniHRM.Application.Tests.LeaveRequests;

public class ApproveLeaveRequestCommandHandlerTests
{
    private readonly IApplicationDbContext _context;
    private readonly ICurrentUserService _currentUserService;
    private readonly IUnitOfWork _unitOfWork;
    private readonly ApproveLeaveRequestCommandHandler _handler;

    private readonly Guid _reviewerEmployeeId = Guid.NewGuid();
    private readonly Guid _requestorEmployeeId = Guid.NewGuid();

    public ApproveLeaveRequestCommandHandlerTests()
    {
        _context = Substitute.For<IApplicationDbContext>();
        _currentUserService = Substitute.For<ICurrentUserService>();
        _unitOfWork = Substitute.For<IUnitOfWork>();
        _handler = new ApproveLeaveRequestCommandHandler(_context, _currentUserService, _unitOfWork);
    }

    [Fact]
    public async Task Handle_WithValidRequest_ShouldApproveAndSave()
    {
        var leaveRequest = LeaveRequest.Create(
            _requestorEmployeeId, LeaveType.Annual,
            DateTime.Today.AddDays(1), DateTime.Today.AddDays(3), "Vacation");

        // Setup mock context...
        // This is simplified — in real tests use MockQueryable helper

        await _unitOfWork.Received(1).SaveChangesAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Handle_WhenLeaveRequestNotFound_ShouldThrowNotFoundException()
    {
        // Setup returns null for FindAsync
        var act = () => _handler.Handle(
            new ApproveLeaveRequestCommand(Guid.NewGuid(), null), CancellationToken.None);

        await act.Should().ThrowAsync<NotFoundException>();
    }
}
```

**Step: Commit**

```bash
git add tests/MiniHRM.Application.Tests/
git commit -m "test(app): add application handler unit tests for LeaveRequest and Employee"
```

---

### Task 12.2: Integration Tests Setup

**Files:**
- Create: `tests/MiniHRM.API.Tests/CustomWebApplicationFactory.cs`
- Create: `tests/MiniHRM.API.Tests/Helpers/TestDatabaseHelper.cs`
- Create: `tests/MiniHRM.API.Tests/Controllers/DepartmentsControllerTests.cs`
- Create: `tests/MiniHRM.API.Tests/Controllers/AuthControllerTests.cs`

**Step 1: Create CustomWebApplicationFactory**

```csharp
// tests/MiniHRM.API.Tests/CustomWebApplicationFactory.cs
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using MiniHRM.Infrastructure.Data;
using Testcontainers.MsSql;

namespace MiniHRM.API.Tests;

public class CustomWebApplicationFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly MsSqlContainer _sqlContainer = new MsSqlBuilder()
        .WithImage("mcr.microsoft.com/mssql/server:2025-latest")
        .WithPassword("MiniHrm@2026!")
        .Build();

    public async Task InitializeAsync()
    {
        await _sqlContainer.StartAsync();
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            // Remove existing DbContext registration
            var descriptor = services.SingleOrDefault(
                d => d.ServiceType == typeof(DbContextOptions<ApplicationDbContext>));
            if (descriptor != null)
                services.Remove(descriptor);

            // Register test DbContext pointing to container
            services.AddDbContext<ApplicationDbContext>(options =>
            {
                options.UseSqlServer(_sqlContainer.GetConnectionString());
            });
        });

        builder.UseEnvironment("Testing");
    }

    async Task IAsyncLifetime.DisposeAsync()
    {
        await _sqlContainer.DisposeAsync();
    }
}
```

**Step 2: Create DepartmentsController integration test**

```csharp
// tests/MiniHRM.API.Tests/Controllers/DepartmentsControllerTests.cs
using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using MiniHRM.Application.Departments.Commands.CreateDepartment;
using MiniHRM.Application.Departments.DTOs;

namespace MiniHRM.API.Tests.Controllers;

public class DepartmentsControllerTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly HttpClient _client;

    public DepartmentsControllerTests(CustomWebApplicationFactory factory)
    {
        _client = factory.CreateClient();
        // TODO: Add auth token helper for authenticated requests
    }

    [Fact]
    public async Task GetAll_WithoutAuth_ShouldReturn401()
    {
        var response = await _client.GetAsync("/api/v1/departments");
        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task GetAll_WithAuth_ShouldReturnDepartmentsList()
    {
        // Authenticate first
        // var token = await AuthHelper.GetAdminTokenAsync(_client);
        // _client.DefaultRequestHeaders.Authorization = new("Bearer", token);

        var response = await _client.GetAsync("/api/v1/departments");
        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var departments = await response.Content.ReadFromJsonAsync<List<DepartmentDto>>();
        departments.Should().NotBeNull();
    }
}
```

**Step: Commit**

```bash
git add tests/MiniHRM.API.Tests/
git commit -m "test(integration): add WebApplicationFactory with Testcontainers SQL Server"
```

---

## Phase 13: DevOps

### Task 13.1: GitHub Actions CI Pipeline

**Files:**
- Create: `.github/workflows/ci.yml`

**Step 1: Create CI workflow**

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  build-and-test:
    name: Build and Test
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup .NET 10
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '10.0.x'

      - name: Restore dependencies
        run: dotnet restore MiniHRM.sln

      - name: Build solution
        run: dotnet build MiniHRM.sln --no-restore --configuration Release

      - name: Run Domain unit tests
        run: dotnet test tests/MiniHRM.Domain.Tests --no-build --configuration Release --logger "trx;LogFileName=domain-tests.trx"

      - name: Run Application unit tests
        run: dotnet test tests/MiniHRM.Application.Tests --no-build --configuration Release --logger "trx;LogFileName=application-tests.trx"

      - name: Run Integration tests
        run: dotnet test tests/MiniHRM.API.Tests --no-build --configuration Release --logger "trx;LogFileName=api-tests.trx"

      - name: Publish test results
        uses: dorny/test-reporter@v1
        if: always()
        with:
          name: Test Results
          path: '**/*.trx'
          reporter: dotnet-trx

      - name: Build Docker image
        run: docker build -t minihrm-api:${{ github.sha }} .
```

**Step 2: Build and verify**

```bash
dotnet build MiniHRM.sln
```

**Step 3: Commit**

```bash
git add .github/
git commit -m "ci: add GitHub Actions CI pipeline for build and test"
```

---

### Task 13.2: Add Employee.UserId Field (Linking Identity ↔ Employee)

> This is a critical cross-cutting concern noted in Phase 10. An Employee profile must be linked to an Identity user.

**Step 1: Add UserId to Employee entity**

```csharp
// Add to Employee entity
public string? UserId { get; private set; }

public void LinkToUser(string userId)
{
    UserId = userId;
}
```

**Step 2: Add to EF config**

```csharp
// In EmployeeConfiguration.cs
builder.Property(e => e.UserId).HasMaxLength(450);
builder.HasIndex(e => e.UserId).IsUnique();
```

**Step 3: Update Register command to link user to employee**

In the `RegisterAsync` flow: after creating identity user, optionally create employee profile linked to it.

**Step 4: Create new migration**

```bash
dotnet ef migrations add AddUserIdToEmployee -p src/MiniHRM.Infrastructure -s src/MiniHRM.API
```

**Step 5: Commit**

```bash
git add -A
git commit -m "feat(domain): add UserId to Employee for identity linkage + migration"
```

---

## Final Verification

### Run full test suite

```bash
dotnet test MiniHRM.sln -v n
```

Expected output: All tests PASS.

### Run with Docker

```bash
docker-compose up --build
```

Verify:
- API running at `http://localhost:5000`
- Swagger UI at `http://localhost:5000/swagger`
- Seq log viewer at `http://localhost:8081`
- Health check at `http://localhost:5000/health`

### Final commit

```bash
git add -A
git commit -m "chore: final verification and cleanup"
```

---

## Summary Checklist

- [ ] Phase 1: Solution scaffolding, NuGet packages, Docker, .gitignore
- [ ] Phase 2: Domain — BaseEntity, AggregateRoot, Enums, Value Objects, Entities, Domain Events, Repository Interfaces
- [ ] Phase 3: Infrastructure — DbContext, EF configs, Interceptor, Repositories, Seed data, DI
- [ ] Phase 4: Application common — Exceptions, PaginatedList, Pipeline Behaviors, Mapster, IApplicationDbContext, DI
- [ ] Phase 5: Department CQRS (Commands + Queries + Validators)
- [ ] Phase 6: Position CQRS
- [ ] Phase 7: Employee CQRS with pagination, value object mapping
- [ ] Phase 8: Identity — ASP.NET Identity, JWT, Login/Register
- [ ] Phase 9: API layer — Program.cs, Middleware, Controllers, EF Migration
- [ ] Phase 10: Leave Management — Request + Approval workflow + Domain Events + Balance deduction
- [ ] Phase 11: Attendance — CheckIn/CheckOut + Monthly report
- [ ] Phase 12: Tests — Unit (Application) + Integration (Testcontainers)
- [ ] Phase 13: DevOps — GitHub Actions CI, Docker verification
