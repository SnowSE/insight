# https://docs.microsoft.com/en-us/azure/virtual-machines/scripts/virtual-machines-linux-powershell-sample-create-vm?toc=%2fazure%2fvirtual-machines%2flinux%2ftoc.json
# https://mcpmag.com/articles/2019/05/14/azure-cognitive-service-accounts-powershell.aspx

# Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; 
# Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'

#to install
Install-Module -Name Az -AllowClobber -Scope CurrentUser
import-module Az

#teardown