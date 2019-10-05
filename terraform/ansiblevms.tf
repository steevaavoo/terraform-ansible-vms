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
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "22"
  }

  tags = {
    environment = "smb ansible"
  }
}

# Creating a Virtual NIC and connecting to the above subnet (need to think about NSG for this?)
# resource "azurerm_network_interface" "jumpvmintnic" {
#   name                = "${var.prefix}-jumpIntNic"
#   location            = "${azurerm_resource_group.smbrg.location}"
#   resource_group_name = "${azurerm_resource_group.smbrg.name}"
#   # network_security_group_id = "${TO BE CONFIGURED?}"

#   ip_configuration {
#     name                          = "jumpVmIntIpConfig"
#     subnet_id                     = "${azurerm_subnet.smbsubnet.id}"
#     private_ip_address_allocation = "Dynamic"
#   }

#   tags = {
#     environment = "smb ansible"
#   }
# }

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
    # When creating multiple NICs, one must be set as Primary - also should be defined as "primary_network_interface_id"
    # in "azurerm_virtual_machine" below.
    # primary = true
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
  network_interface_ids = [
    #"${azurerm_network_interface.jumpvmintnic.id}", <-- may not be required.
  "${azurerm_network_interface.jumpvmpubnic.id}"]
  # If multiple NICs assigned here, the same as below must be defined as Primary in resource creation above
  # primary_network_interface_id = "${azurerm_network_interface.jumpvmpubnic.id}"
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
    admin_username = "${var.admin_username}"
    # Create this variable in AzDo
    # admin_password = "##jumpvmadminpassword##"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      # Path is instructing where to store the key_data
      path     = "/home/${var.admin_username}/.ssh/authorized_keys"
      key_data = "${var.public_ssh_key}"
    }
  }

  tags = {
    environment = "smb ansible"
  }
}

data "azurerm_public_ip" "smbpublicip" {
  name                = "${azurerm_public_ip.smbpublicip.name}"
  resource_group_name = "${azurerm_virtual_machine.jumpvm.resource_group_name}"
}
output "jump_public_ip_address" {
  value = "${data.azurerm_public_ip.smbpublicip.ip_address}"
}

resource "null_resource" "debug" {
  provisioner "local-exec" {
    command     = "ls d:/a/_temp/id_rsa ; cat d:/a/_temp/id_rsa"
    interpreter = ["PowerShell", "-Command"]
  }
}

resource "null_resource" "init" {
  # Define connection
  connection {
    type        = "ssh"
    host        = "${data.azurerm_public_ip.smbpublicip.ip_address}"
    user        = "${var.admin_username}"
    private_key = "${file("d:/a/_temp/id_rsa")}"
    agent       = "true"
  }

  # Upload and run script(s)
  provisioner "remote-exec" {
    scripts = [
      "../scripts/Install-Ansible.sh"
    ]
  }

  # Run inline code
  provisioner "remote-exec" {
    inline = [
      "whoami",
      "hostname",
      "which pip",
      "pip -V",
      "which ansible",
      "ansible --version"
    ]
  }

  depends_on = ["azurerm_public_ip.smbpublicip", "azurerm_virtual_machine.jumpvm", "null_resource.debug"]
}
