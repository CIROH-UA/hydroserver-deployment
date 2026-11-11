# ---------------------------------
# HydroServer Version Settings
# ---------------------------------

# Settings that depend on the HydroServer major version. This is the only file that differs between the main
# branch (HydroServer v2) and the v1 branch (HydroServer v1). The hydroserver_version variable in main.tf must
# match hydroserver_supported_major, so each branch only deploys the HydroServer versions it's configured for.
#
# TODO: Remove after all environments are on v2. Move these values back into ecs.tf and s3.tf, delete this file,
# and remove the major version check on hydroserver_version in main.tf.

locals {
  hydroserver_supported_major = 1

  # Environment variables passed to every HydroServer container. HydroServer v1 doesn't read the v2-only settings
  # (rate limits, OIDC, cache, session cookie, log format and service account email domain), so those variables
  # have no effect on this branch.
  hydroserver_app_env = merge(
    {
      # Networking / security
      DEPLOYMENT_BACKEND = "aws"
      PROXY_BASE_URL     = var.proxy_base_url
      DEBUG              = var.debug_enabled
      NOINDEX            = var.noindex_enabled
      CELERY_BROKER_URL  = "rediss://${local.redis_host}:6379/1?ssl_cert_reqs=required"

      # Storage
      SSL_REQUIRED       = "True"
      MEDIA_BUCKET_NAME  = aws_s3_bucket.hydroserver_media_bucket.bucket
      STATIC_BUCKET_NAME = aws_s3_bucket.hydroserver_static_bucket.bucket

      # Accounts / auth
      ACCOUNT_SIGNUP_ENABLED    = var.account_signup_enabled
      ACCOUNT_OWNERSHIP_ENABLED = var.account_ownership_enabled
      SOCIALACCOUNT_SIGNUP_ONLY = var.socialaccount_signup_only

      # Email
      DEFAULT_FROM_EMAIL = var.auto_email
    },
    # v1 only uses its defaults when these are missing, not when they're empty. An empty ALLOWED_HOSTS would reject
    # requests to PROXY_BASE_URL's host, so they're only set when they have a value.
    var.allowed_hosts != "" ? { ALLOWED_HOSTS = var.allowed_hosts } : {},
    var.csrf_trusted_origins != "" ? { TRUSTED_ORIGINS = var.csrf_trusted_origins } : {},
  )

  # Secrets Manager secrets passed to every HydroServer container. The ECS execution role can only read these.
  # v1 doesn't use the OIDC private key, so its secret is created but not passed.
  hydroserver_app_secret_env = {
    DATABASE_URL = aws_secretsmanager_secret.hydroserver_database_url.arn
    SMTP_URL     = aws_secretsmanager_secret.hydroserver_smtp_url.arn
    SECRET_KEY   = aws_secretsmanager_secret.hydroserver_secret_key.arn
  }

  # Object ownership for the media bucket. v1 sends ACL "private" with media uploads, which buckets with ACLs turned
  # off (BucketOwnerEnforced) reject. BucketOwnerPreferred allows the ACL, and the public access block still keeps
  # objects private.
  hydroserver_media_object_ownership = "BucketOwnerPreferred"

  # S3 object actions HydroServer needs in addition to s3:GetObject, s3:PutObject and s3:DeleteObject. v1 needs
  # s3:PutObjectAcl to send the media upload ACL.
  hydroserver_extra_object_actions = ["s3:PutObjectAcl"]
}
