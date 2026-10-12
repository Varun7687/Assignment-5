# Bluefin Freight AWS Landing Zone — Design

**Status:** Draft for mentor review; do not create AWS resources until the design PR is approved.  
**Version:** 0.1  
**Region assumption:** Asia Pacific (Mumbai), `ap-south-1`  
**Build-window assumption:** 3 days  
**Application assumption:** Reuse the Assignment 4 Flask/MySQL inventory application code and deploy it into the new production VPC; do not attach the old VPC to this landing zone.  
**Cost status:** AWS Pricing Calculator estimate and share/export link are still required before submission.

## 1. Goal and design principles

Provide Bluefin Freight with isolated production and development networks, one controlled administrative entry point, private name resolution, auditable AWS API activity, least-privilege team access, and recoverable database and instance backups.

* Use RFC 1918 private address space and do not overlap the three VPCs.
* Route administration through the shared-services bastion; do not expose SSH on production or development instances to the internet.
* Allow shared-services to reach both workload VPCs, but do not create a production-to-development route.
* Keep the database private and allow application-to-database traffic only.
* Use instance roles instead of embedded AWS access keys for S3 and SNS operations.
* Review this document in a GitHub pull request and obtain mentor approval before provisioning.

## 2. CIDR and subnet plan

All VPCs are in `ap-south-1`. Subnet pairs are placed in two Availability Zones (AZs) for the multi-AZ application and ALB. The CIDRs are examples for this isolated lab and must be checked against any networks that will be connected later.

| VPC | VPC CIDR | Subnet | CIDR | Purpose |
|---|---|---|---|---|
| Shared services | `10.10.0.0/16` | `shared-public-a` | `10.10.0.0/24` | Bastion; internet gateway route |
| Shared services | `10.10.0.0/16` | `shared-public-b` | `10.10.1.0/24` | Reserved second-AZ public subnet |
| Shared services | `10.10.0.0/16` | `shared-private-a` | `10.10.10.0/24` | Optional future shared tools; no workload required for this lab |
| Shared services | `10.10.0.0/16` | `shared-private-b` | `10.10.11.0/24` | Optional future shared tools |
| Production | `10.20.0.0/16` | `prod-public-a` | `10.20.0.0/24` | ALB; NAT Gateway in the selected AZ for lab egress |
| Production | `10.20.0.0/16` | `prod-public-b` | `10.20.1.0/24` | ALB second-AZ subnet |
| Production | `10.20.0.0/16` | `prod-app-a` | `10.20.10.0/24` | Private Auto Scaling instances |
| Production | `10.20.0.0/16` | `prod-app-b` | `10.20.11.0/24` | Private Auto Scaling instances |
| Production | `10.20.0.0/16` | `prod-db-a` | `10.20.20.0/24` | RDS DB subnet group |
| Production | `10.20.0.0/16` | `prod-db-b` | `10.20.21.0/24` | RDS DB subnet group, second AZ |
| Development | `10.30.0.0/16` | `dev-private-a` | `10.30.10.0/24` | Development EC2; no public IP or internet gateway route |
| Development | `10.30.0.0/16` | `dev-private-b` | `10.30.11.0/24` | Reserved second-AZ private subnet |

The subnets reserve room for future resources while keeping application, database, and public ingress tiers distinct. Dev has no public subnet or internet-facing resource. No subnet is shared between VPCs.

## 3. Network traffic policy

| Source | Destination | Allowed traffic | Reason |
|---|---|---|---|
| Approved admin public IP `/32` | Bastion public IP | TCP 22 | Controlled operator entry; never open SSH to `0.0.0.0/0` |
| Bastion subnet `10.10.0.0/24` | Prod app instances | TCP 22 | Linux administration through the bastion only |
| Bastion subnet `10.10.0.0/24` | Dev instance | TCP 22 | Linux administration through the bastion only |
| Internet clients | Production ALB | TCP 80/443 | Application ingress; use HTTPS for the final demo if a certificate is available |
| ALB security group | Prod app security group | Application port (for example TCP 5000) | Only the load balancer can reach the app instances |
| Prod app security group | RDS security group | TCP 3306 | Application database access only |
| Prod app security group | Internet via NAT | Required outbound updates/dependencies only | Private instances have outbound access but no public addresses |
| Shared services | Prod and dev private addresses | Only explicitly needed administration/application ports | TGW reachability is constrained by security groups and routes |
| Prod | Dev | None | Environment isolation; no TGW route or VPC route |
| Dev | Prod | None | Environment isolation; no TGW route or VPC route |

SSH ingress in prod and dev uses the **bastion subnet CIDR** (`10.10.0.0/24`) rather than an entire shared-services VPC CIDR. This is narrow and is easy to demonstrate with the required AWS service set. Keep the bastion subnet dedicated to the bastion; if another resource is later placed there, revise the SSH rule. Security groups remain stateful; NACLs provide a coarse subnet-level guardrail and must allow return/ephemeral traffic.

