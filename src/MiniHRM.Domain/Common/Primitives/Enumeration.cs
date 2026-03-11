namespace MiniHRM.Domain.Common.Primitives;

/// <summary>
/// Rich enumeration với behavior — dùng thay plain enum
/// khi cần methods, descriptions, hoặc logic phức tạp per value.
/// </summary>
public abstract class Enumeration(int id, string name) : IComparable<Enumeration>
{
    public int Id { get; } = id; public string Name { get; } = name;

    public static IEnumerable<T> GetAll<T>() where T : Enumeration =>
        typeof(T).GetFields(System.Reflection.BindingFlags.Public |
                            System.Reflection.BindingFlags.Static |
                            System.Reflection.BindingFlags.DeclaredOnly)
                 .Select(f => f.GetValue(null)).Cast<T>();

    public int CompareTo(Enumeration? other) => Id.CompareTo(other?.Id);
    public override string ToString() => Name;
}
