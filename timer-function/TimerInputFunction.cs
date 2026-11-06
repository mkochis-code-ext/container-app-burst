using System.Text.Json.Nodes;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

public sealed class TimerInputFunction
{
    private static readonly HashSet<string> ActiveStatuses = new(
        ["Running", "Processing", "Pending", "Starting"],
        StringComparer.OrdinalIgnoreCase);

    private readonly ILogger<TimerInputFunction> _logger;

    public TimerInputFunction(ILogger<TimerInputFunction> logger)
    {
        _logger = logger;
    }

    [Function("CheckForInputFiles")]
    public async Task Run(
        [TimerTrigger("0 * * * * *")] TimerInfo timerInfo,
        CancellationToken cancellationToken)
    {
        IReadOnlyDictionary<string, string> jobResourceIds = GetJobResourceIds();
        if (jobResourceIds.Count == 0)
        {
            _logger.LogInformation(
                "No Container Apps Jobs are configured in 'ACA_JOB_RESOURCE_IDS' yet (bootstrap phase); skipping.");
            return;
        }

        foreach (KeyValuePair<string, string> job in jobResourceIds)
        {
            await ProcessJobAsync(job.Key, job.Value, cancellationToken);
        }
    }

    private async Task ProcessJobAsync(
        string jobName,
        string jobResourceId,
        CancellationToken cancellationToken)
    {
        using var jobClient = new ArmJobClient(jobResourceId);
        IReadOnlyList<JobExecution> executions =
            await jobClient.GetExecutionsAsync(cancellationToken);

        bool hasActiveExecution = false;
        foreach (JobExecution execution in executions)
        {
            if (!ActiveStatuses.Contains(execution.Status))
            {
                continue;
            }

            hasActiveExecution = true;
            int timeoutMinutes = GetExecutionTimeoutMinutes();
            if (execution.StartTime.HasValue &&
                DateTimeOffset.UtcNow - execution.StartTime.Value.ToUniversalTime() >
                TimeSpan.FromMinutes(timeoutMinutes))
            {
                _logger.LogWarning(
                    "Stopping timed-out Container Apps Job execution {ExecutionName} for {JobName}; status={Status}; started={StartTime}",
                    execution.Name,
                    jobName,
                    execution.Status,
                    execution.StartTime);
                await jobClient.StopAsync(execution.Name, cancellationToken);
            }
            else
            {
                _logger.LogInformation(
                    "Container Apps Job execution {ExecutionName} for {JobName} is still active with status {Status}.",
                    execution.Name,
                    jobName,
                    execution.Status);
            }
        }

        if (hasActiveExecution)
        {
            return;
        }

        var inputScanner = new AzureFileInputScanner($"{jobName}/Input");
        if (!await inputScanner.HasInputFilesAsync(cancellationToken))
        {
            _logger.LogInformation(
                "No input files found for {JobName}; its Container Apps Job remains scaled to zero.",
                jobName);
            return;
        }

        await jobClient.StartAsync(cancellationToken);
        _logger.LogInformation(
            "Started Container Apps Job {JobName} because {JobName}/Input contains new files.",
            jobName,
            jobName);
    }

    private static IReadOnlyDictionary<string, string> GetJobResourceIds()
    {
        string jobsJson = Environment.GetEnvironmentVariable("ACA_JOB_RESOURCE_IDS")
            ?? throw new InvalidOperationException("Required setting 'ACA_JOB_RESOURCE_IDS' is not configured.");

        JsonNode? jobsNode = JsonNode.Parse(jobsJson);
        JsonObject jobsObject = jobsNode?.AsObject()
            ?? throw new InvalidOperationException("Setting 'ACA_JOB_RESOURCE_IDS' must contain a JSON object.");

        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (KeyValuePair<string, JsonNode?> job in jobsObject)
        {
            string? resourceId = job.Value?.GetValue<string>();
            if (!string.IsNullOrWhiteSpace(resourceId))
            {
                result.Add(job.Key, resourceId);
            }
        }

        return result;
    }

    private static int GetExecutionTimeoutMinutes()
    {
        string value = Environment.GetEnvironmentVariable("ACA_JOB_MAX_EXECUTION_MINUTES") ?? "30";
        return int.TryParse(value, out int parsed) && parsed > 0 ? parsed : 30;
    }
}
