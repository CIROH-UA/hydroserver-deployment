# Security Policy

There MUST be no unpatched vulnerabilities of medium or higher severity that have been publicly known for more than 60 days. 

The vulnerability must be patched and released by the project itself (patches may be developed elsewhere). A vulnerability becomes publicly known (for this purpose) once it has a CVE with publicly released non-paywalled information (reported, for example, in the <a href="https://nvd.nist.gov/">National Vulnerability Database</a>) or when the project has been informed and the information has been released to the public (possibly by the project). A vulnerability is considered medium or higher severity if its <a href="https://www.first.org/cvss/" >Common Vulnerability Scoring System (CVSS)</a> base qualitative score is medium or higher. In CVSS versions 2.0 through 3.1, this is equivalent to a CVSS score of 4.0 or higher. Projects may use the CVSS score as published in a widely-used vulnerability database (such as the <a href="https://nvd.nist.gov">National Vulnerability Database</a>) using the most-recent version of CVSS reported in that database. Projects may instead calculate the severity themselves using the latest version of <a href="https://www.first.org/cvss/">CVSS</a> at the time of the vulnerability disclosure, if the calculation inputs are publicly revealed once the vulnerability is publicly known. <strong>Note</strong>: this means that users might be left vulnerable to all attackers worldwide for up to 60 days. This criterion is often much easier to meet than what Google recommends in <a href="https://security.googleblog.com/2010/07/rebooting-responsible-disclosure-focus.html">Rebooting responsible disclosure</a>, because Google recommends that the 60-day period start when the project is notified _even_ if the report is not public. Also note that this badge criterion, like other criteria, applies to the individual project. Some projects are part of larger umbrella organizations or larger projects, possibly in multiple layers, and many projects feed their results to other organizations and projects as part of a potentially-complex supply chain. An individual project often cannot control the rest, but an individual project can work to release a vulnerability patch in a timely way. Therefore, we focus solely on the individual project's response time.  Once a patch is available from the individual project, others can determine how to deal with the patch (e.g., they can update to the newer version or they can apply just the patch as a cherry-picked solution).

The public repositories MUST NOT leak any valid private credential (e.g., a working password or private key) that is intended to limit public access.

## Supported Versions

This project is in beta and doesn't publish maintained release branches. Security fixes are made on the `main`
branch only. Deployments should run the latest workflows and Terraform configuration from `main`.

This repository deploys HydroServer but doesn't contain HydroServer's source code. Which HydroServer release a
deployment runs is set by its **HYDROSERVER_VERSION** variable, so keep that up to date with
[HydroServer releases](https://github.com/hydroserver2/hydroserver/releases) as well.

## Reporting a Vulnerability

Don't report security vulnerabilities in public issues, pull requests, or discussions.

Report them privately using GitHub's
[private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability):
open this repository's **Security** tab and select **Report a vulnerability**. Include the affected workflow or
Terraform file, the steps to reproduce the issue, and its impact. Don't include working credentials, AWS account IDs,
or other details about a specific deployment.

Maintainers will acknowledge the report, investigate it, and keep you updated through the private advisory. If the
report is accepted, the fix is released on `main` and the advisory is published once deployments have had a chance to
update. If it's declined, the advisory explains why.

Vulnerabilities in HydroServer itself (rather than in how this repository deploys it) should be reported to the
[HydroServer project](https://github.com/hydroserver2/hydroserver) instead.
