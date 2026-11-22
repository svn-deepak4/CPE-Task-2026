resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem       = tls_private_key.ca.private_key_pem
  validity_period_hours = 87600
  is_ca_certificate     = true
  set_subject_key_id    = true
  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "digital_signature",
  ]

  subject {
    common_name  = "${local.name} local CA"
    organization = "CPE Assessment"
  }
}

resource "tls_private_key" "server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "server" {
  private_key_pem = tls_private_key.server.private_key_pem

  subject {
    common_name  = "internal.${local.name}.local"
    organization = "CPE Assessment"
  }
}

resource "tls_locally_signed_cert" "server" {
  cert_request_pem      = tls_cert_request.server.cert_request_pem
  ca_private_key_pem    = tls_private_key.ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.ca.cert_pem
  validity_period_hours = 8760
  is_ca_certificate     = false
  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
  ]
}

resource "tls_private_key" "client" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "client" {
  private_key_pem = tls_private_key.client.private_key_pem

  subject {
    common_name  = "${local.name} test client"
    organization = "CPE Assessment"
  }
}

resource "tls_locally_signed_cert" "client" {
  cert_request_pem      = tls_cert_request.client.cert_request_pem
  ca_private_key_pem    = tls_private_key.ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.ca.cert_pem
  validity_period_hours = 8760
  is_ca_certificate     = false
  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "client_auth",
  ]
}

resource "aws_acm_certificate" "server" {
  private_key       = tls_private_key.server.private_key_pem
  certificate_body  = tls_locally_signed_cert.server.cert_pem
  certificate_chain = tls_self_signed_cert.ca.cert_pem

  tags = {
    Name = "${local.name}-server-certificate"
  }
}

resource "aws_lb_trust_store" "client_ca" {
  name                             = local.name
  ca_certificates_bundle_s3_bucket = aws_s3_bucket.mtls.id
  ca_certificates_bundle_s3_key    = aws_s3_object.ca_bundle.key

  depends_on = [aws_s3_bucket_policy.mtls]
}
