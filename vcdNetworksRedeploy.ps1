#requires -version 4
	Param (
	[Parameter(Mandatory = $False, Position = 1)]
	[ValidateNotNullOrEmpty()]
	[string]$CSVInputFile,
	
	[Parameter(Mandatory = $True, Position = 2)]
	[ValidateNotNullOrEmpty()]
	[string]$vcdServer,
	
	[Parameter(Mandatory = $False, Position = 3)]
	[ValidateNotNullOrEmpty()]
	[string[]]$Orgs,
	
	[Parameter(Mandatory = $False, Position = 4)]
	[ValidateNotNullOrEmpty()]
	[string[]]$Exclude = "none"
	
	)

#Region Functions

Function getResetHref {
	Param (
	[Parameter(Mandatory = $True, Position = 1)]
	[ValidateNotNullOrEmpty()]
	[string]$networkHref,
	
	[Parameter(Mandatory = $True, Position = 2)]
	[ValidateNotNullOrEmpty()]
	[string]$vcdServer,
	
	[Parameter(Mandatory = $False, Position = 3)]
	[ValidateNotNullOrEmpty()]
	[bool]$returnId = $False
	)
	
	# extracting the edge id from href url format https://<vCD>/api/network/f2dd7530-1614-435c-b3a1-f7c329c6221f
	$slashIndex = $networkHref.LastIndexOf("/")
	$netId = $networkHref.Substring($slashIndex+1)
								
	# Set the network href reset url
	$networkResetHref = "https://" + $vcdServer + "/api/admin/network/" + $netId + "/action/reset"
	Write-Log $logFile 0 "full" "Network reset href url is: $networkResetHref"
	
	# giving user option to chose is they want just the id of full href in return
	if ($returnId) { return $netId }
	else { return $networkResetHref }
}

Function Write-Log {
	
	[CmdletBinding()]
	Param(
	[Parameter(Mandatory = $True, Position=1)]
	[ValidateNotNullOrEmpty()]
	[string]$logFile,
		
	[Parameter(Mandatory = $False, Position=2)]
	[int]$severity = 0,

	[Parameter(Mandatory = $False, Position=3)]
	[string]$type = "terse",
	   
	[Parameter(Mandatory = $True, Position=4)]
	[ValidateNotNullOrEmpty()]
	[string]$logMessage
	) 

	$timestamp = (Get-Date -Format ("[dd-MM-yyyy HH:mm:ss] "))
	$ui = (Get-Host).UI.RawUI

	switch ($severity) {

			{$_ -eq 1} {$ui.ForegroundColor = "red"; $type ="full"; $LogEntry = $timestamp + ":Error: " + $logMessage; break;}
			{$_ -eq 0} {$ui.ForegroundColor = "green"; $LogEntry = $timestamp + ":Info: " + $logMessage; break;}
			{$_ -eq 2} {$ui.ForegroundColor = "yellow"; $LogEntry = $timestamp + ":Warning: " + $logMessage; break;}
			{$_ -eq 3} {$ui.ForegroundColor = "cyan"; $LogEntry = $timestamp + ":Info: " + $logMessage; break;}
			{$_ -eq 4} {$ui.ForegroundColor = "gray"; $LogEntry = $timestamp + ":Global: " + $logMessage; break;}

	}
	switch ($type) {
	   		"console"	{
				Write-Output $LogEntry
				break
			}
			"full"	{
				Write-Host $LogEntry
				$LogEntry | Out-file $logFile -Append;
				break;
			}
			"logonly"	{
				$LogEntry | Out-file $logFile -Append
				break
			}
		 
	}

	$ui.ForegroundColor = "white" 

} 

Function Catch-Error {
	[CmdletBinding()]
	Param(
	[Parameter(Mandatory = $True, Position = 1)]
	[ValidateNotNullOrEmpty()]
	[string]$errorMessage
	)   
	Write-Log $logFile 1 "full" "There has been an error, the error message is: **** $errorMessage ****"
}

Function Rewrite-url {
	[CmdletBinding()]
	Param(
	   [Parameter(Mandatory = $True, Position = 1)]
	   [ValidateNotNullOrEmpty()]
	   [string]$url,
	   
	   [Parameter(Mandatory = $True, Position = 2)]
	   [ValidateNotNullOrEmpty()]
	   [string]$baseUrl
	)
	
	$arrayURL = [uri]$url
	$basearrayURL = [uri]$baseUrl
	
	# check if the base url and the given url have the same host. If not modify with the user base url
	if($arrayURL.Host -ne $basearrayURL.Host) {
		$endurl = $arrayURL.AbsolutePath
		$returnurl = "https://$vcdServer" + $endurl
		#write-host "Change url $url to $returnurl"
	}
	else {
		$returnurl=$url
	}
	return $returnurl
}

