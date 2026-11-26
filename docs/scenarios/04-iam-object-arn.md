# 04: Website returns HTTP 502 "Forbidden" (IAM resource ARN)

`scenario = "iam-object-arn"`

## Symptom

The page loads, so the network is fine. It returns HTTP 502 with the app's error text, similar to:

```text
Web server is up, but it cannot read from S3:
fatal error: An error occurred (403) when calling the HeadObject operation: Forbidden
```

(`aws s3 cp` calls `HeadObject` before `GetObject`. Both need `s3:GetObject`.)

## Investigation

1. **Which identity?** On the instance (Session Manager): `aws sts get-caller-identity`. Expected: the `lab-web-instance` role.
2. **IAM policy simulator** for that role and the exact object:

   ```bash
   aws iam simulate-principal-policy \
     --policy-source-arn arn:aws:iam::<account-id>:role/lab-web-instance \
     --action-names s3:GetObject \
     --resource-arns arn:aws:s3:::<bucket>/message.txt \
     --query 'EvaluationResults[0].[EvalDecision,MatchedStatements]'
   ```

   Expected result in this lab: `implicitDeny` and no matched statements.
3. **Read the policy:**

   ```bash
   aws iam get-role-policy --role-name lab-web-instance --policy-name read-lab-content
   ```

   Expected: `"Resource": "arn:aws:s3:::<bucket>"`, with no `/*`.
4. **Other causes ruled out:** the bucket policy has no deny, Block Public Access does not affect a same-account role, and the object is SSE-S3 (no KMS key policy involved).

> **Evidence:** _placeholder. Add the simulator output and the 502 page from your own run._

## Root cause

S3 actions apply to different resource types. Bucket actions such as `s3:ListBucket` use the bucket ARN `arn:aws:s3:::bucket`. Object actions such as `s3:GetObject` use object ARNs `arn:aws:s3:::bucket/key`. The policy allowed `s3:GetObject` on the bucket ARN only, which matches no object, so every request fell through to an implicit deny.

## Fix

Use the object ARN pattern (in this lab: `scenario = "healthy"`):

```json
{ "Effect": "Allow", "Action": "s3:GetObject", "Resource": "arn:aws:s3:::<bucket>/*" }
```

## Prevention

- Test permissions in the pipeline: run the policy simulator for the few calls the app must be able to make, and fail the build on `implicitDeny`.
- Run IAM Access Analyzer policy validation (`aws accessanalyzer validate-policy`) in CI to catch grammar errors and risky patterns early.
- A 403 from AWS is never a network fault. Read the error text first: it tells you which call failed.
