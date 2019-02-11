$ModulePath = if ($PSScriptRoot) {
	$PSScriptRoot
} else {
	(Get-Module -ListAvailable TervisCustomer).ModuleBase
}
. $ModulePath\Definition.ps1

function Find-TervisCustomer {
    param (
		$Address1,
		$Postal_Code,
		$State,
        $PhoneNumber,
        $Email_Address,
		$Person_Last_Name,
		$Party_Name,
		[Switch]$ReturnEBSQueryOnly
    )
	$Parameters = $PSBoundParameters |
	ConvertFrom-PSBoundParameters -ExcludeProperty PhoneNumber, State

	if ($Address1) {
		$Parameters |
		Add-Member -MemberType ScriptProperty -Name Address1 -Force -Value {
			$Address1 | Get-AddressLinePossibility
		}
	}

	if ($PhoneNumber) {
		$PhoneNumberParameters = @{
			Transposed_Phone_Number = $PhoneNumber | Get-EBSTransposedPhoneNumberPossibility
		} 
	}

	$ParametersHash = $Parameters | ConvertTo-HashTable
    Find-EBSCustomerAccountNumber @ParametersHash @PhoneNumberParameters -ReturnQueryOnly:$ReturnEBSQueryOnly
}

function Get-EBSTransposedPhoneNumberPossibility {
	param (
        [Parameter(Mandatory,ValueFromPipeline)]$PhoneNumber
	)
	if (-not [Phonenumbers.PhoneNumberUtil]) {
		Add-Type -path "C:\Program Files\PackageManagement\NuGet\Packages\libphonenumber-csharp.8.9.7\lib\portable-net45+win8+wp8+wpa81\PhoneNumbers.dll" | Out-Null
	}
	$PhoneNumberUtil = [Phonenumbers.PhoneNumberUtil]::GetInstance()
	$Number = $PhoneNumberUtil.Parse($PhoneNumber, "US")
	#https://en.wikipedia.org/wiki/Telephone_number#/media/File:Phone_number_setup.png
	$NationalNumber = $Number.NationalNumber.ToString()
	$NationalNumberArray = $NationalNumber.ToCharArray()
	[array]::Reverse($NationalNumberArray)
	$NationalNumberReversed = -join($NationalNumberArray)

	$NationalNumberReversed,
	"$($NationalNumberReversed)1"
}

function Get-AddressSlotCombinations { 
	param (
		$CombinedSlots = @(),
		$SlotsToCombine
	)

	if (-not $SlotsToCombine) {
		$Results.Add($CombinedSlots) | Out-Null
	}

	foreach ($Slot in ($SlotsToCombine | Select-Object -First 1)) {
		if($Slot.Alternative) {
			Get-AddressSlotCombinations -CombinedSlots ($CombinedSlots + $Slot.Alternative) -SlotsToCombine ($SlotsToCombine | Select-Object -Skip 1)
			if ($Slot.Alternative.length -lt $Slot.Word.length ) {
				Get-AddressSlotCombinations -CombinedSlots ($CombinedSlots + "$($Slot.Alternative).") -SlotsToCombine ($SlotsToCombine | Select-Object -Skip 1)
			} else {
				Get-AddressSlotCombinations -CombinedSlots ($CombinedSlots + "$($Slot.Word).") -SlotsToCombine ($SlotsToCombine | Select-Object -Skip 1)
			}
		}
		Get-AddressSlotCombinations -CombinedSlots ($CombinedSlots + $Slot.Word) -SlotsToCombine ($SlotsToCombine | Select-Object -Skip 1)
	}
}

function Get-AddressLinePossibility {
    param (
        [Parameter(Mandatory,ValueFromPipeline)]$AddressLine
	)
	process {
		$AddressLineWithoutSpecialCharacters = $AddressLine | 
		Remove-StringSpecialCharacter -SpecialCharacterToKeep " "

		$Words = $AddressLineWithoutSpecialCharacters -split " "
		$Slots = $Words | ForEach-Object {
			[PSCustomObject]@{
				Word = $_
				Alternative = ($_ | Get-AddressWordAlternative)
			}
		}
		$Results = New-Object System.Collections.ArrayList
		Get-AddressSlotCombinations -SlotsToCombine $Slots
		$UncasedAddressStrings = $Results | % { $_ -join " "}
		$FinalResults = @()
		$FinalResults += $UncasedAddressStrings | % { (Get-Culture).TextInfo.ToTitleCase($_.Tolower()) }
		$FinalResults += $UncasedAddressStrings | % { $_.Tolower() }
		$FinalResults += $UncasedAddressStrings | % { $_.ToUpper() }
		$FinalResults
	}
}

function Get-AddressWordAlternative {
    param (
        [Parameter(Mandatory,ValueFromPipeline)]$Word
    )
    process {
        $AddressAlternativesHash[$Word.ToUpper()]
    }
}