Function vAppNetworkReset {

	[CmdletBinding()]
	Param(
	[Parameter(Mandatory = $True, Position = 1)]
	[ValidateNotNullOrEmpty()]
	[string]$orgName,
	
	[Parameter(Mandatory = $True, Position = 2)]
	[ValidateNotNullOrEmpty()]
	[string]$vAppName,
	
	[Parameter(Mandatory = $True, Position = 3)]
	[ValidateNotNullOrEmpty()]
	[string]$vseName,
	
	[Parameter(Mandatory = $True, Position = 4)]
	[ValidateNotNullOrEmpty()]
	[string]$vcdServer
	)
	
	$poweredOn = $true
	
	# Check values are not null
	if ($orgName -and $vAppName -and $vseName -and $vcdServer ) {
		Try {
			# Get the Org href from the name
			$URI = "https://$vcdServer/api/query?type=organization&fields=name&filter=(name==$orgName)"
			$response = Invoke-RestMethod -Uri $URI -Headers $headers -Method GET -WebSession $vcdSession
			$orgHref =  $response.QueryResultRecords.OrgRecord.href
			# check if the organization exists
			if ($orgHref) {
				Write-Log $logFile 0 "full" "Organization $orgName found"
				
				# if vApp = N/A it's an Isolated Org VDC Network with a corresponding Edge
				if (($vAppName -eq "N/A") -or ($vAppName -eq "n/a")) {
					# Query the ORG for a list of networks
					$response = Invoke-RestMethod -Uri $orgHref -Headers $headers -Method GET -WebSession $vcdSession
					# Get isolated network href, format is https://<vCD>/api/network/fda83d39-c0e3-4df2-ae21-ead14d4def08
					$vAppNetworkHref = ($response.Org.Link | where {$_.name -eq $vseName}).href
					Write-Log $logFile 0 "full" "Isolated Org VDC Edge href url is: $vAppNetworkHref"
				}
				else {
								
					# get the vApp edge href, filtering by ORG and vAppName
					Write-Log $logFile 0 "full" "Querying vApp $vAppHref"
					$URI = "https://$vcdServer/api/query?type=adminVAppNetwork&filter=(org==$orgHref;vappName==$vAppName;name==$vseName)"
					$response = Invoke-RestMethod -Uri $URI -Headers $headers -Method GET -WebSession $vcdSession
					# Get the vApp Href
					$vAppHref = $response.QueryResultRecords.AdminVAppNetworkRecord.vApp
					$vAppNetworkHref = $response.QueryResultRecords.AdminVAppNetworkRecord.href
					Write-Log $logFile 0 "full" "vApp Network href url is: $vAppNetworkHref"
					# Querying the vApp endpoint
					$response = Invoke-RestMethod -Uri $vAppHref -Headers $headers -Method GET -WebSession $vcdSession
					# Checking if vApp is powered-on
					if ($response.VApp.status -ne 4) {
						$poweredOn = $false						
					}
				}
											
				# check if the vAppNetwork href exist
				if ($vAppNetworkHref -and $poweredOn) {
					$networkResetHref = getResetHref $vAppNetworkHref $vcdServer
					# query the network object
					$response = Invoke-RestMethod -Uri $vAppNetworkHref -Headers $headers -Method GET -WebSession $vcdSession
					Write-Log $logFile 0 "full" "Querying network object: $vAppNetworkHref"
					
					# case 1: isolated Org VDC network
					if (($vAppName -eq "N/A") -or ($vAppName -eq "n/a")) {
						$fenceMode = $response.OrgVdcNetwork.Configuration.FenceMode
						$dhcpEnabled = $response.OrgVdcNetwork.Configuration.IpScopes.IpScope.IsEnabled
					}
					# case 2: vApp network
					else {
						# Get FenceMode. Possible values = isolated, natRouted
						$fenceMode = $response.VAppNetwork.Configuration.FenceMode
						# Get the DHCP status. Possible values:true,false
						$dhcpEnabled = $response.VAppNetwork.Configuration.Features.DhcpService.IsEnabled
					}
						
					# case 1 edge is isolated and provides DHCP server: <FenceMode>isolated</FenceMode> and <IsEnabled>true</IsEnabled>
					# case 2 vApp edge is routing via ORG VDC edge: 	<FenceMode>natRouted</FenceMode>
					if ((($fenceMode -eq "isolated") -and $dhcpEnabled) -or ($fenceMode -eq "natRouted") -or ($fenceMode -eq "isolated")) {
							
						# reset the vApp network
						$response = Invoke-RestMethod -Uri $networkResetHref -Headers $headers -Method POST -WebSession $vcdSession
						Write-Log $logFile 0 "full"  "Start network reset operation for vApp:$vAppName, Network: $vseName, Org:$orgName, Mode:$fenceMode, DCHP: $dhcpEnabled"
					
						# Get the task href
						$taskHref = $response.Task.href
						$response = Invoke-RestMethod -Uri $taskHref -Headers $headers -Method GET -WebSession $vcdSession
						
						# Get the tesk status
						$taskStatus = $response.Task.status
						Do {
							Try {
								# Get the task status 
								$response = Invoke-RestMethod -Uri $taskHref -Headers $headers -Method GET -WebSession $vcdSession
								$taskStatus = $response.Task.status
								Write-Progress -Activity "Resetting Network, please wait... vApp:$vAppName, Network: $vseName, Org:$orgName, Mode:$fenceMode, DCHP: $dhcpEnabled" -Status "Current status: $taskStatus" -ParentId 1
								# Sleep before doing another GET
								Start-Sleep -Milliseconds $sleeptime
							}
							Catch {
								Catch-Error $_.Exception.Message
							}
						} While ($taskStatus -eq "running")
					
						Write-Log $logFile 0 "full" "Network reset task finished with status: $($taskStatus.toUpper()) for vApp: $vAppName, Network: $vseName,  Organization: $orgName"
							
						if ($taskStatus -ne "success") {
							Write-Log $logFile 1 "full" "The task failed check the log files the error message"
							Catch-Error $response.Task.Error.message		
						}
						# return the status back into the key/value hash table
						$outputLine.TASK_STATUS = $taskStatus
					}
					
					# Case 3: just a virtualWire, no need to reset any network
					if (($fenceMode -eq "isolated") -and (-not $dhcpEnabled)) {
						Write-Log $logFile 0 "full" "There is no vSE deployed for vApp:$vAppName, Org:$orgName, Mode:$fenceMode, DCHP: $dhcpEnabled"
					}
				}
				else {
					if (!$vAppNetworkHref) {
						Write-Log $logFile 2 "full" "Network not found for Org: $orgName, vApp: $vAppName, Edge: $vseName. Redeployment not possible, check the csv fields for this network!"
						$outputLine.TASK_STATUS = "Network not found!"
					}
					if (!$poweredOn) {
						Write-Log $logFile 2 "full" "vApp $vAppName is not powered-on, skipping."
						$outputLine.TASK_STATUS = "vApp not powered-on"
					}
				}
			}
			else {
				Write-Log $logFile 2 "full" "Organization $orgName not found, redeployment is not possible! Check the Organization name!"
				$outputLine.TASK_STATUS = "ORG not found!"
			}
		}
		Catch {
			Catch-Error $_.Exception.Message
		}
	}
	else {
		Write-Log $logFile 1 "full" "Organization/vApp/vCD server parameters cannot be empty or null! Skipping!"
	}
}

