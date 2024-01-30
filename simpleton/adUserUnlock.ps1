# Specify the sam account name of the locked user
$LockedUser = Read-Host "Locked user (SAM account name"

# Unlock the user account
Unlock-ADAccount -Identity $LockedUser
