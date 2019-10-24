[cmdletbinding()]
param(
    
)

$location = 'West US 2'

$salt = get-random
$resourceGroupRoot = "cognetiveResourceGroup"
$resourceGroupName = $resourceGroupRoot+$salt
$storageAccountName = 'ocrapistorage'+$salt
$functionAppName = 'ocrapi'+$salt
$functionName = 'ocrapifunction'+$salt
$SourceFile = 'sourcefile.ps1'

$ErrorActionPreference = "Stop"

if ((get-command -module "az*").count -eq 0) {
    write-verbose "Couldn't find any Az modules, so I'm installing them"
    write-progress -Activity "Installing Azure management modules"
    Install-Module -Name Az -AllowClobber -Scope CurrentUser -Force
    Import-Module Az
}

try {
    write-progress "Testing user authentication with Azure"
    Get-AzResourceGroup | out-null
} catch {
    Connect-AzAccount
}

$resourceGroups = Get-AzResourceGroup
Write-Verbose "Removing any previous resource groups from this project..."
$resourceGroups | Where-Object {$_.ResourceGroupName -like "$resourceGroupRoot*"} | Remove-AzResourceGroup -Verbose -AsJob -Force

$resourceGroup = $resourceGroups | Where-Object { $_.ResourceGroupName -eq $resourceGroupName }
if ( $null -eq $resourceGroup) {
    write-verbose "Creating resource group"
    Write-Progress -Activity "Creating resource group $resourceGroupName"
    New-AzResourceGroup -Name $resourceGroupName -Location $location -force
}

# $storageAccounts = Get-AzStorageAccount
# $storageAccount = $storageAccounts | Where-Object {$_.StorageAccountName -eq $storageAccountName}
# if ($null -eq $storageAccount)
# {
#     write-host "Creating storage account"
#     Write-Progress -Activity "Creating storage account $storageAccountName"
#     New-AzStorageAccount -ResourceGroupName $resourceGroupName -AccountName $storageAccountName -Location $location -SkuName “Standard_LRS”
# }

write-host "Looking for web app (function)"
$functionAppResource = Get-AzResource | Where-Object { $_.ResourceName -eq $functionAppName -And $_.ResourceType -eq ‘Microsoft.Web/Sites’ }

if ($null -eq $functionAppResource) {
    # https://clouddeveloper.space/2017/10/26/deploy-azure-function-using-powershell/

    write-verbose "Creating web app (function)"

    # Create the parameters for the file, which for this template is the function app name.
    $TemplateParams = @{
        "subscriptionId" = (Get-AzSubscription).Id;
        "name" = $functionAppName;
        "location" = "West US 2";
        "hostingEnvironment" = "";
        "hostingPlanName" = $resourceGroupRoot+"HostingPlan"+$salt;
        "serverFarmResourceGroup" = "serverFarmResourceGroup"+$salt;
        "alwaysOn" = $false;
        "storageAccountName" = $storageAccountName;
        "linuxFxVersion" = "DOCKER|microsoft/azure-functions-dotnet-core2.0:2.0";
        "sku" = "Dynamic";
        "skuCode" = "Y1";
        "workerSize" = "0";
        "workerSizeId" = "0";
        "numberOfWorkers"="1";
        #"nameFromTemplate" = $functionAppName;
    }

    # Deploy the template
    $valid = test-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile template.json -TemplateParameterObject $TemplateParams -Verbose
    if($valid) {
        New-AzResourceGroupDeployment -Name "functionDeployment" -ResourceGroupName $resourceGroupName -TemplateFile template.json -TemplateParameterObject $TemplateParams -Verbose
    }
    write-host "Function app created!"
}

write-verbose "Getting storage account key"
$keys = Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -AccountName $storageAccount

$accountKey = $keys | Where-Object { $_.KeyName -eq “Key1” } | Select-Object Value

$storageAccountConnectionString = ‘DefaultEndpointsProtocol=https;AccountName=’ + $storageAccount + ‘;AccountKey=’ + $accountKey.Value

$AppSettings = @{ }

$AppSettings = @{‘AzureWebJobsDashboard’       = $storageAccountConnectionString;

    ‘AzureWebJobsStorage’                      = $storageAccountConnectionString;

    ‘FUNCTIONS_EXTENSION_VERSION’              = ‘~1’;

    ‘WEBSITE_CONTENTAZUREFILECONNECTIONSTRING’ = $storageAccountConnectionString;

    ‘WEBSITE_CONTENTSHARE’                     = $storageAccount;

    ‘CUSTOMSETTING1’                           = ‘CustomValue1’;

    ‘CUSTOMSETTING2’                           = ‘CustomValue2’;

    ‘CUSTOMSETTING3’                           = ‘CustomValue3’
}

Set-AzWebApp -Name $functionAppName -ResourceGroupName $resourceGroupName -AppSettings $AppSettings

# =========================================================================

$baseResource = Get-AzureRmResource -ExpandProperties | Where-Object { $_.kind -eq ‘functionapp’ -and $_.ResourceType -eq ‘Microsoft.Web/sites’ -and $_.ResourceName -eq $functionAppName }

$SourceFileContent = Get-Content -Raw $SourceFile

$functionFileName = ‘run.ps1’

#schedule – run every 1am every day

$props = @{

    config = @{

        ‘bindings’ = @(

            @{

                ‘name’      = ‘myTimer’

                ‘type’      = ‘timerTrigger’

                ‘direction’ = ‘in’

                ‘schedule’  = ‘0 0 1 * * *’

            }

        )

    }

}

$props.files = @{$functionFileName = “$SourceFileContent” }

$newResourceId = ‘{0}/functions/{1}’ -f $baseResource.ResourceId, $functionName

# now deploy the function itself

New-AzureRmResource -ResourceId $newResourceId -Properties $props -force -ApiVersion 2015-08-01

# =========================================================================

function Get-PublishingProfileCredentials($resourceGroupName, $webAppName)
{

    $resourceType = “Microsoft.Web/sites/config”

    $resourceName = “$webAppName/publishingcredentials”

    $publishingCredentials = Invoke-AzureRmResourceAction -ResourceGroupName $resourceGroupName -ResourceType $resourceType

    -ResourceName $resourceName -Action list -Force -ApiVersion 2015-08-01

    return $publishingCredentials

}

function Get-KuduApiAuthorisationHeaderValue($resourceGroupName, $webAppName)
{

    $publishingCredentials = Get-PublishingProfileCredentials $resourceGroupName $webAppName

    return (“Basic {0}” -f [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes((“{0}:{1}” -f

                    $publishingCredentials.Properties.PublishingUserName, $publishingCredentials.Properties.PublishingPassword))))

}

function UploadFile($kuduApiAuthorisationToken, $functionAppName, $functionName, $fileName, $localPath )
{

    $kuduApiUrl = “https://$functionAppName.scm.azurewebsites.net/api/vfs/site/wwwroot/$functionName/modules/$fileName&\#8221";

    $result = Invoke-RestMethod -Uri $kuduApiUrl `

        -Headers @{“Authorization” = $kuduApiAuthorisationToken; ”If-Match” = ”*” } `

        -Method PUT `

        -InFile $localPath `

        -ContentType “multipart/form-data”

}

# =========================================================================

$accessToken = Get-KuduApiAuthorisationHeaderValue $resourceGroupName $functionAppName

$moduleFiles = Get-ChildItem ‘modules’

$moduleFiles | % {

    Write-Host “Uploading $($_.Name) … ” -NoNewline

    UploadFile $accessToken $functionAppName $functionName $_.Name $_.FullName

    Write-Host -f Green ” [Done]”

}