Function EdgeRedeploy {

	[CmdletBinding()]
	Param(
	[Parameter(Mandatory = $True, Position = 1)]
	[ValidateNotNullOrEmpty()]
	[string]$orgName,
	
	[Parameter(Mandatory = $True, Position = 2)]
	[ValidateNotNullOrEmpty()]
	[string]$vseName,
	
	[Parameter(Mandatory = $True, Position = 3)]
	[ValidateNotNullOrEmpty()]
	[string]$vcdServer
	)
	
	if ($vseName -and $orgName) {
		Try {
			# Get ORG href
			$URI = "https://$vcdServer/api/query?type=organization&filter=(name==$orgName)"
			$response = Invoke-RestMethod -Uri $URI -Headers $headers -Method GET -WebSession $vcdSession
			$orgHref =  $response.QueryResultRecords.OrgRecord.href
			# check if the organization exists
			if ($orgHref) {
				# Get all ORG VDCs href
				$response = Invoke-RestMethod -Uri $orgHref -Headers $headers -Method GET -WebSession $vcdSession
				$orgVDChref = $($response.Org.Link | Where {$_.type -eq "application/vnd.vmware.vcloud.vdc+xml"}).href
				# Printing out all the Org VDC href url found
				Write-Log $logFile 0 "full" "Found the following Org VDC href url for Organization $orgName"
				foreach ($href in $orgVDChref) {
					Write-Log $logFile 0 "full" "  > $href"
					
				}
				# vCD query service filtered by vCD Edge name
				$URI = "https://$vcdServer/api/query?type=edgeGateway&filter=(name==$vseName)"
				# Get the vCD edge href
				$response = Invoke-RestMethod -Uri $URI -Headers $headers -Method GET -WebSession $vcdSession
				$totalRecords = $response.QueryResultRecords.total
				Write-Log $logFile 0 "full"  "Number of vShield Edge found by name $vseName : $totalRecords"
				
				# Check if multiple edges with the same name exist
				if ($totalRecords -gt 1) {
					$found = $false
					# multiple edges found with the same name across different organizations
					Write-Log $logFile 0 "full"  "Filtering edge by organization $orgName"
					$edgeGatewayRecord = $response.QueryResultRecords.EdgeGatewayRecord
					foreach ($edge in $edgeGatewayRecord) {
						foreach ($href in $orgVDChref) {
							# the edge vdc must be one of the organization VDCs
							if ($edge.vdc -eq $href)  {
								$edgeHref = $edge.href
								$found = $true
							}
						}
						# exit foreach if found
						if ($found) {
							break
						}
					}
				}
				else {
					# only 1 edge found with the given name
					$edgeHref = $response.QueryResultRecords.EdgeGatewayRecord.href
					
				}
				# check if the edgeHref exists
				if ($edgeHref) {
					Write-Log $logFile 0 "full" "vShield Edge href url is: $edgeHref"
					$edgeHref = Rewrite-url $edgeHref $baseurl
					# Set the redeploy action
					$URI = $edgeHref + "/action/redeploy"
					Write-Log $logFile 0 "full"  "Start Redeploy operation for vShield Edge: $vseName - Organization: $orgName"
					# Start the Redeploy operation
					$response = Invoke-RestMethod -Uri $URI -Headers $headers -Method POST -WebSession $vcdSession
					$taskHref = $response.Task.href
					$taskHref = Rewrite-url $taskHref $baseurl
					# Monitor the task until it finishes 
					
						Do {
							Try {
								# Get the task status 
								$response = Invoke-RestMethod -Uri $taskHref -Headers $headers -Method GET -WebSession $vcdSession
								$taskStatus = $response.Task.status
								Write-Progress -Activity "Redeploying vShield Edge: $vseName - Organization: $orgName" -Status "Current status: $taskStatus" -ParentId 1
								# sleep before doing another GET
								Start-Sleep -Milliseconds $sleeptime
							}
							Catch {
								Catch-Error $_.Exception.Message
							}
						} While ($taskStatus -eq "running") 
						
						# return the status back into the key/value hash table
						$outputLine.TASK_STATUS = $taskStatus
							
						#Write-Progress -Activity "Redeploying vShield Edge: $vseName - Organization: $orgName" -Status $taskStatus -PercentComplete ($counter / ($networkNameList.count) * 100)
						Write-Log $logFile 0 "full" "Task Redeploy finished with status: $($taskStatus.toUpper()) for $vseName in Organization $orgName"
						# if the status is not success (error, abort)
						if ($taskStatus -ne "success") {
							Write-Log $logFile 1 "full" "The task failed check the log files the error message"
							Catch-Error $response.Task.Error.message		
						}
				}
				else {
					Write-Log $logFile 2 "full" "Edge $vseName not found, redeployment is not possible! Check the Edge name!"
					$outputLine.TASK_STATUS = "Edge $vseName not found!"
				}
			}
			else {
				Write-Log $logFile 2 "full" "Organization $orgName not found, redeployment is not possible! Check the Organization name!"
				$outputLine.TASK_STATUS = "ORG not found!"
			}
		}
		Catch {
			Catch-Error $_.Exception.Message
		}
	}
	else {
		Write-Log $logFile 1 "full" "vShield Edge or vCD server parameters cannot be null or empty! Skipping!"
	}
}

