output "api_dns_name" {
  description = "Private ALB DNS name; reachable only from allowed VPC client ranges."
  value       = aws_lb.api.dns_name
}

output "lambda_arn" {
  description = "Lambda function ARN."
  value       = aws_lambda_function.api.arn
}

output "mtls_bucket_name" {
  description = "Private bucket containing the ALB client CA trust bundle."
  value       = aws_s3_bucket.mtls.id
}

output "alb_log_bucket_name" {
  description = "Private bucket storing ALB access and TLS connection logs."
  value       = aws_s3_bucket.alb_logs.id
}

output "vpc_endpoint_ids" {
  description = "Private SSM, CloudWatch Logs, and S3 endpoint IDs."
  value = concat(
    [for endpoint in aws_vpc_endpoint.interface : endpoint.id],
    [aws_vpc_endpoint.s3.id]
  )
}

output "client_certificate_pem" {
  description = "Client certificate for testing the mTLS listener."
  value       = tls_locally_signed_cert.client.cert_pem
}

output "client_private_key_pem" {
  description = "Client private key for testing. Stored in Terraform state; protect state accordingly."
  value       = tls_private_key.client.private_key_pem
  sensitive   = true
}
