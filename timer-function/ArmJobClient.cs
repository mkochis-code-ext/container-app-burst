using System.Globalization;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json.Nodes;
using Azure.Core;
using Azure.Identity;

public sealed record JobExecution(string Name, string Status, DateTimeOffset? StartTime);

public sealed class ArmJobClient : IDisposable
{
    private readonly HttpClient _httpClient;
    private readonly DefaultAzureCredential _credential;
    private readonly string _jobResourceId;
    private readonly string _apiVersion;

    public ArmJobClient(string jobResourceId)
    {
        _httpClient = new HttpClient();
        _credential = new DefaultAzureCredential();
        if (string.IsNullOrWhiteSpace(jobResourceId))
        {
            throw new ArgumentException("A Container Apps Job resource ID is required.", nameof(jobResourceId));
        }

        _jobResourceId = jobResourceId;
        _apiVersion = Environment.GetEnvironmentVariable("ARM_API_VERSION") ?? "2025-07-01";
    }

    public async Task<IReadOnlyList<JobExecution>> GetExecutionsAsync(CancellationToken cancellationToken)
    {
        Uri uri = BuildUri("executions");
        using HttpRequestMessage request = await CreateRequestAsync(HttpMethod.Get, uri, cancellationToken);
        using HttpResponseMessage response = await _httpClient.SendAsync(request, cancellationToken);
        string body = await response.Content.ReadAsStringAsync(cancellationToken);
        EnsureSuccess(response, body);

        JsonNode? root = JsonNode.Parse(body);
        var results = new List<JobExecution>();
        JsonArray? values = root?["value"]?.AsArray();
        if (values is null)
        {
            return results;
        }

        foreach (JsonNode? execution in values)
        {
            string name = execution?["name"]?.GetValue<string>() ?? string.Empty;
            JsonObject? properties = execution?["properties"]?.AsObject();
            string status = properties?["status"]?.GetValue<string>() ?? "Unknown";
            DateTimeOffset? startTime = null;
            string? startTimeText = properties?["startTime"]?.GetValue<string>();
            if (DateTimeOffset.TryParse(
                    startTimeText,
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.AssumeUniversal,
                    out DateTimeOffset parsedStartTime))
            {
                startTime = parsedStartTime;
            }

            results.Add(new JobExecution(name, status, startTime));
        }

        return results;
    }

    public async Task StartAsync(CancellationToken cancellationToken)
    {
        Uri uri = BuildUri("start");
        using HttpRequestMessage request = await CreateRequestAsync(
            HttpMethod.Post,
            uri,
            cancellationToken,
            new StringContent("{}", Encoding.UTF8, "application/json"));
        using HttpResponseMessage response = await _httpClient.SendAsync(request, cancellationToken);
        string body = await response.Content.ReadAsStringAsync(cancellationToken);
        EnsureSuccess(response, body);
    }

    public async Task StopAsync(string executionName, CancellationToken cancellationToken)
    {
        Uri uri = BuildUri($"executions/{Uri.EscapeDataString(executionName)}/stop");
        using HttpRequestMessage request = await CreateRequestAsync(
            HttpMethod.Post,
            uri,
            cancellationToken,
            new StringContent("{}", Encoding.UTF8, "application/json"));
        using HttpResponseMessage response = await _httpClient.SendAsync(request, cancellationToken);
        string body = await response.Content.ReadAsStringAsync(cancellationToken);
        EnsureSuccess(response, body);
    }

    private Uri BuildUri(string operation)
    {
        return new Uri(
            $"https://management.azure.com{_jobResourceId}/{operation}?api-version={_apiVersion}",
            UriKind.Absolute);
    }

    private async Task<HttpRequestMessage> CreateRequestAsync(
        HttpMethod method,
        Uri uri,
        CancellationToken cancellationToken,
        HttpContent? content = null)
    {
        AccessToken token = await _credential.GetTokenAsync(
            new TokenRequestContext(["https://management.azure.com/.default"]),
            cancellationToken);

        var request = new HttpRequestMessage(method, uri)
        {
            Content = content
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token.Token);
        return request;
    }

    private static void EnsureSuccess(HttpResponseMessage response, string body)
    {
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException(
                $"Azure Resource Manager returned {(int)response.StatusCode} {response.ReasonPhrase}: {body}");
        }
    }

    private static string GetRequiredSetting(string name)
    {
        return Environment.GetEnvironmentVariable(name)
            ?? throw new InvalidOperationException($"Required setting '{name}' is not configured.");
    }

    public void Dispose()
    {
        _httpClient.Dispose();
    }
}