Function ResetOrgNetworks {

	[CmdletBinding()]
	Param(
	[Parameter(Mandatory = $True, Position = 1)]
	[ValidateNotNullOrEmpty()]
	[string]$orgName,
	
	[Parameter(Mandatory = $True, Position = 2)]
	[ValidateNotNullOrEmpty()]
	[string]$vcdServer,
	
	[Parameter(Mandatory = $False, Position = 3)]
	[ValidateNotNullOrEmpty()]
	[bool]$csvFile = $true,
	
	[Parameter(Mandatory = $False, Position = 4)]
	[ValidateNotNullOrEmpty()]
	[string[]]$Exclude = "none"
	)
	
	# Initialize Array of Org networks
	$orgNetworks = @()
			
	if ($orgName) {
		Try {
			# Get ORG href
			$URI = "https://$vcdServer/api/query?type=organization&filter=(name==$orgName)"
			$response = Invoke-RestMethod -Uri $URI -Headers $headers -Method GET -WebSession $vcdSession
			$orgHref =  $response.QueryResultRecords.OrgRecord.href
			# check if the organization exists
			if ($orgHref) {
				Write-Log $logFile 0 "full" "Organization $orgName found! Href: $orgHref"
				# Get all ORG VDCs href
				$response = Invoke-RestMethod -Uri $orgHref -Headers $headers -Method GET -WebSession $vcdSession
				$orgVDClist = $($response.Org.Link | Where {$_.type -eq "application/vnd.vmware.vcloud.vdc+xml"} | Select name,href)
				$totalOrgVDC = ($orgVDClist | measure).count
				
				# Printing out all the Org VDC href url found
				Write-Log $logFile 0 "full" "Found $totalOrgVDC organization VDC for $orgName"
				
				# Check if there is at least 1 Org VDC
				if ($totalOrgVDC -ge 1) {
					# ================== EDGES =====================
					Write-Log $logFile 0 "full" "Starting network reset operations."
					Write-Log $logFile 0 "full" "************** Edges Reset Section Begin **************"
					# For each Org VDC reset its Edges and vApp
					$counter = 1
					if (($Exclude.toLower() | where {$_ -eq "edge"}) -ne "edge") {
						foreach ($orgVDC in $orgVDClist) {
						Write-Log $logFile 0 "full" "Org VDC: $($orgVDC.name), href: $($orgVDC.href)"
						Write-Progress -Activity "Org VDC: $($orgVDC.name) - $counter of $totalOrgVDC." -PercentComplete (($counter / $totalOrgVDC)*100) -Id 2 -ParentId 1
											
						# Get Org VDC Edge
						$URI = "https://$vcdServer/api/query?type=edgeGateway&filter=(vdc==$($orgVDC.href))"
						$response = Invoke-RestMethod -Uri $URI -Headers $headers -Method GET -WebSession $vcdSession
						$orgVDCedges = $response.QueryResultRecords.EdgeGatewayRecord
						
						# Check if at least 1 Org VDC Edge exist
						$totalEdges = ($orgVDCedges | measure).count
						if ($totalEdges -ge 1 ) {
							
							# Redeploy Org VDC Edge Gateway
							Write-Log $logFile 0 "full" "Number of Edges found for Org VDC $($orgVDC.name) : $totalEdges"
							
							foreach ($edge in $orgVDCedges) {
								# Get edge href
								$response = Invoke-RestMethod -Uri $edge.href -Headers $headers -Method GET -WebSession $vcdSession 
								# Get redeploy href
								$URI = $($response.EdgeGateway.Link | where {$_.rel -eq "edgeGateway:redeploy"}).href
								# Invoke redeploy
								Write-Log $logFile 0 "full" "Task Redeploy started for Edge: $($edge.name)"
								$response = Invoke-RestMethod -Uri $URI -Headers $headers -Method POST -WebSession $vcdSession
								$taskHref = $response.Task.href
								$taskHref = Rewrite-url $taskHref $baseurl
								
								# Monitor the task until it finishes 
								Do {
									Try {
										# Get the task status 
										$response = Invoke-RestMethod -Uri $taskHref -Headers $headers -Method GET -WebSession $vcdSession
										$taskStatus = $response.Task.status
										Write-Progress -Activity "Redeploying Edge: $($edge.name)" -Status "Current status: $taskStatus" -Id 3 -ParentId 2
										# sleep before doing another GET
										Start-Sleep -Milliseconds $sleeptime
									}
									Catch {
										Catch-Error $_.Exception.Message
									}
								} While ($taskStatus -eq "running") 
								# get the network object id
								$netId = getResetHref $edge.href $vcdServer $true
								# return the status back into the key/value hash table
								$orgNetworks += @{Organization = $orgName; NetworkName = "$($edge.name)($($netId))"; NetworkType = "Edge"; Status = $taskStatus;}
																
								Write-Log $logFile 0 "full" "Task Redeploy finished for Edge: $($edge.name) with status: $($taskStatus.toUpper())"
								# if the status is not success (error, abort)
								if ($taskStatus -ne "success") {
									Write-Log $logFile 1 "full" "The task failed check the log files the error message"
									Catch-Error $response.Task.Error.message		
								}
							}
							$counter++
						}
						else {
							Write-Log $logFile 2 "full" "Org VDC $($orgVDC.name) does not have any Edge deployed."
							$counter++
						}
					}
					}
					else {
						Write-Log $logFile 0 "full" "Org Edge Gateways excluded via Exclude parameter"	
					}
					Write-Log $logFile 0 "full" "************** Edges Reset Section End **************"
					
					# ================== ISOLATED ORGVDC NETWORKS =====================
					Write-Log $logFile 0 "full" "************** Isolated Org VDC Reset Section Begin **************"
					
					if (($Exclude.toLower() | where {$_ -eq "orgvdc"}) -ne "orgvdc") {
					# Get the list of Org VDC Networks on a per Org basis (not Org VDC basis)
					$response = Invoke-RestMethod -Uri $orgHref -Headers $headers -Method GET -WebSession $vcdSession
					$orgVDCNetworkList = $($response.Org.Link | where {$_.type -eq "application/vnd.vmware.vcloud.orgNetwork+xml"}) | select name,href
					$totalVDCNetworks = ($orgVDCNetworkList | measure).count
						# Check if at least 1 Org VDC network exist
						if ($totalVDCNetworks -ge 1) {
						Write-Progress -Activity "Found $totalVDCNetworks OrgVDC Networks for $orgName. Executing reset:" -Id 2 -ParentId 1
						
							$counter = 1
							# For each Org VDC Network, check if  it's Isolated, if so do a Reset
							foreach ($orgVDCNetwork in $orgVDCNetworkList) {
								# query the network object
								$response = Invoke-RestMethod -Uri $orgVDCNetwork.href -Headers $headers -Method GET -WebSession $vcdSession
								Write-Log $logFile 0 "full" "Querying network : $($orgVDCNetwork.name)"
								$fenceMode = $response.OrgVdcNetwork.Configuration.FenceMode
								# if Isolated then Reset
								if ($fenceMode -eq "isolated") {
									
									Write-Log $logFile 0 "full" "The Org VDC Network $($orgVDCNetwork.name) is Isolated."
									$networkResetHref = getResetHref $orgVDCNetwork.href $vcdServer
															
									# reset the Org VDC Isolated network
									$response = Invoke-RestMethod -Uri $networkResetHref -Headers $headers -Method POST -WebSession $vcdSession
									Write-Log $logFile 0 "full"  "Started network reset operation for Org VDC Isolated Network $($orgVDCNetwork.name)"
									
									# Get the task href
									$taskHref = $response.Task.href
									$response = Invoke-RestMethod -Uri $taskHref -Headers $headers -Method GET -WebSession $vcdSession
							
									# Get the tesk status
									$taskStatus = $response.Task.status
									Do {
										Try {
											# Get the task status 
											$response = Invoke-RestMethod -Uri $taskHref -Headers $headers -Method GET -WebSession $vcdSession
											$taskStatus = $response.Task.status
											$percentage = (($counter / $totalVDCNetworks)*100)
											Write-Progress -Activity "Resetting Org VDC Isolated Network $($orgVDCNetwork.name) , please wait..." -Status "Current status: $taskStatus $percentage%" -PercentComplete $percentage -Id 3 -ParentId 2
											# Sleep before doing another GET
											Start-Sleep -Milliseconds $sleeptime
										}
										Catch {
											Catch-Error $_.Exception.Message
										}
									} While ($taskStatus -eq "running")
						
									Write-Log $logFile 0 "full" "Network reset task finished with status: $($taskStatus.toUpper()) for Org VDC Network $($orgVDCNetwork.name)"
								
									if ($taskStatus -ne "success") {
										Write-Log $logFile 1 "full" "The task failed check the log files the error message"
										Catch-Error $response.Task.Error.message		
									}
									
									$netId = getResetHref $orgVDCNetwork.href $vcdServer $true
									# return the status back into the key/value hash table
									$orgNetworks += @{Organization = $orgName; NetworkName = "$($orgVDCNetwork.name)($netId)"; NetworkType = "OrgVDC-Network"; Status = $taskStatus;}
																	
								}
								else {
									Write-Log $logFile 0 "full" "The Org VDC Network $($orgVDCNetwork.name) is not Isolated, no need to reset."
								}
								$counter++
							}
						}
						else {
							Write-Log $logFile 0 "full" "Zero Org VDC Networks found for Org VDC $($orgVDC.name)"
						}
					}
					else {
						Write-Log $logFile 0 "full" "Org VDC Networks excluded via Exclude parameter"	
					}
					Write-Log $logFile 0 "full" "************** Isolated Org VDC Reset Section End **************"
					
					# ================== VAPP NETWORKS =====================
					Write-Log $logFile 0 "full" "************** vApp Networks Reset Section Begin **************"
					if (($Exclude.toLower() | where {$_ -eq "vapp"}) -ne "vapp") {
						$URI = "https://$vcdServer/api/query?type=adminVAppNetwork&filter=(org==$orgHref)"
						$response = Invoke-RestMethod -Uri $URI -Headers $headers -Method GET -WebSession $vcdSession
						$vAppRecords = $response.QueryResultRecords.AdminVAppNetworkRecord | Select vappName,vApp,name,href
						$totalvAppNetworks = $vAppRecords.count
						$counter = 1
						Write-Log $logFile 0 "full" "Number of vApp Networks found for $($orgName): $totalvAppNetworks"
						# checking at least 1 vApp exist
						if ($totalvAppNetworks -ge 1) {
							# for each vApp (if it's powered-on) if natRouted or isolated then reset
							foreach ($record in $vAppRecords) {
								$vAppName = $record.vappName
								$vAppHref = $record.vApp
								$vAppNetworkName = $record.name
								$vAppNetworkHref = $record.href
								
								# Querying the vApp endpoint
								$response = Invoke-RestMethod -Uri $vAppHref -Headers $headers -Method GET -WebSession $vcdSession
								Write-Log $logFile 0 "full" "Querying vApp $vAppHref"
								
								# Checking if vApp is powered-on
								if ($response.VApp.status -eq 4) {
									
									# Querying the vApp Network endpoint
									$response = Invoke-RestMethod -Uri $vAppNetworkHref -Headers $headers -Method GET -WebSession $vcdSession
									# Get fence mode
									$fenceMode = $response.VAppNetwork.Configuration.FenceMode
									# Get the DHCP status. Possible values:true,false
									$dhcpEnabled = $response.VAppNetwork.Configuration.Features.DhcpService.IsEnabled
																	
									# case 1 edge is isolated and provides DHCP server: <FenceMode>isolated</FenceMode> and <IsEnabled>true</IsEnabled>
									# case 2 vApp edge is routing via ORG VDC edge: 	<FenceMode>natRouted</FenceMode>
									if ((($fenceMode -eq "isolated") -and $dhcpEnabled) -or ($fenceMode -eq "natRouted")) {
										$percentage = (($counter / $totalvAppNetworks) * 100)
										$networkResetHref = getResetHref $vAppNetworkHref $vcdServer
										# reset the vApp network
										$response = Invoke-RestMethod -Uri $networkResetHref -Headers $headers -Method POST -WebSession $vcdSession
										Write-Log $logFile 0 "full"  "Start network reset operation for vApp:$vAppName, Network: $vAppNetworkName, Org: $orgName, Mode: $fenceMode, DCHP: $dhcpEnabled"
									
										# Get the task href
										$taskHref = $response.Task.href
										$response = Invoke-RestMethod -Uri $taskHref -Headers $headers -Method GET -WebSession $vcdSession
										
										# Get the tesk status
										$taskStatus = $response.Task.status
										Do {
											Try {
												# Get the task status 
												$response = Invoke-RestMethod -Uri $taskHref -Headers $headers -Method GET -WebSession $vcdSession
												$taskStatus = $response.Task.status
												Write-Progress -Activity "Resetting Network, please wait... vApp: $vAppName, Network: $vAppNetworkName, Org: $orgName, Mode: $fenceMode, DCHP: $dhcpEnabled" -PercentComplete $percentage -Status "Current status: $taskStatus ($counter of $totalvAppNetworks)" -Id 2 -ParentId 1
												# Sleep before doing another GET
												Start-Sleep -Milliseconds $sleeptime
											}
											Catch {
												Catch-Error $_.Exception.Message
											}
										} While ($taskStatus -eq "running")
									
										Write-Log $logFile 0 "full" "Network reset task finished with status: $($taskStatus.toUpper()) for vApp: $vAppName, Network: $vAppNetworkName, Org: $orgName"
											
										if ($taskStatus -ne "success") {
											Write-Log $logFile 1 "full" "The task failed check the log files the error message"
											Catch-Error $response.Task.Error.message		
										}
										$netId = getResetHref $vAppNetworkHref $vcdServer $true
										# return the status back into the key/value hash table
										$orgNetworks += @{Organization = $orgName; NetworkName = $vAppName + "/" + $vAppNetworkName + "($($NetId))"; NetworkType = "vApp-Network"; Status = $taskStatus;}
										
									}
								}
								else {
									Write-Log $logFile 0 "full" "vApp $vAppName is not powered-on, skipping."
								}
								$counter++
							}
						}
						else {
							Write-Log $logFile 2 "full" "Zero vApp found for Organization $orgName"
						}
					}
					else {
						Write-Log $logFile 0 "full" "vApp Networks excluded via Exclude parameter"
					}
					Write-Log $logFile 0 "full" "************** vApp Networks Reset Section End **************"
				}
				else {
					Write-Log $logFile 2 "full" "Zero Org VDC found for Organization $orgName"
				
					if ($csvFile) {
						# Filling with Not Applicable the remaining CSV fields
						$outputLine.VS_NAME_VSPHERE = "N/A"
						$outputLine.TASK_STATUS = "see csv output file"
					}
				}
			}
			else {
				if ($csvFile) {
					# Filling with Not Applicable the remaining CSV fields
					$outputLine.VS_NAME_VSPHERE = "N/A"
					$outputLine.TASK_STATUS = "ORG not found!"
				}
				Write-Log $logFile 2 "full" "Organization $orgName not found!"
			}
		}
		Catch {
			Catch-Error $_.Exception.Message
		}
	}
	else {
		Write-Log $logFile 2 "full" "Organization $orgName cannot be empty!"
	}
	return $orgNetworks
}

