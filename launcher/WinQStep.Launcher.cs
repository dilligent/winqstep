using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows.Forms;

namespace WinQStep.Launcher
{
    internal static class Program
    {
        private const string ScriptName = "WinQStep.ps1";

        [STAThread]
        private static int Main(string[] args)
        {
            try
            {
                string baseDirectory = AppDomain.CurrentDomain.BaseDirectory;
                string scriptPath = Path.Combine(baseDirectory, ScriptName);
                if (!File.Exists(scriptPath))
                {
                    ShowError("WinQStep could not start because WinQStep.ps1 was not found next to WinQStep.exe.");
                    return 2;
                }

                string powershellPath = ResolveWindowsPowerShell();
                if (powershellPath == null)
                {
                    ShowError("WinQStep could not start because Windows PowerShell 5.1 was not found.");
                    return 3;
                }

                List<string> arguments = new List<string>
                {
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    scriptPath
                };
                arguments.AddRange(args);

                ProcessStartInfo startInfo = new ProcessStartInfo
                {
                    FileName = powershellPath,
                    Arguments = JoinArguments(arguments),
                    WorkingDirectory = baseDirectory,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    WindowStyle = ProcessWindowStyle.Hidden
                };

                Process.Start(startInfo);
                return 0;
            }
            catch (Exception exc)
            {
                ShowError("WinQStep could not start.\r\n\r\n" + exc.Message);
                return 1;
            }
        }

        private static string ResolveWindowsPowerShell()
        {
            string windowsDirectory = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            if (!string.IsNullOrWhiteSpace(windowsDirectory))
            {
                string systemPowerShell = Path.Combine(
                    windowsDirectory,
                    "System32",
                    "WindowsPowerShell",
                    "v1.0",
                    "powershell.exe");
                if (File.Exists(systemPowerShell))
                {
                    return systemPowerShell;
                }
            }

            return FindOnPath("powershell.exe");
        }

        private static string FindOnPath(string fileName)
        {
            string pathValue = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
            foreach (string directory in pathValue.Split(Path.PathSeparator))
            {
                if (string.IsNullOrWhiteSpace(directory))
                {
                    continue;
                }

                try
                {
                    string candidate = Path.Combine(directory.Trim(), fileName);
                    if (File.Exists(candidate))
                    {
                        return candidate;
                    }
                }
                catch (ArgumentException)
                {
                }
                catch (NotSupportedException)
                {
                }
            }

            return null;
        }

        private static string JoinArguments(IEnumerable<string> arguments)
        {
            StringBuilder builder = new StringBuilder();
            foreach (string argument in arguments)
            {
                if (builder.Length > 0)
                {
                    builder.Append(' ');
                }

                builder.Append(QuoteArgument(argument));
            }

            return builder.ToString();
        }

        private static string QuoteArgument(string argument)
        {
            argument = argument ?? string.Empty;
            if (argument.Length == 0)
            {
                return "\"\"";
            }

            bool needsQuotes = false;
            foreach (char character in argument)
            {
                if (char.IsWhiteSpace(character) || character == '"')
                {
                    needsQuotes = true;
                    break;
                }
            }

            if (!needsQuotes)
            {
                return argument;
            }

            StringBuilder result = new StringBuilder();
            result.Append('"');
            int backslashes = 0;
            foreach (char character in argument)
            {
                if (character == '\\')
                {
                    backslashes++;
                    continue;
                }

                if (character == '"')
                {
                    result.Append('\\', backslashes * 2 + 1);
                    result.Append('"');
                    backslashes = 0;
                    continue;
                }

                if (backslashes > 0)
                {
                    result.Append('\\', backslashes);
                    backslashes = 0;
                }

                result.Append(character);
            }

            if (backslashes > 0)
            {
                result.Append('\\', backslashes * 2);
            }

            result.Append('"');
            return result.ToString();
        }

        private static void ShowError(string message)
        {
            MessageBox.Show(message, "WinQStep", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
