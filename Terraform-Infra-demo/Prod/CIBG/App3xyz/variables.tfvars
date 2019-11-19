AppName="App5xyz"

busunit="CIBG"

#Location of the spoke VNET
location = "uaenorth"

# Hub VNET for Peering 
hub_private_rg="rg-hub-itservices-uaen"
hub_private_vnet="vnet-hub-itservices-uaen"


#spoke VNET CIDR Range  , Not used ,auto generated by script
vnet_cidr_range="10.210.0.0/16"
spoke_subnet_prefixes=["10.210.1.0/24","10.210.2.0/24","10.210.3.0/24","10.210.4.0/24"]

#Subnet names for the spoke Vnet 
spoke_subnet_names=["mgmt","web","app","db"]

#on prem address range and FW Ip used in NSGs
onprem_address_prefix="10.0.0.0/16"
hubfwip="10.100.1.4"


#dns server list
dns_servers=["10.200.1.5"]

tags={
           environment = "nonProd"
           costcenter  = "CorelBanking" 
}

