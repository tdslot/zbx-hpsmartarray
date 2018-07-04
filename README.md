# zbx-hpsmartarray
PowerShell script for monitoring HP SmartArray RAID controllers (Zabbix)
  
Zabbix Share page: https://share.zabbix.com/storage-devices/hp/hp-smart-array-controller  
Also you can contact me with Telegram: @asand3r

zbx-hpsmartarray provides possibility to make Low Level Discovery of HP Smart Array components, such as controllers, logical and physical drives. Also you can request health status of each discovered component.
The script wrote with PowerShell and works from version 2.0. To communicate with Smart Array it's using HP Array Configuration Utility which you must install yourself. Also, you can install HP Smart Storage Administrator toolkit, but in my case it works slowly.

**Latest stable version:** 0.3

__Please, read [Requirements and Installation](https://github.com/asand3r/zbx-hpsmartarray/wiki/Requirements-and-Installation) section in Wiki before use. Need to edit zabbix_agentd.conf file.__  

## Dependencies
 - HP Array Configuration Utility or HP Smart Storage Administrator

## Feautres  
**Low Level Discovery:**
 - [x] physical disks 
 - [x] virtual disks
 - [x] controllers

**Component status:**
 - [x] physical disks 
 - [x] virtual disks
 - [x] controllers (main status, cache status and battery status)

## TODO  
- [ ] Discovery of hpacucli.exe location

## Supported arguments  
**-action**  
What we want to do - make LLD or get component health status (takes: lld, health)  
**-part**  
Smart array component - controller, logical drive or physical drive (takes: ctrl, ld, pd)  
**-identity**  
Part of target, depends of context:  
 - controllers: main controller status, it's battery or cache status (takes: main, batt, cache);  
 - logical drives: id of logical drive (takes: 1, 2, 3, 4 etc);  
 - physical drives: id of physical drive (takes: 1E:1:1..2E:1:12 etc)  

**-ctrlsn**  
Controller serial number    
**-version**  
Print script version and exit.  

## Usage
You can find more examples on Wiki page, but I placed some cases here too.  
- LLD of enclosures, controllers, virtual disks and physical disks:
```powershell
PS C:\> .\Zbx-HPSmartArray.ps1 -action lld -part ctrl

{"data":[{"{#VDISKNAME}":"vDisk01"},{"{#VDISKNAME}":"vDisk02"}]}
```
- Request health status of one component. E.g. disk '2E:1:12':
```powershell
PS C:\> .\Zbx-HPSmartArray.ps1 -action health -ctrlsn "P98690G9SVA0BE" -part pd -identity 2E:1:12

Rebuilding
```

## Zabbix templates
In addition I've attached preconfigured Zabbix Template here, so you can use it in your environment. It's using Low Level Discovery functionality.   
Have fun and rate it on [share.zabbix.com](https://share.zabbix.com/storage-devices/hp/hp-smart-array-controller) if you like it. =)

**Tested with**:  
HP SmartArray P800, Smart Array P420i, Smart Array P440ar

**Known Issues**:
- 