The bastion should have a public address, a restrictive inbound SSH rule for the administrator's current public IP, and outbound SSH only to the prod/dev private address ranges. Private instances must have no public IP. Use separate key pairs or tightly controlled authorized keys and one Linux login per administrator. Do not reuse a shared Linux account.

## 4. Transit Gateway design

Attach all three VPCs to one Transit Gateway (TGW). Disable default route-table association and propagation so routes are explicitly controlled.

| TGW route table | Associated attachment | Routes installed | Purpose |
|---|---|---|---|
| `tgw-rt-shared` | Shared-services | `10.20.0.0/16` → prod attachment; `10.30.0.0/16` → dev attachment | Shared services can initiate to both environments |
| `tgw-rt-prod` | Production | `10.10.0.0/16` → shared-services attachment | Prod can return traffic to shared services; no dev route |
| `tgw-rt-dev` | Development | `10.10.0.0/16` → shared-services attachment | Dev can return traffic to shared services; no prod route |

VPC route tables must match the TGW design:

* Shared-services private/bastion subnet route table: `10.20.0.0/16` and `10.30.0.0/16` → TGW.
* Prod private app subnet route table: `10.10.0.0/16` → TGW; default route → NAT Gateway for approved egress.
* Prod DB subnet route table: `10.10.0.0/16` → TGW only if administration/monitoring requires it; do not add a default internet route.
* Dev private subnet route table: `10.10.0.0/16` → TGW; no route to prod and no default route to an internet gateway or NAT.
* Public subnet route tables: default route → the VPC internet gateway. Never place the prod app, DB, or dev instance in these subnets.

The TGW route tables do not contain a route between `10.20.0.0/16` and `10.30.0.0/16`. Also omit those routes from the VPC route tables. Security groups are an additional control, not a substitute for this route separation.

## 5. VPC peering comparison decision

Create a temporary peering connection between shared-services and dev, accept it, add the required routes, and perform a controlled private connectivity test. Record the test and then delete the peering connection and its routes before handover.

**Decision: remove the test peering connection.** TGW is the intended long-term hub, and retaining both paths would duplicate connectivity, complicate troubleshooting, and create a risk of inconsistent routing. VPC peering is point-to-point and non-transitive; it does not provide a path from dev through shared-services to prod. TGW is transitive through explicitly configured route tables and is easier to scale as additional VPCs are added. Peering has no TGW attachment/hourly charge but can require many individual connections and routes; TGW introduces attachment and data-processing charges. Confirm the current regional rates in the Pricing Calculator.

## 6. Private DNS plan

Create the Route 53 private hosted zone `bluefin.internal` and associate it with all three VPCs in the same region. Enable DNS support and DNS hostnames on each VPC.

| Record | Type | Target |
|---|---|---|
| `app.prod.bluefin.internal` | Alias A/AAAA where supported | Production ALB |
| `db.prod.bluefin.internal` | CNAME | Current RDS endpoint |
| `dev01.dev.bluefin.internal` | A | Dev instance private IP |

The Flask/MySQL application configuration must refer to `db.prod.bluefin.internal`, never the raw RDS endpoint. The RDS CNAME target should be updated if the RDS endpoint changes. The dev A record must be updated if the instance is replaced with a different private IP. Verify resolution from the bastion and from an authorized instance in each VPC using `dig` or `nslookup`; also verify that the app can resolve and connect to the DB name.

## 7. Production and development compute

Production uses a public ALB across two public subnets, a Launch Template, and an Auto Scaling group spanning two private app subnets. Use desired/minimum capacity 2 for the assignment demo. The app security group accepts the application port only from the ALB security group; SSH is separately limited to the bastion subnet. Place RDS in a DB subnet group covering the two private DB subnets and allow MySQL only from the app security group. A single-AZ small RDS instance is a cost-conscious lab default, not a production availability recommendation; use Multi-AZ if the mentor requires a production-grade availability posture.

Development uses one small EC2 instance in a private subnet, with no public IP and no inbound access other than SSH from the bastion subnet. Because dev has no internet egress by default, use a prebuilt image or approved private artifact path for packages; do not add an internet route merely to simplify setup.

## 8. IAM access model

Create IAM groups `bluefin-admins` and `bluefin-developers`. Use named IAM users only for the required controlled test and prefer federation/role-based access for real users if the account supports it.

| Group | Intended permissions | Guardrails |
|---|---|---|
| `bluefin-admins` | Administrative access for the lab | Enforce MFA with an explicit deny for non-MFA sessions, except the minimum actions needed to enroll/manage MFA and sign in. Do not create long-lived access keys for console users. |
| `bluefin-developers` | Read-only EC2 and RDS visibility; create/update/delete only resources tagged `Environment=dev` | Use custom policies with resource-tag conditions for supported actions and request-tag conditions on create. Restrict `iam:PassRole` to the specific dev instance role. Do not attach broad EC2/RDS full-access managed policies. |

Tag-based access must be tested against the actual actions and resource types because not every AWS API supports resource-level or tag-based authorization identically. The developer test user should be able to inspect EC2/RDS, change an allowed dev resource, and be denied changes to prod/shared resources. The admin test user should be denied required admin actions before MFA and succeed after MFA. Capture policy-simulator or console evidence without exposing credentials.

