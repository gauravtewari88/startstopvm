<#
.SYNOPSIS
	Start/Stop Azure VM in parallel on schedule based on two VM Tags (PowerOn/PowerOff).
.DESCRIPTION
	This Azure Automation PowerShell Workflow type Runbook Start/Stop Azure VM in parallel on schedule based on two VM Tags (PowerOn/PowerOff).
#>

Workflow StartStopVM
{
	Param (
		[Parameter(Mandatory, Position = 1)]
		[string]$AzureSubscription
		 ,
		[Parameter(Mandatory, Position = 2)]
		[string]$AzureResourceGroup
		 ,
		#[System.TimeZoneInfo]::GetSystemTimeZones() |ft -au
		[Parameter(Mandatory = $false, Position = 3)]
		[string]$AzureVmTimeZone = 'Singapore Standard Time'
	)
	


	$ErrorActionPreference = 'Stop'
	$Conn = Get-AutomationConnection -Name AzureRunAsConnection; $Conn    
    Connect-AzureRmAccount -ServicePrincipal -Tenant $Conn.TenantID -ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint
    $AzureContext = Select-AzureRmSubscription -SubscriptionId $Conn.SubscriptionID; $AzureContext
    Select-AzureRmSubscription -SubscriptionId $AzureContext.Subscription.Id    


	#$azCredential = Get-AutomationPSCredential -Name $AzureCredentialAsset
	#$null = Login-AzureRmAccount -Credential $azCredential
	#$null = Set-AzureRmContext -SubscriptionName $AzureSubscription
	
	$AzVms = Get-AzureRmVm -ResourceGroupName $AzureResourceGroup |
	select Name, Tags, @{ N = 'PowerState'; E = { (Get-AzureRmVM -Name $_.Name -ResourceGroupName $_.ResourceGroupName -Status |
	select -expand Statuses | ? { $_.Code -match 'PowerState/' } |
	select @{ N = 'PowerState'; E = { $_.Code.Split('/')[1] } }).PowerState } } | sort Name
	
	Foreach -Parallel ($AzVm in $AzVms)
	{
		Try 
		{
			### Running VM ###
			if ($AzVm.PowerState -eq 'running')
			{
				### Flag to NOT PowerOff ###
				if ($AzVm.Tags.PowerOff -ne '22:22:22')
				{
					$azTime = [datetime]::Now
					$TimeShort = $azTime.ToString('HH:mm')
					$TimeVm = [System.TimeZoneInfo]::ConvertTimeFromUtc($TimeShort, [System.TimeZoneInfo]::FindSystemTimeZoneById($AzureVmTimeZone))
					
					### 00:00---On+++Off---00:00 ###
					if ([datetime]$AzVm.Tags.PowerOn -lt [datetime]$AzVm.Tags.PowerOff)
					{
						if ($TimeVm -gt [datetime]$AzVm.Tags.PowerOff -or $TimeVm -lt [datetime]$AzVm.Tags.PowerOn)
						{
							if ($WhatIf) { $Status = 'Simulation' }
							else
							{
								$Status = (Stop-AzureRmVm -Name $AzVm.Name -ResourceGroupName $AzureResourceGroup -Force).StatusCode
							}
							$Execution = 'Stopped'
						}
						else { $Execution = 'NotRequired' }
						
					### 00:00+++Off---On+++00:00 ###
					}
					else
					{
						if ($TimeVm -gt [datetime]$AzVm.Tags.PowerOff -and $TimeVm -lt [datetime]$AzVm.Tags.PowerOn)
						{
							if ($WhatIf) { $Status = 'Simulation' }
							else
							{
								$Status = (Stop-AzureRmVm -Name $AzVm.Name -ResourceGroupName $AzureResourceGroup -Force).StatusCode
							}
							$Execution = 'Stopped'
						}
						else { $Execution = 'NotRequired' }
					}
				}
			}
			### Not running VM (stopped/deallocated/suspended etc.) ###
			else
			{
				### Flag to NOT PowerOn ###
				if ($AzVm.Tags.PowerOn -ne '11:11:11')
				{
					$azTime = [datetime]::Now
					$TimeShort = $azTime.ToString('HH:mm')
					$TimeVm = [System.TimeZoneInfo]::ConvertTimeFromUtc($TimeShort, [System.TimeZoneInfo]::FindSystemTimeZoneById($AzureVmTimeZone))
					
					### 00:00---On+++Off---00:00 ###
					if ([datetime]$AzVm.Tags.PowerOn -lt [datetime]$AzVm.Tags.PowerOff)
					{
						if ($TimeVm -gt [datetime]$AzVm.Tags.PowerOn -and $TimeVm -lt [datetime]$AzVm.Tags.PowerOff)
						{
							if ($WhatIf) { $Status = 'Simulation' }
							else
							{
								$Status = (Start-AzureRmVm -Name $AzVm.Name -ResourceGroupName $AzureResourceGroup).StatusCode
							}
							$Execution = 'Started'
						}
						else { $Execution = 'NotRequired' }
						
					### 00:00+++Off---On+++00:00 ###
					}
					else
					{
						if ($TimeVm -gt [datetime]$AzVm.Tags.PowerOn -or $TimeVm -lt [datetime]$AzVm.Tags.PowerOff)
						{
							if ($WhatIf) { $Status = 'Simulation' }
							else
							{
								$Status = (Start-AzureRmVm -Name $AzVm.Name -ResourceGroupName $AzureResourceGroup).StatusCode
							}
							$Execution = 'Stopped'
						}
						else { $Execution = 'NotRequired' }
					}
				}
			}
			$Prop = [ordered]@{
				AzureVM       = $AzVm.Name
				ResourceGroup = $AzureResourceGroup
				PowerState    = (Get-Culture).TextInfo.ToTitleCase($AzVm.PowerState)
				PowerOn       = $AzVm.Tags.PowerOn
				PowerOff      = $AzVm.Tags.PowerOff
				StateChange   = $Execution
				StatusCode    = $Status
				TimeStamp     = $TimeVm
			}
		}
		Catch
		{
			$Prop = [ordered]@{
				AzureVM       = $AzVm.Name
				ResourceGroup = $AzureResourceGroup
				PowerState    = (Get-Culture).TextInfo.ToTitleCase($AzVm.PowerState)
				PowerOn       = $AzVm.Tags.PowerOn
				PowerOff      = $AzVm.Tags.PowerOff
				StateChange   = 'Unknown'
				StatusCode    = 'Error'
				TimeStamp     = $TimeVm
			}
		}
		Finally
		{
			$Obj = New-Object PSObject -Property $Prop
			Write-Output -InputObject $Obj
		}	
	}
} #End Workflow Apply-AzVmPowerStatePolicy