data "aws_route53_zone" "app" {
  name         = var.domain_name
  private_zone = false
}

# dns route53 record -> ALB DNS name
resource "aws_route53_record" "april_alb_record" {
  zone_id = data.aws_route53_zone.app.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_alb.april_alb.dns_name
    zone_id                = aws_alb.april_alb.zone_id
    evaluate_target_health = true
  }
}

# The ONE ACM certificate used by the ALB
resource "aws_acm_certificate" "april_alb_cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "april-cert"
  }
}

# DNS record that proves you own the domain
resource "aws_route53_record" "cert_validation" {
  for_each = { for dvo in aws_acm_certificate.april_alb_cert.domain_validation_options : dvo.domain_name => {
    name   = dvo.resource_record_name
    type   = dvo.resource_record_type
    record = dvo.resource_record_value
  } }

  zone_id         = data.aws_route53_zone.app.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

# NEW: waits until AWS confirms the certificate is validated
resource "aws_acm_certificate_validation" "april_cert" {
  certificate_arn         = aws_acm_certificate.april_alb_cert.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}