## 9. Audit, backups, and alerts

### CloudTrail

Create a dedicated S3 bucket for CloudTrail logs. Enable a multi-region trail for management events, log file validation, S3 Block Public Access, versioning, and server-side encryption. The bucket policy should permit delivery only from CloudTrail and limit read access to the audit/admin role. Add lifecycle retention only after the mentor approves a retention period. Store the trail name, bucket name, and validation steps in the runbook.

### Database backups

* Enable RDS automated backups with a 7-day retention period and a defined maintenance/backup window.
* Run `db-backup.sh` nightly on a dedicated prod backup instance or a prod app instance with a narrowly scoped instance profile. Prefer a dedicated backup instance if cost allows.
* Write compressed dumps to `s3://<backup-bucket>/db/YYYY-MM-DD.sql.gz`; encrypt objects and enable bucket versioning. The instance role can write only to the designated backup prefix and publish to the backup SNS topic.
* Keep no more than seven local dump copies and delete local dumps older than seven days with `find`. Log each run to `/var/log/db-backup.log`; publish success only after upload and cleanup succeed, otherwise publish failure and exit nonzero.
* Keep database credentials in a root-readable configuration file with mode `0600` for the lab; never put credentials in the script or Git. A managed secret store is preferable for a production deployment.
* Define S3 retention in the Calculator/design review; proposed starting point is 30 days for daily SQL dumps, subject to mentor approval.

### Development AMI

Create and test an AMI of the dev instance after configuration. Tag the AMI and its snapshots with the required project/environment/owner tags. Retain the handover AMI plus the most recent known-good image; deregister obsolete AMIs and delete their snapshots only after confirming they are not needed for recovery.

### SNS notifications

Create operational SNS topics for Auto Scaling events, RDS events, and backup job results. Configure Auto Scaling notifications for launch/termination events; subscribe to relevant RDS availability, failure, and backup events; have the script publish its success/failure result. Confirm each email subscription and perform a test notification. Do not include secrets or database dump contents in notifications.

## 10. Required tags

Apply these tags to every taggable resource and carry them onto launch-template-created instances, volumes, snapshots, AMIs, and backup objects where supported:

| Tag key | Value |
|---|---|
| `Project` | `BluefinFreight` |
| `Environment` | `shared`, `prod`, or `dev` |
| `Owner` | `VarunKumar` |

Record any AWS resource that cannot be tagged in the handover inventory and explain the nearest taggable parent/resource.

## 11. Cost estimate and approval gate

The following assumptions should be entered into AWS Pricing Calculator for `ap-south-1`. They are planning inputs, not verified prices:

| Cost driver | Estimate assumption to enter |
|---|---|
| EC2 | Bastion `t3.micro`; dev `t3.micro`; prod ASG two `t3.micro` instances running continuously |
| RDS | MySQL `db.t3.micro`, single-AZ lab configuration, 20 GiB gp storage; 7-day automated backup retention |
| ALB | One internet-facing ALB, two AZs, low demo traffic |
| NAT Gateway | One NAT Gateway for the 3-day lab; include hourly and data-processing charges |
| Transit Gateway | One TGW and three VPC attachments for the build window; include hourly and data-processing charges |
| Storage and logging | EBS volumes, S3 CloudTrail logs, S3 database dumps, Route 53 private hosted zone, SNS, and data transfer |
| Runtime | Calculate both 730 hours/month if left running and 72 hours for a 3-day build window; clearly note resources that remain billable after compute is stopped |

**Monthly estimate:** Pending Pricing Calculator output.  
**Three-day build-window estimate:** Pending Pricing Calculator output.  
**AWS Pricing Calculator estimate/share link:** Pending creation and export by the project owner: <https://calculator.aws/>  

Do not treat the 3-day number as the cost if NAT Gateway, TGW, RDS, ALB, EBS, backups, or snapshots remain after the build. The estimate should state whether these resources are deleted, stopped, or retained. Save the calculator share/export link in this section before requesting design approval.

### Approval gate

No AWS resources are to be created until a mentor approves the design PR. The approval should specifically cover the CIDR plan, TGW isolation, single-AZ lab tradeoffs, retention, and cost estimate.

## 12. Design validation checklist

* [ ] Confirm region and CIDRs do not overlap with any network to be connected.
* [ ] Review the design PR and record mentor approval before building.
* [ ] Verify prod can reach required shared services and dev can reach required shared services.
* [ ] Verify prod cannot connect to dev and dev cannot connect to prod.
* [ ] Verify SSH works only through the bastion and direct public SSH is unavailable.
* [ ] Verify DNS records from all three VPCs and application DB configuration uses `db.prod.bluefin.internal`.
* [ ] Verify CloudTrail records a test management API call and log file validation is enabled.
* [ ] Verify admin MFA enforcement and developer allow/deny tests.
* [ ] Verify a database dump uploads, cleanup/logging work, and SNS reports success/failure.
* [ ] Verify the dev AMI exists and its restore path is documented.
* [ ] Record cleanup actions for temporary resources and any resources intentionally retained.
