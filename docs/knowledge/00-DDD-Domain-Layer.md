# DDD Clean Architecture — Domain Layer (2026)

> Tài liệu tổng hợp về thiết kế, cấu trúc, naming convention, coding convention và thứ tự implement Domain Layer theo DDD + Clean Architecture chuẩn 2026.

---

## Mục lục

1. [Domain Events là gì?](#1-domain-events-là-gì)
2. [record vs class](#2-record-vs-class)
3. [Cấu trúc thư mục](#3-cấu-trúc-thư-mục)
4. [Naming Convention](#4-naming-convention)
5. [Coding Convention](#5-coding-convention)
6. [Implementation chi tiết](#6-implementation-chi-tiết)
   - [Common Layer](#common-layer)
   - [Orders Aggregate](#orders-aggregate)
   - [Customers Aggregate](#customers-aggregate)
   - [Products Aggregate](#products-aggregate)
   - [Shared](#shared)
7. [Thứ tự implement](#7-thứ-tự-implement)
8. [Nguyên tắc cốt lõi](#8-nguyên-tắc-cốt-lõi)
9. [Tech Stack 2026](#9-tech-stack-2026)

---

## 1. Domain Events là gì?

**Domain Event** là một sự kiện biểu diễn điều gì đó đã xảy ra trong domain nghiệp vụ. Sự kiện đã xảy ra thì không thể thay đổi — đây là lý do Events phải **immutable**.

### Đặt Events ở đâu?

Events nằm **trong folder của chính Aggregate** đó, không tách ra ngoài:

```
Orders/
├── Order.cs
└── Events/
    ├── OrderCreatedEvent.cs      ← tìm event của Order → vào folder Orders
    ├── OrderConfirmedEvent.cs
    └── OrderCancelledEvent.cs
```

### Dispatch Events khi nào?

Events được dispatch **sau khi `SaveChangesAsync` thành công** — đảm bảo DB commit trước khi side-effects xảy ra:

```csharp
public override async Task<int> SaveChangesAsync(CancellationToken ct = default)
{
    var result = await base.SaveChangesAsync(ct);

    var aggregates = ChangeTracker
        .Entries<AggregateRoot>()
        .Where(e => e.Entity.DomainEvents.Any())
        .Select(e => e.Entity)
        .ToList();

    var events = aggregates.SelectMany(a => a.DomainEvents).ToList();
    aggregates.ForEach(a => a.ClearDomainEvents());

    foreach (var @event in events)
        await _publisher.Publish(@event, ct);

    return result;
}
```

### Outbox Pattern (Distributed Systems)

Thay vì dispatch trực tiếp, lưu event vào bảng `OutboxMessages` trong **cùng 1 transaction** với aggregate — đảm bảo at-least-once delivery:

```
Infrastructure/
└── Messaging/
    └── Outbox/
        ├── OutboxMessage.cs
        ├── OutboxProcessor.cs      ← Background worker
        └── OutboxInterceptor.cs    ← EF Core SaveChanges interceptor
```

---

## 1.1 Aggregate là gì?

**Aggregate** là một nhóm các object liên quan, được quản lý **như một đơn vị duy nhất**.

Trong nhóm đó luôn có **một object đứng đầu** — gọi là **Aggregate Root** — là cửa ngõ duy nhất để tương tác với cả nhóm.

---

### Ví dụ dễ hiểu — Đơn hàng

Một đơn hàng thực tế gồm nhiều thứ:

```
Order (Aggregate Root)        ← "ông chủ"
├── OrderItem (sản phẩm A)    ← "nhân viên"
├── OrderItem (sản phẩm B)    ← "nhân viên"
└── Address (địa chỉ giao)    ← "nhân viên"
```

**Quy tắc:** Muốn làm gì với `OrderItem`, bạn phải đi qua `Order` — không được động thẳng vào `OrderItem` từ bên ngoài.

```csharp
// ❌ SAI — tương tác thẳng với OrderItem
orderItem.Quantity = 5;

// ✅ ĐÚNG — đi qua Aggregate Root
order.AddItem(productId, productName, quantity, price);
//    ↑ Order tự quyết định làm gì với OrderItem bên trong
```

**Tại sao?** Vì `Order` mới biết rule nghiệp vụ: "chỉ thêm item khi đơn hàng đang `Pending`", "nếu item đã tồn tại thì tăng số lượng thay vì thêm mới"... `OrderItem` không biết những điều đó.

---

### Nôm na một câu

> **Aggregate = một "bộ phận" trong công ty, Aggregate Root = trưởng bộ phận.** Muốn giao việc cho bộ phận đó → chỉ được nói chuyện với trưởng bộ phận, không được chỉ đạo thẳng nhân viên cấp dưới.

---

### Tại sao dùng `IReadOnlyList<IDomainEvent>`?

Có **2 lý do**, tách biệt nhau:

---

### Lý do 1 — `IReadOnlyList` thay vì `List`

`List<T>` cho phép bên ngoài làm mọi thứ: thêm, xóa, sửa, clear... Đó là điều không muốn — chỉ có `AggregateRoot` mới được thêm event vào, không ai khác:

```csharp
public abstract class AggregateRoot
{
    private readonly List<IDomainEvent> _domainEvents = [];

    // ✅ Bên ngoài chỉ được ĐỌC — không thêm/xóa được
    public IReadOnlyList<IDomainEvent> DomainEvents => _domainEvents.AsReadOnly();

    // ✅ Chỉ class con (Order, Customer...) mới được thêm event
    protected void Raise(IDomainEvent domainEvent) =>
        _domainEvents.Add(domainEvent);
}
```

Nếu để `public List<IDomainEvent>`, Infrastructure layer có thể vô tình (hoặc cố ý) làm điều này:

```csharp
// ❌ Nếu là List — ai cũng làm được, rất nguy hiểm
order.DomainEvents.Add(new OrderCreatedEvent(...));   // thêm event giả
order.DomainEvents.Clear();                           // xóa hết events trước khi dispatch
order.DomainEvents.RemoveAt(0);                       // xóa event cụ thể
```

---

### Lý do 2 — `IDomainEvent` thay vì type cụ thể

`IDomainEvent` là interface chung cho **tất cả** domain events. Nhờ vậy một `Order` có thể chứa nhiều loại event khác nhau trong cùng một list:

```csharp
// Một order có thể raise nhiều loại event trong cùng một transaction
order.Confirm();           // → thêm OrderConfirmedEvent
order.AddItem(...);        // → thêm OrderItemAddedEvent

// DomainEvents chứa cả hai — được vì đều là IDomainEvent
// [OrderConfirmedEvent, OrderItemAddedEvent]
IReadOnlyList<IDomainEvent> events = order.DomainEvents;
```

Infrastructure dispatch không cần biết type cụ thể:

```csharp
// ✅ Dùng IDomainEvent — dispatch được tất cả mà không cần biết type cụ thể
foreach (var @event in order.DomainEvents)
    await _publisher.Publish(@event, ct);

// ❌ Nếu dùng type cụ thể — phải xử lý riêng từng loại, không scalable
foreach (var @event in order.OrderCreatedEvents) ...
foreach (var @event in order.OrderConfirmedEvents) ...
```

---

### Tóm tắt

```
IReadOnlyList<IDomainEvent>
│              │
│              └── IDomainEvent → chứa được MỌI loại event
│                                 Infrastructure không cần biết type cụ thể
│
└── IReadOnlyList → chỉ được ĐỌC từ bên ngoài
                    chỉ AggregateRoot mới được thêm event qua Raise()
```

## 2. record vs class

### Sự khác biệt cốt lõi

| | `class` | `record` |
|---|---|---|
| Mutable mặc định | ✅ có thể sửa | ❌ không thể sửa |
| So sánh `==` | So sánh địa chỉ bộ nhớ | So sánh giá trị |
| Kế thừa | ✅ | ✅ (`abstract record`) |
| `with` expression | ❌ | ✅ |
| Phù hợp cho | Logic, services | Data, events, DTOs |

### Immutability

```csharp
var e = new OrderCreatedEvent(Guid.NewGuid(), DateTime.UtcNow);

e.OrderId = Guid.NewGuid(); // ❌ COMPILE ERROR
```

### Value Equality

```csharp
var event1 = new OrderCreatedEvent(id, DateTime.UtcNow);
var event2 = new OrderCreatedEvent(id, DateTime.UtcNow);

// class  → false (so sánh reference)
// record → true  (so sánh giá trị)
event1 == event2;
```

### with expression

```csharp
var original = new OrderCreatedEvent(OrderId: Guid.NewGuid(), ...);

// Tạo bản mới, giữ nguyên các field còn lại
var copy = original with { OccurredOn = DateTime.UtcNow.AddHours(1) };
// original vẫn không thay đổi
```

### Base record

"Base record" là `record` được dùng làm lớp cha — không có keyword đặc biệt:

```csharp
// Base record
public abstract record DomainEvent : IDomainEvent
{
    public Guid EventId { get; } = Guid.NewGuid();
    public DateTime OccurredOn { get; } = DateTime.UtcNow;
    public string EventType => GetType().Name;
}

// Kế thừa từ base record — tự động có EventId, OccurredOn, EventType
public sealed record OrderCreatedEvent(
    Guid OrderId,
    decimal TotalAmount
) : DomainEvent;
```

---

## 3. Cấu trúc thư mục

```
Domain/
├── Common/
│   ├── Abstractions/
│   │   ├── AggregateRoot.cs
│   │   ├── DomainEvent.cs
│   │   ├── Entity.cs
│   │   ├── IAggregateRoot.cs
│   │   ├── IDomainEvent.cs
│   │   └── ValueObject.cs
│   ├── Guards/
│   │   └── GuardClauses.cs
│   ├── Primitives/
│   │   └── Enumeration.cs
│   └── Results/
│       ├── Error.cs
│       └── Result.cs
│
├── Orders/
│   ├── Order.cs
│   ├── OrderItem.cs
│   ├── Enums/
│   │   └── OrderStatus.cs
│   ├── Errors/
│   │   └── OrderErrors.cs
│   ├── Events/
│   │   ├── OrderCancelledEvent.cs
│   │   ├── OrderConfirmedEvent.cs
│   │   ├── OrderCreatedEvent.cs
│   │   └── OrderItemAddedEvent.cs
│   ├── Repositories/
│   │   └── IOrderRepository.cs
│   ├── Specifications/
│   │   └── ActiveOrderSpecification.cs
│   └── ValueObjects/
│       ├── Address.cs
│       └── OrderNumber.cs
│
├── Customers/
│   ├── Customer.cs
│   ├── Enums/
│   │   └── CustomerTier.cs
│   ├── Errors/
│   │   └── CustomerErrors.cs
│   ├── Events/
│   │   ├── CustomerDeactivatedEvent.cs
│   │   ├── CustomerEmailChangedEvent.cs
│   │   └── CustomerRegisteredEvent.cs
│   ├── Repositories/
│   │   └── ICustomerRepository.cs
│   ├── Specifications/
│   │   └── ActiveCustomerSpecification.cs
│   └── ValueObjects/
│       ├── Email.cs
│       ├── FullName.cs
│       └── PhoneNumber.cs
│
├── Products/
│   ├── Product.cs
│   ├── Enums/
│   │   └── ProductStatus.cs
│   ├── Errors/
│   │   └── ProductErrors.cs
│   ├── Events/
│   │   ├── ProductCreatedEvent.cs
│   │   ├── ProductPriceChangedEvent.cs
│   │   ├── ProductRestockedEvent.cs
│   │   └── ProductStockDepletedEvent.cs
│   ├── Repositories/
│   │   └── IProductRepository.cs
│   └── ValueObjects/
│       ├── ProductName.cs
│       └── Sku.cs
│
└── Shared/
    └── ValueObjects/
        └── Money.cs
```

### Mỗi Aggregate có đủ 7 thành phần

| Thành phần | Mục đích |
|---|---|
| `[Noun].cs` | Aggregate Root — entry point duy nhất |
| `[Noun]Item.cs` | Child Entity (nếu có) |
| `Events/` | Domain Events của aggregate này |
| `ValueObjects/` | Value Objects thuộc aggregate |
| `Enums/` | Enums chỉ dùng trong aggregate này |
| `Errors/` | Static class định nghĩa lỗi domain |
| `Repositories/` | Interface contract (impl ở Infrastructure) |
| `Specifications/` | Business rules có thể tái sử dụng |

---

## 4. Naming Convention

### Bảng tổng hợp

| Loại | Convention | Ví dụ |
|---|---|---|
| Interface | `I` + PascalCase | `IDomainEvent`, `IOrderRepository` |
| Abstract class | PascalCase, không prefix | `AggregateRoot`, `Entity` |
| Sealed class (Aggregate) | PascalCase | `Order`, `Customer` |
| Sealed record (ValueObject) | Noun, PascalCase | `Money`, `Email`, `OrderNumber` |
| Domain Event | `[Noun][PastTenseVerb]Event` | `OrderCreatedEvent` |
| Enum type | `[Noun]Status` / `[Noun]Type` / `[Noun]Tier` | `OrderStatus`, `CustomerTier` |
| Error static class | `[Noun]Errors` (số nhiều) | `OrderErrors`, `ProductErrors` |
| Specification | `[Adjective][Noun]Specification` | `ActiveOrderSpecification` |
| Repository interface | `I[Noun]Repository` | `IOrderRepository` |
| Folder | số nhiều nếu chứa nhiều file | `Events/`, `ValueObjects/`, `Enums/` |
| Folder | số ít nếu là layer/concept | `Common/`, `Domain/`, `Shared/` |

### Rule 1 — Event naming: động từ quá khứ

Sự kiện là việc **đã xảy ra** → luôn dùng past tense:

```
✅ OrderCreated       ✅ CustomerRegistered    ✅ StockDepleted
❌ CreateOrder        ❌ RegisterCustomer      ❌ DepletingStock
```

### Rule 2 — Folder số nhiều, File số ít

```
✅ Folders: Events/  ValueObjects/  Enums/  Errors/  Repositories/
✅ Files:   OrderCreatedEvent.cs  Money.cs  OrderStatus.cs
```

### Rule 3 — `Base` prefix là anti-pattern

```csharp
❌ BaseEntity.cs          // "Base" là implementation detail
❌ BaseAggregateRoot.cs
❌ BaseDomainEvent.cs

✅ Entity.cs              // abstract keyword đã nói lên đây là base class
✅ AggregateRoot.cs
✅ DomainEvent.cs
```

`Base` chỉ hợp lệ khi cần phân biệt 2+ class cùng cấp (ví dụ: `BaseController` khi có nhiều loại Controller).

### Rule 4 — `Entity` không phải `BaseEntity`

```csharp
public class Order : BaseEntity  // "Order là một BaseEntity" ← nghe kỳ
public class Order : Entity      // "Order là một Entity"     ← tự nhiên, đúng DDD
```

---

## 5. Coding Convention

### Access Modifiers

```csharp
public sealed class Order : AggregateRoot
{
    // ✅ private set — bên ngoài không mutate trực tiếp
    public OrderStatus Status { get; private set; }

    // ✅ private init — set một lần khi tạo, không thay đổi
    public DateTime CreatedAt { get; private init; }

    // ✅ Constructor private — bắt buộc dùng factory method
    private Order() { } // EF Core

    // ✅ Factory method public static
    public static Result<Order> Create(...) { }

    // ✅ Raise protected — chỉ AggregateRoot con mới gọi được
    protected void Raise(IDomainEvent domainEvent) { }
}
```

### sealed cho Aggregate Root và ValueObject

```csharp
public sealed class Order : AggregateRoot { }       // không cho kế thừa ngoài ý muốn
public sealed record Money(decimal Amount, ...) { }  // không cho kế thừa
```

### internal cho Child Entity factory

```csharp
// OrderItem chỉ được tạo bởi Order aggregate
internal static OrderItem Create(...) { }
```

### Result pattern thay vì throw Exception

```csharp
// ❌ throw exception cho business rule violation
public void Confirm()
{
    if (Status == OrderStatus.Confirmed)
        throw new InvalidOperationException("Already confirmed.");
}

// ✅ trả về Result
public Result Confirm()
{
    if (Status == OrderStatus.Confirmed)
        return Result.Failure(OrderErrors.AlreadyConfirmed);

    Status = OrderStatus.Confirmed;
    Raise(new OrderConfirmedEvent(Id, CustomerId));
    return Result.Success();
}
```

### GuardClauses cho input validation

```csharp
// ❌ inline if/throw
public static Email Of(string value)
{
    if (string.IsNullOrWhiteSpace(value))
        throw new ArgumentException("...");
}

// ✅ GuardClauses
public static OrderItem Create(Guid productId, string name, int quantity, Money price)
{
    GuardClauses.NotEmpty(productId, nameof(productId));
    GuardClauses.NotNullOrWhiteSpace(name, nameof(name));
    GuardClauses.Positive(quantity, nameof(quantity));
    // ...
}
```

### XML Doc Comments

```csharp
/// <summary>
/// Raised when a new order is successfully created.
/// </summary>
public sealed record OrderCreatedEvent(...) : DomainEvent;

/// <summary>
/// Required by EF Core — never call directly.
/// </summary>
private Order() { }
```

### Domain layer không import gì ngoài .NET BCL

```csharp
// ❌ KHÔNG import trong Domain layer
using Microsoft.EntityFrameworkCore;
using MediatR;
using Newtonsoft.Json;

// ✅ Chỉ được dùng
using System;
using System.Collections.Generic;
using System.Linq;
```

---

## 6. Implementation chi tiết

### Common Layer

#### `IDomainEvent.cs`

```csharp
namespace Domain.Common.Abstractions;

public interface IDomainEvent
{
    Guid EventId { get; }
    DateTime OccurredOn { get; }
    string EventType { get; }
}
```

#### `IAggregateRoot.cs`

```csharp
namespace Domain.Common.Abstractions;

public interface IAggregateRoot
{
    IReadOnlyList<IDomainEvent> DomainEvents { get; }
    void ClearDomainEvents();
}
```

#### `DomainEvent.cs`

```csharp
namespace Domain.Common.Abstractions;

public abstract record DomainEvent : IDomainEvent
{
    public Guid EventId { get; } = Guid.NewGuid();
    public DateTime OccurredOn { get; } = DateTime.UtcNow;
    public string EventType => GetType().Name;
}
```

#### `Entity.cs`

```csharp
namespace Domain.Common.Abstractions;

public abstract class Entity : IEquatable<Entity>
{
    public Guid Id { get; protected init; }

    protected Entity(Guid id)
    {
        if (id == Guid.Empty)
            throw new ArgumentException("Entity Id cannot be empty.", nameof(id));
        Id = id;
    }

    protected Entity() { } // EF Core

    public bool Equals(Entity? other)
    {
        if (other is null) return false;
        if (ReferenceEquals(this, other)) return true;
        return Id == other.Id && GetType() == other.GetType();
    }

    public override bool Equals(object? obj) =>
        obj is Entity entity && Equals(entity);

    public override int GetHashCode() =>
        HashCode.Combine(GetType(), Id);

    public static bool operator ==(Entity? left, Entity? right) =>
        left?.Equals(right) ?? right is null;

    public static bool operator !=(Entity? left, Entity? right) =>
        !(left == right);
}
```

#### `AggregateRoot.cs`

```csharp
namespace Domain.Common.Abstractions;

public abstract class AggregateRoot : Entity, IAggregateRoot
{
    private readonly List<IDomainEvent> _domainEvents = [];

    public IReadOnlyList<IDomainEvent> DomainEvents => _domainEvents.AsReadOnly();

    protected AggregateRoot(Guid id) : base(id) { }
    protected AggregateRoot() { } // EF Core

    protected void Raise(IDomainEvent domainEvent) =>
        _domainEvents.Add(domainEvent);

    public void ClearDomainEvents() =>
        _domainEvents.Clear();
}
```

#### `ValueObject.cs`

```csharp
namespace Domain.Common.Abstractions;

public abstract class ValueObject : IEquatable<ValueObject>
{
    protected abstract IEnumerable<object?> GetEqualityComponents();

    public bool Equals(ValueObject? other)
    {
        if (other is null) return false;
        if (GetType() != other.GetType()) return false;
        return GetEqualityComponents().SequenceEqual(other.GetEqualityComponents());
    }

    public override bool Equals(object? obj) =>
        obj is ValueObject valueObject && Equals(valueObject);

    public override int GetHashCode() =>
        GetEqualityComponents()
            .Aggregate(0, (hash, component) =>
                HashCode.Combine(hash, component?.GetHashCode() ?? 0));

    public static bool operator ==(ValueObject? left, ValueObject? right) =>
        left?.Equals(right) ?? right is null;

    public static bool operator !=(ValueObject? left, ValueObject? right) =>
        !(left == right);
}
```

#### `Error.cs`

```csharp
namespace Domain.Common.Results;

public sealed record Error(string Code, string Message)
{
    public static readonly Error None = new(string.Empty, string.Empty);

    public static Error NotFound(string resource) =>
        new($"{resource}.NotFound", $"{resource} was not found.");

    public static Error Validation(string field, string message) =>
        new($"Validation.{field}", message);

    public static Error Conflict(string resource) =>
        new($"{resource}.Conflict", $"{resource} already exists.");
}
```

#### `Result.cs`

```csharp
namespace Domain.Common.Results;

public class Result
{
    protected Result(bool isSuccess, Error error)
    {
        IsSuccess = isSuccess;
        Error = error;
    }

    public bool IsSuccess { get; }
    public bool IsFailure => !IsSuccess;
    public Error Error { get; }

    public static Result Success() => new(true, Error.None);
    public static Result Failure(Error error) => new(false, error);
    public static Result<TValue> Success<TValue>(TValue value) => new(value, true, Error.None);
    public static Result<TValue> Failure<TValue>(Error error) => new(default, false, error);
}

public sealed class Result<TValue> : Result
{
    private readonly TValue? _value;

    internal Result(TValue? value, bool isSuccess, Error error)
        : base(isSuccess, error) => _value = value;

    public TValue Value => IsSuccess
        ? _value!
        : throw new InvalidOperationException("Cannot access Value of a failed result.");

    public static implicit operator Result<TValue>(TValue value) => Success(value);
}
```

#### `GuardClauses.cs`

```csharp
namespace Domain.Common.Guards;

public static class GuardClauses
{
    public static T NotNull<T>(T? value, string paramName) where T : class
    {
        if (value is null)
            throw new ArgumentNullException(paramName);
        return value;
    }

    public static string NotNullOrWhiteSpace(string? value, string paramName)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new ArgumentException($"{paramName} cannot be null or whitespace.", paramName);
        return value;
    }

    public static Guid NotEmpty(Guid value, string paramName)
    {
        if (value == Guid.Empty)
            throw new ArgumentException($"{paramName} cannot be empty.", paramName);
        return value;
    }

    public static decimal Positive(decimal value, string paramName)
    {
        if (value <= 0)
            throw new ArgumentOutOfRangeException(paramName, $"{paramName} must be positive.");
        return value;
    }
}
```

#### `Enumeration.cs`

```csharp
namespace Domain.Common.Primitives;

/// <summary>
/// Rich enumeration với behavior — dùng thay plain enum
/// khi cần methods, descriptions, hoặc logic phức tạp per value.
/// </summary>
public abstract class Enumeration : IComparable<Enumeration>
{
    public int Id { get; }
    public string Name { get; }

    protected Enumeration(int id, string name) { Id = id; Name = name; }

    public static IEnumerable<T> GetAll<T>() where T : Enumeration =>
        typeof(T).GetFields(System.Reflection.BindingFlags.Public |
                            System.Reflection.BindingFlags.Static |
                            System.Reflection.BindingFlags.DeclaredOnly)
                 .Select(f => f.GetValue(null)).Cast<T>();

    public int CompareTo(Enumeration? other) => Id.CompareTo(other?.Id);
    public override string ToString() => Name;
}
```

---

### Orders Aggregate

#### `OrderStatus.cs`

```csharp
namespace Domain.Orders.Enums;

public enum OrderStatus
{
    Pending = 1,
    Confirmed = 2,
    Shipped = 3,
    Delivered = 4,
    Cancelled = 5
}
```

#### `OrderErrors.cs`

```csharp
namespace Domain.Orders.Errors;

public static class OrderErrors
{
    public static readonly Error NotFound =
        new("Order.NotFound", "The order with the specified Id was not found.");

    public static readonly Error AlreadyConfirmed =
        new("Order.AlreadyConfirmed", "The order has already been confirmed.");

    public static readonly Error AlreadyCancelled =
        new("Order.AlreadyCancelled", "The order has already been cancelled.");

    public static readonly Error CannotCancelConfirmedOrder =
        new("Order.CannotCancelConfirmed", "A confirmed order cannot be cancelled directly.");

    public static readonly Error EmptyItems =
        new("Order.EmptyItems", "An order must contain at least one item.");

    public static Error ItemNotFound(Guid itemId) =>
        new("Order.ItemNotFound", $"Order item '{itemId}' was not found.");
}
```

#### `OrderEvents.cs`

```csharp
namespace Domain.Orders.Events;

public sealed record OrderCreatedEvent(
    Guid OrderId,
    Guid CustomerId,
    string OrderNumber,
    Money TotalAmount
) : DomainEvent;

public sealed record OrderConfirmedEvent(
    Guid OrderId,
    Guid CustomerId
) : DomainEvent;

public sealed record OrderCancelledEvent(
    Guid OrderId,
    Guid CustomerId,
    string Reason
) : DomainEvent;

public sealed record OrderItemAddedEvent(
    Guid OrderId,
    Guid ProductId,
    int Quantity,
    Money UnitPrice
) : DomainEvent;
```

#### `Address.cs`

```csharp
namespace Domain.Orders.ValueObjects;

public sealed record Address
{
    public string Street { get; }
    public string City { get; }
    public string Province { get; }
    public string PostalCode { get; }
    public string Country { get; }

    private Address(string street, string city, string province,
                    string postalCode, string country)
    {
        Street = street; City = city; Province = province;
        PostalCode = postalCode; Country = country;
    }

    public static Address Of(string street, string city, string province,
                             string postalCode, string country)
    {
        if (string.IsNullOrWhiteSpace(street))
            throw new ArgumentException("Street cannot be empty.", nameof(street));
        if (string.IsNullOrWhiteSpace(city))
            throw new ArgumentException("City cannot be empty.", nameof(city));

        return new Address(street.Trim(), city.Trim(), province.Trim(),
                           postalCode.Trim(), country.Trim().ToUpperInvariant());
    }
}
```

#### `OrderItem.cs` (Child Entity)

```csharp
namespace Domain.Orders;

/// <summary>
/// Child entity — không raise events, không tồn tại độc lập ngoài Order.
/// internal static Create() — chỉ Order aggregate mới tạo được.
/// </summary>
public sealed class OrderItem : Entity
{
    public Guid ProductId { get; private set; }
    public string ProductName { get; private set; } = string.Empty;
    public int Quantity { get; private set; }
    public Money UnitPrice { get; private set; } = null!;
    public Money Subtotal => UnitPrice.Multiply(Quantity);

    private OrderItem() { } // EF Core

    internal static OrderItem Create(Guid productId, string productName,
                                     int quantity, Money unitPrice)
    {
        if (productId == Guid.Empty)
            throw new ArgumentException("ProductId cannot be empty.");
        if (quantity <= 0)
            throw new ArgumentOutOfRangeException(nameof(quantity));

        return new OrderItem
        {
            Id = Guid.NewGuid(),
            ProductId = productId,
            ProductName = productName.Trim(),
            Quantity = quantity,
            UnitPrice = unitPrice
        };
    }

    internal void IncreaseQuantity(int amount) => Quantity += amount;
}
```

#### `Order.cs` (Aggregate Root)

```csharp
namespace Domain.Orders;

public sealed class Order : AggregateRoot
{
    private readonly List<OrderItem> _items = [];

    public OrderNumber Number { get; private set; } = null!;
    public Guid CustomerId { get; private set; }
    public Address ShippingAddress { get; private set; } = null!;
    public OrderStatus Status { get; private set; }
    public DateTime CreatedAt { get; private set; }
    public DateTime? ConfirmedAt { get; private set; }
    public DateTime? CancelledAt { get; private set; }

    public IReadOnlyList<OrderItem> Items => _items.AsReadOnly();
    public Money Total => _items.Aggregate(Money.Zero("VND"), (acc, i) => acc.Add(i.Subtotal));

    private Order() { } // EF Core

    public static Result<Order> Create(Guid customerId, OrderNumber number,
                                       Address shippingAddress, List<OrderItem> items)
    {
        if (items is null || items.Count == 0)
            return Result.Failure<Order>(OrderErrors.EmptyItems);

        var order = new Order
        {
            Id = Guid.NewGuid(),
            CustomerId = customerId,
            Number = number,
            ShippingAddress = shippingAddress,
            Status = OrderStatus.Pending,
            CreatedAt = DateTime.UtcNow
        };
        order._items.AddRange(items);
        order.Raise(new OrderCreatedEvent(order.Id, customerId, number.Value, order.Total));

        return Result.Success(order);
    }

    public Result Confirm()
    {
        if (Status == OrderStatus.Confirmed)
            return Result.Failure(OrderErrors.AlreadyConfirmed);
        if (Status == OrderStatus.Cancelled)
            return Result.Failure(OrderErrors.AlreadyCancelled);

        Status = OrderStatus.Confirmed;
        ConfirmedAt = DateTime.UtcNow;
        Raise(new OrderConfirmedEvent(Id, CustomerId));
        return Result.Success();
    }

    public Result Cancel(string reason)
    {
        if (Status == OrderStatus.Cancelled)
            return Result.Failure(OrderErrors.AlreadyCancelled);
        if (Status == OrderStatus.Confirmed)
            return Result.Failure(OrderErrors.CannotCancelConfirmedOrder);

        Status = OrderStatus.Cancelled;
        CancelledAt = DateTime.UtcNow;
        Raise(new OrderCancelledEvent(Id, CustomerId, reason));
        return Result.Success();
    }
}
```

#### `IOrderRepository.cs`

```csharp
namespace Domain.Orders.Repositories;

public interface IOrderRepository
{
    Task<Order?> GetByIdAsync(Guid id, CancellationToken ct = default);
    Task<Order?> GetByNumberAsync(OrderNumber number, CancellationToken ct = default);
    Task<IReadOnlyList<Order>> GetByCustomerIdAsync(Guid customerId, CancellationToken ct = default);
    Task AddAsync(Order order, CancellationToken ct = default);
    Task UpdateAsync(Order order, CancellationToken ct = default);
    Task<bool> ExistsByNumberAsync(OrderNumber number, CancellationToken ct = default);
}
```

---

### Customers Aggregate

#### `CustomerValueObjects.cs`

```csharp
// Email — validated email address
public sealed record Email
{
    public string Value { get; }
    private static readonly Regex EmailRegex = new(@"^[^@\s]+@[^@\s]+\.[^@\s]+$", RegexOptions.Compiled | RegexOptions.IgnoreCase);

    private Email(string value) => Value = value;

    public static Email Of(string value)
    {
        var trimmed = value.Trim().ToLowerInvariant();
        if (!EmailRegex.IsMatch(trimmed))
            throw new ArgumentException($"'{value}' is not a valid email.");
        return new Email(trimmed);
    }
}

// FullName — first + last name
public sealed record FullName
{
    public string FirstName { get; }
    public string LastName { get; }

    private FullName(string firstName, string lastName) { FirstName = firstName; LastName = lastName; }

    public static FullName Of(string firstName, string lastName) =>
        new(firstName.Trim(), lastName.Trim());

    public string Display => $"{FirstName} {LastName}";
}
```

#### `Customer.cs` (Aggregate Root)

```csharp
public sealed class Customer : AggregateRoot
{
    public FullName Name { get; private set; } = null!;
    public Email Email { get; private set; } = null!;
    public PhoneNumber? Phone { get; private set; }
    public CustomerTier Tier { get; private set; }
    public bool IsActive { get; private set; }

    private Customer() { }

    public static Customer Register(Guid id, FullName name, Email email, PhoneNumber? phone = null)
    {
        var customer = new Customer { Id = id, Name = name, Email = email,
                                      Phone = phone, Tier = CustomerTier.Standard, IsActive = true };
        customer.Raise(new CustomerRegisteredEvent(id, email.Value, name.Display));
        return customer;
    }

    public Result ChangeEmail(Email newEmail)
    {
        if (Email == newEmail)
            return Result.Failure(CustomerErrors.EmailSameAsCurrent(newEmail.Value));

        var oldEmail = Email.Value;
        Email = newEmail;
        Raise(new CustomerEmailChangedEvent(Id, oldEmail, newEmail.Value));
        return Result.Success();
    }

    public Result Deactivate(string reason)
    {
        if (!IsActive)
            return Result.Failure(CustomerErrors.AlreadyDeactivated);

        IsActive = false;
        Raise(new CustomerDeactivatedEvent(Id, reason));
        return Result.Success();
    }
}
```

---

### Shared

#### `Money.cs`

```csharp
namespace Domain.Shared.ValueObjects;

/// <summary>
/// Dùng chung cho Orders và Products.
/// Đặt ở Shared/ vì nhiều Aggregate cần.
/// </summary>
public sealed record Money
{
    public decimal Amount { get; }
    public string Currency { get; }

    private Money(decimal amount, string currency) { Amount = amount; Currency = currency; }

    public static Money Of(decimal amount, string currency)
    {
        if (amount < 0) throw new ArgumentOutOfRangeException(nameof(amount));
        if (currency.Length != 3) throw new ArgumentException("Currency must be ISO 4217.");
        return new Money(amount, currency.ToUpperInvariant());
    }

    public static Money Zero(string currency) => Of(0, currency);

    public Money Add(Money other)      { EnsureSameCurrency(other); return Of(Amount + other.Amount, Currency); }
    public Money Subtract(Money other) { EnsureSameCurrency(other); return Of(Amount - other.Amount, Currency); }
    public Money Multiply(decimal factor) => Of(Amount * factor, Currency);

    private void EnsureSameCurrency(Money other)
    {
        if (Currency != other.Currency)
            throw new InvalidOperationException($"Cannot mix {Currency} and {other.Currency}.");
    }

    public override string ToString() => $"{Amount:F2} {Currency}";
}
```

---

## 7. Thứ tự implement

```
BƯỚC 1 — Zero dependencies
├── Common/Results/Error.cs
├── Common/Abstractions/IDomainEvent.cs
└── Common/Abstractions/IAggregateRoot.cs

BƯỚC 2 — Phụ thuộc bước 1
├── Common/Results/Result.cs
├── Common/Abstractions/DomainEvent.cs
├── Common/Abstractions/Entity.cs
└── Common/Abstractions/ValueObject.cs

BƯỚC 3 — Phụ thuộc bước 2
├── Common/Abstractions/AggregateRoot.cs
├── Common/Guards/GuardClauses.cs
└── Common/Primitives/Enumeration.cs

──────── Common layer hoàn chỉnh ────────

BƯỚC 4 — Shared (dùng bởi nhiều Aggregate)
└── Shared/ValueObjects/Money.cs

BƯỚC 5 — Orders: Enums + ValueObjects
├── Orders/Enums/OrderStatus.cs
├── Orders/ValueObjects/Address.cs
└── Orders/ValueObjects/OrderNumber.cs

BƯỚC 6 — Orders: Errors + Events
├── Orders/Errors/OrderErrors.cs
├── Orders/Events/OrderCreatedEvent.cs
├── Orders/Events/OrderConfirmedEvent.cs
├── Orders/Events/OrderCancelledEvent.cs
└── Orders/Events/OrderItemAddedEvent.cs

BƯỚC 7 — Orders: Entities + Aggregate Root
├── Orders/OrderItem.cs
└── Orders/Order.cs

BƯỚC 8 — Orders: Contract + Rule
├── Orders/Repositories/IOrderRepository.cs
└── Orders/Specifications/ActiveOrderSpecification.cs

──────── Lặp lại pattern cho Customers ────────

BƯỚC 9 — Customers: ValueObjects + Enums
├── Customers/ValueObjects/Email.cs
├── Customers/ValueObjects/FullName.cs
├── Customers/ValueObjects/PhoneNumber.cs
└── Customers/Enums/CustomerTier.cs

BƯỚC 10 — Customers: Errors + Events
├── Customers/Errors/CustomerErrors.cs
├── Customers/Events/CustomerRegisteredEvent.cs
├── Customers/Events/CustomerEmailChangedEvent.cs
└── Customers/Events/CustomerDeactivatedEvent.cs

BƯỚC 11 — Customers: Aggregate Root + Contract
├── Customers/Customer.cs
├── Customers/Repositories/ICustomerRepository.cs
└── Customers/Specifications/ActiveCustomerSpecification.cs

──────── Lặp lại pattern cho Products ────────

BƯỚC 12 — Products: ValueObjects + Enums
├── Products/Enums/ProductStatus.cs
├── Products/ValueObjects/ProductName.cs
└── Products/ValueObjects/Sku.cs

BƯỚC 13 — Products: Errors + Events
├── Products/Errors/ProductErrors.cs
├── Products/Events/ProductCreatedEvent.cs
├── Products/Events/ProductPriceChangedEvent.cs
├── Products/Events/ProductStockDepletedEvent.cs
└── Products/Events/ProductRestockedEvent.cs

BƯỚC 14 — Products: Aggregate Root + Contract
├── Products/Product.cs
└── Products/Repositories/IProductRepository.cs
```

### Tại sao thứ tự này?

| Quy tắc | Lý do |
|---|---|
| Interfaces trước Implementation | Tránh circular dependency |
| Errors trước Aggregate Root | Aggregate dùng `OrderErrors` bên trong methods |
| Events trước Aggregate Root | `Order.Create()` gọi `Raise(new OrderCreatedEvent(...))` |
| ValueObjects trước Entity | Entity dùng VO làm property type |
| Shared trước tất cả Aggregate | `Money` dùng ở cả Orders lẫn Products |
| Child Entity trước Aggregate Root | `Order` chứa `List<OrderItem>` |

---

## 8. Nguyên tắc cốt lõi

| Nguyên tắc | Mô tả |
|---|---|
| **Events trong folder Aggregate** | `Orders/Events/` — không tách ra ngoài |
| **Repositories interface ở Domain** | Domain định nghĩa contract, Infrastructure implement |
| **Domain layer không import gì ngoài BCL** | Không có EF Core, MediatR, Newtonsoft |
| **Mỗi Aggregate là 1 transaction boundary** | Không gọi repo của Aggregate khác trong cùng use case |
| **Shared/ chỉ chứa thứ thực sự dùng chung** | Tránh biến Shared thành thùng rác |
| **`sealed` cho Aggregate Root và VO** | Không cho kế thừa ngoài ý muốn |
| **Result pattern cho business rules** | Throw exception chỉ cho lỗi kỹ thuật |
| **Raise() sau khi state đã thay đổi** | Event phản ánh state mới, không phải intent |
| **`IntegrationEvent` không thuộc Domain** | Đặt ở `Application/Common/Abstractions/` |

---

## 9. Tech Stack 2026

| Mục đích | Thư viện |
|---|---|
| Dispatch internal events | **MediatR** (`INotificationHandler<T>`) |
| Publish ra message broker | **Wolverine** hoặc **MassTransit** |
| Message broker | RabbitMQ, Azure Service Bus, Kafka |
| Auto dispatch sau SaveChanges | **EF Core Interceptors** |
| Outbox processor | **Quartz.NET** hoặc **Hangfire** |
| Validation | **FluentValidation** (Application layer) |

### Event Versioning (distributed systems)

```csharp
public sealed record OrderCreatedEvent(
    Guid OrderId,
    Guid CustomerId,
    decimal TotalAmount,
    DateTime CreatedAt,
    int SchemaVersion = 2  // ← backward compatibility
) : DomainEvent;
```

---

*Tài liệu này tổng hợp từ conversation về DDD Domain Layer Design — March 2026*
