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


# CSV Examples
ORG02,N/A,ORG01-VSE01,VS_EDGE,edge-1                        <--- vShield Edge

ORG02,ORG07_vApp02,ORG02-vAppNet02,VS_ISOLATED,edge-15      <--- Isolated vApp Network

ORG03,ORG03_vAppRouted02,ORG03_vAppNet02,VS_VAPP,edge-17    <--- Routed vApp Network

ORG03,N/A,ISOLATED-NET01,VS_ISOLATED,edge-20                <--- Isolated Org VDC Network

# Usage example 1:
vcdNetworksRedeploy -CSVInputFile ./vcdNetworksRedeployInputList.csv -vcdServer "vcdcell01"

# Usage example 2:
vcdNetworksRedeploy -Orgs ORG01,ORG02,ORG03
