# Installation instructions

These steps set up a new HydroServer deployment in AWS. See the [README](README.md) for an overview of the
deployment, the full list of [configuration settings](README.md#configuration), and how to
[manage existing deployments](README.md#usage).

## Provision a HydroServer Deployment

### GitHub Environment Setup

1. In this repository (`hydroserver-deployment`), create a new environment with a short, unique name
   (e.g., `dev`, `test`, `prod`).
   - Under **Deployment branches and tags**, choose *Selected branches and tags* and add the branches deployments run
     from (e.g., `main`). AWS only grants workflow access to jobs running in an environment.
   - Add the environment name to the deployer role's trust policy (see *AWS Account Setup*, *Step 6*). Workflows
     can't authenticate to AWS from an environment that isn't listed there.
2. Create the following variables in the GitHub environment:

   - **PROXY_BASE_URL**
     The base URL HydroServer will be served from, including the HTTP scheme.
     *Example*: `https://hydroserver.ciroh.org`

   - **HYDROSERVER_VERSION**
     The tag of the HydroServer release you want to deploy. See https://github.com/hydroserver2/hydroserver/releases.
     This variable is required, and `latest` isn't allowed. To deploy a new release, change this value and rerun the
     *Apply HydroServer Deployment* workflow.
     *Example*: `v2.0.0`
     <!-- TODO: Remove after all environments are on v2. See "HydroServer v1 and v2" in README. -->
     Deploy v1 releases from the `v1` branch, and v2 releases from `main`.

     *WARNING*: Don't deploy prerelease builds (e.g., `v2.0.0b7`) to production instances. These builds are meant to
     be used for dev and test instances and may break Django's database migration history.

   - **PUBLIC_ACCESS_ENABLED**
     Controls whether HydroServer is reachable from the internet. While this is `false`, Terraform creates the
     CloudFront distribution disabled and doesn't let CloudFront read the static and media buckets. This should be set
     to `false` during initial set up. After the services are created, AWS account administrators should resolve
     anything that would block a public CloudFront distribution (see
     [Deploy HydroServer](#deploy-hydroserver)). Then change this value to `true`
     and rerun the *Apply HydroServer Deployment* workflow. The buckets and load balancer are never public themselves,
     so HydroServer is only reachable at `PROXY_BASE_URL`.

   - **PREVENT_DATA_DELETION**
     Controls whether the *Teardown HydroServer Deployment* workflow can be run, and prevents deletion of the RDS
     database and media bucket. This can be set to `false` for testing or development deployments, but should always
     be set to `true` for production instances.

   - **PREVENT_SERVICE_DELETION**
     Turns on deletion protection for the load balancer and prevents deletion of a static bucket that still has files
     in it. Set this to `false` before running the *Teardown HydroServer Deployment* workflow.
     *Default*: `true`

### AWS Account Setup

1. Choose the **AWS account** that will host HydroServer. Each account can host multiple deployments if environment
   names are unique. Every resource Terraform creates is named `hs-<environment>` (or starts with it) and tagged with
   `hydroserver:environment`.
2. Create a private **S3 bucket** to store Terraform state, in the region HydroServer will be deployed in. The bucket
   name must be globally unique.
   ```
   aws s3api create-bucket --bucket <bucket-name> --region <region> \
     --create-bucket-configuration LocationConstraint=<region>
   aws s3api put-public-access-block --bucket <bucket-name> \
     --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
   aws s3api put-bucket-versioning --bucket <bucket-name> --versioning-configuration Status=Enabled
   ```
   Leave out `--create-bucket-configuration` in `us-east-1`. Versioning lets earlier state versions be restored if a
   deployment needs to be rolled back.
   - Add a lifecycle rule that deletes saved Terraform plans (stored under `plans/`) after 14 days. Save the following
     as `lifecycle.json`:
     ```json
     {"Rules": [
       {"ID": "expire-saved-plans", "Status": "Enabled", "Filter": {"Prefix": "plans/"},
        "Expiration": {"Days": 14}, "NoncurrentVersionExpiration": {"NoncurrentDays": 1}}
     ]}
     ```
     Then run `aws s3api put-bucket-lifecycle-configuration --bucket <bucket-name> --lifecycle-configuration file://lifecycle.json`.
     This replaces any lifecycle rules already on the bucket, so check for existing rules first with
     `aws s3api get-bucket-lifecycle-configuration --bucket <bucket-name>` and merge them in.
3. Use **AWS Certificate Manager** in **us-east-1** to request a public certificate for the domain/subdomain HydroServer
   will use, and complete its DNS validation. CloudFront only uses certificates from us-east-1. If HydroServer will be
   deployed in a different region, request a second certificate for the same domain in that region for the load
   balancer.
   - Choose **RSA 2048** or **ECDSA P 256** as the key algorithm. The load balancer doesn't accept larger RSA keys.
   - The certificate must be **Issued** before the first deployment.
4. Create an **IAM OIDC identity provider** to connect GitHub Actions to the AWS account. This only needs to be done
   once per account.
   ```
   aws iam create-open-id-connect-provider \
     --url https://token.actions.githubusercontent.com \
     --client-id-list sts.amazonaws.com
   ```
5. Create an **IAM policy** for Terraform to provision and manage AWS services. Copy
   [`iam/terraform-deployer-policy.json`](iam/terraform-deployer-policy.json), replace `<ACCOUNT_ID>` and
   `<TERRAFORM_BUCKET>`, and create it:
   ```
   aws iam create-policy --policy-name hydroserver-terraform --policy-document file://terraform-deployer-policy.json
   ```
   Permissions may need updates periodically if workflows fail due to insufficient access. See
   [Required IAM Permissions](#required-iam-permissions-for-terraform-aws-role).
6. Create an **IAM role** for provisioning AWS services that GitHub Actions can assume. Save the following as
   `trust-policy.json`, listing every GitHub environment that deploys to this account:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Principal": {"Federated": "arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com"},
       "Action": "sts:AssumeRoleWithWebIdentity",
       "Condition": {
         "StringEquals": {
           "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
           "token.actions.githubusercontent.com:sub": [
             "repo:CIROH-UA@119541160/hydroserver-deployment@1444965402:environment:dev",
             "repo:CIROH-UA@119541160/hydroserver-deployment@1444965402:environment:test",
             "repo:CIROH-UA@119541160/hydroserver-deployment@1444965402:environment:prod"
           ]
         }
       }
     }]
   }
   ```
   The `sub` values must match GitHub's token exactly, including case. GitHub includes the organization and
   repository IDs in the subject (`<org>@<org-id>/<repo>@<repo-id>`) for this repository. A fork or a repository in
   another organization has different IDs, or may use the shorter `repo:<org>/<repo>:environment:<name>` format. If
   a workflow fails with `Not authorized to perform sts:AssumeRoleWithWebIdentity`, find the failed
   `AssumeRoleWithWebIdentity` event in CloudTrail *Event history* (in **AWS_REGION**). Its `userIdentity` shows the
   subject GitHub sent, which you can copy into the trust policy.

   Then create the role and attach the policy from *Step 5*. Some workflows run for more than an hour, so the role's
   maximum session duration is two hours. If you create the role in the AWS console instead, choose
   *Custom trust policy*, and after creating it, edit the role's *Maximum session duration* to 2 hours. Otherwise
   workflows fail with `The requested DurationSeconds exceeds the MaxSessionDuration set for this role`.
   ```
   aws iam create-role --role-name hydroserver-terraform \
     --assume-role-policy-document file://trust-policy.json --max-session-duration 7200
   aws iam attach-role-policy --role-name hydroserver-terraform \
     --policy-arn arn:aws:iam::<account-id>:policy/hydroserver-terraform
   ```
7. In the GitHub environment for the deployment, create the following additional variables.

   - **AWS_REGION**
     The AWS region HydroServer will be deployed in. Choose a region physically near where most HydroServer users will
     be located if possible. `us-east-1` is simplest, because one certificate then covers both CloudFront and the
     load balancer.
     *Example*: `us-east-1`

   - **AWS_ACCOUNT_ID**
     The ID of the AWS account from *Step 1*. Terraform refuses to run against any other account.
     *Example*: `123456789012`

   - **TERRAFORM_BUCKET**
     The name of the S3 bucket you created in *Step 2*. This bucket will store the Terraform state generated by the
     GitHub Actions workflows in this repository. To avoid untracked AWS resources, never delete or modify this bucket
     or its contents unless all HydroServer deployments within the account have been fully decommissioned using the
     *Teardown HydroServer Deployment* workflow.

   - **CLOUDFRONT_CERTIFICATE_ARN**
     The ARN of the us-east-1 certificate you created in *Step 3*.
     *Example*: `arn:aws:acm:us-east-1:123456789012:certificate/0f1e2d3c-...`

   - **ALB_CERTIFICATE_ARN**
     The ARN of the regional certificate you created in *Step 3*. Only required when **AWS_REGION** isn't
     `us-east-1`.

   - **AWS_ROLE_ARN**
     The ARN of the role you created in *Step 6*. Terraform will use this role to provision necessary HydroServer
     resources in AWS.
     *Example*: `arn:aws:iam::123456789012:role/hydroserver-terraform`

   - **IAM_PERMISSIONS_BOUNDARY_ARN**
     The ARN of an IAM permissions boundary to attach to the roles Terraform creates for ECS. Only needed if the
     account requires one.
     *Default*: `` (no boundary)

### Deploy HydroServer

Every deployment is planned, reviewed, and applied with the *Apply HydroServer Deployment* workflow, as described in
[HydroServer Terraform Apply Workflow](README.md#hydroserver-terraform-apply-workflow). Optional settings are
described in [Configuration](README.md#configuration).

For a new deployment:

1. Plan and apply as described above. A first apply takes 20–30 minutes, mostly waiting for RDS, ElastiCache and
   CloudFront.
2. After the apply finishes successfully, AWS administrators should:
   - Make sure no organization policy (SCP) or account setting blocks a public CloudFront distribution, or a bucket
     policy that lets CloudFront read the static and media buckets. If one does, add an exception for resources
     tagged `hydroserver:environment`.
   - Create a **CNAME record** in the domain's DNS pointing to the CloudFront distribution's domain name. The apply
     log prints it as `cloudfront_domain_name` (e.g., `d1234abcd.cloudfront.net`). It's also listed in the CloudFront
     console. If the domain is hosted in Route 53, use an alias record instead.
3. Update **PUBLIC_ACCESS_ENABLED** to `true` in the GitHub environment, then plan and apply again.
4. Verify HydroServer is running at the configured domain.
5. See [HydroServer documentation](https://hydroserver.org/hosting-and-deployment/how-to/using-the-administrator-dashboard.html) for completing the deployment.

## Required IAM Permissions for Terraform AWS Role

[`iam/terraform-deployer-policy.json`](iam/terraform-deployer-policy.json) lists the permissions the deployer role
needs. Most are limited to resources whose names start with `hs-`, so the role can't change other workloads in the
same account:

- **IAM**: Terraform creates two roles per environment (`hs-<environment>-ecs-execution` and
  `hs-<environment>-ecs-task`). The policy only lets it create roles named `hs-*`, attach the AWS-managed
  `AmazonECSTaskExecutionRolePolicy` to them, and pass them to ECS. It can also create the service-linked roles ECS,
  Application Auto Scaling, Elastic Load Balancing, RDS, ElastiCache, and CloudFront VPC origins need the first time
  they're used in an account.
- **Scoped to `hs-*` resources**: ECR, ECS, Elastic Load Balancing, RDS, ElastiCache, S3 (`hs-static-*` and
  `hs-media-*`), Secrets Manager, CloudWatch Logs, CloudWatch alarms, SNS, and EventBridge.
- **Not scoped by name**: VPC and security group management, CloudFront, WAF, and Route 53 health checks. These
  resources have generated IDs, so the policy can't limit them by name. Application Auto Scaling and ECS task
  definition registration are also unscoped.
- **Terraform state**: read and write access to **TERRAFORM_BUCKET**.

If the account requires a permissions boundary on new roles, set **IAM_PERMISSIONS_BOUNDARY_ARN** and add a condition
to the policy's `Roles` statement requiring `iam:PermissionsBoundary` to equal that ARN.
