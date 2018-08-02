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

    .PARAMETER partid
    Smart array component - controller, logical drive or physical drive (takes: ctrl, ld, pd)

    .PARAMETER identity
    Part of target, depends of context:
    For controllers: main controller status, it's battery or cache status (takes: main, batt, cache);
    For logical drives: id of logical drive (takes: 1, 2, 3, 4 etc);
    For physical drives: id of physical drive (takes: 1E:1:1..2E:1:12 etc)

    .PARAMETER ctrlid
    Controller identity. Usual it's controller slot, but may be set to serial number.

    .PARAMETER version
    Print verion number and exit

    .EXAMPLE
    Zbx-HPSmartArray.ps1 -action lld -part ctrl
    {"data":[{"{#CTRL.MODEL}":"Smart Array P800","{#CTRL.SN}":"P98690G9SVA0BE"},"{#CTRL.SLOT}":"0"}]}

    .EXAMPLE
    Zbx-HPSmartArray.ps1 health ld 0 1
    OK

    .EXAMPLE
    Zbx-HPSmartArray.ps1 health pd 0 2E:1:12
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
$VERSION_NUM="0.3.2"
if ($version) {
    Write-Host $VERSION_NUM
    break
}

# HP Array Configuration Utility location
$ssacli = "$env:ProgramFiles\Smart Storage Administrator\ssacli\bin\ssacli.exe"
if (! (Test-Path $ssacli)) {
    $ssacli = "$env:ProgramFiles\Compaq\Hpacucli\Bin\hpacucli.exe"
}

# Determine which controller id is provided
if ($ctrlid -match "^\d{1,}\w?$") {
    $ctrid_type = "slot"
} else {
    $ctrid_type = "sn"
}

# Detect all HP Smart Array Controllers
$all_ctrls = & "$ssacli" "ctrl all show".Split() | Where-Object {$_ -match "\w"}
# Global string to store formed LLD string
$lld_data = ""

# Retrieve one Smart Array Controller info from given string
function Get-CtrlInfo($ctrl) {
        $model = $ctrl -replace "\sin.*$"
        if ($ctrl.Contains("(sn: ")) {
            $sn = $ctrl -replace ".+sn:|\)|\(|\s"
        } else {
            $sn = "UNKNOWN"
        }
        $slot = $ctrl -replace "^.+Slot\s" -replace "\s.+$"
        return $model, $sn, $slot
}

# Makes LLD of HP SmartArray Controllers
function LLD-Controllers() {
    foreach ($ctrl in $all_ctrls) {
        $ctrl_model, $ctrl_sn, $ctrl_slot = Get-CtrlInfo($ctrl)

        $ctrl_info = [string]::Format('{{"{{#CTRL.MODEL}}":"{0}","{{#CTRL.SN}}":"{1}","{{#CTRL.SLOT}}":"{2}"}},',$ctrl_model,$ctrl_sn, $ctrl_slot)
        $ctrl_json += $ctrl_info
    }
    $lld_data = '{"data":[' + $($ctrl_json -replace ',$') + ']}'
    return $lld_data
}

# Makes LLD of HP Logical drives
function LLD-LogicalDrives() {
    foreach ($ctrl in $all_ctrls) {
        $ctrl_model, $ctrl_sn, $ctrl_slot = Get-CtrlInfo($ctrl)
        
        # All found logical drives
        $all_ld = & "$ssacli" "ctrl slot=$($ctrl_slot) ld all show".Split() | Where-Object {$_ -match "logicaldrive \d"}
        foreach ($ld in $all_ld) {
            $ld_num = $ld -replace '.*logicaldrive ' -replace '\s.+$'
            $ld_caption, $ld_raid = $ld -replace '.+logicaldrive.+?\(' -replace '(?<=RAID \d).*$' -split ', '
            $ld_info = [string]::Format('{{"{{#LD.NUM}}":"{0}","{{#LD.RAID}}":"{1}","{{#LD.CAPACITY}}":"{2}","{{#CTRL.SN}}":"{3}","{{#CTRL.SLOT}}":"{4}"}},',$ld_num, $ld_raid, $ld_caption,$ctrl_sn, $ctrl_slot)
            $ld_json += $ld_info
        }
    }
    $lld_data = '{"data":[' + $($ld_json -replace ',$') + ']}'
    return $lld_data
}

