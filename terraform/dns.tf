resource "aws_route53_zone" "private" {
  lifecycle {
    ignore_changes = [vpc]
  }
  name = "bluefin.internal"
  vpc {
    vpc_id = aws_vpc.this["shared"].id
  }
  comment = "Bluefin private service discovery"
  tags    = merge(local.tags.shared, { Name = "${local.name}-private-zone" })
}

resource "aws_route53_zone_association" "prod" {
  zone_id = aws_route53_zone.private.zone_id
  vpc_id  = aws_vpc.this["prod"].id
}

resource "aws_route53_zone_association" "dev" {
  zone_id = aws_route53_zone.private.zone_id
  vpc_id  = aws_vpc.this["dev"].id
}

resource "aws_route53_record" "app_prod" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "app.prod.bluefin.internal"
  type    = "A"
  alias {
    name                   = aws_lb.prod.dns_name
    zone_id                = aws_lb.prod.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "db_prod" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "db.prod.bluefin.internal"
  type    = "CNAME"
  ttl     = 60
  records = [aws_db_instance.prod.address]
}

resource "aws_route53_record" "dev01" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "dev01.dev.bluefin.internal"
  type    = "A"
  ttl     = 60
  records = [aws_instance.dev.private_ip]
}
