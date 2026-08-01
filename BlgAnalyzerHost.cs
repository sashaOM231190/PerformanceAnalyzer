using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;

[assembly: AssemblyTitle("BLG Performance Counter Dashboard")]
[assembly: AssemblyDescription("Interactive Windows Performance Monitor BLG analyzer")]
[assembly: AssemblyProduct("BLG Analyzer")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

internal static class BlgAnalyzerHost
{
    private const string ScriptResourceName = "BlgDashboardScript";

    private static int Main(string[] args)
    {
        if (args.Length == 0 || IsHelp(args[0]))
        {
            PrintUsage();
            return args.Length == 0 ? 1 : 0;
        }

        string blgPath = Path.GetFullPath(args[0]);
        if (!File.Exists(blgPath))
        {
            Console.Error.WriteLine("Error: BLG file not found:");
            Console.Error.WriteLine("  " + blgPath);
            return 2;
        }

        if (!string.Equals(
                Path.GetExtension(blgPath),
                ".blg",
                StringComparison.OrdinalIgnoreCase))
        {
            Console.Error.WriteLine("Error: Input must be a .blg file.");
            return 3;
        }

        int port = 8765;
        bool noBrowser = false;
        for (int index = 1; index < args.Length; index++)
        {
            if (string.Equals(
                    args[index],
                    "--no-browser",
                    StringComparison.OrdinalIgnoreCase))
            {
                noBrowser = true;
                continue;
            }

            if (string.Equals(
                    args[index],
                    "--port",
                    StringComparison.OrdinalIgnoreCase) &&
                index + 1 < args.Length)
            {
                int parsedPort;
                if (!int.TryParse(args[++index], out parsedPort) ||
                    parsedPort < 1024 ||
                    parsedPort > 65535)
                {
                    Console.Error.WriteLine(
                        "Error: Port must be between 1024 and 65535.");
                    return 4;
                }

                port = parsedPort;
                continue;
            }

            Console.Error.WriteLine("Error: Unknown argument: " + args[index]);
            PrintUsage();
            return 5;
        }

        string dashboardScript;
        try
        {
            dashboardScript = ReadEmbeddedScript();
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(
                "Error loading embedded dashboard: " + exception.Message);
            return 6;
        }

        PowerShell shell = null;
        Runspace runspace = null;
        bool cancelled = false;
        ConsoleCancelEventHandler cancelHandler =
            delegate(object sender, ConsoleCancelEventArgs eventArgs)
            {
                eventArgs.Cancel = true;
                cancelled = true;
                if (shell != null)
                {
                    try
                    {
                        shell.Stop();
                    }
                    catch
                    {
                    }
                }
            };

        Console.CancelKeyPress += cancelHandler;
        try
        {
            runspace = RunspaceFactory.CreateRunspace();
            runspace.Open();
            runspace.SessionStateProxy.SetVariable("BlgInputPath", blgPath);
            runspace.SessionStateProxy.SetVariable("DashboardPort", port);
            runspace.SessionStateProxy.SetVariable(
                "DashboardNoBrowser",
                noBrowser);

            shell = PowerShell.Create();
            shell.Runspace = runspace;
            shell.Streams.Error.DataAdded +=
                delegate(object sender, DataAddedEventArgs eventArgs)
                {
                    ErrorRecord record = shell.Streams.Error[eventArgs.Index];
                    Console.Error.WriteLine(record.ToString());
                };
            shell.Streams.Warning.DataAdded +=
                delegate(object sender, DataAddedEventArgs eventArgs)
                {
                    WarningRecord record =
                        shell.Streams.Warning[eventArgs.Index];
                    Console.Error.WriteLine("Warning: " + record.Message);
                };

            string invocation =
                "& {" + Environment.NewLine +
                dashboardScript + Environment.NewLine +
                "} -InputPath $BlgInputPath -Port $DashboardPort " +
                "-NoBrowser:$DashboardNoBrowser";

            shell.AddScript(invocation);
            Collection<PSObject> output = shell.Invoke();
            foreach (PSObject item in output)
            {
                if (item != null)
                {
                    Console.WriteLine(item.ToString());
                }
            }

            if (cancelled)
            {
                return 0;
            }

            return shell.HadErrors ? 7 : 0;
        }
        catch (PipelineStoppedException)
        {
            return cancelled ? 0 : 8;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(
                "Dashboard failed: " + exception.Message);
            return 9;
        }
        finally
        {
            Console.CancelKeyPress -= cancelHandler;
            if (shell != null)
            {
                shell.Dispose();
            }
            if (runspace != null)
            {
                runspace.Dispose();
            }
        }
    }

    private static bool IsHelp(string value)
    {
        return string.Equals(
                   value,
                   "-h",
                   StringComparison.OrdinalIgnoreCase) ||
               string.Equals(
                   value,
                   "--help",
                   StringComparison.OrdinalIgnoreCase) ||
               string.Equals(
                   value,
                   "/?",
                   StringComparison.OrdinalIgnoreCase);
    }

    private static string ReadEmbeddedScript()
    {
        Assembly assembly = Assembly.GetExecutingAssembly();
        using (Stream stream =
               assembly.GetManifestResourceStream(ScriptResourceName))
        {
            if (stream == null)
            {
                throw new InvalidOperationException(
                    "Embedded PowerShell resource was not found.");
            }

            using (StreamReader reader = new StreamReader(stream))
            {
                return reader.ReadToEnd();
            }
        }
    }

    private static void PrintUsage()
    {
        Console.WriteLine("BLG Performance Counter Dashboard");
        Console.WriteLine();
        Console.WriteLine("Usage:");
        Console.WriteLine("  BlgAnalyzer.exe \"E:\\Path\\Capture.blg\"");
        Console.WriteLine();
        Console.WriteLine("Optional:");
        Console.WriteLine(
            "  --port <1024-65535>  Use a different local HTTP port.");
        Console.WriteLine(
            "  --no-browser         Do not open the browser automatically.");
        Console.WriteLine();
        Console.WriteLine(
            "A .blg file can also be dragged onto BlgAnalyzer.exe.");
    }
}
