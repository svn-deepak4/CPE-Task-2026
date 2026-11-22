# CPE Task 2026 — Private AWS API

Terraform provisions a private two-AZ VPC, an internal Application Load Balancer
with mutual TLS, and a Python Lambda request handler. The ALB accepts traffic
only from configured VPC CIDRs, and the Lambda uses private SSM and CloudWatch
Logs endpoints rather than internet egress.

## Architecture

![AWS architecture diagram (SVG)](./docs/aws-architecture.svg)

Presentation exports: [SVG](./docs/aws-architecture.svg) ·
[PNG](./docs/aws-architecture.png).

For a presentation-ready high-level and low-level design, see
[Application and Infrastructure Design](./docs/application-infrastructure-design.md).

- Two private subnets in separate Availability Zones; no internet gateway or NAT.
- Internal ALB with HTTPS and client-certificate verification against a CA
  bundle in a private, versioned S3 bucket.
- ALB request access logs and TLS connection logs delivered to a separate
  private S3 bucket, with a 30-day lifecycle retention period.
- Lambda target attached to the ALB. `POST` requests require a JSON string
  `message`; `GET /health` is used by the target health check.
- Lambda loads its encrypted message-length setting from SSM Parameter Store.
- Interface endpoints for SSM and CloudWatch Logs; an S3 gateway endpoint.
- KMS key for the SSM SecureString, CloudWatch log groups with 30-day retention,
  and a Lambda error alarm publishing to an SNS topic stub (no subscriber is
  configured).
- Lambda emits structured application logs and writes API access records to a
  separate CloudWatch log group.
- ALB access logs record HTTP requests; connection logs record TLS and
  certificate-verification outcomes once per connection. Security-group
  rejects that never reach the ALB are not captured by these logs.

The ALB is internal and has no public IP. Clients must have private network
connectivity to the VPC (for example, VPN or peering) and a client certificate
signed by the configured CA.

## Requirements and configuration

- Terraform 1.6 or later.
- AWS credentials with permissions to create the resources in this project.
- An AWS region with at least two available Availability Zones.
- An S3 state bucket and locking configuration if remote state is used.

Defaults are in `variables.tf`. To customize, create a local
`terraform.tfvars` (ignored by Git), for example:

```hcl
aws_region           = "eu-west-2"
environment          = "dev"
vpc_cidr             = "10.20.0.0/16"
allowed_client_cidrs = ["10.20.0.0/16"]
```

The default deployment region is London (`eu-west-2`). This is separate from
the IAM Identity Center home region used when signing in with AWS SSO.

Set `allowed_client_cidrs` to the actual internal client ranges that should
reach the ALB. The default permits only the VPC CIDR.

## Initialize, plan, and deploy

