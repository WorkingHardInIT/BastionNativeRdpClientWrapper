# BastionNativeRdpClientWrapper
A PowerShell script to take away the complexity of connecting to an Azure VM over Azure Bastion via native RDP client via VM name or IP. It only needs the VM resource Name or the IP address to work. Optionally you can opt to have it install/upgrade Az CLI and/or the Az Modules for PowerShell. Both are a requirement for this script to work. The script should work in both Windows PowerShell (5.1) and PowerShell Core.
Note that this does not work when run from Azure Cloud Shell.
