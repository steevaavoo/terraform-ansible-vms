$key = (Get-AzStorageAccountKey -ResourceGroupName $env:TERRAFORMSTORAGERG -AccountName $env:TERRAFORMSTORAGEACCOUNT).Value[0]

Write-Host "##vso[task.setvariable variable=storagekey]$key"
