<#
.SYNOPSIS
A PowerShell-only script to launch a native RDP client to connect to an Azure Bastion host.
.DESCRIPTION
A PowerShell-only script to launch a native RDP client to connect to an Azure Bastion host.
This script does not require Az CLI on the host where you run it.

Limitation:
Version 1.0 does not support using a tunnel. That means it is only usable on Windows clients with modern RDP clients.

The script will do all of the following:

It will connect to the subscription holding the Azure Bastion host if the subscription exists; otherwise, exit the script.
Check if Azure VM can be found in the specified tenant, if so continue ...
Check if the  bastion host can be found in the specified tenant, if so continue ...
Check if we can get the raw access token, if so continue ...
Creates an RDP file on your desktop. It is ready to connect to your Azure VM over Bastion
with a date/time stamp in the filename.
Launch the created RDP file for you ready for customization and use.
.NOTES
Filename:       NativeRdpViaBastionToAzureVmPoShOnly.ps1
Created:        24/09/2023
Last modified:  21/10/2023
Author:         Didier Van Hoye - @WorkingHardInIT
Version:        1.0
PowerShell:     Azure PowerShell
Requires:       PowerShell Az and Az.ResourceGraph
Action:         Provide the Azure VM name as a parameter and change the other
                variables to reflect your environment prior to using the script.
Disclaimer:     This script is provided "as is" with no warranties.
.EXAMPLE
.\ativeRdpViaBastionToAzureVmPoShOnly.ps1 <"Azure VM name here"> <"Bastion hostname here"> 

-> .\NativeRdpViaBastionToAzureVmPoShOnly.ps1 AzureVmToConnectTo BastiionHostname

.LINK
https://workinghardinit.work
#>

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Parameters

param(
    # $subscriptionName -> Name of the subscription holding the Azure Bastion host
    [parameter(Mandatory = $true)][ValidateNotNullOrEmpty()] [string] $AzureVmName,
    # $bastionName -> Name of the Azure Bastion host
    [parameter(Mandatory = $false)][string] $BastionHostName = 'NameOfYourBastionHost'
)

Clear-Host
$TenantId = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
$BastionSubscriptionId = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
$BastionResoureGroup = 'NameOfBastioResourceGroup'
#If the optional $BastionHostName is null or empty this means we use the default bastion host.
#The default value is provided in the param itself - this is redundant! TODO: clean it up.
If (([string]::IsNullOrEmpty($BastionHostName))) {
    $BastionHostName = 'NameOfYourBastionHost'
}

Connect-AzAccount -Tenant $TenantId -Subscription $BastionSubscriptionId | Out-Null

write-host -ForegroundColor Green "Welcome To Bastion Native RDP"
write-host -ForegroundColor Yellow "Looking for the resource id of the specified Azure VM"

#We search for the VM resource ID so the user does have to and this without the user needing
#to know and provide the subscription and resource group of the VM.
#Looping through the tenant its subscription for this works but is too slow when you have a lot of them.
#The secret sauce to make looking up the resource ID of a VM super fast is Azure Graph.
#You need to have Az.ResourceGraph installed. Run 'Install-Module Az.ResourceGraph'
#It is significantly faster than looping to subs and running Get-AzVM

$VMToConnectTo = Search-AzGraph -Query "Resources | where type == 'microsoft.compute/virtualmachines' and name == '$AzureVmName'"
$VmResourceId = $VMToConnectTo.ResourceId
If (!([string]::IsNullOrEmpty($VmResourceId))) {
    write-host -ForegroundColor Green "Found it: $VmResourceId"
    write-host -ForegroundColor Yellow "Connecting to DV Tenant and Bastion subscription"
    #Connect to the baston sub in the correct tenant. The latter is important if you have multiple.
    Select-AzSubscription $BastionSubscriptionId -Tenant  $TenantId | out-null
    #Grab the Azure Access token
    $AccessToken = (Get-AzAccessToken).Token
    If (!([string]::IsNullOrEmpty($AccessToken))) {
        #Grab your centralized bastion host
        try {
            $Bastion = Get-AzBastion -ResourceGroupName $BastionResoureGroup -Name $BastionHostName
            if ($Null -ne $Bastion ) {
                write-host -ForegroundColor Cyan "Connected to Bastion$($Bastion.Name)"
                write-host -ForegroundColor yellow "Generating RDP file for you to desktop..."
                $target_resource_id = $VmResourceId
                $enable_mfa = "true" #"true"
                $bastion_endpoint = $Bastion.DnsName
                $resource_port = "3389"

                $url = "https://$($bastion_endpoint)/api/rdpfile?resourceId=$($target_resource_id)&format=rdp&rdpport=$($resource_port)&enablerdsaad=$($enable_mfa)"

                $headers = @{
                    "Authorization"   = "Bearer $($AccessToken)"
                    "Accept"          = "*/*"
                    "Accept-Encoding" = "gzip, deflate, br"
                    #  "Connection" = "keep-alive"
                    "Content-Type"    = "application/json"
                }

                $DesktopPath = [Environment]::GetFolderPath("Desktop")
                $DateStamp = Get-Date -Format yyyy-MM-dd
                $TimeStamp = Get-Date -Format HHmmss
                $DateAndTimeStamp = $DateStamp + '@' + $TimeStamp 
                $RdpPathAndFileName = "$DesktopPath\$AzureVmName-$DateAndTimeStamp.rdp"
                $progressPreference = 'silently continue'
            }
            else {
                write-host -ForegroundColor Red  "We could not connect to the Azure bastion host"
            }
        }
        catch {
            <#Do this if a terminating exception happens#>
        }
        finally {
            <#Do this after the try block regardless of whether an exception occurred or not#>
        }
        try {
            Invoke-WebRequest $url -Method Get -Headers $headers -OutFile $RdpPathAndFileName
            if (Test-Path $RdpPathAndFileName -PathType leaf) {
                Start-Process $RdpPathAndFileName
            }
            else {
                write-host -ForegroundColor Red  "The RDP file was not found on your desktop"
            }
        }
        catch {
            write-host -ForegroundColor Red  "An error occurred during the creation of the RDP file."
            $Error[0]
        }
        finally {
            $progressPreference = 'Continue'
        }
    }
    else {
        write-host -ForegroundColor Red  "We could not get the access token to authenticate"
    }
}
Else {
    write-host -ForegroundColor Red  "We could not find $AzureVmName"
}
