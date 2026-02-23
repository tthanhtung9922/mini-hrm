using MiniHRM.Domain.Common;
using MiniHRM.Domain.Enums;

namespace MiniHRM.Domain.Entities
{
    public class Position : BaseEntity
    {
        public string Code { get; set; } = null!;
        public string Title { get; set; } = null!;
        public PositionLevel Level { get; set; }

        // Navigation properties
        public virtual ICollection<Employee> Employees { get; set; } = new List<Employee>();
    }
}
