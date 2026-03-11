using System.Diagnostics.CodeAnalysis;

namespace MiniHRM.Domain.Common.Results;

public class Result
{
    public bool IsSuccess { get; }
    public bool IsFailure => !IsSuccess;
    public Error Error { get; }

    protected Result(bool isSuccess, Error error)
    {
        IsSuccess = isSuccess;
        Error = error;
    }

    public static Result Success() => new(true, Error.None);
    public static Result<TValue> Success<TValue>(TValue value) => new(value, true, Error.None);
    public static Result Failure(Error error) => new(false, error);
    public static Result<TValue> Failure<TValue>(Error error) => new(default, false, error);
}

public sealed class Result<TValue> : Result
{
    internal Result(TValue? value, bool isSuccess, Error error)
        : base(isSuccess, error) => Value = value;

    [AllowNull]
    public TValue Value => IsSuccess
        ? field!
        : throw new InvalidOperationException("Cannot access Value of a failed result.");

    public static implicit operator Result<TValue>(TValue value) => Success(value);
}
