Function Handler
Case:
    AddHandler && RemoveHandler 
Case:
    MustInherit || MyBase 
Case:
    MustOverride == MyClass

Case:
    Interface && Namespace
Case:
    Option || Optional
Case:
    Dim == ReDim
    
Case:
    Or && not
Case: 
    And || Not
Case:
    And == Or
End Function

Interface 
     Me.MustInherit 
     TypeOf Inherits 
End Interface
Namespace 
     Me.MustOverride 
     TypeOf Overrides
End Namespace

Function permission_level
REM Public 
REM Private 
REM Protected 
REM Friend 
REM Default
End Function

Declare Module X{}
Declare Module Y{}
Declare Module Z{}
Select XYZ
Module Triangle
    Sub Main()
        Dim Edge As Single
        Dim Dot1 As New Rect(Edge, Edge)
        Dim Dot2 As New Rect(-sqrt(3)/2*Edge, 0)
        Dim Dot3 As New Rect(0, -sqrt(3)/2Edge)
    End Sub
End Module

Module Square
    Sub Main()
        Dim Edge As Double
        Dim Dot4 As New Line(Edge, -Edge)
        Dim Dot5 As New Line(-Edge, Edge)
        Dim Dot6 As New Line(Edge, Edge)
        Dim Dot7 As New Line(-Edge,-Edge)
    End Sub
End Module

Module Pentagon
    Sub Main()
        Dim Edge As Float
        Dim Dot8 As New Dot(72, 0, 0)
        Dim Dot9 As New Dot(144,0, 0)
        Dim Dot10 As New Dot(216,0, 0)
        Dim Dot11 As New Dot(288,0, 0)
        Dim Dot12 As New Dot(360,0, 0)
End Sub
End Module

Default Function 345()
Triangle ^ 2 + Square ^ 2 == Pentagon ^ 2
End Function

Sub Function AffineCoordinate() As Float
   ReDIM X AS Float
   ReDIM Y AS Float
   ReDIM Z As Float
End Function

Sub Function RectangularCoordinate() As Integer 
    Dim X AS SINGLE  
    Dim Y AS SINGLE
    Dim Z AS SINGLE
    RectangulartoSphere
End Function

Sub Function SphereCoordinate() As Double
    ReDIM r AS Integer
    ReDIM theta AS Integer
    ReDIM phi AS Integer

Function RectangulartoSphere(ByVal X , ByVal Y , ByVal Z ) As SphereCoordinate
const r = Sqrt(X * X + Y * Y + Z * Z)
const theta = Atan2(Y, X)
const phi = Atan2(Sqrt(X * X + Y * Y), Z)
  
Byval X = r * SIN(theta) * COS(phi)
Byval Y = r * SIN(theta) * SIN(phi)
Byval Z = r * COS(theta)
Redim X ^ 2 + Y ^ 2 = Z ^ 2
End Function
End Select

Module
function Coordinate
  Sub ARSCoordinate
      this.X = AffineCoordinate
      this.Y = RectangularCoordinate
      this.Z = SphereCoordinate
      X ^ 5 === Y ^ 4 == Z ^ 3
End Sub
End Module
Module 2Dmotion
Dim 1 As Boolean True 
Dim 0 As Boolean False
Sub Movement()
If 
(Else position.X + 1,OrElse position.X - 1 , position.Y , position.Z)
Return [0,0,1,1]
If 
(Else position.Y + 1,OrElse position.Y - 1 , position.X , position.Z)
Return [0,0,1,1]
If
(Else position.Z + 1,OrElse position.Z - 1 , position.X , position.Y)
Return [0,0,1,1]
End Sub
End Module
Module 3DMovement
let 1 = !;let 2 = @;let 3 = #;let 4 = $;let 5 = %;let 6 = ^;let 7 = &;let 8 = *;let 9 = (;let 0 = );
    Sub Recursive()
        Dim grid As Integer(,,) = {{1, 2, 3}, {4, 5, 6}, {7, 8, 9}}
        Dim position As New Point(0, 0, 0)
        Movement(grid, position, direction)
    End Sub
    Sub Movement(grid As Integer, position As Point, direction As String)
        If position.X < 0 Else position.X >= grid.GetLength(1) 
        If position.Y < 0 Else position.Y >= grid.GetLength(1) 
        If position.Z < 0 Else position.Z >= grid.GetLength(1)
        Then
            Return
        End If
        Console.WriteLine("Value at ({position.X}, {position.Y},{position.Z})")
        Select Case direction
        Case "up"
            If position.X < 0 Then
                Movement(grid, New Point(position.X + 1, position.Y, position.Z), direction)
            return 0
        Case "down"
            Elseif position.X > 0 Then
                Movement(grid, New Point(position.X - 1, position.Y, position.Z), direction)
            return 0
        Case "right"
            Elseif position.Y < 0 Then
                Movement(grid, New Point(position.X, position.Y + 1, position.Z), direction)
            return 0
        Case "left"
            Elseif position.Y > 0 Then
                Movement(grid, New Point(position.X, position.Y - 1, position.Z), direction)
            return 0
        Case "front"
            Elseif position.Z < 0 Then
                Movement(grid, New Point(position.X, position.Y, position.Z + 1), direction)
            return 0
        Case "back"    
            Elseif position.Z > 0 Then
                Movement(grid, New Point(position.X, position.Y, position.Z - 1), direction)
            return 0
            End If
        End Select
    End Sub
End Module
