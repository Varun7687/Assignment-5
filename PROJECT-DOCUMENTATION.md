# Assignment 5 — Project Documentation

## Scope

This is the `us-east-1` Bluefin landing-zone lab baseline. It combines Terraform networking, compute, database, IAM, DNS, backup, audit, and notification resources with an adapted Assignment 4 inventory application. It is not approved for deployment merely because it is packaged or published.

## Network inventory

All CIDRs below are source configuration, not evidence of existing AWS resources.

| VPC | Public subnets a / b | Private subnets a / b | Database subnets a / b |
|---|---|---|---|
| Shared `10.50.0.0/16` | `10.50.0.0/24` / `10.50.1.0/24` | `10.50.10.0/24` / `10.50.11.0/24` | None |
| Prod `10.60.0.0/16` | `10.60.0.0/24` / `10.60.1.0/24` | `10.60.10.0/24` / `10.60.11.0/24` | `10.60.20.0/24` / `10.60.21.0/24` |
| Dev `10.70.0.0/16` | None | `10.70.10.0/24` / `10.70.11.0/24` | `10.70.20.0/24` / `10.70.21.0/24` |

AZ a is `us-east-1a`; AZ b is `us-east-1b` in the selected baseline. Configure and independently verify the AZs privately.

Shared and Prod public routes use their own internet gateways. Their private routes use one NAT gateway per VPC, in public-a. Database route tables have no internet default route. Dev has neither an internet gateway nor a NAT/default internet route.

Each VPC attaches to the Transit Gateway using its private-a/private-b subnets. Shared TGW routing receives Prod and Dev routes; each environment has a route back to Shared, not to the other environment. Security groups further limit allowed ports.

The optional Shared–Dev peering connection is created by default, but its routes are disabled. Enabling `enable_peering_routes` replaces the Shared–Dev private-path routes with peering routes while keeping the Dev DB subnet return path on TGW. Review forward and return paths before any exercise change; do not assume peering is transitive.

## Compute and data

| Component | Configuration |
|---|---|
| Bastion | Shared public-a; public address; per-admin Linux users and public keys |
| Application | Prod private-a/b; launch template; fixed two-instance ASG; rolling refresh configured |
| Load balancer | Internet-facing ALB in Prod public-a/b; HTTP 80; target group 8080; `/health` requires schema access |
| Backup host | Prod private-a; schema initialization; cron-based database backups |
| Development host | Dev private-a; associated AMI resource captures an OS baseline, not proven application readiness |
| Database | Private RDS MySQL; encrypted storage; one instance; automated retention default 7 days |
| Application table | `inventory.items`; ten demo records created by bootstrap |

The backup bootstrap creates the database table and a separate `bluefinapp` MySQL user with SELECT/INSERT/UPDATE/DELETE on the inventory database and REQUIRE SSL. Only the backup role reads the bootstrap/master secret; the app role reads the app secret. An old reconstructed starter's `inventory.inventory` table is not automatically migrated into `inventory.items`.

The bootstrap and backup scripts use the private DB CNAME. PyMySQL checks the RDS CA chain but disables hostname verification for that CNAME; the dump client uses the RDS CA bundle. Review TLS hostname verification before any production use.

## DNS, storage, and notifications

* Private hosted zone: `bluefin.internal`, associated with Shared, Prod, and Dev.
* Records: `app.prod.bluefin.internal`, `db.prod.bluefin.internal`, and `dev01.dev.bluefin.internal`.
* Backups: nightly 02:00 UTC, gzip, private S3 `db/` prefix; at most seven local dated copies; S3 current/noncurrent dump expiration set to 30 days.
* S3 backup and audit buckets: public access blocked, versioning enabled, AES256 encryption, and policy requiring secure transport.
* CloudTrail: multi-region trail with log-file validation. This baseline does not add S3 object-level data-event selectors.
* Notifications: backup script publishes success/failure; EventBridge forwards selected ASG events; RDS event subscription forwards selected database event categories. Email subscriptions require recipient confirmation.

## IAM and operational review

The lab creates named admin/developer groups and test users but no login profile or access keys. Admins receive AdministratorAccess plus an MFA-conditioned deny policy. Developers have broad read discovery plus selected management of already `Environment=dev` tagged EC2/RDS resources; retagging is explicitly denied. This is an instructional policy, not a guarantee that every developer API workflow works under tag conditions. Review each relevant action and resource type with the mentor.

The app has an SSM managed-policy attachment, but no dedicated SSM endpoints are provisioned here; successful session management still depends on the agent and outbound service connectivity. Bastion and Dev do not have the app instance profile.

SCP restrictions remain authoritative over IAM allows. Do not remove security controls or change region solely to bypass an unapproved deployment boundary.

## State compatibility and revision boundary

The package preserves 107 resource block declarations and one data block declaration from the repaired baseline, including resource labels, networking keys, naming defaults, and the original provider lockfile. This is a declaration comparison, not an AWS state import or a guarantee of zero replacements.

Modified integration files include the app, HTML template, requirements, `locals.tf`, app user-data template, DB bootstrap schema, offline checks, public example variables, and documentation. These changes can update the launch template and refresh application instances in an approved apply. No existing private state was copied into the public package.

Compare any subsequent local edits, including IAM tag changes, before copying files into your state-bearing working directory. Do not overwrite local changes blindly. No latest local plan was reviewed while this package was created.

## Validation performed while packaging

* Nine offline source/template checks passed: variable/resource references, local file dependencies, policy JSON, Python syntax, shell syntax, user-data sizes, basic balanced HCL delimiters, no added discovery lookups, and sensitive-file exclusions within the Terraform folder.
* Twelve mocked application contract tests passed. They check credentials/configuration, schema health behavior, template/schema inputs, insert parameterization, validation, error handling, and public example inputs.
* Sample rendered user-data sizes: app 11,774 bytes; backup 10,227 bytes; bastion 601 bytes. The checks use synthetic fixtures; actual input lengths can change the result.
* Resource declarations were compared to the repaired source; networking and compute resource files are unchanged.

These checks do not run Terraform's parser/provider, real Flask/Jinja, MySQL, AWS APIs, deployment, or restoration. Run Terraform formatting, validation, a fresh plan, and approved end-to-end tests in the correct account before considering an apply.
