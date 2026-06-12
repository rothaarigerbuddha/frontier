# ---- Build stage ----
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy the whole solution and restore + publish the API project (project
# references are resolved automatically).
COPY . .
RUN dotnet restore FrontierWeb/FrontierWeb.Api.csproj
RUN dotnet publish FrontierWeb/FrontierWeb.Api.csproj \
    -c Release -o /app/publish /p:UseAppHost=false

# ---- Runtime stage ----
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish ./

# Keep a pristine copy of the bundled images so the persistent uploads volume
# can be re-seeded on first run (see docker-entrypoint.sh).
RUN mkdir -p /seed && \
    if [ -d ./wwwroot/images/posts ]; then cp -r ./wwwroot/images/posts /seed/posts; fi

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENV ASPNETCORE_URLS=http://+:8080
ENV ASPNETCORE_ENVIRONMENT=Production
EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
