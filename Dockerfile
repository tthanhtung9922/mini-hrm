FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY MiniHRM.slnx .
COPY Directory.Build.props .
COPY Directory.Packages.props .

#src
COPY src/MiniHRM.Domain/MiniHRM.Domain.csproj src/MiniHRM.Domain/
COPY src/MiniHRM.Application/MiniHRM.Application.csproj src/MiniHRM.Application/
COPY src/MiniHRM.Infrastructure/MiniHRM.Infrastructure.csproj src/MiniHRM.Infrastructure/
COPY src/MiniHRM.API/MiniHRM.API.csproj src/MiniHRM.API/

#tests
COPY tests/MiniHRM.API.Tests/MiniHRM.API.Tests.csproj tests/MiniHRM.API.Tests/
COPY tests/MiniHRM.Application.Tests/MiniHRM.Application.Tests.csproj tests/MiniHRM.Application.Tests/
COPY tests/MiniHRM.Domain.Tests/MiniHRM.Domain.Tests.csproj tests/MiniHRM.Domain.Tests/

RUN dotnet restore

COPY src/ src/
RUN dotnet publish src/MiniHRM.API/MiniHRM.API.csproj -c Release -o /app/publish --no-restore

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .
EXPOSE 8080
ENTRYPOINT ["dotnet", "MiniHRM.API.dll"]