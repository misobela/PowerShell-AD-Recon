function Discover-MSSQLServers.ps1
{

<#
.SYNOPSIS
This script is used to discover Microsoft SQL servers without port scanning.
SQL discovery in the Active Directory Forest is performed by querying an Active Directory Gloabl Catalog via LDAP.
The script can also provide additional computer information such as OS and last bootup time.

PowerSploit Function: Discover-MSSQLServers.ps1
Author: Sean Metcalf, Twitter: @PyroTek3
License: BSD 3-Clause
Required Dependencies: None
Optional Dependencies: None

Version: 1.1

.DESCRIPTION
This script is used to discover Microsoft SQL servers in the Active Directory Forest.
The script can also provide additional computer information such as OS and last bootup time.

Currently, the script performs the following actions:
    * Queries a Global Catalog in the Active Directory root domain for all Microsoft SQL SPNs in the forest
    * Displays the Microsoft SQL server FQDNs ports and instances
    * Also displays additional computer information if ExtendedInfo is enabled.

REQUIRES: Active Directory user authentication. Standard user access is fine - admin access is not necessary.

.PARAMETER ExtendedInfo
Switch: Displays additional information including Operating System, Last Bootup Time (derived from LastLogonTimeStamp), OS Version, and Description.
Operating system properties are populated at first bot-up after joining the domain. 

.PARAMETER GroupResults
String: Groups results by provided parameter data. Default is no grouping. 
Options available by default: "Domain","ServerName","Port","Instance"
The ExtendedInfo parameter adds the following: "OperatingSystem","OSServicePack","LastBootup","OSVersion","Description"

.PARAMETER SortResults
String: Sorts results by provided parameter data. Default is "ServerName".
Options available by default: "Domain","ServerName","Port","Instance"
The ExtendedInfo parameter adds the following: "OperatingSystem","OSServicePack","LastBootup","OSVersion","Description"

.EXAMPLE
Discover-MSSQLServers
Perform Microsoft SQL Server discovery via AD and displays the results in a table.

Discover-MSSQLServers -ExtendedInfo
Perform Microsoft SQL Server discovery via AD (includes additional computer information) and displays the results in a table.

Discover-MSSQLServers -GroupResults "Domain"
Perform Microsoft SQL Server discovery via AD and displays the results in a table grouped by Domain.

Discover-MSSQLServers -SortResults "Port"
Perform Microsoft SQL Server discovery via AD and displays the results in a table sorted by Port.

.NOTES
This script is used to discover Microsoft SQL servers in the Active Directory Forest and can also provide additional computer information such as OS and last bootup time.

.LINK

#>
Param
    (
        [Parameter(Position=0)]
        [switch] $ExtendedInfo = $True,

        [Parameter(Position=1)]
        [ValidateSet("Domain","ServerName","Port","Instance","OperatingSystem","OSServicePack","LastBootup","OSVersion","Description")]
        [string] $GroupResults,

        [Parameter(Position=2)]
        [ValidateSet("Domain","ServerName","Port","Instance","OperatingSystem","OSServicePack","LastBootup","OSVersion","Description")]
        [string] $SortResults = "ServerName"
    )

Write-Verbose "Get current Active Directory domain... "
$ADForestInfo = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
$ADForestInfoRootDomain = $ADForestInfo.RootDomain
$ADForestInfoRootDomainArray = $ADForestInfoRootDomain -Split("\.")
$ADForestInfoRootDomainDN = $Null
ForEach($ADForestInfoRootDomainArrayItem in $ADForestInfoRootDomainArray)
    {
        $ADForestInfoRootDomainDN += "DC=" + $ADForestInfoRootDomainArrayItem + ","     
    }
$ADForestInfoRootDomainDN = $ADForestInfoRootDomainDN.Substring(0,$ADForestInfoRootDomainDN.Length-1)

$ADDomainInfoLGCDN = 'GC://' + $ADForestInfoRootDomainDN

Write-Verbose "Discovering Microsoft SQL Servers in the AD Forest $ADForestInfoRootDomainDN "
$root = [ADSI]$ADDomainInfoLGCDN 
$ADSearcher = new-Object System.DirectoryServices.DirectorySearcher($root,"(serviceprincipalname=mssql*)") 
$ADSearcher.PageSize = 500
$AllADSQLServerSPNs = $ADSearcher.FindAll() 

$AllADSQLServerSPNsCount = $AllADSQLServerSPNs.Count

Write-Output "Processing $AllADSQLServerSPNsCount (user and computer) accounts with MS SQL SPNs discovered in AD Forest $ADForestInfoRootDomainDN `r "

$AllMSSQLSPNs = $NULL
$AllMSSQLSPNHashTable =@{}
ForEach ($AllADSQLServerSPNsItem in $AllADSQLServerSPNs)
    {
        $AllADSQLServerSPNsItemDomainName = $NULL
        [array]$AllADSQLServerSPNsItemArray = $AllADSQLServerSPNsItem.Path -Split(",DC=")
        [int]$DomainNameFECount = 0
        ForEach ($AllADSQLServerSPNsItemArrayItem in $AllADSQLServerSPNsItemArray)
            {
                IF ($DomainNameFECount -gt 0)
                { [string]$AllADSQLServerSPNsItemDomainName += $AllADSQLServerSPNsItemArrayItem + "." }
                $DomainNameFECount++
            }
        $AllADSQLServerSPNsItemDomainName = $AllADSQLServerSPNsItemDomainName.Substring(0,$AllADSQLServerSPNsItemDomainName.Length-1)

        ForEach ($ADSISQLServersItemSPN in $AllADSQLServerSPNsItem.properties.serviceprincipalname)
            {
                IF ( ($ADSISQLServersItemSPN -like "MSSQL*") -AND ($ADSISQLServersItemSPN -like "*:*") )
                    { 
                        $ADSISQLServersItemSPNArray1 = $ADSISQLServersItemSPN -Split("/")
                        $ADSISQLServersItemSPNArray2 = $ADSISQLServersItemSPNArray1 -Split(":")
                        [string]$ADSISQLServersItemSPNServerFQDN = $ADSISQLServersItemSPNArray2[1]
                        IF ($ADSISQLServersItemSPNServerFQDN -notlike "*$AllADSQLServerSPNsItemDomainName*" )
                            { $ADSISQLServersItemSPNServerFQDN = $ADSISQLServersItemSPNServerFQDN + "." + $AllADSQLServerSPNsItemDomainName }
                        [string]$AllMSSQLSPNsItemServerInstancePort = $ADSISQLServersItemSPNArray2[2]

                        $AllMSSQLSPNsItemServerName = $ADSISQLServersItemSPNServerFQDN -Replace(("."+ $AllADSQLServerSPNsItemDomainName),"")

                        $AllMSSQLSPNHashTableData = $AllMSSQLSPNHashTable.Get_Item($ADSISQLServersItemSPNServerFQDN)
                        IF ( ($AllMSSQLSPNHashTableData) -AND ($AllMSSQLSPNHashTableData -notlike "*$AllMSSQLSPNsItemServerInstancePort*") )
                            {
                                $AllMSSQLSPNHashTableDataUpdate = $AllMSSQLSPNHashTableData + ";" + $AllMSSQLSPNsItemServerInstancePort
                                $AllMSSQLSPNHashTable.Set_Item($ADSISQLServersItemSPNServerFQDN,$AllMSSQLSPNHashTableDataUpdate)  
                            }
                          ELSE 
                            { $AllMSSQLSPNHashTable.Set_Item($ADSISQLServersItemSPNServerFQDN,$AllMSSQLSPNsItemServerInstancePort) }
                    } 
            }
    }

###
Write-Verbose "Loop through the discovered MS SQL SPNs and build the report " 
###
$ALLSQLServerReport = $NULL
$AllMSSQLServerFQDNs = $NULL
ForEach ($AllMSSQLSPNsItem in $AllMSSQLSPNHashTable.GetEnumerator())
    {
        $AllMSSQLSPNsItemServerDomainName = $NULL
        $AllMSSQLSPNsItemServerDomainDN = $NULL

        $AllMSSQLSPNsItemServerFQDN =  $AllMSSQLSPNsItem.Name
        [array]$AllMSSQLServerFQDNs += $AllMSSQLSPNsItemServerFQDN
        $AllMSSQLSPNsItemInstancePortArray = ($AllMSSQLSPNsItem.Value) -Split(';')

        $AllMSSQLSPNsItemServerFQDNArray = $AllMSSQLSPNsItemServerFQDN -Split('\.')
        [int]$FQDNArrayFECount = 0
        ForEach ($AllMSSQLSPNsItemServerFQDNArrayItem in $AllMSSQLSPNsItemServerFQDNArray)
            {
                IF ($FQDNArrayFECount -ge 1)
                    { 
                        [string]$AllMSSQLSPNsItemServerDomainName += $AllMSSQLSPNsItemServerFQDNArrayItem + "." 
                        [string]$AllMSSQLSPNsItemServerDomainDN += "DC=" + $AllMSSQLSPNsItemServerFQDNArrayItem + "," 
                    }
                $FQDNArrayFECount++
            }

        $AllMSSQLSPNsItemServerDomainName = $AllMSSQLSPNsItemServerDomainName.Substring(0,$AllMSSQLSPNsItemServerDomainName.Length-1)
        $AllMSSQLSPNsItemServerDomainDN = $AllMSSQLSPNsItemServerDomainDN.Substring(0,$AllMSSQLSPNsItemServerDomainDN.Length-1)
        $AllMSSQLSPNsItemServerDomainLDAPDN = "LDAP://$AllMSSQLSPNsItemServerDomainDN"

        $AllMSSQLSPNsItemServerName = $AllMSSQLSPNsItemServerFQDN -Replace(("."+$AllMSSQLSPNsItemServerDomainName),"")

        ForEach ($AllMSSQLSPNsItemInstancePortArrayItem in $AllMSSQLSPNsItemInstancePortArray)
            {
                $AllMSSQLSPNsItemServerPort = $NULL
                $AllMSSQLSPNsItemServerInstance = $NULL

                $SQLServerReport = New-Object -TypeName PSObject 
                $SQLServerReport | Add-Member -MemberType NoteProperty -Name Domain -Value $AllMSSQLSPNsItemServerDomainName
                $SQLServerReport | Add-Member -MemberType NoteProperty -Name ServerName -Value $AllMSSQLSPNsItemServerFQDN

                IF ($AllMSSQLSPNsItemInstancePortArrayItem -match "^[\d\.]+$")
                    { [int]$AllMSSQLSPNsItemServerPort = $AllMSSQLSPNsItemInstancePortArrayItem }
                IF ($AllMSSQLSPNsItemInstancePortArrayItem -NOTmatch "^[\d\.]+$")
                    { [string]$AllMSSQLSPNsItemServerInstance = $AllMSSQLSPNsItemInstancePortArrayItem } 
        
                $SQLServerReport | Add-Member -MemberType NoteProperty -Name Port -Value $AllMSSQLSPNsItemServerPort
                $SQLServerReport | Add-Member -MemberType NoteProperty -Name Instance -Value $AllMSSQLSPNsItemServerInstance

                IF ($ExtendedInfo -eq $True)
                    {
                        TRY
                            {
                                $ADComputerSearch = New-Object DirectoryServices.DirectorySearcher([ADSI]"")
                                $ADComputerSearch.SearchRoot = $AllMSSQLSPNsItemServerDomainLDAPDN
                                $ADComputerSearch.PageSize = 500
                                $ADComputerSearch.Filter = "(&(objectCategory=Computer)(name=$AllMSSQLSPNsItemServerName))"
                                $ComputerADInfo = $ADComputerSearch.FindAll()
                        
                                [string]$ComputerADDescription = ($ComputerADInfo.properties.description)
                                [string]$ComputerADInfoOperatingSystem = ($ComputerADInfo.properties.operatingsystem)
                                [string]$ComputerADInfoOperatingSystemServicePack = ($ComputerADInfo.properties.operatingsystemservicepack)
                                [string]$ComputerADInfoOperatingSystemVersion = ($ComputerADInfo.properties.operatingsystemversion)

                                [string]$ComputerADInfoLastLogonTimestamp = ($ComputerADInfo.properties.lastlogontimestamp)
                                TRY { [datetime]$ComputerADInfoLLT = [datetime]::FromFileTime($ComputerADInfoLastLogonTimestamp) }
                                    CATCH { }
                        
                                $SQLServerReport | Add-Member -MemberType NoteProperty -Name OperatingSystem -Value $ComputerADInfoOperatingSystem 
                                $SQLServerReport | Add-Member -MemberType NoteProperty -Name OSServicePack -Value $ComputerADInfoOperatingSystemServicePack 
                                $SQLServerReport | Add-Member -MemberType NoteProperty -Name LastBootup -Value $ComputerADInfoLLT  
                                $SQLServerReport | Add-Member -MemberType NoteProperty -Name OSVersion -Value $ComputerADInfoOperatingSystemVersion 
                                $SQLServerReport | Add-Member -MemberType NoteProperty -Name Description -Value $ComputerADDescription
                            }
                        CATCH { Write-Warning "Unable to gather properties for computer $AllMSSQLSPNsItemServerName" } 
                   }

                [array]$ALLSQLServerReport += $SQLServerReport
            }
    } 

IF ($GroupResults)
    { $ALLSQLServerReport | Sort-Object $SortResults  | Format-Table -GroupBy $GroupResults -AutoSize }
 ELSE
    { $ALLSQLServerReport | Sort-Object $SortResults  | Format-Table -AutoSize }

$AllMSSQLServerFQDNs = $AllMSSQLServerFQDNs | sort-object -Unique
$AllMSSQLServerFQDNsCount = $AllMSSQLServerFQDNs.Count
Write-Output " "
Write-Output "Discovered $AllMSSQLServerFQDNsCount servers running MS SQL `r "

} 
