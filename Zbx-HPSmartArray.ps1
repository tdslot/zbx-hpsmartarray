<#
    .SYNOPSIS
    Script for getting data from HP MSA to Zabbix monitoring system.

    .DESCRIPTION
    The script may generate LLD data for HP Smart Array Controllers, Logical Drives and Physical Drives.
    Also it can takes some components health status. It's using HP Array Configuration Utility to
    connect to controller, so you must install it first:
    https://support.hpe.com/hpsc/swd/public/detail?swItemId=MTX_33fe6fcf4fcb4beab8fee4d2dc

    Works with PowerShell 2.0, so I'm not using ConvertTo-JSON available in PowerShell 3.0 and above
    
    .PARAMETER action
    What we want to do - make LLD or get component health status (takes: lld, health)

    .PARAMETER part
    Smart array component - controller, logical drive or physical drive (takes: ctrl, ld, pd)

    .PARAMETER ctrlid
    Controller identity. Usual it's controller slot.
    
    .PARAMETER partid
    Part of target, depends of context:
    For controllers: main controller status, it's battery or cache status (takes: main, batt, cache);
    For logical drives: id of logical drive (takes: 1, 2, 3, 4 etc);
    For physical drives: id of physical drive (takes: 1E:1:1..2E:1:12 etc)

    .PARAMETER version
    Print verion number and exit

    .EXAMPLE
    Zbx-HPSmartArray.ps1 lld ctrl
    {"data":[{"{#CTRL.MODEL}":"Smart Array P800","{#CTRL.SN}":"P98690G9SVA0BE"},"{#CTRL.SLOT}":"0"}]}

    .EXAMPLE
    Get-HPSmartArray.ps1 health ld 0 1
    OK

    .EXAMPLE
    Get-HPSmartArray.ps1 health pd 0 2E:1:12
    Rebuilding

    .NOTES
    Author: Khatsayuk Alexander
    Github: https://github.com/asand3r/
#>

Param (
[switch]$version = $false,
[ValidateSet("lld","health")][Parameter(Position=0, Mandatory=$True)][string]$action,
[ValidateSet("ctrl","ld","pd")][Parameter(Position=1, Mandatory=$True)][string]$part,
[string][Parameter(Position=2)]$ctrlid,
[string][Parameter(Position=3)]$partid
)

# Script version
$VER_NUM="0.3"
if ($version) {
    Write-Host $VER_NUM
    break
}

# HP Array Configuration Utility location
$cli = "C:\Program Files\Smart Storage Administrator\ssacli\bin\ssacli.exe"

# Detect all HP Smart Array Controllers
$allCtrls = & "$cli" "ctrl all show".Split(" ") | Where-Object {$_ -match "^Smart Array"}

# Makes LLD of HP SmartArray Controllers
function LLD-Controllers() {
    $ctrlJsonBody = ""
    foreach ($ctrl in $allCtrls) {
        $lld_ctrlModel = $ctrl -replace "\sin.*$"
        $lld_ctrlSN = $ctrl -replace ".+sn:|\)|\(|\s"
        $lld_ctrlSlot = $ctrl -replace "^.+Slot\s" -replace "\s.+$"
        $ctrlInfo = [string]::Format('{{"{{#CTRL.MODEL}}":"{0}","{{#CTRL.SN}}":"{1}","{{#CTRL.SLOT}}":"{2}"}},',$lld_ctrlModel,$lld_ctrlSN, $lld_ctrlSlot)
        $ctrlJsonBody += $ctrlInfo
    }
    $ctrlJsonFull = '{"data":[' + $($ctrlJsonBody -replace ',$') + ']}'
    Write-Host $ctrlJsonFull
}

# Makes LLD of HP Logical drives
function LLD-LogicalDrives() {
    $ldJsonBody = ""
    foreach ($ctrl in $allCtrls) {
        $lld_ctrlModel = $ctrl -replace "\sin.*"
        $lld_ctrlSN = $ctrl -replace ".+sn:|\)|\(|\s"
        $lld_ctrlSlot = $ctrl -replace "^.+Slot\s" -replace "\s.+$"
        $allLD = & "$cli" "ctrl slot=$($lld_ctrlSlot) ld all show".Split(" ") | Where-Object {$_ -match "logicaldrive \d"}
        foreach ($ld in $allLD) {
            $ldNum = $ld -replace '.*logicaldrive ' -replace '\s.+$'
            $ldCap, $ldRaid = $ld -replace '.+logicaldrive.+?\(' -replace '(?<=RAID \d).*$' -split ', '
            $ldInfo = [string]::Format('{{"{{#LD.NUM}}":"{0}","{{#LD.RAID}}":"{1}","{{#LD.CAPACITY}}":"{2}","{{#CTRL.SN}}":"{3}","{{#CTRL.SLOT}}":"{4}"}},',$ldNum, $ldRaid, $ldCap,$lld_ctrlSN, $lld_ctrlSlot)
            $ldJsonBody += $ldInfo
        }
    }
    $ldJsonFull = '{"data":[' + $($ldJsonBody -replace ',$') + ']}'
    Write-Host $ldJsonFull
}

