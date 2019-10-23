# https://clouddeveloper.space/2017/10/26/deploy-azure-function-using-powershell/

$location = 'centralus'

$resourceGroupName = 'cognetiveResourceGroup'

$storageAccount = 'saqwerty'

$functionAppName = 'faqwerty'

$functionName = 'azurefunctionqwerty'

$SourceFile = 'sourcefile.ps1'


$resourceGroup = Get-AzureRmResourceGroup | Where-Object { $_.ResourceGroupName -eq $resourceGroupName }

if ( $null -eq $resourceGroup)
{
    New-AzureRmResourceGroup -Name $resourceGroupName -Location $location -force
}

if (!(Test-AzureName -Storage $storageAccount))
{
    New-AzureRmStorageAccount -ResourceGroupName $resourceGroupName -AccountName $storageAccount -Location $location -SkuName “Standard_LRS”
}

$functionAppResource = Get-AzureRmResource | Where-Object { $_.ResourceName -eq $functionAppName -And $_.ResourceType -eq ‘Microsoft.Web/Sites’ }

if ($null -eq $functionAppResource)
{

    New-AzureRmResource -ResourceType ‘Microsoft.Web/Sites’ -ResourceName $functionAppName -kind ‘functionapp’ -Location $location -ResourceGroupName $resourceGroupName -Properties @{ } -force

}

$keys = Get-AzureRmStorageAccountKey -ResourceGroupName $resourceGroupName -AccountName $storageAccount

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

Set-AzureRMWebApp -Name $functionAppName -ResourceGroupName $resourceGroupName -AppSettings $AppSettings

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

New-AzureRmResource -ResourceId $newResourceId -Properties $props -force# -ApiVersion 2015-08-01

# =========================================================================

function Get-PublishingProfileCredentials($resourceGroupName, $webAppName)
{

    $resourceType = “Microsoft.Web/sites/config”

    $resourceName = “$webAppName/publishingcredentials”

    $publishingCredentials = Invoke-AzureRmResourceAction -ResourceGroupName $resourceGroupName -ResourceType $resourceType

    -ResourceName $resourceName -Action list -Force# -ApiVersion 2015-08-01

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