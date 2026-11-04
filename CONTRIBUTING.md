# Guidance on how to contribute

> This project is licensed under the [MIT License](LICENSE). By submitting a pull request, you agree that your
> contributions will be licensed under the same terms.

There are two primary ways to help:
 - Using the issue tracker, and
 - Changing the code-base.


## Using the issue tracker

Use the issue tracker to suggest feature requests, report bugs, and ask questions.
This is also a great way to connect with the developers of the project as well
as others who are interested in this solution.

Use the issue tracker to find ways to contribute. Find a bug or a feature, mention in
the issue that you will take on that effort, then follow the _Changing the code-base_
guidance below.

Issues are public. Don't include secrets, passwords, AWS account IDs, or other details about a specific
deployment. Report security vulnerabilities privately, as described in [SECURITY](SECURITY.md).


## Changing the code-base

Generally speaking, you should fork this repository, make changes in your
own fork, and then submit a pull request. Follow the stylistic and architectural patterns
in the existing workflows and Terraform configuration.

Pull requests are checked automatically by the *Validate Terraform* workflow, which runs `terraform fmt` and
`terraform validate`. It doesn't connect to AWS, so it can't catch everything. Before submitting a pull request:

- Run `terraform fmt -recursive` on any Terraform you changed, so the formatting check passes.
- Run the *Apply HydroServer Deployment* workflow in `plan` mode on a dev environment and confirm the plan shows only
  the changes you expect. If you can, apply it and confirm HydroServer is still running.
- Document any new GitHub environment variables in the [README](README.md) or [INSTALL](INSTALL.md), and give them a
  default in `terraform/main.tf`.
- Update [`iam/terraform-deployer-policy.json`](iam/terraform-deployer-policy.json) if your change needs new AWS
  permissions.
- Add a summary of your change to the "Unreleased" section of the [CHANGELOG](CHANGELOG.md).
