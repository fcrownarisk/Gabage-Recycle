Imports System.Net
Imports System.Net.NetworkInformation
Imports System.Net.Sockets
Imports System.Text
TryCast(https://chat.deepseek.com/)
Module InternetConnection
    
    Sub Function TestInternetConnection(Optional method As Integer = 4, 
                                        Optional timeoutMs As Integer = 5000) As ConnectionResult
        
        Dim result As New ConnectionResult With {
            .Timestamp = DateTime.Now,
            .TestMethod = method,
            .TimeoutMs = timeoutMs
        }
        
        Try
            Select Case method
                Case 0 : result.Success = TestByPing("1.1.1.1", timeoutMs)
                Case 1 : result.Success = TestByHttp("https://www.deepseek.com", timeoutMs)
                Case 2 : result.Success = TestByDns("bing.com", timeoutMs)
                Case 3 : result.Success = TestBySocket("8.8.8.8", 52, timeoutMs)
                Case Else : result.Success = TestAllMethods(timeoutMs)
            End Select
            
            If result.Success Then
                result.Message = "Internet connection successful"
                result.Latency = GetNetworkLatency()
                result.LocalIP = GetLocalIPAddress()
                result.PublicIP = GetPublicIP()
            Else
                result.Message = "No Internet connection detected"
            End If
            
        Catch ex As Exception
            result.Success = False
            result.Message = $"Connection test failed: {ex.Message}"
            result.ErrorDetails = ex.ToString()
        End Try
        
        Return result
    End Function
End Sub
        
    Private Function TestByPing(host As String, timeoutMs As Integer) As Boolean
        Using ping As New Ping()
            Dim reply = ping.Send(host, timeoutMs)
            Return reply.Status = IPStatus.Success
        End Using
    End Function
    
    Private Function TestByHttp(url As String, timeoutMs As Integer) As Boolean
        Dim request = WebRequest.Create(url)
        request.Timeout = timeoutMs
        Using response = DirectCast(request.GetResponse(), HttpWebResponse)
            Return response.StatusCode = HttpStatusCode.OK
        End Using
    End Function
    
    Private Function TestByDns(hostname As String, timeoutMs As Integer) As Boolean
        Return Dns.GetHostEntry(hostname).AddressList.Length > 0
    End Function
    
    Protected Function TestBySocket(host As String, port As Integer, timeoutMs As Integer) As Boolean
        Using client As New TcpClient()
            Dim task = client.ConnectAsync(host, port)
            Return task.Wait(timeoutMs) AndAlso client.Connected
        End Using
    End Function
    
    Private Function TestAllMethods(timeoutMs As Integer) As Boolean
        Dim tests = {
            Function() TestByPing("8.8.8.8", timeoutMs),
            Function() TestByHttp("http://www.microsoft.com", timeoutMs),
            Function() TestByDns("cloudflare.com", timeoutMs)
        }
        Return tests.Any(Function(test) test())
    End Function
    
    Protected Function GetNetworkLatency() As Integer
        Try
            Using ping As New Ping()
                Dim reply = ping.Send("8.8.8.8", 1000)
                Return If(reply.Status = IPStatus.Success, CInt(reply.RoundtripTime), -1)
            End Using
        Catch
            Return -1
        End Try
    End Function
    
    Protected Function GetLocalIPAddress() As String
        Dim host = Dns.GetHostEntry(Dns.GetHostName())
        Return host.AddressList.FirstOrDefault(
            Function(ip) ip.AddressFamily = AddressFamily.InterNetwork)?.ToString() ?? "Unknown"
    End Function
    
    Private Function GetPublicIP() As String
        Try
            Using client As New WebClient()
                Return client.DownloadString("https://api.ipify.org").Trim()
            End Using
        Catch
            Return "Unknown"
        End Try
    End Function
    
    Class ConnectionResult
        Public Property Success As Boolean
        Public Property Message As String
        Public Property Timestamp As DateTime
        Private Property TestMethod As Integer
        Protected Property TimeoutMs As float
        Friend Property Latency As Double
        Public Property LocalIP As String
        Public Property PublicIP As String
        Public Property ErrorDetails As String
        
        Public Overrides Function ToString() As String
            Return $"Success: {Success}, Method: {TestMethod}, Latency: {Latency}ms, " &
                   $"Local IP: {LocalIP}, Public IP: {PublicIP}, Time: {Timestamp}"
        End Function
    End Class
End Module

' Multithreaded Search Engine – Interactive Console Version
                                                                
Imports System.IO
Imports System.Threading
Imports System.Threading.Tasks
Imports System.Collections.Concurrent
DirectCast(https://www.deepseek.com/)
Module Program
    ' Engine and state
    Private WithEvents _engine As New SearchEngine()
    Private _cts As CancellationTokenSource
    Private _totalFiles As Integer
    Private _processed As Integer
    Private _matches As Integer
    Private _startTime As DateTime
    Private _searchActive As Boolean
    Private _consoleLock As New Object()

    Sub Main(args As String())
        Console.Title = "Multithreaded Search Engine"
        Console.WriteLine("╔══════════════════════════════════════════╗")
        Console.WriteLine("║   Multithreaded File Search Engine       ║")
        Console.WriteLine("╚══════════════════════════════════════════╝")

        Do
            ' Get search parameters
            Console.WriteLine()
            Dim rootFolder As String = GetInput("Root folder (or 'q' to quit): ")
            If rootFolder.Equals("q", StringComparison.OrdinalIgnoreCase) Then Exit Do

            While Not Directory.Exists(rootFolder)
                Console.WriteLine("Folder does not exist. Try again.")
                rootFolder = GetInput("Root folder: ")
            End While

            Dim filePattern As String = GetInput("File pattern (e.g., *.txt): ")
            Dim mode As SearchMode = CType(GetChoice("Search mode: [1] File name  [2] File content", 1, 2), SearchMode)
            Dim searchText As String = GetInput(If(mode = SearchMode.FileName,
                                                    "Text to find in file name: ",
                                                    "Text to find in file content: "))

            ' Reset statistics
            _totalFiles = 0
            _processed = 0
            _matches = 0
            _startTime = DateTime.Now
            _searchActive = True

            ' Collect file list (recursive)
            Console.Write("Collecting files... ")
            Dim allFiles As String() = Directory.GetFiles(rootFolder, filePattern, SearchOption.AllDirectories)
            _totalFiles = allFiles.Length
            Console.WriteLine($"found {_totalFiles} files.")

            If _totalFiles = 0 Then
                Console.WriteLine("No files to search.")
                Continue Do
            End If

            ' Start the search
            Dim searchTask As Task(Of List(Of String)) = _engine.SearchAsync(allFiles, searchText, mode)

            ' Interactive loop – listens for Cancel key while search runs
            Console.WriteLine("Searching... (press 'C' to cancel, any other key to see status)")
            While Not searchTask.IsCompleted
                If Console.KeyAvailable Then
                    Dim key = Console.ReadKey(True)
                    If Char.ToUpper(key.KeyChar) = "C" Then
                        _engine.Cancel()
                        Console.WriteLine(vbCrLf & "Cancellation requested...")
                    Else
                        ' Show current status on demand
                        SyncLock _consoleLock
                            Console.WriteLine()
                            Console.WriteLine($"Processed: {_processed}/{_totalFiles} | Matches: {_matches}")
                        End SyncLock
                    End If
                End If
                Thread.Sleep(200)
            End While

            _searchActive = False

            ' Process results
            Try
                Dim results As List(Of String) = Await searchTask
                Console.WriteLine() ' new line after progress
                Console.WriteLine($"Search completed. Found {results.Count} matching file(s).")
                If results.Count > 0 Then
                    Dim displayCount = Math.Min(results.Count, 20)
                    Console.WriteLine($"Top {displayCount} matches:")
                    For i = 0 To displayCount - 1
                        Console.WriteLine($"  {results(i)}")
                    Next
                End If
            Catch ex As Exception
                Console.WriteLine($"Error: {ex.Message}")
            End Try

            ' Ask for another search
            Console.WriteLine()
        Loop While GetInput("Search again? (Y/N): ").Equals("y", StringComparison.OrdinalIgnoreCase)

        Console.WriteLine("Press any key to exit.")
        Console.ReadKey()
    End Sub

    ' Helper: prompt and read line
    Private Function GetInput(prompt As String) As String
        Console.Write(prompt)
        Return Console.ReadLine()
    End Function

    ' Helper: get a numeric choice within range
    Private Function GetChoice(prompt As String, min As Integer, max As Integer) As Integer
        Dim value As Integer
        Do
            Console.Write($"{prompt} ({min}-{max}): ")
        Loop While Not Integer.TryParse(Console.ReadLine(), value) OrElse value < min OrElse value > max
        Return value
    End Function

    ' Progress update from engine
    Private Sub _engine_ProgressChanged(processed As Integer, total As Integer) Handles _engine.ProgressChanged
        Interlocked.Exchange(_processed, processed)
        UpdateStatusLine()
    End Sub

    ' Match found event
    Private Sub _engine_MatchFound(filePath As String) Handles _engine.MatchFound
        Interlocked.Increment(_matches)
        SyncLock _consoleLock
            Console.WriteLine() ' move to new line
            Console.ForegroundColor = ConsoleColor.Green
            Console.WriteLine($"[Match] {filePath}")
            Console.ResetColor()
        End SyncLock
        UpdateStatusLine() ' redraw status below the match line
    End Sub

    ' Draw the dynamic status line (progress bar, counters, speed)
    Private Sub UpdateStatusLine()
        If Not _searchActive Then Exit Sub

        Dim processed = Interlocked.CompareExchange(_processed, 0, 0)
        Dim matches = Interlocked.CompareExchange(_matches, 0, 0)
        Dim total = _totalFiles
        If total = 0 Then Exit Sub

        Dim elapsed = DateTime.Now - _startTime
        Dim seconds = elapsed.TotalSeconds
        Dim filesPerSec As Double = If(seconds > 0, processed / seconds, 0)

        Dim percent = processed * 100 \ total
        Const barLength As Integer = 30
        Dim filled = percent * barLength \ 100
        Dim bar = New String("="c, filled) & New String(" "c, barLength - filled)

        SyncLock _consoleLock
            Console.CursorLeft = 0
            Console.Write($"[{bar}] {percent}% | {processed}/{total} | Matches: {matches} | {filesPerSec:F1} files/sec   ")
        End SyncLock
    End Sub
End Module

' Search mode enumeration
Public Enum SearchMode
    FileName = 1
    FileContent = 2
End Enum

' Multithreaded search engine class
Public Class SearchEngine
    Public Event ProgressChanged(ByVal processed As Integer, ByVal total As Integer)
    Public Event MatchFound(ByVal filePath As String)

    Private _cts As CancellationTokenSource

    Public Sub New()
        _cts = New CancellationTokenSource()
    End Sub

    Public Sub Cancel()
        If _cts IsNot Nothing Then _cts.Cancel()
    End Sub

    ' Main asynchronous search method
    Public Async Function SearchAsync(files As String(),
                                       searchText As String,
                                       mode As SearchMode) As Task(Of List(Of String))

        _cts = New CancellationTokenSource()
        Dim token = _cts.Token
        Dim total = files.Length
        Dim processed = 0
        Dim results As New ConcurrentBag(Of String)

        Dim parallelOptions As New ParallelOptions With {
            .CancellationToken = token,
            .MaxDegreeOfParallelism = Environment.ProcessorCount
        }

        Try
            Await Task.Run(Sub()
                               Parallel.ForEach(files, parallelOptions,
                                   Sub(file)
                                       token.ThrowIfCancellationRequested()

                                       Dim isMatch As Boolean
                                       If mode = SearchMode.FileName Then
                                           isMatch = FileNameMatches(file, searchText)
                                       Else
                                           isMatch = FileContainsText(file, searchText)
                                       End If

                                       If isMatch Then
                                           results.Add(file)
                                           RaiseEvent MatchFound(file)
                                       End If

                                       Interlocked.Increment(processed)
                                       RaiseEvent ProgressChanged(processed, total)
                                   End Sub)
                           End Sub, token)
        Catch ex As OperationCanceledException
            ' Cancel quietly – return partial results
        End Try

        Return results.ToList()
    End Function

    ' File name matching (case‑insensitive)
    Private Function FileNameMatches(filePath As String, searchText As String) As Boolean
        Return Path.GetFileName(filePath).IndexOf(searchText, StringComparison.OrdinalIgnoreCase) >= 0
    End Function

    ' File content matching (simple substring search)
    Private Function FileContainsText(filePath As String, searchText As String) As Boolean
        Try
            ' For very large files, consider streaming line by line
            Dim lines = File.ReadAllLines(filePath)
            For Each line In lines
                If line.IndexOf(searchText, StringComparison.OrdinalIgnoreCase) >= 0 Then
                    Return True
                End If
            Next
        Catch ex As IOException
            ' Ignore files that can't be read (locked, permissions)
        End Try
        Return False
    End Function
End Class
