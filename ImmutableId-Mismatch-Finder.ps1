################################################################################# 
# SCRIPT TO GATHER ALL MISMATCHES BETWEEN IMMUTEABLEID AND MS-DS-CONSISTENCYGUID#
# CREATED BY NATE COX															#
# 8/12/2019																		#
# THIS SCRIPT TAKES A VERY LONG TIME TO RUN IN A LARGE ENVIRONMENT				#
#################################################################################

##Import AD, MSOL, and Azure
Import-Module ActiveDirectory
$username = "ServiceAccount"
$password = ConvertTo-SecureString "Password" -AsPlainText -Force
$cred = new-object -typename System.Management.Automation.PSCredential ` -argumentlist $username, $password
Import-Module MSOnline -ErrorAction Stop -WarningAction Stop
$null = Connect-MsolService -Credential $cred -ErrorAction Stop -WarningAction Continue
Import-Module AzureAD
Connect-AzureAD -Credential $cred




#Gather all MSOL users and put into variable.  Stores to a file to use again if needed.
Get-Msoluser -all | select userprincipalname| export-csv C:\Users\$ENV:USERNAME\Desktop\allmsol.csv -NoTypeInformation
$all = import-csv C:\Users\$ENV:USERNAME\Desktop\allmsol.csv

cls

# Conversion Functions

function isGUID ($data)
{
	try
	{
		$guid = [GUID]$data
		return 1
	}
	catch { return 0 }
}

function isBase64 ($data)
{
	try
	{
		$decodedII = [system.convert]::frombase64string($data)
		return 1
	}
	catch { return 0 }
}

function ConvertIIToHex ($data)
{
	if (isBase64 $data)
	{
		$hex = ([system.convert]::FromBase64String("$data") | ForEach-Object ToString X2) -join ' '
		return $hex
	}
}

function ConvertGUIDToII ($data)
{
	if (isGUID $data)
	{
		$guid = [GUID]$data
		$bytearray = $guid.tobytearray()
		$ImmID = [system.convert]::ToBase64String($bytearray)
		return $ImmID
	}
}


#Set up array to use and sets the stage for the progress bar
$Output = $null
$Output = @()
$count = 0
$TOTAL = $all.count


#Gather all users' ImmutableId and mS-DS-ConsistencyGuid in hex, marks whether or not they are the same, and outputs to an array variable
Foreach ($user in $all)
{
	#Clear variables
	$Issue = 0
	$MSOLUPN = $null
	$azurelink = $null
	$SAM = $null
	
	#Set variables
	$MSOLUPN = $user.userprincipalname
	$azurelink = (Get-AzureADUser -ObjectId $MSOLUPN).OnPremisesSecurityIdentifier
	$isdirsynced = (Get-AzureADUser -ObjectId $MSOLUPN).DirSyncEnabled
	
	#Correct for cloud-only accounts
	If ($isdirsynced -like "False") { $SAM = "Cloud-only account" }
	Else { $SAM = (Get-ADUser -Filter { SID -eq $azurelink }).samaccountname }
	
	#Gather Cloud Hex
	$value = (Get-MsolUser -UserPrincipalName $MSOLUPN | select ImmutableId).ImmutableId
	$HEXIDCLOUD = ConvertIIToHex $Value
	
	#Gather AD Hex
	If ($SAM -eq "Cloud-only account" -or $SAM -eq $null) { $HEXIDAD = "Cloud-only account" }
	Else
	{
		$value = (Get-ADUser $SAM -Properties "mS-DS-ConsistencyGuid")."mS-DS-ConsistencyGuid"
		$ImmID = ConvertGUIDToII $Value
		$HEXIDAD = ConvertIIToHex $ImmID
	}
	if ($HEXIDCLOUD -ne $HEXIDAD) { $Issue = 1 }
	Else { $Issue = 0 }
	if ($HEXIDAD -eq "Cloud-only account") { $Issue = "N/A" }
	
	$Output += [pscustomobject]@{
		UPN	     = $MSOLUPN
		SAM	     = $SAM
		IsIssue  = $Issue
		HEXCloud = $HEXIDCLOUD
		HEXAD    = $HEXIDAD
	}
	
	$count = $count + 1
	$PER = ($Count / $TOTAL * 100)
	$per = $per.ToString("##.##")
	Write-progress -Activity "Getting all users" -status "$per% complete ($count/$total)" -PercentComplete $per
}

# Export to CSV for review
$Output | Export-Csv C:\Users\$ENV:USERNAME\Desktop\Immute.csv -NoTypeInformation

Finally {Clear-Variable * -ErrorAction SilentlyContinue}