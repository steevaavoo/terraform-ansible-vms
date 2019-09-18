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
# Creating resource group for VMs
resource "azurerm_resource_group" "smbrg" {
  name     = "${var.azure_resourcegroup_name}"
  location = "${var.location}"
}

# Provisioning Ansible Jump VM
# Creating virtual network
resource "azurerm_virtual_network" "smbvnet" {
  name                = "${var.prefix}-network"
  address_space       = ["10.0.0.0/16"]
  location            = "${azurerm_resource_group.smbrg.location}"
  resource_group_name = "${azurerm_resource_group.smbrg.name}"
}
# Creating virtual subnet "smbSubnet" within above network
resource "azurerm_subnet" "smbsubnet" {
  name                 = "smbSubnet"
  resource_group_name  = "${azurerm_resource_group.smbrg.name}"
  virtual_network_name = "${azurerm_virtual_network.smbvnet.name}"
  address_prefix       = "10.0.2.0/24"
}
# Creating a Public IP
resource "azurerm_public_ip" "smbpublicip" {
  name                = "ansPublicIP"
  location            = "${azurerm_resource_group.smbrg.location}"
  resource_group_name = "${azurerm_resource_group.smbrg.name}"
  allocation_method   = "Dynamic"

  tags = {
    environment = "smb ansible"
  }
}
# Creating network security group to expose SSH on Ansible Jump Box
resource "azurerm_network_security_group" "smbnsg" {
  name                = "ansNetworkSecurityGroup"
  location            = "${azurerm_resource_group.smbrg.location}"
  resource_group_name = "${azurerm_resource_group.smbrg.name}"

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "smb ansible"
  }
}

# Creating a Virtual NIC and connecting to the above subnet (need to think about NSG for this?)
resource "azurerm_network_interface" "jumpvmintnic" {
  name                = "${var.prefix}-jumpIntNic"
  location            = "${azurerm_resource_group.smbrg.location}"
  resource_group_name = "${azurerm_resource_group.smbrg.name}"
  # When creating multiple NICs, one must be set as Primary - also should be the first listed in
  # "network_interface_ids" below under "azurerm_virtual_machine"
  primary = true
  # network_security_group_id = "${TO BE CONFIGURED?}"

  ip_configuration {
    name                          = "jumpVmIntIpConfig"
    subnet_id                     = "${azurerm_subnet.smbsubnet.id}"
    private_ip_address_allocation = "Dynamic"
  }

  tags = {
    environment = "smb ansible"
  }
}
# Creating an additional Virtual NIC and connecting to the above Public IP
resource "azurerm_network_interface" "jumpvmpubnic" {
  name                      = "${var.prefix}-jumpPubNic"
  location                  = "${azurerm_resource_group.smbrg.location}"
  resource_group_name       = "${azurerm_resource_group.smbrg.name}"
  network_security_group_id = "${azurerm_network_security_group.smbnsg.id}"

  ip_configuration {
    name                          = "jumpVmPubIpConfig"
    subnet_id                     = "${azurerm_subnet.smbsubnet.id}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${azurerm_public_ip.smbpublicip.id}"
  }

  tags = {
    environment = "smb ansible"
  }
}
# Creating a Jump VM and connecting it to the above resources.
resource "azurerm_virtual_machine" "jumpvm" {
  name                = "${var.prefix}-jumpvm"
  location            = "${azurerm_resource_group.smbrg.location}"
  resource_group_name = "${azurerm_resource_group.smbrg.name}"
  # If multiple NICs assigned here, the first in this list must be defined as Primary in resource creation above
  network_interface_ids = [
    "${azurerm_network_interface.jumpvmintnic.id}",
    "${azurerm_network_interface.jumpvmpubnic.id}",
  ]
  vm_size = "${var.agent_pool_profile_vm_size}"

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
    environment = "smb ansible"
  }
}
