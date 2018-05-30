$ModulePath = (Get-Module -ListAvailable TervisCustomer).ModuleBase
. $ModulePath\Definition.ps1

function Find-TervisCustomer {
    param (
        $Address1,
        $PhoneNumber,
        $EmailAddress,
        $Firstame,
        $LastName
    )
	$AddressLinePossibilities = $Address1 | Get-AddressLinePossibility
    Find-EBSCustomerAccountNumber -Address1 $AddressLinePossibilities
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

	$Dashboard = New-UDDashboard -Title "Tervis Customer Search" -Content {
		New-UDInput -Title "Select me" -Endpoint {
			param(
				[ValidateSet("Yes", "No", "Don't care")]$Opinion,
				[String]$Address1
			)
			$EBSPowerShellConfiguration = Get-EBSPowershellConfiguration
			if (-Not $EBSPowerShellConfiguration) { Set-TervisEBSEnvironment -Name Delta}

			$Count++
			if ($Address1) {
				$AccountNumber = Find-TervisCustomer -Address1 $Address1
			}
			New-UDInputAction -Toast "You selected: $Opinion $Count $($AccountNumber| out-string)"
			
			if ($AccountNumber) {
				New-UDInputAction -Content @(
					New-UDCard -Title "Account Number(s)" -Text ($AccountNumber | Out-String)
				)
			}			
		} -FontColor "black"
	}
	Start-UDDashboard -Dashboard $Dashboard -Port 10000 -AllowHttpForLogin

#### Query String test
Get-UDDashboard | Where port -eq 10000 | Stop-UDDashboard

	$CustomerSearchInputPage = New-UDPage -Name "CustomerSearchInput" -Icon home -Content {
		New-UDInput -Title "Customer Search" -Endpoint {
			param(
				[String]$Address1
			)
			if ($Address1) {
				$QueryString = @{Address1=$Address1} | ConvertTo-URLEncodedQueryStringParameterString
				New-UDInputAction -RedirectUrl "/AccountResults/?$QueryString"
			}
		}
	}

	$AccountResultsPage = New-UDPage -Url "/AccountResults/" -Icon link -Endpoint {
		Wait-Debugger
		$Address1 = $Request.Query["Address1"]

		if ($Address1) {
			$AccountNumber = Find-TervisCustomer -Address1 $Address1
		}
		
		if ($AccountNumber) {
			New-UDCard -Title "Account Number(s)" -Text ($AccountNumber | Out-String)
			
			
			New-UDTable -Title "Account Number" -Headers @("Account Number") -Endpoint {
				$AccountNumber | 
				% { [psCustomObject]@{AccountNumber = $_} } |
				Out-UDTableData -Property AccountNumber
			}
			
			New-UDGrid -Title "Customers" -Headers AccountNumber, PARTY_NAME, ADDRESS1, CITY, STATE, POSTAL_CODE -Properties AccountNumber, PARTY_NAME, ADDRESS1, CITY, STATE, POSTAL_CODE -Endpoint {
				$AccountNumber | 
				% { 
					$Account = Get-EBSTradingCommunityArchitectureCustomerAccount -Account_Number $_
					$Organization = Get-EBSTradingCommunityArchitectureOrganizationObject -Party_ID $Account.Party_ID
					$Organization | 
					Select-Object -Property PARTY_NAME, ADDRESS1, CITY, STATE, POSTAL_CODE, @{
						Name = "AccountNumber"
						Expression = {$Account.ACCOUNT_NUMBER}
					}
				} |
				Out-UDGridData
			}

			New-UDCollection -Header "Account Number" -Content {
				$AccountNumber | ForEach-Object {
					New-UDCollectionItem -Content { $_ }
				}
			}
		}
	}
	$Dashboard = New-UDDashboard -Pages @($CustomerSearchInputPage, $AccountResultsPage) -Title "Tervis Customer Search" -EndpointInitializationScript {
		if (-Not $Cache:EBSPowershellConfiguration ) {
			$Cache:EBSPowershellConfiguration = Get-TervisEBSPowershellConfiguration -Name Delta
		}
		Set-EBSPowershellConfiguration -Configuration $Cache:EBSPowershellConfiguration
	}
	Start-UDDashboard -Dashboard $Dashboard -Port 10000 -AllowHttpForLogin
####



	Get-UDDashboard | Where port -eq 10000 | Stop-UDDashboard

	$CustomerSearchInputPage = New-UDPage -Name "CustomerSearchInput" -Icon home -Content {
		New-UDInput -Title "Customer Search" -Endpoint {
			param(
				[String]$Address1
			)
			if ($Address1) {
				New-UDInputAction -RedirectUrl "/AccountResults/$Address1"
			}
		}
	}

	$AccountResultsPage = New-UDPage -Url "/AccountResults/:Address1" -Icon link -Endpoint {
		param (
			$Address1
		)
		
		if ($Address1) {
			$AccountNumber = Find-TervisCustomer -Address1 $Address1
		}
		
		if ($AccountNumber) {
			New-UDCard -Title "Account Number(s)" -Text ($AccountNumber | Out-String)
			
			
			New-UDTable -Title "Account Number" -Headers @("Account Number") -Endpoint {
				$AccountNumber | 
				% { [psCustomObject]@{AccountNumber = $_} } |
				Out-UDTableData -Property AccountNumber
			}
			
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

			New-UDCollection -Header "Account Number" -Content {
				$AccountNumber | ForEach-Object {
					New-UDCollectionItem -Content { $_ }
				}
			}
		}
	}

	$AccountDetailsPage = New-UDPage -Url "/AccountDetails/:AccountNumber" -Icon link -Endpoint {
		param (
			$AccountNumber
		)
		$Account = Get-EBSTradingCommunityArchitectureCustomerAccount -Account_Number $AccountNumber
		$Organization = Get-EBSTradingCommunityArchitectureOrganizationObject -Party_ID $Account.Party_ID
		
		
		#New-UDHtml -Markup (
		#	$Organization | FL | out-string | Replace-ContentValue -OldValue "`r`n" -NewValue "<br>"
		#)
		Remove-TypeData System.Array
		New-UDHtml -Markup @"
		<pre>
		$($Organization | ConvertTo-Json -Depth 100)
		</pre>
"@

		#New-UDCard -Title "Account Details" -Text (
		#	$Organization | FL | out-string | Replace-ContentValue -OldValue "`r`n" -NewValue "<br>"
		#)
	}
	
	$Dashboard = New-UDDashboard -Pages @($CustomerSearchInputPage, $AccountResultsPage, $AccountDetailsPage) -Title "Tervis Customer Search" -EndpointInitializationScript {
		if (-Not $Cache:EBSPowershellConfiguration ) {
			$Cache:EBSPowershellConfiguration = Get-TervisEBSPowershellConfiguration -Name Delta
		}
		Set-EBSPowershellConfiguration -Configuration $Cache:EBSPowershellConfiguration
	}

	Start-UDDashboard -Dashboard $Dashboard -Port 10000 -AllowHttpForLogin


    $dashboard = New-UDDashboard -Title "Tervis Customer Search" -Content {
        New-UDInput -Title "New Work Order" -Id "Form" -DebugEndpoint -Endpoint {
			param (
				$Address1,
				$PhoneNumber,
				$EmailAddress,
				$Firstame,
				$LastName
			)
			$EBSPowerShellConfiguration = Get-EBSPowershellConfiguration
			if (-Not $EBSPowerShellConfiguration) { Set-TervisEBSEnvironment -Name Delta}
			Find-TervisCustomer @PSBoundParameters
		}
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

