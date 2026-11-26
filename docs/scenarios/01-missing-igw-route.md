# 01: Website times out (missing internet gateway route)

`scenario = "missing-igw-route"`

## Symptom

`curl http://<public-ip>/` hangs and times out. The instance is `running` and both EC2 status checks pass. Session Manager cannot connect to it either.

## Investigation

1. **Is it the network or the app?** A timeout (no HTTP status at all) points to the network path. An app fault returns a status code, for example 502.
2. **Route table.** The subnet's route table has only the `local` route:

   ```bash
   aws ec2 describe-route-tables --filters Name=association.subnet-id,Values=<subnet-id> \
     --query 'RouteTables[0].Routes[].[DestinationCidrBlock,GatewayId]' --output table
   ```

   Expected output in this lab: one row, `10.42.0.0/16 | local`. There is no `0.0.0.0/0 -> igw-...` row.
3. **Confirm with Reachability Analyzer.** `scripts/diagnose.sh --reachability` builds a path from the internet gateway to the instance on tcp/80. The explanation names the route table as the blocking component.

> **Evidence:** _placeholder. Add a screenshot of the route table and the Reachability Analyzer result from your own run._

## Root cause

A subnet is "public" only because its route table sends `0.0.0.0/0` to an internet gateway. The route was missing, so packets from the instance to the internet had nowhere to go. A public IP on the instance is not enough.

## Fix

Add the default route (in this lab: set `scenario = "healthy"` and apply):

```bash
aws ec2 create-route --route-table-id <rtb-id> --destination-cidr-block 0.0.0.0/0 --gateway-id <igw-id>
```

## Prevention

- Keep routes in Terraform and review `terraform plan` output for removed `aws_route` resources.
- Add an AWS Config rule or a CI test (see `terraform/tests/`) that checks public subnets have a route to an internet gateway.
- Monitor the site from outside AWS (for example a Route 53 health check or CloudWatch Synthetics canary), so a timeout raises an alarm.
