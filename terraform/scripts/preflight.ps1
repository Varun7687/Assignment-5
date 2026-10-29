# Read-only checks. Does not create, modify or delete AWS resources.
# Run from the SAME Terraform working directory/profile you intend to use.
param([Parameter(Mandatory=$true)][string]$Region,
      [Parameter(Mandatory=$true)][string]$ExpectedAccountId,
      [Parameter(Mandatory=$true)][string]$AmiId)
$ErrorActionPreference = 'Stop'
$identity = aws sts get-caller-identity --output json
if ($LASTEXITCODE -ne 0) { throw 'AWS identity check failed.' }
$account = ($identity | ConvertFrom-Json).Account
if ($account -ne $ExpectedAccountId) { throw "Wrong account: $account" }
Write-Host "Account verified: $account"
aws ec2 describe-availability-zones --region $Region --query 'AvailabilityZones[].{Name:ZoneName,State:State,OptIn:OptInStatus}' --output table
if ($LASTEXITCODE -ne 0) { throw 'AZ lookup denied/failed. Stop and ask your administrator; do not bypass it.' }
aws ec2 describe-images --region $Region --image-ids $AmiId --query 'Images[].{ID:ImageId,Architecture:Architecture,State:State,Owner:OwnerId,Name:Name}' --output table
if ($LASTEXITCODE -ne 0) { throw 'AMI verification denied/failed. Stop and ask your administrator.' }
aws ec2 describe-vpcs --region $Region --query 'Vpcs[].{ID:VpcId,CIDR:CidrBlock,Default:IsDefault}' --output table
if ($LASTEXITCODE -ne 0) { throw 'VPC inventory check failed.' }
aws ec2 describe-addresses --region $Region --query 'Addresses[].{Allocation:AllocationId,IP:PublicIp,Association:AssociationId}' --output table
if ($LASTEXITCODE -ne 0) { throw 'Elastic IP inventory check failed.' }
Write-Host 'Inventory checks completed. This does NOT prove Create permissions or sufficient quota.'
