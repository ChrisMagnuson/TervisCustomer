$ModulePath = (Get-Module -ListAvailable TervisCustomer).ModuleBase
. $ModulePath\Definition.ps1

function Find-TervisCustomer {
    param (
		$Address1,
		$Postal_Code,
		$State,
        $PhoneNumber,
        $Email_Address,
        $Person_First_Name,
        $Person_Last_Name
    )
	$Parameters = $PSBoundParameters | 
	ConvertFrom-PSBoundParameters -ExcludeProperty PhoneNumber, State

	if ($Address1) {
		$Parameters |
		Add-Member -MemberType ScriptProperty -Name Address1 -Force -Value {
			$Address1 | Get-AddressLinePossibility
		}
	}

	$ParametersHash = $Parameters | ConvertTo-HashTable
    Find-EBSCustomerAccountNumber @ParametersHash
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

function New-TervisCustomerSearchDashboard {
	Get-UDDashboard | Where port -eq 10000 | Stop-UDDashboard

	$CustomerSearchInputPage = New-UDPage -Name "CustomerSearchInput" -Icon home -Content {
		New-UDInput -Title "Customer Search" -Endpoint {
			param(
				$Address1,
				$FirstName,
				$LastName,
				$PhoneNumber,
				$EmailAddress
			)
			$GUID = New-Guid | Select-Object -ExpandProperty GUID
			Set-Item -Path Cache:$GUID -Value $PSBoundParameters
			New-UDInputAction -RedirectUrl "/AccountResults/$GUID"			
		}
	}

	$AccountResultsPage = New-UDPage -Url "/AccountResults/:GUID" -Icon link -Endpoint {
		param(
			$GUID
		)
		$BoundParameters = Get-Item Cache:$GUID
		$AccountNumber = Find-TervisCustomer -Email_Address $BoundParameters["EmailAddress"]
		
		if ($AccountNumber) {
			New-UDCard -Title "Account Number(s)" -Text ($AccountNumber | Out-String)

			New-UDGrid -Title "Customers" -Headers AccountNumber, PARTY_NAME, ADDRESS1, CITY, STATE, POSTAL_CODE -Properties AccountNumber, PARTY_NAME, ADDRESS1, CITY, STATE, POSTAL_CODE -Endpoint {
				$AccountNumber | 
				% { 
					$Account = Get-EBSTradingCommunityArchitectureCustomerAccount -Account_Number $_
					$Organization = Get-EBSTradingCommunityArchitectureOrganizationObject -Party_ID $Account.Party_ID
					$Organization | 
					Select-Object -Property PARTY_NAME, ADDRESS1, CITY, STATE, POSTAL_CODE, @{
						Name = "AccountNumber"
						Expression = {New-UDLink -Text $Account.ACCOUNT_NUMBER -Url "/AccountDetails/$($Account.ACCOUNT_NUMBER)"}
					}
				} |
				Out-UDGridData
			}
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
	
	$Dashboard = New-UDDashboard -Pages @($CustomerSearchInputPage, $AccountResultsPage, $AccountDetailsPage) -Title "Tervis Customer Search" -EndpointInitializationScript {
		if (-Not $Cache:EBSPowershellConfiguration ) {
			$Cache:EBSPowershellConfiguration = Get-TervisEBSPowershellConfiguration -Name Delta
		}
		Set-EBSPowershellConfiguration -Configuration $Cache:EBSPowershellConfiguration
	}

	Start-UDDashboard -Dashboard $Dashboard -Port 10000 -AllowHttpForLogin

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