# Makes LLD of HP SmartArray Physical drives
function LLD-PhysicalDrives() {
    foreach ($ctrl in $all_ctrls) {
        $ctrl_model, $ctrl_sn, $ctrl_slot = Get-CtrlInfo($ctrl)

        $all_pd = & "$ssacli" "ctrl slot=$($ctrl_slot) pd all show status".Split() | Where-Object {$_ -match "physicaldrive"}
        foreach ($pd in $all_pd) {
                $pd_num = $pd -replace '^.*physicaldrive\s' -replace '\s.+$'
                $pd_info = [string]::Format('{{"{{#PD.NUM}}":"{0}","{{#CTRL.SN}}":"{1}","{{#CTRL.SLOT}}":"{2}"}},',$pd_num, $ctrl_sn, $ctrl_slot)
                $pd_json += $pd_info
        }
    }
    $lld_data = '{"data":[' + $($pd_json -replace ',$') + ']}'
    return $lld_data
}

# Gets HP Array Controller status
function Get-CtrlStatus() {
    Param (
        # Smart Array Controller serial number
        [string]$ctrlid,
        # Smart Array Controller component
        [ValidateSet("main","cache","batt")][string]$ctrl_part
    )

    $ctrl_status = & "$ssacli" "ctrl $($ctrid_type)=$($ctrlid) show status".Split() | Where-Object {$_ -match "controller status|cache status|battery.*status"}
    if ($ctrl_status.Length -eq 3) {
        switch ($ctrl_part) {
            "main" {return ($ctrl_status[0] -replace ".+:\s")}
            "cache" {return ($ctrl_status[1] -replace ".+:\s")}
            "batt" {return ($ctrl_status[2] -replace ".+:\s")}
        }
    } else {
        return ($ctrl_status -replace ".+:\s")
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

    $ld_status = & "$ssacli" "ctrl $($ctrid_type)=$($ctrlid) ld $($ldnum) show status".Split() | Where-Object {$_ -match 'logicaldrive \d'}
    return ($ld_status -replace '.+:\s')
}

# Gets physical drive status
function Get-PDStatus() {
    param(
        # Smart Array Controller id
        [string]$ctrlid,
        # Physical Disk number
        [string]$pdnum
    )
    $pd_status = & "$ssacli" "ctrl $($ctrid_type)=$($ctrlid) pd $($pdnum) show status".Split() | Where-Object {$_ -match 'physicaldrive \d'}
    return ($pd_status -replace '.+\:\s')
}

switch ($action) {
    "lld" {
        switch ($part) {
            "ctrl" {
                Write-Host $(LLD-Controllers)
            }
            "ld" {
                Write-Host $(LLD-LogicalDrives)
            }
            "pd" {
                Write-Host $(LLD-PhysicalDrives)
            }
            default {Write-Host "ERROR: Wrong second argument: use 'ctrl', 'ld' or 'pd'"}
        }
    }
    "health" {
        switch ($part) {
            "ctrl" {
                Write-Host $(Get-CtrlStatus -ctrlid $ctrlid -ctrl_part $partid)
            }
            "ld" {
                Write-Host $(Get-LDStatus -ctrlid $ctrlid -ldnum $partid)
            }
            "pd" {
                Write-Host $(Get-PDStatus -ctrlid $ctrlid -pdnum $partid)
            }
            default {Write-Host "ERROR: Wrong second argument: use 'ctrl', 'ld' or 'pd'"}
        }
    }
    default {Write-Host "ERROR: Wrong first argument: use 'lld' or 'health'"}
}