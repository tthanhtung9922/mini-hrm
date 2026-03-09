# MiniHRM — Backend Design Document

**Date:** 2026-03-09
**Purpose:** Portfolio project + learning — targeting mid-level .NET developer role (2-3 years experience)
**Architecture:** Clean Architecture + DDD-lite + CQRS (MediatR)

---

## 1. Tech Stack

| Category | Technology | Version |
|---|---|---|
| Framework | .NET | 10 (LTS) |
| ORM | Entity Framework Core | 10.x |
| Database | SQL Server | 2025 |
| Auth | ASP.NET Identity + JWT | - |
| Mediator/CQRS | MediatR | 14.x |
| Validation | FluentValidation | 12.x |
| Mapping | Mapster | latest |
| API Versioning | Asp.Versioning.Mvc | latest stable |
| Logging | Serilog | latest |
| Testing | xUnit + NSubstitute + FluentAssertions + Bogus + Testcontainers | latest |
| CI/CD | GitHub Actions | - |
| Container | Docker + docker-compose | SQL Server 2025 |

---

## 2. Feature Scope

### Core HR
- Employee management (CRUD, search, filter, pagination)
- Department management (CRUD, assign manager)
- Position management (CRUD, salary range)

### Attendance & Leave
- Leave request workflow (submit, approve, reject, cancel)
- Leave balance tracking (per employee, per leave type, per year)
- Attendance tracking (check-in, check-out, daily records)
- Attendance reports (by employee, by date range, monthly)

### Authentication & Authorization
- JWT-based authentication with refresh tokens
- Role-based access: Admin, HRManager, Manager, Employee
- ASP.NET Identity for user management

---

## 3. Solution Structure

```
MiniHRM/
├── src/
│   ├── MiniHRM.Domain/              # Entities, Value Objects, Enums, Domain Events, Interfaces
│   ├── MiniHRM.Application/         # CQRS Handlers, DTOs, Validators, Behaviors, Mappings
│   ├── MiniHRM.Infrastructure/      # EF Core, Repositories, External Services, Identity
│   └── MiniHRM.API/                 # Controllers, Middleware, Filters, Configuration
├── tests/
│   ├── MiniHRM.Domain.Tests/        # Domain logic unit tests
│   ├── MiniHRM.Application.Tests/   # Handler unit tests with mocking
│   └── MiniHRM.API.Tests/           # Integration tests with WebApplicationFactory
├── docs/
│   └── plans/                       # Design & planning documents
├── docker-compose.yml
├── Dockerfile
├── .github/workflows/ci.yml
└── MiniHRM.slnx
```

**Layer dependency rules (strict):**
- **Domain** → depends on nothing
- **Application** → depends on Domain only
- **Infrastructure** → depends on Application + Domain
- **API** → depends on Application + Infrastructure (for DI registration only)

---

## 4. Domain Layer — DDD-lite

### 4.1 Aggregates & Entities

#### Employee (Aggregate Root)
- `EmployeeId` (Value Object)
- `FullName` (Value Object: FirstName, LastName)
- `Email` (Value Object — validated format)
- `PhoneNumber` (Value Object)
- `DateOfBirth`
- `HireDate`
- `EmploymentStatus` (Enum: Active, OnLeave, Resigned, Terminated)
- `DepartmentId` (FK)
- `PositionId` (FK)
- `Gender` (Enum)

#### Department (Aggregate Root)
- `DepartmentId` (Value Object)
- `Name`
- `Description`
- `ManagerId` (FK to Employee, nullable)

#### Position (Aggregate Root)
- `PositionId` (Value Object)
- `Title`
- `Description`
- `MinSalary` / `MaxSalary`
- `DepartmentId` (FK)

#### LeaveRequest (Aggregate Root)
- `LeaveRequestId` (Value Object)
- `EmployeeId` (FK)
- `LeaveType` (Enum: Annual, Sick, Unpaid, Maternity, Paternity, Other)
- `StartDate` / `EndDate`
- `Reason`
- `Status` (Enum: Pending, Approved, Rejected, Cancelled)
- `ReviewedBy` (FK to Employee, nullable)
- `ReviewedDate`
- `ReviewNote`

#### Attendance (Entity)
- `AttendanceId`
- `EmployeeId` (FK)
- `Date`
- `CheckIn` / `CheckOut`
- `Status` (Enum: Present, Absent, Late, HalfDay)
- `Note`

#### LeaveBalance (Entity)
- `EmployeeId` (FK)
- `LeaveType`
- `Year`
- `TotalDays` / `UsedDays` / `RemainingDays`

