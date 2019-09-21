# Update and upgrade packages
sudo apt-get update -y
sudo apt-get upgrade -y

# Install Python and Kerberos packages
sudo apt-get install python-dev python-pip -y
  # Default Kerberos version 5 realm:
  # SUMMIT2019.LOCAL
  # Kerberos servers for your realm:
  # dc01.summit2019.local
  # Administrative server for your Kerberos realm:
  # dc01.summit2019.local

# Install Ansible and packages required for Windows WinRM
sudo pip install --upgrade ansible pywinrm requests-credssp

# Add host entry for dc01 (needed for kerberos / AD comms used in 4_custom_module_demo)
# '192.168.56.2    dc01.summit2019.local' | sudo tee -a /etc/hosts