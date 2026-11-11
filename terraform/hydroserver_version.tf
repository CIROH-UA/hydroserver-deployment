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
  hydroserver_supported_major = 2

  # Environment variables passed to every HydroServer container.
  hydroserver_app_env = {
    # Networking / security
    STRICT_SECURITY      = "True"
    PROXY_BASE_URL       = var.proxy_base_url
    SAME_ORIGIN_FRONTEND = "True"
    CSRF_TRUSTED_ORIGINS = var.csrf_trusted_origins
    ALLOWED_HOSTS        = var.allowed_hosts
    DEBUG                = var.debug_enabled
    NOINDEX              = var.noindex_enabled
    SESSION_COOKIE_NAME  = var.session_cookie_name
    CACHE_URL            = "rediss://${local.redis_host}:6379/0"
    CELERY_BROKER_URL    = "rediss://${local.redis_host}:6379/1?ssl_cert_reqs=required"

    # Storage
    SSL_REQUIRED           = "True"
    STATIC_STORAGE_BACKEND = "storages.backends.s3.S3Storage"
    STATIC_STORAGE_OPTIONS = jsonencode({
      bucket_name      = aws_s3_bucket.hydroserver_static_bucket.bucket
      region_name      = var.aws_region
      location         = "static"
      custom_domain    = local.proxy_host
      querystring_auth = false
    })
    MEDIA_STORAGE_BACKEND = "storages.backends.s3.S3Storage"
    MEDIA_STORAGE_OPTIONS = jsonencode({
      bucket_name      = aws_s3_bucket.hydroserver_media_bucket.bucket
      region_name      = var.aws_region
      location         = "media"
      custom_domain    = local.proxy_host
      querystring_auth = false
    })
    MEDIA_STORAGE_ENABLED = var.media_storage_enabled

    # Rate limiting
    API_RATE_LIMITS     = var.api_rate_limits
    ACCOUNT_RATE_LIMITS = var.account_rate_limits

    # Accounts / auth
    ACCOUNT_SIGNUP_ENABLED    = var.account_signup_enabled
    ACCOUNT_OWNERSHIP_ENABLED = var.account_ownership_enabled
    SOCIALACCOUNT_SIGNUP_ONLY = var.socialaccount_signup_only
    IDP_OIDC_ENABLED          = var.idp_oidc_enabled

    # Email
    DEFAULT_FROM_EMAIL           = var.auto_email
    SERVICE_ACCOUNT_EMAIL_DOMAIN = var.service_account_email_domain

    # Logging
    LOG_FORMAT = var.log_format
  }

  # Secrets Manager secrets passed to every HydroServer container. The ECS execution role can only read these.
  hydroserver_app_secret_env = {
    DATABASE_URL         = aws_secretsmanager_secret.hydroserver_database_url.arn
    SMTP_URL             = aws_secretsmanager_secret.hydroserver_smtp_url.arn
    SECRET_KEY           = aws_secretsmanager_secret.hydroserver_secret_key.arn
    IDP_OIDC_PRIVATE_KEY = aws_secretsmanager_secret.hydroserver_idp_oidc_private_key.arn
  }

  # Object ownership for the media bucket. BucketOwnerEnforced turns off ACLs, which works because HydroServer
  # doesn't send ACLs with media uploads.
  hydroserver_media_object_ownership = "BucketOwnerEnforced"

  # S3 object actions HydroServer needs in addition to s3:GetObject, s3:PutObject and s3:DeleteObject.
  hydroserver_extra_object_actions = []
}
