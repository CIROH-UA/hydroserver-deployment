[Short description explaining the high-level reason for the pull request]

## Additions

-

## Removals

-

## Changes

-

## Testing

1.

## Screenshots


## Notes

-

## Todos

-

## Checklist

- [ ] PR has an informative and human-readable title
- [ ] Changes are limited to a single goal (no scope creep)
- [ ] Code can be automatically merged (no conflicts)
- [ ] Code follows project standards (link if applicable)
- [ ] Placeholder code is flagged / future todos are captured in comments
- [ ] Project documentation has been updated (including the "Unreleased" section of the CHANGELOG)
- [ ] Reviewers requested with the [Reviewers tool](https://help.github.com/articles/requesting-a-pull-request-review/) :arrow_right:

## Deployment checklist

- [ ] *Validate Terraform* check passes
- [ ] Ran *Apply HydroServer Deployment* in `plan` mode on a dev environment, and the plan shows only the expected
      changes (link the run)
- [ ] Applied to a dev environment, and HydroServer is running
- [ ] New GitHub environment variables are documented in the README or INSTALL, with defaults in `terraform/main.tf`
- [ ] `iam/terraform-deployer-policy.json` is updated if new AWS permissions are needed
- [ ] No secrets, account IDs, or environment-specific values are committed
