# DumpEpfErf

A small Windows helper that unpacks 1C/BAF external data processors (`.epf`) and reports (`.erf`) into plain files next to the original:

`MyProcessor.epf` → `MyProcessor.epf__UnPacked\`

You need an installed 1C or BAF platform with `1cv8.exe` on the machine.

## Install

Run `Install-ContextMenu.cmd`.  
It adds a right-click menu item in Explorer. No admin rights required.

## Usage

1. Select one or more `.epf` / `.erf` files.
2. Right-click → **1C Unpack To Files**.
3. Pick the platform version when asked (press Esc to cancel).

You can also unpack from the command line:

```bat
Dump-ExternalToFiles.cmd "C:\path\MyProcessor.epf"
```

## Uninstall

Run `Uninstall-ContextMenu.cmd` to remove the context menu entry.
