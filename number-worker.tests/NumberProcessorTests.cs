using NumberWorker;

namespace NumberWorker.Tests;

[TestClass]
public sealed class NumberProcessorTests
{
    [TestMethod]
    public void ProcessAddsWeightWritesOutputAndDeletesInput()
    {
        using TestDirectory directory = TestDirectory.Create();
        File.WriteAllText(directory.InputFile, "7");
        File.WriteAllText(directory.WeightFile, "5.25");

        var summary = new NumberProcessor(directory.Options).Process();

        Assert.AreEqual(1, summary.ProcessedCount);
        Assert.AreEqual(0, summary.SkippedCount);
        Assert.IsFalse(File.Exists(directory.InputFile));
        Assert.HasCount(1, Directory.GetFiles(directory.OutputDirectory));
        string result = File.ReadAllText(Directory.GetFiles(directory.OutputDirectory).Single()).Trim();
        Assert.AreEqual("12.25", result);
    }

    [TestMethod]
    public void InvalidInputIsSkippedAndNotDeleted()
    {
        using TestDirectory directory = TestDirectory.Create();
        File.WriteAllText(directory.InputFile, "not-a-number");
        File.WriteAllText(directory.WeightFile, "5");

        var summary = new NumberProcessor(directory.Options).Process();

        Assert.AreEqual(0, summary.ProcessedCount);
        Assert.AreEqual(1, summary.SkippedCount);
        Assert.IsTrue(File.Exists(directory.InputFile));
        Assert.IsEmpty(Directory.GetFiles(directory.OutputDirectory));
    }

    [TestMethod]
    public void MissingWeightDirectoryThrowsBeforeProcessing()
    {
        using TestDirectory directory = TestDirectory.Create();
        Directory.Delete(directory.WeightsDirectory, recursive: true);
        File.WriteAllText(directory.InputFile, "7");

        Assert.ThrowsExactly<DirectoryNotFoundException>(() => new NumberProcessor(directory.Options).Process());
    }

    private sealed class TestDirectory : IDisposable
    {
        private TestDirectory(string rootDirectory)
        {
            RootDirectory = rootDirectory;
            InputDirectory = Path.Combine(rootDirectory, "Input");
            WeightsDirectory = Path.Combine(rootDirectory, "Weights");
            OutputDirectory = Path.Combine(rootDirectory, "Output");
            Directory.CreateDirectory(InputDirectory);
            Directory.CreateDirectory(WeightsDirectory);
            Directory.CreateDirectory(OutputDirectory);

            InputFile = Path.Combine(InputDirectory, "input.txt");
            WeightFile = Path.Combine(WeightsDirectory, "weight.txt");
            Options = new WorkerOptions
            {
                InputDirectory = InputDirectory,
                WeightsDirectory = WeightsDirectory,
                OutputDirectory = OutputDirectory,
                WeightFileName = "weight.txt"
            };
        }

        public string RootDirectory { get; }
        public string InputDirectory { get; }
        public string WeightsDirectory { get; }
        public string OutputDirectory { get; }
        public string InputFile { get; }
        public string WeightFile { get; }
        public WorkerOptions Options { get; }

        public static TestDirectory Create()
        {
            string root = Path.Combine(Path.GetTempPath(), "NumberWorker.Tests", Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            return new TestDirectory(root);
        }

        public void Dispose()
        {
            if (Directory.Exists(RootDirectory))
            {
                Directory.Delete(RootDirectory, recursive: true);
            }
        }
    }
}
