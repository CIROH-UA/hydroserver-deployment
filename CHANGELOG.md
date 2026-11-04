All notable changes to this project will be documented in this file.
We follow the [Semantic Versioning 2.0.0](http://semver.org/) format.


## Unreleased

### Added

- GitHub Actions workflows and Terraform configuration for deploying HydroServer to AWS, adapted from
  HydroServer deployment workflows for Google Cloud Platform (GCP):
  - *Apply HydroServer Deployment*: plan, review, and apply saved Terraform plans, then run `migrate` and
    `collectstatic`.
  - *Teardown HydroServer Deployment*, *Stage HydroServer Data from Source Environment*,
    *Create HydroServer Admin Account*, and *Run HydroServer Setup Commands*.
- AWS infrastructure: ECS Fargate (web, Celery worker, Celery scheduler), RDS PostgreSQL, ElastiCache,
  S3 static and media buckets, CloudFront with a VPC origin to an internal load balancer, and AWS WAF with
  managed rules and per-IP rate limits.
- CloudWatch alarms, Route 53 uptime check, and EventBridge RDS event alerts, delivered by email through SNS.
- *Validate Terraform* workflow that runs `terraform fmt -check` and `terraform validate` on pull requests.
- IAM deployer policy (`iam/terraform-deployer-policy.json`) scoped to `hs-*` resources.
- README, installation guide, and architecture diagram (`doc/architecture.drawio`).

### Deprecated

- Nothing.

### Removed

- Nothing.

### Fixed

- Nothing.
