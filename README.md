# vcdNetworksRedeploy
This PowerShell script can redeploy all types of vCloud Director Networks, such as:
- vShield Edges
- vApp Networks (natRouted, isolated)
- Isolated Org VDC Networks

The script takes as input either a CSV file with a list of networks (see vcdNetworksRedeployInputList.csv) or a list or vCD Organizations.
In the latter case the script will execute a full Organization network reset, inclunding Edges, vApp Networks and Isolated Org VDC Networks.

The CSV input file must be formatted as following:

ORG_NAME        = vCD Organization Name

VAPP_NAME       = vApp Name

VS_NAME         = vShield Edge (if applicable)

VS_TYPE         = Type of network. Possible values: VS_EDGE, VS_APP, VS_ISOLATED

VS_ID           = vShield Manager ID

VS_NAME_VSPHERE = vSphere Name

ORG02,N/A,ORG01-VSE01,VS_EDGE,edge-1,vse-VSE01 (66afb29d-a5d1-4395-b2c4-f9821f2f3b02)

# Usage example 1:
vcdNetworksRedeploy -CSVInputFile ./vcdNetworksRedeployInputList.csv -vcdServer "vcdcell01"

# Usage example 2:
vcdNetworksRedeploy -Orgs ORG01,ORG02,ORG03
