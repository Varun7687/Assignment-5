resource "aws_vpc" "this" {
  for_each             = local.vpcs
  cidr_block           = each.value.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.tags[each.key], { Name = "${local.name}-${each.key}-vpc" })
}

resource "aws_internet_gateway" "this" {
  for_each = toset(["shared", "prod"])
  vpc_id   = aws_vpc.this[each.key].id
  tags     = merge(local.tags[each.key], { Name = "${local.name}-${each.key}-igw" })
}

resource "aws_subnet" "this" {
  for_each                = local.subnets
  vpc_id                  = aws_vpc.this[each.value.vpc].id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = each.value.role == "public"
  tags                    = merge(local.tags[each.value.vpc], { Name = "${local.name}-${each.key}", Tier = each.value.role })
}

resource "aws_eip" "nat" {
  for_each = toset(["shared", "prod"])
  domain   = "vpc"
  tags     = merge(local.tags[each.key], { Name = "${local.name}-${each.key}-nat-eip" })
}

resource "aws_nat_gateway" "this" {
  for_each      = toset(["shared", "prod"])
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.this["${each.key}-public-a"].id
  depends_on    = [aws_internet_gateway.this]
  tags          = merge(local.tags[each.key], { Name = "${local.name}-${each.key}-nat" })
}

resource "aws_route_table" "public" {
  for_each = toset(["shared", "prod"])
  vpc_id   = aws_vpc.this[each.key].id
  tags     = merge(local.tags[each.key], { Name = "${local.name}-${each.key}-public-rt" })
}

resource "aws_route" "public_default" {
  for_each               = toset(["shared", "prod"])
  route_table_id         = aws_route_table.public[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[each.key].id
}

resource "aws_route_table" "private" {
  for_each = toset(["shared", "prod", "dev"])
  vpc_id   = aws_vpc.this[each.key].id
  tags     = merge(local.tags[each.key], { Name = "${local.name}-${each.key}-private-rt" })
}

resource "aws_route" "private_default" {
  for_each               = toset(["shared", "prod"])
  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.key].id
}

resource "aws_route_table" "db" {
  for_each = toset(["prod", "dev"])
  vpc_id   = aws_vpc.this[each.key].id
  tags     = merge(local.tags[each.key], { Name = "${local.name}-${each.key}-db-rt" })
}

resource "aws_route_table_association" "public" {
  for_each       = { for k, s in local.subnets : k => s if s.role == "public" }
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.public[each.value.vpc].id
}

resource "aws_route_table_association" "private" {
  for_each       = { for k, s in local.subnets : k => s if s.role == "private" }
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.private[each.value.vpc].id
}

resource "aws_route_table_association" "db" {
  for_each       = { for k, s in local.subnets : k => s if s.role == "db" }
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.db[each.value.vpc].id
}

resource "aws_network_acl" "baseline" {
  for_each = local.vpcs
  vpc_id   = aws_vpc.this[each.key].id
  tags     = merge(local.tags[each.key], { Name = "${local.name}-${each.key}-baseline-nacl" })
}

