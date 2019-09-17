# Deploying Terraform Remote State to AZ Storage Container - tokens will be replaced in pipeline with current values
terraform {
  required_version = ">= 0.11"
  backend "azurerm" {
    storage_account_name = "__terraformstorageaccount__"
    container_name       = "__tf_container_name__"
    key                  = "__tf_key__"
    # Retrieved by script.
    access_key = "##storagekey##"
  }
}
# creating resource group for VMs
resource "azurerm_resource_group" "smbrg" {
  name     = "${var.azure_resourcegroup_name}"
  location = "${var.location}"
}

# Provisioning Ansible Jump VM

resource "azurerm_virtual_network" "smbvnet" {
  name                = "${var.prefix}-network"
  address_space       = ["10.0.0.0/16"]
  location            = "${azurerm_resource_group.smbrg.location}"
  resource_group_name = "${azurerm_resource_group.smbrg.name}"
}

resource "azurerm_subnet" "internal" {
  name                 = "internal"
  resource_group_name  = "${azurerm_resource_group.smbrg.name}"
  virtual_network_name = "${azurerm_virtual_network.smbvnet.name}"
  address_prefix       = "10.0.2.0/24"
}

resource "azurerm_network_interface" "jumpvm" {
  name                = "${var.prefix}-jumpnic"
  location            = "${azurerm_resource_group.smbrg.location}"
  resource_group_name = "${azurerm_resource_group.smbrg.name}"

  ip_configuration {
    name                          = "jumpvmipconfig"
    subnet_id                     = "${azurerm_subnet.internal.id}"
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_virtual_machine" "jumpvm" {
  name                  = "${var.prefix}-jumpvm"
  location              = "${azurerm_resource_group.smbrg.location}"
  resource_group_name   = "${azurerm_resource_group.smbrg.name}"
  network_interface_ids = ["${azurerm_network_interface.jumpvm.id}"]
  vm_size               = "${var.agent_pool_profile_vm_size}"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  delete_os_disk_on_termination = true


  # Uncomment this line to delete the data disks automatically when deleting the VM
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
  storage_os_disk {
    name              = "jumpvmdisk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "ansible"
    admin_username = "ansible"
    # Create this variable in AzDo
    admin_password = "##jumpvmadminpassword##"
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
  tags = {
    environment = "production"
  }
}
