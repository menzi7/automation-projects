# Set the username
$username = Read-Host "SAM account name"
# Set password to a default password
$newpassword = "newpassw0rd"

# Convert the password to a secure string
$securePassword = ConvertTo-SecureString $newpassword -AsPlainText -Force

# Get the AD user object
$user = Get-ADUser -Identity $username

# Set the new password for the user
Set-ADAccountPassword $user -NewPassword $securePassword -Reset

# Enable the user account (in case it was disabled)
Enable-ADAccount $user
