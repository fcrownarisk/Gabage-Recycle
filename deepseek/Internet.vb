Imports System.Net
Imports System.Text

Public Class WebSurfer
    Public Shared Function SurfWebsite(url As String) As String
        Try
            ' Create a new WebClient instance
            Using client As New WebClient()
                ' Set the encoding to UTF8
                client.Encoding = Encoding.UTF8
                
                ' Download the content of the web page
                Dim htmlContent As String = client.DownloadString(url)
                
                ' Return the downloaded content
                Return htmlContent
            End Using
        Catch ex As Exception
            ' If an error occurs, return the error message
            Return "Error: " & ex.Message
        End Try
    End Function
End Class

Module Program
    Sub Main()
        ' URL of the website you want to "surf"
        Dim url As String = "https://www.deepseek.com/"
        
        ' Call the SurfWebsite function
        Dim content As String = WebSurfer.SurfWebsite(url)
        
        ' Print the content
        Console.WriteLine(content)
        
        ' Wait for user input before closing
        Console.ReadLine()
    End Sub
    
End Module
