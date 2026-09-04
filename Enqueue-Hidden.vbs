' Hidden enqueue launcher for Explorer context menu.
' Avoids console window flash when multi-select starts one process per file.
' Usage:
'   Enqueue-Hidden.vbs "%1"              (unpack, default — keeps old menu command working)
'   Enqueue-Hidden.vbs unpack "%1"
'   Enqueue-Hidden.vbs pack "%1"
Option Explicit

Dim sh, fso, scriptDir, ps1, pathArg, mode, cmd, a0, a1

If WScript.Arguments.Count < 1 Then
  WScript.Quit 1
End If

Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
mode = "unpack"
pathArg = ""

a0 = LCase(Trim(WScript.Arguments(0)))
If a0 = "unpack" Or a0 = "pack" Then
  mode = a0
  If WScript.Arguments.Count < 2 Then
    WScript.Quit 1
  End If
  pathArg = WScript.Arguments(1)
Else
  pathArg = WScript.Arguments(0)
  If WScript.Arguments.Count >= 2 Then
    a1 = LCase(Trim(WScript.Arguments(1)))
    If a1 = "unpack" Or a1 = "pack" Then
      mode = a1
    End If
  End If
End If

pathArg = Replace(pathArg, """", "")

If Len(pathArg) = 0 Then
  WScript.Quit 1
End If

' "%V" from Directory Background often has a trailing backslash;
' a trailing \" pair would break the quoted PowerShell argument.
If Len(pathArg) > 3 Then
  Do While Right(pathArg, 1) = "\"
    pathArg = Left(pathArg, Len(pathArg) - 1)
    If Len(pathArg) <= 3 Then Exit Do
  Loop
End If

If mode = "pack" Then
  ps1 = fso.BuildPath(scriptDir, "Pack-ExternalFromFiles.ps1")
Else
  ps1 = fso.BuildPath(scriptDir, "Dump-ExternalToFiles.ps1")
End If

If Not fso.FileExists(ps1) Then
  WScript.Quit 1
End If

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """ -Enqueue """ & pathArg & """"

' 0 = hidden window, False = do not wait
sh.Run cmd, 0, False