function Invoke-TervisCustomerSearchDashboard {
    $CertificateFilePassword = Get-TervisPasswordstatePassword -GUID "49d35824-dcce-4fc1-98ff-ebb7ecc971de" -AsCredential |
    Select-Object -ExpandProperty Password
    
    $ScriptContent = Get-Content -Path $MyInvocation.ScriptName -Raw
    $EndpointInitializationScript = [Scriptblock]::Create($ScriptContent.Replace("Invoke-TervisCustomerSearchDashboard",""))
    $File = Get-item -Path .\certificate.pfx
    New-TervisCustomerSearchDashboard -EndpointInitializationScript $EndpointInitializationScript -CertificateFile $File -CertificateFilePassword $CertificateFilePassword
}

function New-TervisCustomerSearchDashboard {
	param (
        [ScriptBlock]$EndpointInitializationScript,
        $CertificateFile,
        $CertificateFilePassword
    )
	Get-UDDashboard | Where port -eq 10000 | Stop-UDDashboard

	$CustomerSearchInputPage = New-UDPage -Name "CustomerSearchInput" -Icon home -Content {
		New-UDInput -Title "Customer Search" -Endpoint {
			param (
				$Address1,
				$Postal_Code,
				$State,
				$PhoneNumber,
				$Email_Address,
				$Person_Last_Name,
				$Party_Name
			)
			$GUID = New-Guid | Select-Object -ExpandProperty GUID
			Set-Item -Path Cache:$GUID -Value (
				$PSBoundParameters |
				ConvertFrom-PSBoundParameters -AsHashTable |
				Remove-HashtableKeysWithEmptyOrNullValues
			)
			New-UDInputAction -RedirectUrl "/AccountResults/$GUID"			
		}
	}

	$AccountResultsPage = New-UDPage -Url "/AccountResults/:GUID" -Icon link -Endpoint {
		param(
			$GUID
		)		
		$BoundParameters = Get-Item Cache:$GUID
		$AccountNumber = Find-TervisCustomer @BoundParameters
		
		if ($AccountNumber) {
			New-UDCard -Title "Account Number(s)" -Text ($AccountNumber | Out-String)

			New-UDGrid -Title "Customers" -Headers AccountNumber, PARTY_NAME, EMAIL_ADDRESS, PhoneNumber, ADDRESS1, CITY, STATE, POSTAL_CODE -Properties AccountNumber, PARTY_NAME, EMAIL_ADDRESS, PhoneNumber, ADDRESS1, CITY, STATE, POSTAL_CODE -Endpoint {
				$AccountNumber | 
				% { 
					$Account = Get-EBSTradingCommunityArchitectureCustomerAccount -Account_Number $_
					$Organization = Get-EBSTradingCommunityArchitectureOrganizationObject -Party_ID $Account.Party_ID
					$Organization | 
					Select-Object -Property PARTY_NAME, EMAIL_ADDRESS, @{
						Name = "PhoneNumber"
						Expression = {
							"$($_.PRIMARY_PHONE_COUNTRY_CODE)$($_.PRIMARY_PHONE_AREA_CODE)$($_.PRIMARY_PHONE_NUMBER)"
						}
					}, ADDRESS1, CITY, STATE, POSTAL_CODE, @{
						Name = "AccountNumber"
						Expression = {New-UDLink -Text $Account.ACCOUNT_NUMBER -Url "/AccountDetails/$($Account.ACCOUNT_NUMBER)"}
					}
				} |
				Out-UDGridData
			}
		} else {
			New-UDCard -Title "No Account Number(s) found that match your criteria"
		}
		New-UDCard -Title "Query" -Content {
			New-UDLink -Text Query -Url /CustomerSearchSQLQuery/$GUID
		}		
	}

	$CustomerSearchSQLQueryPage = New-UDPage -Url "/CustomerSearchSQLQuery/:GUID" -Icon link -Endpoint {
		param(
			$GUID
		)		
		$BoundParameters = Get-Item Cache:$GUID
		$Query = Find-TervisCustomer @BoundParameters -ReturnEBSQueryOnly
		
		if ($Query) {
			New-UDCard -Title "Query"
			New-UDHtml -Markup @"
<pre>
$($Query | out-string)
</pre>
"@
		} else {
			New-UDCard -Title "No Query returned"
		}
	}

	$AccountDetailsPage = New-UDPage -Url "/AccountDetails/:AccountNumber" -Icon link -Endpoint {
		param (
			$AccountNumber
		)
		$Account = Get-EBSTradingCommunityArchitectureCustomerAccount -Account_Number $AccountNumber
		$Organization = Get-EBSTradingCommunityArchitectureOrganizationObject -Party_ID $Account.Party_ID
		
		Remove-TypeData System.Array -ErrorAction SilentlyContinue
		New-UDHtml -Markup @"
<pre>
$($Organization | ConvertTo-Yaml)
</pre>
"@
	}
	
	$EndpointInitializationScript |
    Out-File -FilePath .\InitilizationModule.psm1

    $InitilizationModuleFullName = Get-Item -Path .\InitilizationModule.psm1 |
    Select-Object -ExpandProperty FullName
    
    $EndpointInitialization = New-UDEndpointInitialization -Module @( $InitilizationModuleFullName )

	$Dashboard = New-UDDashboard -Pages @(
		$CustomerSearchInputPage,
		$AccountResultsPage,
		$CustomerSearchSQLQueryPage,
		$AccountDetailsPage
	) -Title "Tervis Customer Search" -EndpointInitialization $EndpointInitialization

	Start-UDDashboard -Dashboard $Dashboard -Port 10000 -CertificateFile $CertificateFile -CertificateFilePassword $CertificateFilePassword -Wait
}