resource "aws_network_acl_rule" "inbound" {
  for_each       = local.vpcs
  network_acl_id = aws_network_acl.baseline[each.key].id
  rule_number    = 100
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

resource "aws_network_acl_rule" "outbound" {
  for_each       = local.vpcs
  network_acl_id = aws_network_acl.baseline[each.key].id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

resource "aws_network_acl_association" "subnets" {
  for_each       = aws_subnet.this
  subnet_id      = each.value.id
  network_acl_id = aws_network_acl.baseline[local.subnets[each.key].vpc].id
}

resource "aws_ec2_transit_gateway" "this" {
  description                     = "Bluefin shared-services/prod/dev TGW"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  tags                            = merge(local.common, { Environment = "shared", Name = "${local.name}-tgw" })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each           = local.vpcs
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = aws_vpc.this[each.key].id
  subnet_ids         = [aws_subnet.this["${each.key}-private-a"].id, aws_subnet.this["${each.key}-private-b"].id]
  dns_support        = "enable"
  tags               = merge(local.tags[each.key], { Name = "${local.name}-${each.key}-tgw-attachment" })
}

resource "aws_ec2_transit_gateway_route_table" "this" {
  for_each           = local.vpcs
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = merge(local.tags[each.key], { Name = "${local.name}-${each.key}-tgw-rt" })
}

resource "aws_ec2_transit_gateway_route_table_association" "this" {
  for_each                       = local.vpcs
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.key].id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "shared_from_envs" {
  for_each                       = toset(["prod", "dev"])
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this["shared"].id
}

resource "aws_ec2_transit_gateway_route" "prod_to_shared" {
  destination_cidr_block         = local.vpcs.shared.cidr
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this["prod"].id
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this["shared"].id
}

resource "aws_ec2_transit_gateway_route" "dev_to_shared" {
  destination_cidr_block         = local.vpcs.shared.cidr
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this["dev"].id
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this["shared"].id
}

resource "aws_route" "shared_to_prod" {
  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
  for_each               = toset(["public", "private"])
  route_table_id         = each.key == "public" ? aws_route_table.public["shared"].id : aws_route_table.private["shared"].id
  destination_cidr_block = local.vpcs.prod.cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
}

resource "aws_route" "shared_to_dev" {
  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
  for_each               = local.peering_routes_enabled ? toset([]) : toset(["public", "private"])
  route_table_id         = each.key == "public" ? aws_route_table.public["shared"].id : aws_route_table.private["shared"].id
  destination_cidr_block = local.vpcs.dev.cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
}

resource "aws_route" "prod_to_shared" {
  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
  for_each               = toset(["private", "db"])
  route_table_id         = each.key == "private" ? aws_route_table.private["prod"].id : aws_route_table.db["prod"].id
  destination_cidr_block = local.vpcs.shared.cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
}

resource "aws_route" "dev_to_shared" {
  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
  for_each               = local.peering_routes_enabled ? toset(["db"]) : toset(["private", "db"])
  route_table_id         = each.key == "private" ? aws_route_table.private["dev"].id : aws_route_table.db["dev"].id
  destination_cidr_block = local.vpcs.shared.cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
}

resource "aws_vpc_peering_connection" "shared_dev" {
  count       = var.enable_peering_exercise ? 1 : 0
  vpc_id      = aws_vpc.this["shared"].id
  peer_vpc_id = aws_vpc.this["dev"].id
  auto_accept = true

  tags        = merge(local.common, { Environment = "shared", Name = "${local.name}-shared-dev-peering-exercise" })
}

resource "aws_route" "shared_to_dev_peer" {
  for_each                  = local.peering_routes_enabled ? toset(["public", "private"]) : toset([])
  route_table_id            = each.key == "public" ? aws_route_table.public["shared"].id : aws_route_table.private["shared"].id
  destination_cidr_block    = local.vpcs.dev.cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.shared_dev[0].id
}

resource "aws_route" "dev_to_shared_peer" {
  count                     = local.peering_routes_enabled ? 1 : 0
  route_table_id            = aws_route_table.private["dev"].id
  destination_cidr_block    = local.vpcs.shared.cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.shared_dev[0].id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this["prod"].id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private["prod"].id, aws_route_table.db["prod"].id]
  tags              = merge(local.tags.prod, { Name = "${local.name}-prod-s3-endpoint" })
}

resource "aws_security_group" "endpoint" {
  name   = "${local.name}-endpoint-sg"
  vpc_id = aws_vpc.this["prod"].id
  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = [local.vpcs.prod.cidr]
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.tags.prod, { Name = "${local.name}-endpoint-sg" })
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = toset(["secretsmanager", "sns"])
  vpc_id              = aws_vpc.this["prod"].id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.this["prod-private-a"].id, aws_subnet.this["prod-private-b"].id]
  security_group_ids  = [aws_security_group.endpoint.id]
  private_dns_enabled = true
  tags                = merge(local.tags.prod, { Name = "${local.name}-prod-${each.key}-endpoint" })
}