### 4.2 DDD Patterns Applied

- **Value Objects:** `Email`, `FullName`, `PhoneNumber`, `EmployeeId`, `DepartmentId`, `PositionId`, `LeaveRequestId` — encapsulate validation, immutable
- **Domain Events:** `EmployeeCreatedEvent`, `LeaveRequestApprovedEvent`, `LeaveRequestRejectedEvent` — trigger side effects like updating LeaveBalance
- **Domain Services:** `LeaveBalanceService` — business rules spanning multiple aggregates
- **Base classes:** `BaseEntity` (Id, CreatedAt, UpdatedAt, CreatedBy, UpdatedBy), `AggregateRoot` (extends BaseEntity, adds domain event collection)

### 4.3 Key Business Rules (enforced in Domain)

1. Leave request dates cannot overlap for the same employee
2. Leave request cannot exceed remaining balance
3. Approving a leave request deducts from LeaveBalance
4. Employee cannot approve their own leave request
5. Department manager must be an employee in that department

---

## 5. Application Layer — CQRS & Cross-cutting

### 5.1 Folder Structure

```
Application/
├── Common/
│   ├── Behaviors/
│   │   ├── ValidationBehavior.cs
│   │   ├── LoggingBehavior.cs
│   │   └── UnhandledExceptionBehavior.cs
│   ├── Interfaces/
│   │   ├── IApplicationDbContext.cs
│   │   ├── ICurrentUserService.cs
│   │   └── IDateTimeService.cs
│   ├── Mappings/
│   │   └── MapsterConfig.cs
│   ├── Models/
│   │   ├── Result.cs
│   │   └── PaginatedList.cs
│   └── Exceptions/
│       ├── NotFoundException.cs
│       ├── ForbiddenException.cs
│       └── ValidationException.cs
│
├── Employees/
│   ├── Commands/ (Create, Update, Delete)
│   ├── Queries/ (GetById, GetList, GetByDepartment)
│   ├── DTOs/ (EmployeeDto, EmployeeBriefDto)
│   └── EventHandlers/ (EmployeeCreatedEventHandler)
│
├── Departments/
│   ├── Commands/ (Create, Update, Delete)
│   ├── Queries/ (GetById, GetList)
│   └── DTOs/
│
├── Positions/
│   ├── Commands/ (Create, Update, Delete)
│   ├── Queries/ (GetById, GetList, GetByDepartment)
│   └── DTOs/
│
├── LeaveRequests/
│   ├── Commands/ (Create, Approve, Reject, Cancel)
│   ├── Queries/ (GetById, GetMyRequests, GetPending)
│   ├── DTOs/
│   └── EventHandlers/ (ApprovedHandler, RejectedHandler)
│
├── Attendance/
│   ├── Commands/ (CheckIn, CheckOut, ManualEntry)
│   ├── Queries/ (GetByEmployee, GetByDate, GetMonthlyReport)
│   └── DTOs/
│
├── LeaveBalances/
│   ├── Commands/ (Initialize, Adjust)
│   ├── Queries/ (GetMyBalance, GetByEmployee)
│   └── DTOs/
│
└── Identity/
    ├── Commands/ (Login, Register, RefreshToken, ChangePassword)
    ├── Queries/ (GetCurrentUser)
    └── DTOs/ (AuthResponse, TokenDto)
```

### 5.2 Roles & Authorization

| Role | Permissions |
|---|---|
| Admin | Full access, manage users, system configuration |
| HRManager | Manage employees, approve/reject all leaves, view all attendance |
| Manager | Approve leaves for their department, view department attendance |
| Employee | View own profile, submit leave requests, check in/out |

### 5.3 MediatR Pipeline Behaviors

1. **LoggingBehavior** — logs every request entry/exit with timing
2. **ValidationBehavior** — runs FluentValidation before handler, throws ValidationException
3. **UnhandledExceptionBehavior** — catches unexpected errors, logs with context

---

## 6. Infrastructure Layer

### 6.1 Folder Structure

```
Infrastructure/
├── Data/
│   ├── ApplicationDbContext.cs
│   ├── Configurations/ (per entity Fluent API configs)
│   ├── Migrations/
│   ├── Interceptors/
│   │   └── AuditableEntityInterceptor.cs
│   └── Seeds/
│       └── ApplicationDbContextSeed.cs
│
├── Repositories/
│   ├── GenericRepository.cs
│   ├── EmployeeRepository.cs
│   ├── LeaveRequestRepository.cs
│   └── AttendanceRepository.cs
│
├── Identity/
│   ├── IdentityService.cs
│   ├── JwtTokenGenerator.cs
│   └── CurrentUserService.cs
│
├── Services/
│   └── DateTimeService.cs
│
└── DependencyInjection.cs
```

