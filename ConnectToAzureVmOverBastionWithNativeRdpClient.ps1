Function Test-CommandExists {
    Param ($command)
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = ‘stop’
    Try {
        if (Get-Command $command) {
            RETURN $true
        }
    }
    Catch {
        #Write-Host “$command does not exist”
        RETURN $false
    }
    Finally {
        $ErrorActionPreference = $oldPreference
    }
}

function InstallOrUpgradeAzModuleForPoSh() {
    #this will be eitehr for PoSh core or PoSh for windows depending in which of those two shells this is runb
    try {

        if (Test-CommandExists Az-Context) {

            Write-Host ("$(Get-Date): Azure CLI is already installed and will be upgraded to the latest version if needed. This can take a couple of minutes." )`
                -foregroundcolor Green
            Update-Module -Name Az -Force
            Write-Host ("$(Get-Date): Azure PowerShell module  has been upgraded." )`
                -foregroundcolor Green
        }
        else {
            # Install Azure CLI with MSI
            Write-Host ("$(Get-Date): The Azure PowerShell module needs to be installed. This can take a couple of minutes." )`
                -foregroundcolor Green
            $ProgressPreference = 'Continue'
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
            #Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force
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
        if (Test-CommandExists az version --help) {

            Write-Host ("$(Get-Date): Azure CLI is already installed and will be upgraded to the latest version if needed. This can take a couple of minutes." )`
                -foregroundcolor Green
            az upgrade --yes --only-show-errors 2>nul
            Write-Host ("$(Get-Date): Azure CLI has been upgraded." )`
                -foregroundcolor Green
            #Enable auto upgrade ...
            $Result = config set auto-upgrade.enable=yes --only-show-errors 2>nul
            Return $Result
        }
        else {
            # Install Azure CLI with MSI
            $ProgressPreference = 'Continue'
            Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi -UseBasicParsing

            $Install = Start-Process msiexec.exe -ArgumentList '/I AzureCLI.msi /quiet'
            Return $Install
            #Clean up the download
            Remove-Item .\AzureCLI.msi

            #Enable auto upgrade ...
            az config set auto-upgrade.enable=yes --only-show-errors 2>nul
            #Add Bastion extnsion ...
            az extension add --name 'bastion'
        }
    }
    catch {
        Write-Host -foregroundcolor red ("$(Get-Date): An error has occured: $($error[0].ToString())")`
    }
    Finally {
        Write-Host ("$(Get-Date): Azure CLI is installed and running the latest version") -foregroundcolor Green
    }
}

<#
    $ErrorActionPreference = 'SilentlyContinu'
    Try {
        $bastionExtension = az extension show --name bastion --only-show-errors #| out-null
        $config = $bastionExtension | ConvertFrom-Json
        $Installedversion = $config.version
        write-host -foregroundcolor green "$(Get-Date): Az extension bastion version $Installedversion is allready installed. Checking if this is the lastest version"

        $Versions = az extension list-versions --name 'bastion'
        $Versionsobj = $Versions | ConvertFrom-Json
        $VersionString = $Versionsobj.Item($Versionsobj.Length - 1).version
        $LatestVersion = If ($VersionString -match '(max compatible version)') {
            write-host -foregroundcolor cyan "$(Get-Date): The latest available version of bastion extension is" $VersionString.Substring(0, 5)
        }

        If ($LatestVersion -eq $config.version -or $LatestVersion -lt $config.version) {
            write-host -foregroundcolor green  "$(Get-Date): Latest version of bastion extension is installed "
        }
        else {
            write-host -foregroundcolor yellow "$(Get-Date): Upgrading to latest version of bastion extension"
            az extension update --name 'bastion'  --only-show-errors
        }
    }
    Catch {
        write-host -Foregroundcolor yellow "$(Get-Date): az extension bastion is not installed - we will do this now -please wait, this will not take long"
        az extension add --name 'bastion'
    }
    Finally {
        Write-Host ""
    }
    $ErrorActionPreference = 'Continue'
    #>


function Login($SubscriptionId) {
    Try {
        if (Test-CommandExists Get-AzContext) {
            If ($UpgradePoshModule) {
                InstallOrUpgradeAzModuleForPoSh
            }
            $AzContext = Get-AzContext
            #$AzContext
            if (!$AzContext -or ($AzContext.Subscription.Id -ne $SubscriptionId)) {
                Write-Host -ForegroundColor Yellow "$(Get-Date): You need to connect to the Bastion subscripton named ... "
                Connect-AzAccount -Subscription $SubscriptionId
            }
            else {
                Write-Host -ForegroundColor green "$(Get-Date): You are already connected to the Bastion subscripton named '$($AzContext.Subscription.Name)' with SubscriptionId '$SubscriptionId'"
            }
        }
        Else {

            $whiteSpace = " " * ((Get-Date).ToString()).Length
            Write-Host -ForegroundColor magenta "$(Get-Date): Cannot log you in to Azure . This script requires the Azure PowerShell module to be installed."
            Write-Host -ForegroundColor magenta "$(Get-Date): Please do this before running the script"
            Write-Host -ForegroundColor magenta "$whiteSpace  Alternatively, run this script with the -$InstallOrUpgradeAzModuleForPoSh  parameter set to $True"
        }
    }
    Catch {
        Write-Host -ForegroundColor red "$(Get-Date): An error has occured. Exiting sript"
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

    try {
    #This is a fake subscription ID - adapt it your bastion sunscription ID
        $AzureBastionSub = 's4wdt5p5-q7g9-8456-4k56-e2l745c87eec'
        Login $AzureBastionSub
        #Connect-AzAccount -UseDeviceAuthentication -Subscription $AzureBastionSub
        #az login
        #az account set --subscription $AzureBastionSub
        $VerifyWorkingSub = az account show #| Out-Null
        $config = $VerifyWorkingSub | ConvertFrom-Json

        if ($config.id -eq $AzureBastionSub) {
            $BastionName = 'bas-centralbastion-vwan-dv' #Get-AzBastion --Name 'bas-centralbastion-vwan-dv'
            $BastionResourceGroup = 'rg-centralbastion-vwan-dv'
        }
        else {
            write-host -ForegroundColor yellow "$(Get-Date): You are not connected to the correct Bastion subscription - aborting the process!"
            exit
        }
    }
    Catch {
        Write-Host -ForegroundColor green "$(Get-Date): This script requires the Azure PowerShell module to be installed. Please do this before running the script"
        Write-Host -ForegroundColor green "Alternativelyrun this script with the -$InstallOrUpgradeAzModuleForPoSh  parameter set to $True"
        #Exit
    }
    #Finally{}
    Try {
        Write-host -ForegroundColor green  "$(Get-Date): Connecting to Azure VM via native RDP client ..."
        if ('' -ne $VmName) {
            Write-host -ForegroundColor magenta  "You chose to connect via the VM name (based on resource ID)."
            #$VmName = 'peeredclientvm'
            $VMToConnectTo = Get-AZVM -name $VmName #'peeredclientvm'
            [string]$VmID = $VMToConnectTo.Id
            
            write-Host -ForegroundColor Yellow "$(Get-Date): connecting to VM named: [$VmName]" 
            az network bastion rdp --name $BastionName --resource-group $BastionResourceGroup --configure --target-resource-id $VmID  --only-show-errors
        }
        else {

            if ('' -ne $VmIp) {
                write-Host -ForegroundColor magenta "$(Get-Date): You chose to connect to VM via IP."
                write-Host -ForegroundColor Yellow "$(Get-Date): Connecting to VM via IP: [$VmIp]"
                az network bastion rdp --name $BastionName --resource-group $BastionResourceGroup --target-ip-address $VmIp --configure --only-show-errors
            }
        }
    }
    Catch {}
    Finally {}
}

#TESTING TWO OPTIONS - COMMENT/UNCOMMENT AS REQUIRED
ConnectToAzVM -VmName 'democlientvminspoke' 
ConnectToAzVM -VmName 'democlientvminspoke' -InstallOrUpgradePoshModule $True
#ConnectToAzVM -VmIp 10.10.20.4 -InstallAndUpgradeAzCliTooling $True
ConnectToAzVM -VmName 'democlientvminspoke' -InstallOrUpgradePoshModule $True -InstallAndUpgradeAzCliTooling $True
