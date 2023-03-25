Function Test-CommandExists {
    Param ($command)
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = ‘stop’
    Try {
        if (Get-Command $command) {
            #Write-Host -foregroundcolor green “$command exists”
            RETURN $true
        }
    }
    Catch {
        #Write-Host -foregroundcolor yellow “$command does not exist”
        RETURN $false
    }
    Finally {
        $ErrorActionPreference = $oldPreference
    }
}

function InstallOrUpgradeAzModuleForPoSh() {
    #this will be eitehr for PoSh core or PoSh for windows depending in which of those two shells this is runb
    try {
        if (Test-CommandExists Get-AzContext) {

            Write-Host ("$(Get-Date): Azure PowerShell module is already installed and will be upgraded to the latest version if needed. This can take a couple of minutes." )`
                -foregroundcolor Green
            If ((Get-Module -list -name az.accounts).Version -ne '2.11.2') {
                Install-PackageProvider -Name NuGet -Force > $Null
                Update-Module -Name Az -Force
                Write-Host ("$(Get-Date): Azure PowerShell module  has been upgraded." )`
                    -foregroundcolor Green
            }
        }
        else {
            # Install Azure CLI with MSI
            Write-Host ("$(Get-Date): The Azure PowerShell module needs to be installed. This can take a quite a while." )`
                -foregroundcolor Green
            $ProgressPreference = 'Continue'
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
            Install-PackageProvider -Name NuGet -Force > $Null
            Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force
            Write-Host ("$(Get-Date): The Azure PowerShell module has been installed." )`
                -foregroundcolor Green
        }
    }
    catch {
        Write-Host -foregroundcolor red ("$(Get-Date): An error has occured: $($error[0].ToString())")`
    
    }
    Finally {
        Write-Host ("$(Get-Date): The Azure PowerShell is at the latest version") -foregroundcolor Green
    }
}

function InstallOrUpgradeAzCliWithBastionExtension() {
    try {
        if (Test-CommandExists az) {

            Write-Host ("$(Get-Date): Azure CLI is already installed and will be upgraded to the latest version if needed. This can take a couple of minutes." )`
                -foregroundcolor Green
            az upgrade --yes --only-show-errors --all 2> $null
            Write-Host ("$(Get-Date): Azure CLI has been upgraded or was already running the latest version." )`
                -foregroundcolor Green
            #Enable auto upgrade ... it will keep az cli up to date
            az config set auto-upgrade.enable=yes --only-show-errors 2> $null
            az config set auto-upgrade.prompt=no  --only-show-errors 2> $null
        }
        else {
            # Install Azure CLI with MSI
            $ProgressPreference = 'Continue'
            Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi -UseBasicParsing

            Start-Process msiexec.exe -ArgumentList '/I AzureCLI.msi /quiet'
            # Return $Install
            #Clean up the download
            Remove-Item .\AzureCLI.msi

            #Enable auto upgrade ...
            az config set auto-upgrade.enable=yes --only-show-errors 2> $null
            az config set auto-upgrade.prompt=no  --only-show-errors 2> $null
            #Add Bastion extnsion ...
            az extension add --name 'bastion'
        }
    }
    catch {
        Write-Host -foregroundcolor Red ("$(Get-Date): An error has occured: $($error[0].ToString())")`
    
    }
    Finally {
        Write-Host ("$(Get-Date): Azure CLI is installed and running the latest version") -foregroundcolor Green
    }
}

function Login($SubscriptionId, $AzureTenant) {
    Try {
        if (Test-CommandExists Get-AzContext) {
            $AzContext = Get-AzContext
            if (!$AzContext -or ($AzContext.Subscription.Id -ne $SubscriptionId)) {
                Write-Host -ForegroundColor Yellow "$(Get-Date): You need to authenticate to your Bastion host in your tenant and subscription."
                Connect-AzAccount -Subscription $SubscriptionId -Tenant $AzureTenant
            }
            else {
                Write-Host -ForegroundColor green "$(Get-Date): You are already connected to the Bastion subscripton named '$($AzContext.Subscription.Name)' with SubscriptionId '$SubscriptionId'"
            }
        }
        Else {

            $whiteSpace = " " * ((Get-Date).ToString()).Length
            Write-Host -ForegroundColor Magenta   "$(Get-Date): Cannot log you in to Azure . This script requires the Azure PowerShell module to be installed."
            Write-Host -ForegroundColor Magenta "$(Get-Date): Please do this before running the script"
            Write-Host -ForegroundColor Magenta "$whiteSpace  Alternatively, run this script with the -$InstallOrUpgradeAzModuleForPoSh  parameter set to $True"
        }
    }
    Catch {
        Write-Host -ForegroundColor Red "$(Get-Date): An error has occured during login. Exiting sript"
    }
    Finally {
    }
}

