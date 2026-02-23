using MiniHRM.Domain.Common;
using MiniHRM.Domain.Enums;

namespace MiniHRM.Domain.Entities
{
    public class Employee : BaseEntity
    {
        public string EmployeeCode { get; set; } = null!;
        public string FirstName { get; set; } = null!;
        public string LastName { get; set; } = null!;
        public string FullName => $"{LastName} {FirstName}";
        public string Email { get; set; } = null!;
        public string? Phone { get; set; }
        public DateOnly? DateOfBirth { get; set; }
        public Gender Gender { get; set; }
        public string? AvatarUrl { get; set; }

        public int DepartmentId { get; set; }
        public int PositionId { get; set; }

        public DateOnly HireDate { get; set; }
        public DateOnly? TerminationDate { get; set; }
        public EmployeeStatus Status { get; set; } = EmployeeStatus.Active;

        // Navigation properties
        public virtual Department Department { get; set; } = null!;
        public virtual Position Position { get; set; } = null!;
    }
}
