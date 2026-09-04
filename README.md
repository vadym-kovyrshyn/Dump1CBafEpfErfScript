# DumpEpfErf

A small Windows helper that unpacks 1C/BAF external data processors (`.epf`) and reports (`.erf`) into plain files next to the original, and packs them back:

`MyProcessor.epf` → `MyProcessor.epf__UnPacked\` → `MyProcessor_Packed.epf` (default)

You need an installed 1C or BAF platform with `1cv8.exe` on the machine.

## Install

Run `Install-ContextMenu.cmd`.  
It adds Explorer right-click items. No admin rights required.

- **1C Unpack To Files** on `.epf` / `.erf` files
- **1C Pack To File** on folders whose name contains `__UnPacked` (also from empty space inside a folder)

On Windows 11 the items may be under **Show more options**.

## Usage

Unpack:

1. Select one or more `.epf` / `.erf` files.
2. Right-click → **1C Unpack To Files**.
3. Pick the platform version when asked (press Esc to cancel).

Each file dumps to a sibling folder `<Name.ext>__UnPacked`.

Pack:

1. Select one or more `*__UnPacked` folders, or right-click empty space inside such a folder.
2. Right-click → **1C Pack To File**.
3. Pick the platform version when asked (press Esc to cancel).
4. Choose whether to add `_Packed` to the output name: **Y** / Enter = yes (default), **N** = write `<Name>.epf` / `<Name>.erf`.

Default output is `<Name>_Packed.epf` or `<Name>_Packed.erf` next to the folder. With **N** the original file name is used (that file is overwritten if it exists). If the chosen output file already exists, it is replaced.

You can also run from the command line:

```bat
Dump-ExternalToFiles.cmd "C:\path\MyProcessor.epf"
Pack-ExternalFromFiles.cmd "C:\path\MyProcessor.epf__UnPacked"
```

## Uninstall

Run `Uninstall-ContextMenu.cmd` to remove the context menu entries.
