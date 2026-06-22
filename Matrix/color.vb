Imports System.Math
class Red
     element1=
     [[1][0][0][0],
      [0][1][0][0],
      [0][0][1][0],
      [0][0][0][1]]

     element2=
     [[0][1][0][0],
      [0][0][1][0],
      [0][0][0][1],
      [1][0][0][0]]

     element3=
     [[0][0][0][1],
      [1][0][0][0],
      [0][1][0][0],
      [0][0][1][0]]

     element4 =
     [[0][0][1][0],
      [0][0][0][1],
      [1][0][0][0],
      [0][1][0][0]]
End Class
console.WriteLine(element1,element2,element3,element4)
class Blue
     element9 =
    [[0][1][0][1],
     [1][0][1][0],
     [0][0][0][1],
     [0][0][0][0]]

     element10 =
    [[0][1][0][1],
     [0][0][1][0],
     [0][1][0][1],
     [0][0][0][0]]

     element11 =
    [[0][1][0][1],
     [0][0][1][0],
     [0][0][0][1],
     [0][0][1][0]]
 
     element12 =
    [[0][1][0][1],
     [0][0][1][0],
     [0][0][0][1],
     [1][0][0][0]]
End class
console.WriteLine(element9,element10,element11,element12)
Class Green
    element5 =
    [[1][0][1][0],
     [0][1][0][0],
     [0][0][1][0],
     [0][0][0][1]]

    element6 =
    [[1][0][0][0],
     [0][1][0][1],
     [0][0][1][0],
     [0][0][0][1]]

    element7 =
    [[1][0][0][0],
     [0][1][0][0],
     [0][0][1][0],
     [0][1][0][1]]
     
    element8 =
    [[1][0][0][0],
     [0][1][0][0],
     [1][0][1][0],
     [0][0][0][1]]
End Class
Console.WriteLine(element5,element6,element7,element8)
class white
    element13 =
    [[1][0][1][0],
     [0][0][0][1],
     [1][0][0][0],
     [0][1][0][0]]

    element14 =
    [[0][0][1][0],
     [0][1][0][1],
     [1][0][0][0],
     [0][1][0][0]]

    element15 =
    [[0][0][1][0],
     [0][0][0][1],
     [1][0][1][0],
     [0][1][0][0]]

    element16 =
    [[0][0][1][0],
     [0][0][0][1],
     [1][0][0][0],
     [0][1][0][1]]

    element17 =
    [[0][1][0][0],
     [1][0][0][0],
     [0][1][0][0],
     [1][0][1][0]]

    element18 =
    [[0][0][0][0],
     [1][0][1][0],
     [0][1][0][0],
     [1][0][1][0]]

    element19 =
    [[0][0][0][0],
     [1][0][0][0],
     [0][1][0][1],
     [0][0][1][0]]

    element20 =
    [[0][0][0][1],
     [1][0][0][0],
     [0][1][0][0],
     [1][0][1][0]]
End Class
console.WriteLine(element13,element14,element15,element16,element17,element18,element19,element20)
Imports System
Imports System.Collections.Generic

Module Red
Public Interface IC1H4
    ReadOnly Property CarbonCount As Integer
    ReadOnly Property HydrogenCount As Integer
End Interface

Class C1H4
    Implements IC1H4

    Public ReadOnly Property CarbonCount As Integer Implements IC1H4.CarbonCount
            Return 1
    End Property

    Public ReadOnly Property HydrogenCount As Integer Implements IC1H4.HydrogenCount
            Return 4
    End Property
End Class

Class C5H8
    Implements IC1H4
          
    Public ReadOnly Property CarbonCount As Integer Implements IC1H4.CarbonCount
            Return 5
    End Property
    Public ReadOnly Property HydrogenCount As Integer Implements IC1H4.HydrogenCount
            Return 8
    End Property
End Class

Class C13H24
    Implements IC1H4
          
    Public ReadOnly Property CarbonCount As Integer Implements IC1H4.CarbonCount
            Return 13
    End Property
    Public ReadOnly Property HydrogenCount As Integer Implements IC1H4.HydrogenCount
            Return 24
    End Property
End Class
End Module

Module Green
    Function GenerateC2H2() As IEnumerable(Of IC1H4)
        Dim result As New List(Of IC1H4)
        result.Add(New C1H4())
        result.Add(New C5H8())
        result.Add(New C13H24())
        Return result
    End Function

    Sub Main()
        For Each compound As IC1H4 In GenerateC2H2()
            Console.WriteLine($"Carbon: {compound.CarbonCount}, Hydrogen: {compound.HydrogenCount}")
        Next

        Console.ReadLine() ' Keep console window open
    End Sub