```sh
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Deployment creates billable resources, including an internal ALB, interface
VPC endpoints, KMS key, and CloudWatch log groups. Review the plan and expected
regional costs before applying. Do not apply from CI without an explicit
deployment workflow and approval.

### Remote state

Terraform state contains generated CA, client, and server private keys. For any
shared or persistent deployment, use encrypted remote state with tightly
restricted access and locking. Configure the S3 backend during initialization
using a secured backend configuration; do not commit state bucket names,
credentials, or state files. The backend must exist before `terraform init`.

The GitHub workflow validates Terraform and runs the Lambda unit tests on pull
requests. It also runs Checkov against the Terraform code: medium, high, and
critical findings fail the security job; low and informational findings are
reported as soft failures and do not block it. Checkov is pinned in
`requirements-dev.txt`.

To make these checks merge gates, configure a GitHub ruleset or branch
protection rule for `main` that requires pull requests and the status checks
`Format and validate` and `Terraform security scan`. Review lower-severity
Checkov output, but do not require it to pass before merging.

The AWS plan job runs only on pushes to `main` or manual runs on `main`, and
intentionally uses `terraform init -backend=false`. Therefore it is a
post-merge check, not a merge gate, and it cannot detect drift against remote
state. Configure the repository variable `AWS_PLAN_ROLE_ARN` and an AWS IAM
OIDC role whose trust policy is restricted to this repository and
`refs/heads/main`. The workflow uses `eu-west-2` for AWS credentials and
Terraform uses the default region above. The role needs read/plan permissions
for the managed resources; no long-lived AWS access keys are used. Pull
requests do not receive AWS credentials.

## Cost estimate

The assessment does not require a paid deployment: a costed and documented
design is acceptable. Formatting, Terraform validation, and local Lambda tests
can be run without creating AWS infrastructure. Skip `terraform apply` if you
do not want AWS charges.

Approximate London (`eu-west-2`) baseline, before usage-based charges:

| Component | Approximate cost / assumption |
|---|---:|
| Interface endpoints (`ssm` and `logs`) | At about $0.01 per endpoint-AZ-hour, 2 endpoints across 2 AZs are about $0.04/hour or $29/month (730 hours), plus data processing. |
| Internal ALB | About $16/month, plus usage/LCU charges. |
| Customer-managed KMS key | About $1/month, plus API requests. |
| Lambda, S3, SSM, CloudWatch Logs/alarm, and SNS | Usage-dependent; likely small for a short test, but not guaranteed to be free. |
| S3 gateway endpoint, VPC, subnets, route tables, security groups, IAM | No direct hourly charge for these resources. |

The assessment's estimate of about $7.50/month per interface endpoint across
two AZs does not match the stated $0.01 per AZ-hour rate: that rate calculates
to about $14.60/month per endpoint across two AZs. For this configuration, the
rough fixed baseline is therefore about $46/month before endpoint data
processing and other usage. Estimates assume 730 hours/month; verify current
prices in the AWS Pricing Calculator before deployment. A run lasting only a
few hours may cost well under £1, as the assessment suggests, but this is not
guaranteed and should not be treated as a spending cap. Free Tier or credits
may reduce charges but are account- and eligibility-dependent.

If a remote state backend is added, include S3 storage/requests and any
DynamoDB lock-table usage in the estimate. The backend is not configured by
this project.

## Test

Run the local Lambda tests:

```sh
python3 -m unittest discover -s tests -v
```

After applying, retrieve the test client certificate and key. Keep the key
private and remove it after testing:

```sh
terraform output -raw client_certificate_pem > client.crt
terraform output -raw client_private_key_pem > client.key
chmod 600 client.key
API_DNS="$(terraform output -raw api_dns_name)"
curl -k --cert client.crt --key client.key \
  -H 'content-type: application/json' \
  -d '{"message":"hello"}' \
  "https://${API_DNS}/"