function ConnectToAzVM {
    [CmdletBinding()]
    Param
    (
        #[parameter(mandatory = $True, ParameterSetName = 'useVMName')][AllowNull()][AllowEmptySTring()][string]$VmName,
        [parameter(mandatory = $True, ParameterSetName = 'useVMName')][string]$VmName,
        [parameter(mandatory = $True, ParameterSetName = 'useVMIP')][IPaddress]$VmIp,
        [parameter(mandatory = $false )][Boolean]$InstallAndUpgradeAzCliTooling = $False,
        [parameter(mandatory = $false )][Boolean]$InstallOrUpgradePoshModule = $False
    )

    If ($InstallAndUpgradeAzCliTooling) {
        InstallOrUpgradeAzCliWithBastionExtension
    }

    If ($InstallOrUpgradePoshModule) {
        InstallOrUpgradeAzModuleForPoSh
    }

    try {

        #I am also passing in the tenant because when you have multiple one it polutes the output.
        #This is a fake Tenant ID - adapt it your bastion tenant ID
        $AzureTenant = '474f3521-88t9-541p-s5w9-8547rf1z473q'
        #This is a fake subscription ID - adapt it your bastion subscription ID
        $AzureBastionSub = 's4wdt5p5-q7g9-8456-4k56-e2l745c87eec'

        #Call the login function
        Login $AzureBastionSub $AzureTenant

        $VerifyWorkingSub = az account show --only-show-errors
        $config = $VerifyWorkingSub | ConvertFrom-Json 

        if ($config.id -eq $AzureBastionSub) {
            $BastionName = 'bas-centralbastion-vwan-dv' #Get-AzBastion --Name 'bas-centralbastion-vwan-dv'
            $BastionResourceGroup = 'rg-centralbastion-vwan-dv'
        }
        else {
            write-host -ForegroundColor Tellow "$(Get-Date): You are not connected to the correct Bastion subscription - aborting the process!"
            exit
        }
    }
    Catch {
        Write-Host -ForegroundColor Green "$(Get-Date): This script requires the Azure PowerShell module to be installed. Please do this before running the script"
        Write-Host -ForegroundColor Green "Alternatively run this script with the -$InstallOrUpgradeAzModuleForPoSh  parameter set to $True"
        #Exit
    }

    Try {
        Write-host -ForegroundColor Green  "$(Get-Date): Connecting to Azure VM via native RDP client ..."
        if ('' -ne $VmName) {
            Write-host -ForegroundColor Magenta  "You chose to connect via the VM name (based on resource ID)."

            $VMToConnectTo = Get-AZVM -name $VmName

            [string]$VmID = $VMToConnectTo.Id
            #$VmID

            write-Host -ForegroundColor Yellow "$(Get-Date): connecting to VM named: [$VmName]"
            az network bastion rdp --name $BastionName --resource-group $BastionResourceGroup --configure --target-resource-id $VmID  --only-show-errors
        }
        else {

            if ('' -ne $VmIp) {
                write-Host -ForegroundColor Magenta "$(Get-Date): You chose to connect to VM via IP."
                write-Host -ForegroundColor Yellow "$(Get-Date): Connecting to VM via IP: [$VmIp]"
                az network bastion rdp --name $BastionName --resource-group $BastionResourceGroup --target-ip-address $VmIp --configure --only-show-errors
            }
        }
    }
    Catch {}
    Finally {
        #Remove the conn.rdp created when the RDP session is stopped
        $RDPFileToClean = Get-ChildItem | Where-Object Name -Like 'conn.rdp'
        $RDPFileToClean = Get-ChildItem | Where-Object Name -eq 'conn.rdp'
        if ($Null -ne $RDPFileToClean) {
            Remove-Item -LiteralPath  $RDPFileToClean.Name
            Write-Host -ForegroundColor Green "$(Get-Date): Your RDP session has finnished and the temporary RDP file has been removed."
        }
    }
}

#TESTING TWO OPTIONS - COMMENT/UNCOMMENT AS REQUIRED
#ConnectToAzVM -VmName 'peeredclientvm' -InstallAndUpgradeAzCliTooling $True -InstallOrUpgradePoshModule $True
ConnectToAzVM -VmName 'peeredclientvm' -InstallAndUpgradeAzCliTooling $True #-InstallOrUpgradePoshModule $True
#ConnectToAzVM -VmIp 172.25.12.11 -InstallAndUpgradeAzCliTooling $True

