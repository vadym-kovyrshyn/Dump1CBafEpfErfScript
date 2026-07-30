' Hidden enqueue launcher for Explorer context menu.
' Avoids console window flash when multi-select starts one process per file.
Option Explicit

Dim sh, fso, scriptDir, ps1, fileArg, cmd

If WScript.Arguments.Count < 1 Then
  WScript.Quit 1
End If

Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = fso.BuildPath(scriptDir, "Dump-ExternalToFiles.ps1")
fileArg = WScript.Arguments(0)

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """ -Enqueue """ & fileArg & """"

' 0 = hidden window, False = do not wait
sh.Run cmd, 0, False
