# 02: Website times out, security group looks correct (stateless NACL)

`scenario = "nacl-ephemeral"`

## Symptom

`curl` times out. The route table has a default route to the internet gateway. The security group allows tcp/80 from your IP.

## Investigation

1. **Rule out routes and security group.** `scripts/diagnose.sh` checks 2 and 3 pass. Check 4 fails.
2. **Network ACL entries** for the subnet:

   ```bash
   aws ec2 describe-network-acls --filters Name=association.subnet-id,Values=<subnet-id> \
     --query 'NetworkAcls[0].Entries[].[RuleNumber,Egress,RuleAction,Protocol,PortRange.From,PortRange.To,CidrBlock]' --output table
   ```

   Expected output in this lab: inbound rule 100 allows tcp/80 from your IP. Outbound has rule 100 (tcp/443) and the default `*` deny. Nothing allows tcp 1024-65535 back to your IP.
3. **VPC flow logs** (log group `/lab/vpc-flow-logs`). In CloudWatch Logs Insights:

   ```text
   fields @timestamp, srcAddr, srcPort, dstAddr, dstPort, action
   | filter action = "REJECT" and srcPort = 80
   | sort @timestamp desc
   | limit 20
   ```

   Expected result: records with `srcPort 80` from the instance to your IP on a high port, marked `REJECT`. The request got in; the reply was dropped on the way out.

> **Evidence:** _placeholder. Add the NACL table and the flow log query result from your own run._

## Root cause

Security groups are stateful: a reply to an allowed request is allowed automatically. Network ACLs are stateless: the reply is a new packet that needs its own outbound rule. The client opened the connection from an ephemeral port (Linux uses 32768-60999, Windows 49152-65535), so the NACL must allow outbound tcp 1024-65535 to the client.

## Fix

Add the outbound ephemeral rule (in this lab: `scenario = "healthy"`):

```bash
aws ec2 create-network-acl-entry --network-acl-id <acl-id> --egress --rule-number 110 \
  --protocol tcp --port-range From=1024,To=65535 --cidr-block <your-ip>/32 --rule-action allow
```

## Prevention

- Use security groups for most filtering. Use NACLs only for broad subnet-level denies, and always add the matching return rule.
- Keep VPC flow logs on. `REJECT` records with a well-known source port are the signature of this fault.
