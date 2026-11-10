# CDE network boundary POC (PCI DSS 1.3.1 / 1.3.2)

Terraform proof of concept for a cardholder data environment where inbound
and outbound traffic are restricted to what is necessary and everything else
is explicitly denied. Diagrams: current state vs. this POC are in the
"CDE Network Boundary" artifact.

```
terraform/
├── versions.tf             providers, versions, (commented) S3 backend
├── variables.tf            inputs: region, AZs, client IP list, cert ARN, DB AMI, package URL
├── locals.tf               values fixed by the design: name, CIDR, egress domains, app port
├── network.tf              VPC, 5 subnet tiers x 2 AZ, IGW, NAT
├── routing.tf              route tables: who can leave, and through what
├── nacl.tf                 network ACLs per tier, explicit deny-all last
├── security_groups.tf      stateful rules, SG-to-SG chaining, no 0.0.0.0/0 ingress
├── firewall.tf             AWS Network Firewall: domain allow-list, default drop, logs
├── alb.tf                  internet-facing ALB, HTTPS listener only, existing ACM cert
├── compute_app.tf          launch template + ASG (desired 1) for the app
├── compute_db.tf           MySQL EC2 in the data tier from a pre-baked AMI
├── outputs.tf              ALB DNS, ASG name, DB IP, log group names
├── templates/
│   ├── app-user-data.sh    mandatory package from example.com, DB check, placeholder app
│   └── db-user-data.sh     start the pre-installed server, create the app user
└── terraform.tfvars.example
```

## Traffic paths

| Direction | Path | Controls on the path |
|---|---|---|
| Inbound | client -> IGW -> ALB subnet -> app subnet | ALB SG (443 from list), NACL, app SG (ALB SG only) |
| App egress | app subnet -> firewall endpoint -> NAT subnet -> IGW | app SG (443 only), NACL, Network Firewall (2 domains, drop rest) |
| App -> DB | local route | app SG -> db SG on 3306, NACL |
| DB egress | none | no 0.0.0.0/0 route, no endpoint, db SG has no egress rule, NACL |

## Run it

```
cd terraform
cp terraform.tfvars.example terraform.tfvars   # client list, cert ARN, DB AMI, package URL
terraform init
terraform plan
terraform apply
```

Network Firewall takes several minutes to create. After apply:

```
terraform output alb_dns_name   # curl https://<name>/ from an allow-listed IP
```

The page shows the app host name and whether MySQL answered. There is no
shell access in the POC (no SSH, no SSM). Boot logs:

```
aws ec2 get-console-output --instance-id <id> --latest --output text
```

Egress evidence: the firewall alert log group lists every dropped
connection with its hostname; the flow log lists the allowed ones to
secureweb.com and example.com.

## Evidence for the auditor

- Configuration standard (1.3.1.a / 1.3.2.a): this repository and `terraform plan` output.
- Configuration of the NSCs (1.3.1.b / 1.3.2.b): `terraform show`, console export of SGs, NACLs, firewall policy.
- Runtime proof: firewall alert log (dropped hostnames) and firewall flow log.

## POC shortcuts to remove before production

- `delete_protection` and `subnet_change_protection` on the firewall are off.
- DB password is passed in user data; move it to Secrets Manager or Parameter Store with an interface endpoint.
- No admin access; add SSM interface endpoints (or SSM domains on the firewall allow-list) when a shell is needed.
- Single MySQL instance, no backup, no replica. Consider RDS.
- The DB AMI must be rebuilt for OS patches (Packer pipeline); the running host cannot download anything.
- Local state; enable the S3 backend in `versions.tf` (native S3 locking, Terraform >= 1.10).

## Cost (eu-central-1, rough)

| Item | Monthly |
|---|---|
| Network Firewall, 2 endpoints | ~ $580 + data processing |
| NAT gateways, 2 | ~ $70 + data processing |
| ALB | ~ $20 |
| 2 x t3.micro | ~ $17 |

Single-AZ for the POC halves the firewall and NAT lines.
