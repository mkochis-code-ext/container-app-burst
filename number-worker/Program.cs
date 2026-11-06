using System.Globalization;

namespace NumberWorker;

public sealed class WorkerOptions
{
    public string InputDirectory { get; init; } = "/mnt/processing/NumberTest1/Input";
    public string WeightsDirectory { get; init; } = "/mnt/processing/NumberTest1/Weights";
    public string OutputDirectory { get; init; } = "/mnt/processing/NumberTest1/Output";
    public string WeightFileName { get; init; } = "weight.txt";

    public static WorkerOptions FromEnvironment()
    {
        return new WorkerOptions
        {
            InputDirectory = Environment.GetEnvironmentVariable("WORKER_INPUT_DIR") ?? "/mnt/processing/NumberTest1/Input",
            WeightsDirectory = Environment.GetEnvironmentVariable("WORKER_WEIGHTS_DIR") ?? "/mnt/processing/NumberTest1/Weights",
            OutputDirectory = Environment.GetEnvironmentVariable("WORKER_OUTPUT_DIR") ?? "/mnt/processing/NumberTest1/Output",
            WeightFileName = Environment.GetEnvironmentVariable("WORKER_WEIGHT_FILE") ?? "weight.txt"
        };
    }
}

public sealed record ProcessingSummary(int ProcessedCount, int SkippedCount, IReadOnlyList<string> OutputFiles);

public sealed class NumberProcessor
{
    private readonly WorkerOptions _options;

    public NumberProcessor(WorkerOptions options)
    {
        _options = options;
    }

    public ProcessingSummary Process()
    {
        if (!Directory.Exists(_options.InputDirectory))
        {
            throw new DirectoryNotFoundException($"Input directory not found: {_options.InputDirectory}");
        }

        if (!Directory.Exists(_options.WeightsDirectory))
        {
            throw new DirectoryNotFoundException($"Weights directory not found: {_options.WeightsDirectory}");
        }

        Directory.CreateDirectory(_options.OutputDirectory);

        decimal weight = ReadWeight();
        string[] inputFiles = Directory.EnumerateFiles(_options.InputDirectory, "*", SearchOption.TopDirectoryOnly)
            .OrderBy(path => path, StringComparer.Ordinal)
            .ToArray();

        var outputFiles = new List<string>();
        int skippedCount = 0;
        var runTimestamp = DateTime.UtcNow;

        for (int index = 0; index < inputFiles.Length; index++)
        {
            string inputFile = inputFiles[index];

            try
            {
                string inputText = File.ReadAllText(inputFile).Trim();
                if (!decimal.TryParse(
                        inputText,
                        NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint | NumberStyles.AllowExponent | NumberStyles.AllowLeadingWhite | NumberStyles.AllowTrailingWhite,
                        CultureInfo.InvariantCulture,
                        out decimal inputNumber))
                {
                    Console.Error.WriteLine($"Skipping '{inputFile}': input is not a number.");
                    skippedCount++;
                    continue;
                }

                decimal sum = inputNumber + weight;
                string outputName =
                    $"sum-{runTimestamp:yyyyMMdd'T'HHmmssfff'Z'}-{index + 1:D4}.txt";
                string outputPath = Path.Combine(_options.OutputDirectory, outputName);
                string temporaryPath = outputPath + ".tmp";

                File.WriteAllText(
                    temporaryPath,
                    sum.ToString(CultureInfo.InvariantCulture),
                    new System.Text.UTF8Encoding(false));
                File.Move(temporaryPath, outputPath);
                File.Delete(inputFile);

                outputFiles.Add(outputPath);
                Console.WriteLine($"Processed '{inputFile}' and wrote '{outputPath}'.");
            }
            catch (IOException exception)
            {
                Console.Error.WriteLine($"Skipping '{inputFile}' because it could not be processed: {exception.Message}");
                skippedCount++;
            }
            catch (UnauthorizedAccessException exception)
            {
                Console.Error.WriteLine($"Skipping '{inputFile}' because it could not be processed: {exception.Message}");
                skippedCount++;
            }
        }

        return new ProcessingSummary(outputFiles.Count, skippedCount, outputFiles);
    }

    private decimal ReadWeight()
    {
        string configuredPath = Path.Combine(_options.WeightsDirectory, _options.WeightFileName);
        string weightPath;

        if (File.Exists(configuredPath))
        {
            weightPath = configuredPath;
        }
        else
        {
            string[] weightFiles = Directory.EnumerateFiles(_options.WeightsDirectory, "*", SearchOption.TopDirectoryOnly)
                .OrderBy(path => path, StringComparer.Ordinal)
                .ToArray();

            if (weightFiles.Length != 1)
            {
                throw new InvalidOperationException(
                    $"Expected one weights file, or {_options.WeightFileName} at {_options.WeightsDirectory}, but found {weightFiles.Length} files.");
            }

            weightPath = weightFiles[0];
        }

        string weightText = File.ReadAllText(weightPath).Trim();
        if (!decimal.TryParse(
                weightText,
                NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint | NumberStyles.AllowExponent | NumberStyles.AllowLeadingWhite | NumberStyles.AllowTrailingWhite,
                CultureInfo.InvariantCulture,
                out decimal weight))
        {
            throw new InvalidDataException($"Weights file '{weightPath}' does not contain a number.");
        }

        return weight;
    }
}

public static class WorkerEntryPoint
{
    public static int Main(string[] args)
    {
        try
        {
            var options = WorkerOptions.FromEnvironment();
            var summary = new NumberProcessor(options).Process();
            Console.WriteLine(
                $"Worker complete. Processed={summary.ProcessedCount}; Skipped={summary.SkippedCount};");
            return summary.ProcessedCount >= 0 ? 0 : 1;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine($"Worker failed: {exception.Message}");
            return 1;
        }
    }
}
