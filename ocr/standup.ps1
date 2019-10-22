# Variables for common values
$resourceGroup = "myResourceGroup"
$location = "centralus "
$visionName = "TestVision"

Connect-AzAccount

New-AzResourceGroup -Name $resourceGroup -Location $location

$vision = New-AzCognitiveServicesAccount -ResourceGroupName $resourceGroup -Name $visionName -Type ComputerVision -SkuName F0 -Location $location

$vision.Endpoint
$vision.Id