### 6.2 EF Core Conventions

- All configurations via Fluent API (no data annotations on domain entities)
- `AuditableEntityInterceptor` using `SaveChangesInterceptor` to auto-set audit fields
- Soft delete via `IsDeleted` flag + global query filter
- Seed data: 4 roles, 1 admin user, sample departments/positions

### 6.3 Repository Pattern

- `IGenericRepository<T>` defined in Application layer (interface)
- `GenericRepository<T>` implemented in Infrastructure
- Specific repositories only for custom query logic
- Uses `IQueryable` for flexible query composition

---

## 7. API Layer

### 7.1 Folder Structure

```
API/
├── Controllers/
│   └── v1/
│       ├── AuthController.cs
│       ├── EmployeesController.cs
│       ├── DepartmentsController.cs
│       ├── PositionsController.cs
│       ├── LeaveRequestsController.cs
│       ├── AttendanceController.cs
│       └── LeaveBalancesController.cs
│
├── Middleware/
│   └── GlobalExceptionHandlerMiddleware.cs
│
├── Filters/
│   └── ApiExceptionFilterAttribute.cs
│
├── Extensions/
│   ├── ServiceCollectionExtensions.cs
│   └── HostExtensions.cs
│
├── appsettings.json
├── appsettings.Development.json
└── Program.cs
```

### 7.2 API Conventions

- Versioning via URL path: `/api/v1/employees`
- Problem Details (RFC 7807) for all error responses
- Pagination: `?pageNumber=1&pageSize=10`
- Filtering/Sorting: `?department=IT&sortBy=hireDate&sortOrder=desc`
- JWT bearer auth in Swagger UI
- XML comments for endpoint documentation

### 7.3 Middleware Pipeline Order

1. Global exception handler
2. Serilog request logging
3. Authentication
4. Authorization
5. API versioning
6. Swagger (dev only)
7. Health checks (`/health`)
8. Controllers

---

## 8. Testing Strategy

### 8.1 Test Projects

| Project | Scope | Tools |
|---|---|---|
| MiniHRM.Domain.Tests | Value objects, entity logic, business rules | xUnit, FluentAssertions |
| MiniHRM.Application.Tests | Command/Query handlers, validators, behaviors | xUnit, NSubstitute, FluentAssertions, Bogus |
| MiniHRM.API.Tests | Full HTTP pipeline, database integration | xUnit, WebApplicationFactory, Testcontainers, FluentAssertions |

### 8.2 Testing Principles

- Domain tests: no mocking, pure logic verification
- Application tests: mock repositories, test handler behavior in isolation
- Integration tests: real HTTP calls, real SQL Server in Docker container
- Naming convention: `MethodName_Scenario_ExpectedResult`

---

## 9. DevOps & CI/CD

### 9.1 Docker

```yaml
# docker-compose.yml
services:
  api:        MiniHRM.API (ports 5000/5001)
  sqlserver:  mcr.microsoft.com/mssql/server:2025-latest (port 1433)
  seq:        Serilog Seq UI for viewing logs (port 5341)
```

Multi-stage Dockerfile: SDK image (build) → ASP.NET runtime image (run).

### 9.2 GitHub Actions CI

Trigger: push to main, pull requests.

Steps:
1. Checkout code
2. Setup .NET 10 SDK
3. Restore dependencies
4. Build solution
5. Run unit tests (Domain + Application)
6. Start SQL Server container
7. Run integration tests
8. Publish test results
9. Upload build artifacts

### 9.3 Serilog Configuration

- Sinks: Console (dev), File (rolling daily), Seq (local dev UI)
- Enrichers: Machine name, environment, request context, user context
- Structured logging — log objects, not string concatenation

### 9.4 Health Checks

- `/health` — overall status
- `/health/db` — database connectivity
- `/health/ready` — readiness probe

---

## 10. Enterprise Touches Summary

| Feature | Purpose |
|---|---|
| Serilog structured logging | Observability |
| Global exception handling | Consistent error responses |
| FluentValidation + MediatR pipeline | Clean validation pattern |
| Mapster | Performant DTO mapping |
| Health checks | Production-readiness |
| Docker + docker-compose | Containerized development |
| API versioning | Long-term maintainability |
| Soft delete | Data safety |
| Audit fields | Traceability |