#https://github.com/lazywinadmin/PowerShell/blob/master/TOOL-Remove-StringSpecialCharacter/Remove-StringSpecialCharacter.ps1
function Remove-StringSpecialCharacter
{
<#
.SYNOPSIS
	This function will remove the special character from a string.
	
.DESCRIPTION
	This function will remove the special character from a string.
	I'm using Unicode Regular Expressions with the following categories
	\p{L} : any kind of letter from any language.
	\p{Nd} : a digit zero through nine in any script except ideographic 
	
	http://www.regular-expressions.info/unicode.html
	http://unicode.org/reports/tr18/
.PARAMETER String
	Specifies the String on which the special character will be removed
.SpecialCharacterToKeep
	Specifies the special character to keep in the output
.EXAMPLE
	PS C:\> Remove-StringSpecialCharacter -String "^&*@wow*(&(*&@"
	wow
.EXAMPLE
	PS C:\> Remove-StringSpecialCharacter -String "wow#@!`~)(\|?/}{-_=+*"
	
	wow
.EXAMPLE
	PS C:\> Remove-StringSpecialCharacter -String "wow#@!`~)(\|?/}{-_=+*" -SpecialCharacterToKeep "*","_","-"
	wow-_*
.NOTES
	Francois-Xavier Cat
	@lazywinadm
	www.lazywinadmin.com
	github.com/lazywinadmin
#>
	[CmdletBinding()]
	param
	(
		[Parameter(ValueFromPipeline)]
		[ValidateNotNullOrEmpty()]
		[Alias('Text')]
		[System.String[]]$String,
		
		[Alias("Keep")]
		#[ValidateNotNullOrEmpty()]
		[String[]]$SpecialCharacterToKeep
	)
	PROCESS
	{
		IF ($PSBoundParameters["SpecialCharacterToKeep"])
		{
			$Regex = "[^\p{L}\p{Nd}"
			Foreach ($Character in $SpecialCharacterToKeep)
			{
				IF ($Character -eq "-"){
					$Regex +="-"
				} else {
					$Regex += [Regex]::Escape($Character)
				}
				#$Regex += "/$character"
			}
			
			$Regex += "]+"
		} #IF($PSBoundParameters["SpecialCharacterToKeep"])
		ELSE { $Regex = "[^\p{L}\p{Nd}]+" }
		
		FOREACH ($Str in $string)
		{
			Write-Verbose -Message "Original String: $Str"
			$Str -replace $regex, ""
		}
	} #PROCESS
}

function Install-TervisCustomer {
	param (
		$ComputerName,
		$EnvironmentName
	)
	$PasswordstateAPIKey = Get-TervisPasswordstatePassword -Guid "2a45b43c-b4d1-49c8-879a-c708716c9c7b" |
    Select-Object -ExpandProperty Password

	Install-PowerShellApplicationUniversalDashboard @PSBoundParameters -ModuleName TervisCustomer -TervisModuleDependencies InvokeSQL,
		OracleE-BusinessSuitePowerShell,
		PasswordstatePowerShell,
		TervisMicrosoft.PowerShell.Utility,
		TervisOracleE-BusinessSuitePowerShell,
		TervisPasswordstatePowerShell,
		TervisGithub,
		TervisUniversalDashboard,
		WebServicesPowerShellProxyBuilder,
		TervisMicrosoft.PowerShell.Security,
		TervisCustomer -PowerShellGalleryDependencies @{
			Name = "powershell-yaml"
		}, 
		@{
				Name = "UniversalDashboard"
				RequiredVersion="2.2.1"
		} -PowerShellNugetDependencies @{
			Name = "Oracle.ManagedDataAccess.Core"
		},
		@{
			Name = "libphonenumber-csharp"
			SkipDependencies = $true
		} -CommandString @"
# Hopefully the below is not still needed, if it is we will have to figure out a way to import the correct directory that contains UD
#`$CacheDrive = Get-PSDrive -Name Cache -ErrorAction SilentlyContinue
#if (-not `$CacheDrive) {
#	Import-Module UniversalDashboard
#}

if (-Not `$Cache:EBSPowershellConfiguration ) {
	`$Cache:EBSPowershellConfiguration = Get-TervisEBSPowershellConfiguration -Name $EnvironmentName
}

Set-EBSPowershellConfiguration -Configuration `$Cache:EBSPowershellConfiguration
Invoke-TervisCustomerSearchDashboard
"@ -UseTLS -DashboardPassswordstateAPIKey $PasswordstateAPIKey -Port 10000
}