#Endregion Functions

#Region Constant-Variables
# vCD Server FQDN
$baseurl="https://$vcdServer"
# vCD API version
$apiVer = "5.5"				
# sleep time to check vSphere task status					
$sleeptime = 8000
# Create a timestamp for the log file 
$logfileTimeStamp = (Get-Date -Format ("dd-MM-yyyy-HH-mm-ss"))
# Script log file name
$logFile = $logfileTimeStamp + "_vcdNetworksRedeploy.log"
# Script version
$version = "2.1"
# Flag variable
$fullOrgReset = $false
# Script title	
$scriptHeader = "vCD Edges & vApp Networks Redeploy Script - Version: $version"
# Declare the array used for full org reset
$orgNetworksOutput = @()
# Output CSV file
$CSVOutputFile = $logfileTimeStamp + "_vcdNetworksRedeploy.csv"
# Org networks CSV file
$orgCSVOutputFile = $logfileTimeStamp + "_vcdOrganizationNetworksRedeploy.csv"
# Operation index
$OpsCounter = 1
# Confirmation message
$confirmationMessage  = "Do you want to continue? [y/n]"
#Endregion Constant-Variables

#Region LoadingFile
# Check if CSV input file is provided
if ($CSVInputFile) {
	# Import CSV
	$inputObj = Import-Csv $CSVInputFile
	# Clone the object to write status updates to the output object 
	$outputObjResult = $inputObj
	# add a TASK_STATUS member
	$outputObjResult | Add-Member -Type NoteProperty -name TASK_STATUS -Value ""
	# Load the list of edges into vseList
	$networkNameList = $outputObjResult.VS_NAME
}

