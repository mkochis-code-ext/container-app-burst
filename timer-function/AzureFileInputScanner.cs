using Azure.Storage;
using Azure.Storage.Files.Shares;
using Azure.Storage.Files.Shares.Models;

public sealed class AzureFileInputScanner
{
    private readonly ShareDirectoryClient _inputDirectory;

    public AzureFileInputScanner()
        : this("Input")
    {
    }

    public AzureFileInputScanner(string relativeInputDirectory)
    {
        string accountName = GetRequiredSetting("STORAGE_ACCOUNT_NAME");
        string accountKey = GetRequiredSetting("STORAGE_ACCOUNT_KEY");
        string shareName = GetRequiredSetting("STORAGE_FILE_SHARE_NAME");
        string normalizedDirectory = relativeInputDirectory.Trim('/').Replace('\\', '/');

        var credential = new StorageSharedKeyCredential(accountName, accountKey);
        var inputDirectoryUri = new Uri(
            $"https://{accountName}.file.core.windows.net/{shareName}/{normalizedDirectory}");
        _inputDirectory = new ShareDirectoryClient(inputDirectoryUri, credential);
    }

    public async Task<bool> HasInputFilesAsync(CancellationToken cancellationToken)
    {
        await foreach (ShareFileItem item in _inputDirectory.GetFilesAndDirectoriesAsync(
                           cancellationToken: cancellationToken))
        {
            if (!item.IsDirectory)
            {
                return true;
            }
        }

        return false;
    }

    private static string GetRequiredSetting(string name)
    {
        return Environment.GetEnvironmentVariable(name)
            ?? throw new InvalidOperationException($"Required setting '{name}' is not configured.");
    }
}
