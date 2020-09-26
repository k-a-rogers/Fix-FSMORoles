Function Take-Output {
	Param(
		[Parameter(Mandatory=$true)]  
		[String]$string,
		[Parameter(Mandatory=$false)]  
		[String]$color
	)
	if (!$color) {
		$color="white"
	}
	Write-Host $string -foregroundcolor $color
	$string | Out-File -Filepath $script:logfile -Append
}

Function Check-FSMORoles {
	cls
	$forestinfo=Get-ADforest
	
	$script:broken=@()
	
	$checked=@()

	# Display Forest-level FSMO roles
	Take-Output -String "Forest-level FSMO roles:`n`n"
	if ($forestinfo.SchemaMaster -match "\\0ADEL:") {
		$color="red"
	} else {
		$color="green" 
	}
	Take-Output -String "Schema Master:`t$($forestinfo.SchemaMaster)`n" -color $color
	Remove-variable -name color -force -erroraction silentlycontinue

	if ($forestinfo.DomainNamingMaster -match "\\0ADEL:") {
		$color="red"
	} else {
		$color="green" 
	}
	Take-Output -String "Domain Naming Master:`t$($forestinfo.DomainNamingMaster)`n" -color $color
	Remove-variable -name color -force -erroraction silentlycontinue

	# Get  Application Partitions
	$partitions=$forestinfo | Select -Expand ApplicationPartitions

	# Get Domains
	$domains=$forestinfo | Select -Expand domains

	Take-Output -String "Domain-level FSMO roles:`n"

	foreach ($domain in $domains) {
		Take-Output -String "Domain:`t$($domain)`n"
		$domaininfo=Get-ADDomain $domain
		if ($domaininfo.PDCEmulator -match "\\0ADEL:") {
			$color="red"
		} else {
			$color="green" 
		}	
		Take-Output -String "`nPDC Emulator:`t$($domaininfo.PDCEmulator)`n" -color $color
		Remove-variable -name color -force -erroraction silentlycontinue
		if ($domaininfo.RIDMaster -match "\\0ADEL:") {
			$color="red"
		} else {
			$color="green" 
		}
		Take-Output -String "RID Master:`t$($domaininfo.RIDMaster)`n" -color $color
		Remove-variable -name color -force -erroraction silentlycontinue
		if ($domaininfo.InfrastructureMaster -match "\\0ADEL:") {
			$color="red"
		} else {
			$color="green" 
		}
		Take-Output -String "Infrastructure Master:`t$($domaininfo.InfrastructureMaster)`n" -color $color
		Remove-variable -name color -force -erroraction silentlycontinue
		
		# Application partition checks go here to ensure a server on the right domain can be used for the checks.
		Take-Output -String "Domain application partition FSMO roles:"
		foreach ($partition in ($partitions | ? {$_ -match $($domaininfo.DistinguishedName)})) {
			$identity="CN=Infrastructure,"+$partition
			try {
				$obj=Get-ADObject -identity $identity -Properties fSMORoleOwner -Server $($domaininfo.PDCEmulator) -ErrorAction Stop
				if ($obj.fSMORoleOwner -match "\\0ADEL:") {
					$color="red"
					$faulty=New-Object System.Object
					$faulty | Add-Member -MemberType NoteProperty -Name "Level" -value "Domain" -Force
					$faulty | Add-Member -MemberType NoteProperty -Name "Domain" -value $domain -Force
					$faulty | Add-Member -MemberType NoteProperty -Name "Role" -value "InfrastructureMaster" -Force
					$faulty | Add-Member -MemberType NoteProperty -Name "FQDN" -value $obj.DistinguishedName -Force					
					$faulty | Add-Member -MemberType NoteProperty -Name "RoleOwner" -value $obj.fSMORoleOwner -Force
					$script:broken+=($faulty)
					Remove-Variable -name faulty -force -erroraction SilentlyContinue
				} else {
					$color="green"
				}
				Take-Output -String "$($partition)`n$($obj.fSMORoleOwner)`n" -color $color
			} catch {
				Take-Output -String "No Infrastructure Master role found for partition $($partition).`n"
			}
			if (!($checked | ? {$_ -eq $($domaininfo.DistinguishedName)})) {
				$checked+=$($partition)
			}
		}
	
		if (!($checked | ? {$_ -eq $($domaininfo.DistinguishedName)})) {
			$checked+=$($domaininfo.DistinguishedName)
		}	
	}

	
	# Get Naming Contexts 
	$NCs=Get-ADRootDSE | Select -Expand NamingContexts

	# Check for Naming Contexts that are not also Domains or Application Partitions, enumerate them and check for an Infrastructure Master role
	Take-Output -String "Naming Context FSMO Roles:`n"

	foreach ($object in (Compare-Object -ReferenceObject $checked -DifferenceObject $NCs -IncludeEqual  | ? {$_.SideIndicator -eq "=>"})) {
		$identity="CN=Infrastructure,"+$($Object.InputObject)
		try {
			$obj=Get-ADObject -identity $identity -Properties fSMORoleOwner -ErrorAction Stop
			if ($obj.fSMORoleOwner -match "\\0ADEL:") {
				$color="red"
				$faulty=New-Object System.Object
				$faulty | Add-Member -MemberType NoteProperty -Name "Level" -value "Domain" -Force
				$faulty | Add-Member -MemberType NoteProperty -Name "Domain" -value $domain -Force
				$faulty | Add-Member -MemberType NoteProperty -Name "Role" -value "InfrastructureMaster" -Force
				$faulty | Add-Member -MemberType NoteProperty -Name "FQDN" -value $obj.DistinguishedName -Force					
				$faulty | Add-Member -MemberType NoteProperty -Name "RoleOwner" -value $obj.fSMORoleOwner -Force
				$script:broken+=($faulty)
				Remove-Variable -name faulty -force -erroraction SilentlyContinue
			} else {
				$color="green"
			}
			Take-Output -String "$($Object.InputObject)`n$($obj.fSMORoleOwner)`n" -color $color
		} catch {
			Take-Output -String "No Infrastructure Master role found for partition $($partition).`n"
		}	
	}
	# Loop for checking faulty entries and fixing them.
	if ($script:broken) {
		foreach ($fault in $script:broken) {
			Take-Output -String "Faulty fSMO Role Owner set at:`n$($fault.FQDN).`n"
			for ($i=2; $i -lt $(($fault.RoleOwner -split ",").count); $i++) {
				$suffix+=","+$(($fault.RoleOwner -split ",")[$i])
			}
			$pdc=((Get-ADdomain $fault.Domain).PDCEmulator -split "\.")[0]
			$newFSMO="CN=NTDS Settings,CN="+$pdc+$suffix
			try {
				Get-ADobject -Identity $newFSMO -ErrorAction Stop | Out-Null
				Take-Output -String "Proposed replacement fSMO Role Owner is:`n$($newFSMO)"
				$proceed=Read-Host("Update specified fSMO Role Owner with replacement? Y/N")
			} catch {
				Write-Host "Unable to determine a suitable replacement fSMO Role Owner, please investigate!" -foregroundcolor red
			}
			if ($proceed -eq "Y") {
				try {
					$target=Get-ADobject -Identity $fault.FQDN -Properties fSMORoleOwner -server $pdc
					$target.fsMORoleOwner=$newFSMO
					Set-ADObject -Instance $target -ErrorAction Stop -Server $pdc
					Take-Output -String "fSMO Role Owner updated successfully!`n`n" -color green
				} catch {
					Take-Output -String "fSMO Role Owner could not be updated, error message was:`n$($_.Exception.Message)`n`n" -color red
				}
				Remove-Variable -Name target -Force -erroraction SilentlyContinue
			} else {
				Take-Output -String "No changes have been made to this fSMO Role Owner.`n`n" -color yellow
			}
			Remove-Variable -name pdc,suffix,newFSMO,proceed -Force -ErrorAction SilentlyContinue
		}
	} else {
		Take-Output -String "All fSMO Role holders are valid, no changes required.`n`n" -color green
	}
}

###################
# Script body
###################

# Define and initialise logfile.
If (!(Test-Path "C:\tmp")) {
	mkdir "C:\tmp"
}
$script:logfile="C:\tmp\$(Get-Date -Format `"yyyy-MM-dd`")"+"_Check-FSMORoles.log"
Take-Output -String $((Get-Date -format "yyyy-MM-dd HH:mm")+": Starting Check-FSMORoles run...")

ipmo ActiveDirectory
Check-FSMORoles