# Check if file exist
if (-not(Test-Path $logFile))  {
	# create the file
	New-Item -Path $logFile -ItemType file | Out-Null
}
#Endregion LoadingFile

$rows = ($networkNameList | measure).count

Write-Log $logFile 0 "full" "*************************** SCRIPT STARTED ***************************"
Write-Log $logFile 0 "full" $scriptHeader

#region Bypass untrusted certificates
# --- Work with Untrusted Certificates
if (-not ([System.Management.Automation.PSTypeName]'TrustAllCertsPolicy').Type) {
        Add-Type @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy {
            public bool CheckValidationResult(
                ServicePoint srvPoint, X509Certificate certificate,
                WebRequest request, int certificateProblem) {
                return true;
            }
        }
"@
	[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
	Write-Log $logFile 0 "full" "Added TrustAllCertsPolicy policy"
    }
	else {
		Write-Log $logFile 0 "full" "TrustAllCertsPolicy policy already installed."
    }
	# adding all security protocols
	$SecurityProtocols = @(
		[System.Net.SecurityProtocolType]::Ssl3,
		[System.Net.SecurityProtocolType]::Tls,
		[System.Net.SecurityProtocolType]::Tls12
    )
	[System.Net.ServicePointManager]::SecurityProtocol = $SecurityProtocols -join ","
	Write-Log $logFile 0 "full" "Adding security protocol Tls,Tls12,Ssl3"

#endregion Bypass untrusted certificates

Write-Log $logFile 0 "full" "Log file name is: $logFile"
#Region ConnectvCD
Write-Log $logFile 0 "full" "Provide the vCloud Director system admin credential:"
Try {
	$vcdCredential = Get-Credential $null
}
Catch {
	Catch-Error $_.Exception.Message
	Write-Log $logFile 1 "full" "Credentials empty or uncomplete! Exiting"
	break
}
Write-Log $logFile 0 "full" "vCloud Director credential accepted."
Write-Log $logFile 0 "full" "*************************************************************************"

## Configure vCD authentication and prepare rest call
# Username and password
$username =  $vcdCredential.Username + "@system"
$password = ($vcdCredential.GetNetworkCredential()).Password

# Build authorization 
$auth = $username + ':' + $password

# Encode basic authorization for the header
$Encoded = [System.Text.Encoding]::UTF8.GetBytes($auth)
$EncodedPassword = [System.Convert]::ToBase64String($Encoded)
 
# Define vCD header
$headers = @{
	"Accept"="application/*+xml;version=$apiVer"
	"Authorization"="Basic $EncodedPassword"
}
# get a vCD token. The token is stored inside $vcdSession var which is later passed as -WebSession
$URI = "https://$vcdServer/api/sessions"
$response = Invoke-RestMethod -Method Post -URI $URI -Headers $Headers -Session vcdSession
#Endregion ConnectvCD

# Check if CSV has VCD_ORG types
$vsTypeList = $outputObjResult.VS_TYPE
$fullOrgResetOnCsv = $false
foreach ($vsType in $vsTypeList) {
	if ($vsType -eq "VCD_ORG") {  $fullOrgResetOnCsv = "$true" }
}

# Case 1: no input file provided and  list of organization providede via -Orgs parameter
if (!$CSVInputFile -and ($Orgs.count -ge 1)) {
	Write-Log $logFile 0 "full" "No CSV input file provided and list of Orgs provided via script parameter"
	if ($Orgs.toLower() -eq "all") {
		Write-Log $logFile 0 "full" "You are requesting a full network reset for all the vCD Organizations"
		# get all Orgs
		$URI = "https://$vcdServer/api/query?type=organization"
		$response = Invoke-RestMethod -Uri $URI -Headers $headers -Method GET -WebSession $vcdSession
		$Orgs = $response.QueryResultRecords.OrgRecord.name | Sort-Object
	}
	else {
		Write-Log $logFile 0 "full" "You are requesting a full network reset for the following Organizations: $Orgs"
	}
	
	# getting confirmation from user for a full org reset
	while ($confirmation -notmatch "[y|n]")	{ 
    	$timestamp = (Get-Date -Format ("[dd-MM-yyyy HH:mm:ss] ")) + ":Info:"
		$confirmation = Read-Host $timestamp $confirmationMessage
	}

	if ($confirmation -eq "y") {	
		foreach ($orgName in $Orgs) {
			Write-Log $logFile 0 "full" "Full Organization network reset requested, type VCD_ORG found for Organization: $orgName. Starting reset operation..."
			Write-Log $logFile 0 "full" "Exclude options: $Exclude"
			$orgNetworks = ResetOrgNetworks $orgName $vcdServer $false $Exclude
			$orgNetworksOutput += $orgNetworks
		}
	}
	else {
		Write-Log $logFile 0 "full" "Operation cancelled by user, terminating script."
	}
		
	# Create a PS object from the hash table
	$orgNetworksObject = $orgNetworksOutput | % { New-Object PSObject -Property $_}
	$orgNetworksObject | Export-Csv -Path $orgCSVOutputFile -Confirm:$false -Delimiter "," -NoTypeInformation -Force:$true
	Write-Log $logFile 0 "full" "For details of the full Organization networks reset see output CSV file: $orgCSVOutputFile"
}

# Case 2: CSV input file provided so this takes priority and -Orgs parameter is ignored
if ($CSVInputFile) {
	Write-Log $logFile 0 "full" "CSV input file provided, ignoring -Orgs parameters!"
	Write-Log $logFile 0 "full" "Number of lines found on the CSV file: $rows"
	# Check if the CSV is actually populated
	if ($rows -gt 0) {
		Foreach ($outputLine in $outputObjResult) {
				$orgName = $outputLine.ORG_NAME
				$vAppName = $outputLine.VAPP_NAME
				$vseName = $outputLine.VS_NAME
				$vsType = $outputLine.VS_TYPE
				
				Write-Progress -Activity "Networks redeployment in progress. Processing CSV row Org: $orgName, vApp: $vAppName, Edge: $vseName, Type: $vsType" -Status "Processing $OpsCounter of $rows" -PercentComplete ($OpsCounter / ($networkNameList.count) * 100) -Id 1		
				Switch ($vsType) {
							
					"VS_EDGE" {
						Write-Log $logFile 0 "full" "Network type EDGE found for Organization: $orgName, Edge: $vseName. Starting reset operation..."
						EdgeRedeploy $orgName $vseName $vcdServer
						break
					}
					
					"VS_VAPP" {
						Write-Log $logFile 0 "full" "vApp network type VAPP found for Organization: $orgName, vApp: $vAppName, Network: $vseName. Starting reset operation..."
						vAppNetworkReset $orgName $vAppName $vseName $vcdServer
						break
					}
					
					"VS_ISOLATED" {
						Write-Log $logFile 0 "full" "vApp network type ISOLATED found for Organization: $orgName, vApp: $vAppName, Network: $vseName. Starting reset operation..."
						vAppNetworkReset $orgName $vAppName $vseName $vcdServer
						break
					}
					
					"VCD_ORG" {
						Write-Log $logFile 0 "full" "Full Organization network reset requested, type VCD_ORG found for Organization: $orgName. Starting reset operation..."
						$orgNetworks = ResetOrgNetworks $orgName -csvFile $true
						$orgNetworksOutput += $orgNetworks
						$fullOrgReset = $true
						break
					}
					default {
						Write-Log $logFile 2 "full" "The valid VS_TYPE are (VS_EDGE,VS_VAPP,VS_ISOLATED,VCD_ORG). The type $vsType found on the csv file is not valid, please correct the file!"
						$outputLine.TASK_STATUS = "VS_TYPE invalid"
					}
				}
				# increase counter for the number of current operation
				$OpsCounter++
			}
			# Export to CSV the object with TASK_RESULT column
			$outputObjResult | Export-Csv -Path $CSVOutputFile -Confirm:$false -Delimiter "," -NoTypeInformation
			Write-Log $logFile 0 "full" "Redeploy result details file for each Edge is: $CSVOutputFile"
			
			# Export to CSV the list of Organization networks that have been redeployed (Edges, vApp Networks and Isolated Org VDC)
			if ($fullOrgReset) {
				# Create a PS object from the hash table
				$orgNetworksObject = $orgNetworksOutput | % { New-Object PSObject -Property $_}
				$orgNetworksObject | Export-Csv -Path $orgCSVOutputFile -Confirm:$false -Delimiter "," -NoTypeInformation -Force:$true
				Write-Log $logFile 0 "full" "For details of the full Organization networks reset see output CSV file: $orgCSVOutputFile"
			}
	}
	else {
		# Empty csv file!
		Write-Log $logFile 0 "full" "No networks were found, exiting! Check the CSV file!"
	}
}
Write-Log $logFile 0 "full" "*************************** SCRIPT COMPLETED ***************************"

Read-Host "Press any key to continue..." | Out-Null