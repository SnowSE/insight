[cmdletbinding()]
param(
    [switch]$preservePreviousResourceGroups
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
    Install-Module -Name Az -AllowClobber -Scope CurrentUser -Force
    Import-Module Az
}

try {
    write-verbose "Testing user authentication with Azure"
    Get-AzResourceGroup | out-null
} catch {
    Connect-AzAccount
}

$resourceGroups = Get-AzResourceGroup

if($preservePreviousResourceGroups) {
    Write-Warning "Preserving previous resource groups...they're still out there..."
} else {
    Write-Verbose "Removing any previous resource groups from this project..."
    $resourceGroups | Where-Object {$_.ResourceGroupName -like "$resourceGroupRoot*"} | Remove-AzResourceGroup -Verbose -AsJob -Force
}

Write-Verbose "Creating resource group $resourceGroupName"
New-AzResourceGroup -Name $resourceGroupName -Location $location -force

# Write-Verbose "Creating storage account $storageAccountName"
# New-AzStorageAccount -ResourceGroupName $resourceGroupName -AccountName $storageAccountName -Location $location -SkuName “Standard_LRS”

write-verbose "Creating AzFunctions web app $functionAppName"

$templateParameters = @{
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
}

Write-Verbose "Testing az resource group deployment"
$valid = test-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile template.json -TemplateParameterObject $templateParameters -Verbose
if($valid) {
    Write-Verbose "Deploying azure functions web app"
    New-AzResourceGroupDeployment -Name "deploy1" -Mode Complete -ResourceGroupName $resourceGroupName -TemplateFile template.json -TemplateParameterObject $templateParameters -Verbose -DeploymentDebugLogLevel All
}
write-host "Function app created!"

return;

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