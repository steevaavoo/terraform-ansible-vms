# This will create an Azure resource group, Storage account and Storage container, used to store terraform remote state
#
# When using Windows agent in Azure DevOps, use batch scripting.
# For batch files use the prefix "call" before every azure command.

# Resource Group
echo "STARTED: Creating Resource Group..."
az group create --location $RESOURCE_LOCATION --name $TERRAFORMSTORAGERG
echo "##vso[task.setprogress value=25;]FINISHED: Creating Resource Group."

# Storage Account
echo "STARTED: Creating Storage Account..."
az storage account create --name $TERRAFORMSTORAGEACCOUNT --resource-group $TERRAFORMSTORAGERG \
--location $RESOURCE_LOCATION --sku Standard_LRS
echo "##vso[task.setprogress value=50;]FINISHED: Creating Storage Account."

# Storage Container
echo "STARTED: Creating Storage Container..."
az storage container create --name $TF_CONTAINER_NAME --account-name $TERRAFORMSTORAGEACCOUNT
echo "##vso[task.setprogress value=75;]FINISHED: Creating Storage Container."
