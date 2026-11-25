# 03: Website times out after a "small" security group change

`scenario = "sg-wrong-port"`

## Symptom

`curl` times out. Routes and the NACL are correct.

## Investigation

1. `scripts/diagnose.sh` check 3 fails and lists the open ports.
2. Security group rules:

   ```bash
   aws ec2 describe-security-group-rules --filters Name=group-id,Values=<sg-id> \
     --query 'SecurityGroupRules[?IsEgress==`false`].[IpProtocol,FromPort,ToPort,CidrIpv4]' --output table
   ```

   Expected output in this lab: one inbound rule, `tcp 8080-8080 <your-ip>/32`.
3. What does the server listen on? Through Session Manager: `sudo ss -tlnp`. Expected: `0.0.0.0:80 ... python3`.
4. Flow logs show `REJECT` for `dstPort 80`, because the security group drops it.
5. CloudTrail shows who changed it: event `AuthorizeSecurityGroupIngress` or `ModifySecurityGroupRules` on the group.

> **Evidence:** _placeholder. Add the rule table and `ss` output from your own run._

## Root cause

The security group opened port 8080, but the server listens on port 80. Port 80 had no allow rule, so the security group dropped the traffic. Security groups drop silently, so the client sees a timeout, not a "connection refused".

## Fix

Change the rule to tcp/80 (in this lab: `scenario = "healthy"`).

## Prevention

- Define the port once (a Terraform variable or local) and use it in the security group, the target group and the app config.
- A post-deploy smoke test (`curl -f`) in the pipeline catches this before users do.
- Note the difference: timeout means a filter dropped the packet. "Connection refused" means the packet arrived but nothing listens on that port.