# Makes LLD of HP SmartArray Physical drives
function LLD-PhysicalDrives() {
    $pdJsonBody = ""
    foreach ($ctrl in $allCtrls) {
        $lld_ctrlModel = $ctrl -replace "\sin.*"
        $lld_ctrlSN = $ctrl -replace ".+sn:|\)|\(|\s"
        $lld_ctrlSlot = $ctrl -replace "^.+Slot\s" -replace "\s.+$"
        $allPD = & "$cli" "ctrl slot=$($lld_ctrlSlot) pd all show status".Split(" ") | Where-Object {$_ -match "physicaldrive"}
        foreach ($pd in $allPD) {
                $pdNum = $pd -replace '^.*physicaldrive\s' -replace '\s.+$'
                $pdInfo = [string]::Format('{{"{{#PD.NUM}}":"{0}","{{#CTRL.SN}}":"{1}","{{#CTRL.SLOT}}":"{2}"}},',$pdNum, $lld_ctrlSN, $lld_ctrlSlot)
                $pdJsonBody += $pdInfo
        }
    }
    $pdJsonFull = '{"data":[' + $($pdJsonBody -replace ',$') + ']}'
    Write-Host $pdJsonFull
}

# Gets HP Array Controller status
function Get-CtrlStatus() {
    Param (
        # Smart Array Controller serial number
        [string]$ctrlid,
        # Smart Array Controller component
        [ValidateSet("main","cache","batt")][string]$ctrl_part
    )

    $ctrlStatus = & "$cli" "ctrl slot=$($ctrlid) show status".Split(" ") | Where-Object {$_ -match 'controller status|cache status|battery.*status'}
    switch ($ctrl_part) {
        "main" {Write-Host ($ctrlStatus[0] -replace ".+:\s")}
        "cache" {Write-Host ($ctrlStatus[1] -replace ".+:\s")}
        "batt" {Write-Host ($ctrlStatus[2] -replace ".+:\s")}
    }
}

# Gets logical drive status
function Get-LDStatus() {
    param(
        # Smart Array Controller id
        [string]$ctrlid,
        # Logical Disk number
        [string]$ldnum
    )

    $ldStatus = & "$cli" "ctrl slot=$($ctrlid) ld $($ldnum) show status".Split(" ") | Where-Object {$_ -match 'logicaldrive \d'}
    Write-Host ($ldStatus -replace '.+:\s')
}

# Gets physical drive status
function Get-PDStatus() {
    param(
        # Smart Array Controller id
        [string]$ctrlid,
        # Physical Disk number
        [string]$pdnum
    )
    $pdStatus = & "$cli" "ctrl slot=$($ctrlid) pd $($pdnum) show status".Split(" ") | Where-Object {$_ -match 'physicaldrive \d'}
    Write-Host ($pdStatus -replace '.+\:\s')
}

switch ($action) {
    "lld" {
        switch ($part) {
            "ctrl" {
                LLD-Controllers
            }
            "ld" {
                LLD-LogicalDrives
            }
            "pd" {
                LLD-PhysicalDrives
            }
            default {Write-Host "ERROR: Wrong second argument: use 'ctrl', 'ld' or 'pd'"}
        }
    }
    "health" {
        switch ($part) {
            "ctrl" {
                Get-CtrlStatus -ctrlid $ctrlid -ctrl_part $partid
            }
            "ld" {
                Get-LDStatus -ctrlid $ctrlid -ldnum $partid
            }
            "pd" {
                Get-PDStatus -ctrlid $ctrlid -pdnum $partid
            }
            default {Write-Host "ERROR: Wrong second argument: use 'ctrl', 'ld' or 'pd'"}
        }
    }
    default {Write-Host "ERROR: Wrong first argument: use 'lld' or 'health'"}
}