End Module
Console.WriteLine(C1H4,C5H8,C13H24)

Module Green
Public Interface IC2H2
    ReadOnly Property CarbonCount As Integer
    ReadOnly Property HydrogenCount As Integer
End Interface

Class C2H2
    Implements IC2H2
    Public ReadOnly Property CarbonCount As Integer Implements IC2H2.CarbonCount
            Return 2
    End Property
    Public ReadOnly Property HydrogenCount As Integer Implements IC2H2.HydrogenCount
            Return 2
    End Property
End Class

Class C4H2
    Implements IC2H2
    Public ReadOnly Property CarbonCount As Integer Implements IC2H2.CarbonCount
            Return 4
    End Property
    Public ReadOnly Property HydrogenCount As Integer Implements IC2H2.HydrogenCount
            Return 2
    End Property
End Class

Class C6H2
    Implements IC2H2
    Public ReadOnly Property CarbonCount As Integer Implements IC2H2.CarbonCount
            Return 6 
    End Property
    Public ReadOnly Property HydrogenCount As Integer Implements IC2H2.HydrogenCount
            Return 2
    End Property
End Class
End Module

Module Blue
    Function GenerateC2H2() As IEnumerable(Of IC2H2)
        Dim result As New List(Of IC2H2)
        result.Add(New C2H2())
        result.Add(New C4H2())
        result.Add(New C6H2())
        Return result
    End Function

    Sub Main()
        For Each compound As IC2H2 In GenerateC2H2()
            Console.WriteLine($"Carbon: {compound.CarbonCount}, Hydrogen: {compound.HydrogenCount}")
        Next

        Console.ReadLine() ' Keep console window open
    End Sub
End Module

Console.WriteLine(C2H2,C4H2,C6H2)

Module white
Public Interface IC2H4
    ReadOnly Property CarbonCount As Integer
    ReadOnly Property HydrogenCount As Integer
End Interface

Class C2H4
    Implements IC2H4
    Public ReadOnly Property CarbonCount As Integer Implements IC2H2.CarbonCount
            Return 2
    End Property
    Public ReadOnly Property HydrogenCount As Integer Implements IC2H2.HydrogenCount
            Return 4
    End Property
End Class

Class C6H8
    Implements IC2H4
    Public ReadOnly Property CarbonCount As Integer Implements IC2H2.CarbonCount
            Return 6
    End Property
    Public ReadOnly Property HydrogenCount As Integer Implements IC2H2.HydrogenCount
            Return 8
    End Property
End Class

Class C6H2
    Implements IC2H4
    Public ReadOnly Property CarbonCount As Integer Implements IC2H2.CarbonCount
            Return 14
    End Property
    Public ReadOnly Property HydrogenCount As Integer Implements IC2H2.HydrogenCount
            Return 12
    End Property
End Class

    Function GenerateC2H2() As IEnumerable(Of IC2H4)
        Dim result As New List(Of IC2H4)
        result.Add(New C2H4())
        result.Add(New C6H8())
        result.Add(New C14H12())
        Return result
    End Function

    Sub Main()
        For Each compound As IC2H4 In GenerateC2H2()
            Console.WriteLine($"Carbon: {compound.CarbonCount}, Hydrogen: {compound.HydrogenCount}")
        Next

        Console.ReadLine() ' Keep console window open
    End Sub
End Module
Console.WriteLine(C2H4,C6H8,C14H12)

Module XYZT
Class SpherePoint
    char X = r * Math.sin(theta) * Math.cos(fai)
    char Y = r * Math.sin(theta) * Math.sin(fai)
    char Z = r * Math.cos(fai)
    char T = r * Math.sin(theta)
    return "X,Y,Z,T"
End Class

Class SphereRadius
    const SphereRadiusx = Math.sin(y) + Math.cos(z) 
    const SphereRadiusy = Math.sin(x) + Math.cos(z) 
    const SphereRadiusz = Math.sin(y) + Math.cos(x)
    return "SphereRadiusx, SphereRadiusy, SphereRadiusz"
End Class
End Module

const impact0 = "element1 + element2 + element3 + element4"
const impact1 = "element5 - element6 - element7 - element8"
const impact2 = "element9 * element10 * element11 * element12"
const impact3 = "element13 / element14 / element15 /  element16"
const impact4 = "element17 % element18 % element19 % element20"

const impact5 = "impact0 * impact1" + "impact2 * impact3"
const impact6 = "impact1 - impact2" + "impact3 - impact4"
const impact7 = "impact2 / impact3" + "impact4 / impact1"
const impact8 = "impact3 % impact4" + "impact1 % impact2"

Console.WriteLine(impact0, impact1, impact2, impact3, impact4, impact5, impact6, impact7, impact8)
