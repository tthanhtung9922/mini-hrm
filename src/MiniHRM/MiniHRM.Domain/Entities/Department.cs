using MiniHRM.Domain.Common;

namespace MiniHRM.Domain.Entities
{
    public class Department : BaseEntity
    {
        public string Code { get; set; } = null!;
        public string Name { get; set; } = null!;
        public int? ManagerId { get; set; }

        // Navigation properties
        public virtual Employee? Manager { get; set; }
        public virtual ICollection<Employee> Employees { get; set; } = new List<Employee>();
    }
}