```

The locally generated server certificate is signed by the assessment CA and
its test hostname does not match the ALB DNS name, so `-k` disables server
certificate verification for this test command. Do not disable server
certificate verification in production. A request without an approved client
certificate should fail during TLS negotiation. Also test malformed JSON, a
missing `message`, and a non-POST method; these should return 400, 400, and 405.

Inspect the Lambda and API-access CloudWatch log groups and confirm the Lambda
error alarm exists. Confirm the ALB scheme is internal and that no public
subnets, internet gateway, or NAT gateway were created.

## Security notes and limitations

- Lambda and server-side access logs avoid recording request bodies.
- Runtime configuration is encrypted in SSM; there are no secret environment
  variables.
- Lambda VPC attachment requires a defined set of EC2 network-interface
  permissions with `Resource = "*"`. An explicit deny conditioned on
  `lambda:SourceFunctionArn` prevents the function code from using those EC2
  permissions; see the [AWS Lambda VPC permissions guidance](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html).
- The test CA and private keys are generated and stored in Terraform state.
  Treat state as sensitive, use encryption and restricted access, and do not
  commit generated keys or state.
- The self-signed CA is for assessment/testing. Production should use a managed
  certificate lifecycle and a controlled private CA.
- ALB log delivery requires SSE-S3. The dedicated log bucket has a 30-day
  lifecycle expiration and is not force-destroyed, so preserve or explicitly
  remove its contents during teardown.
- Interface endpoints incur hourly and data-processing charges. ALB, KMS,
  CloudWatch Logs, and Secrets/SSM usage may also incur charges.
- The GitHub OIDC role is account/repository-specific and should be provisioned
  and reviewed for least privilege before enabling CI plans.

## Gaps and follow-ups

| AWS constraint or gap | What this implementation does and tradeoff | Production follow-up and cost |
|---|---|---|
| An internal ALB is reachable only from networks connected to its VPC, and its generated test certificate does not match the ALB DNS name. | The ALB stays private and accepts only configured CIDRs. Testing uses a locally generated CA and `curl -k`; that bypasses server-certificate validation and is test-only. | Connect clients through approved VPN or VPC connectivity and use internal DNS plus a certificate whose SAN matches the hostname. VPN/connectivity and managed private certificate services may add cost. |
| ALB mutual TLS needs a CA trust bundle in S3; locally generated private keys are retained in Terraform state. | Terraform generates assessment CA, client, and server keys; the CA bundle is stored in a private S3 bucket. This is convenient for a short demonstration but does not provide production key custody or rotation. | Use an enterprise PKI or managed private CA, controlled certificate issuance/rotation, and encrypted, access-restricted remote state. Private CA, KMS, S3, and state-locking resources may add cost. |
| Lambda has no internet route, so it can reach AWS services only through configured private endpoints. | SSM and CloudWatch Logs interface endpoints are deployed in both AZs; S3 uses a gateway endpoint. This avoids NAT but the interface endpoints incur hourly and data-processing charges. | Keep private endpoints, or use a centrally shared endpoint design where appropriate. Include endpoint-AZ hours and processing in the cost estimate. |
| Requests rejected by security groups before reaching the ALB are not logged. Logs are not yet forwarded to a central account. | ALB access and TLS connection logs are delivered to a workload-account S3 bucket with 30-day lifecycle expiration. Lambda also writes structured invocation records to CloudWatch Logs. | Send CloudWatch groups through cross-account subscription filters to a central Firehose/Kinesis destination; deliver ALB logs to a same-region central S3 bucket or replicate from regional buckets. Add VPC Flow Logs if pre-ALB network denies must be audited. Central storage, requests, and retention add usage-based cost. |
| Terraform state must exist before a remote backend can use it, and this project has no backend bootstrap configuration. | The workflow initializes with `-backend=false`, so CI plans start with empty state and do not detect drift against a deployed stack. | Bootstrap a private S3 state bucket and locking mechanism separately, then configure the backend and grant CI narrowly scoped state/read access. S3 and DynamoDB (if used for locking) have usage-based charges. |
| The GitHub OIDC provider and plan role are account-specific and require IAM setup. | They are documented but intentionally not created by this stack; CI runs a plan only and does not apply or destroy resources. | Create the provider and branch-scoped role in the target account, then review least-privilege permissions. IAM has no direct hourly charge; deployment permissions increase operational risk. |

## Teardown

If you deployed the stack, destroy it after testing:

```sh
terraform destroy
```

The CA-bundle S3 bucket is configured for force-destroy. The separate ALB log
bucket is intentionally not force-destroyed; preserve or manually empty its
objects after the required retention period, then rerun `terraform destroy`.
The KMS key is scheduled for deletion with a 7-day waiting period and may
remain visible as pending deletion. The following are outside this stack and
need separate cleanup only if you created them:

- Remote state S3 bucket and DynamoDB lock table.
- GitHub OIDC provider and IAM role.
- Any retained CloudWatch log groups or subscriptions.

Confirm the ALB and interface endpoints are gone and review billing after
teardown. Remove local client files:

```sh
rm -f client.crt client.key
```
