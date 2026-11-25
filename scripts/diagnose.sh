#!/usr/bin/env bash
# Read-only checks for the troubleshooting lab. Run from the repo root after
# "terraform apply". It does not change anything, except with --reachability,
# which creates (and then deletes) one VPC Reachability Analyzer path.
#
# Usage: scripts/diagnose.sh [--reachability]
set -uo pipefail

TF="terraform -chdir=terraform"
URL=$($TF output -raw url)
INSTANCE=$($TF output -raw instance_id)
BUCKET=$($TF output -raw bucket)
REGION=$(aws configure get region || true)
REGION=${AWS_REGION:-${REGION:-eu-west-2}}
export AWS_REGION=$REGION

pass() { printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAILED=1; }
FAILED=0

echo "1. Symptom: HTTP request to $URL"
CODE=$(curl -s -o /tmp/lab-body.txt -w '%{http_code}' --max-time 8 "$URL" || true)
case "$CODE" in
  200) pass "HTTP 200: $(head -c 80 /tmp/lab-body.txt)" ;;
  000) fail "no response (timeout). Suspect the network path: routes, NACL, security group." ;;
  *)   fail "HTTP $CODE: $(head -c 200 /tmp/lab-body.txt)" ;;
esac

SUBNET=$(aws ec2 describe-instances --instance-ids "$INSTANCE" --query 'Reservations[0].Instances[0].SubnetId' --output text)
SG=$(aws ec2 describe-instances --instance-ids "$INSTANCE" --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)
MYIP=$(curl -s --max-time 5 https://checkip.amazonaws.com | tr -d '\n')

echo "2. Route table of $SUBNET"
ROUTE=$(aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$SUBNET" \
  --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].GatewayId | [0]" --output text)
if [[ "$ROUTE" == igw-* ]]; then pass "0.0.0.0/0 -> $ROUTE"; else fail "no 0.0.0.0/0 route to an internet gateway"; fi

echo "3. Security group $SG (inbound tcp/80 from your IP $MYIP)"
SG80=$(aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$SG" \
  --query "SecurityGroupRules[?IsEgress==\`false\` && FromPort<=\`80\` && ToPort>=\`80\`].CidrIpv4" --output text)
if [[ -n "$SG80" && "$SG80" != "None" ]]; then pass "port 80 open to: $SG80"; else
  fail "no inbound rule covers port 80. Open ports: $(aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$SG" \
    --query "SecurityGroupRules[?IsEgress==\`false\`].[FromPort,ToPort]" --output text | tr '\t\n' '- ')"
fi

echo "4. Network ACL of $SUBNET (stateless: needs inbound 80 AND outbound 1024-65535)"
NACL_OUT=$(aws ec2 describe-network-acls --filters "Name=association.subnet-id,Values=$SUBNET" \
  --query "NetworkAcls[0].Entries[?Egress==\`true\` && RuleAction=='allow' && PortRange.From<=\`1024\` && PortRange.To>=\`65535\`].CidrBlock" --output text)
if [[ -n "$NACL_OUT" && "$NACL_OUT" != "None" ]]; then pass "outbound ephemeral allowed to: $NACL_OUT"; else fail "no outbound rule for ephemeral ports: replies to the client are dropped"; fi

echo "5. IAM: can the instance role read s3://$BUCKET/message.txt?"
ROLE_ARN=$(aws iam get-role --role-name lab-web-instance --query Role.Arn --output text)
DECISION=$(aws iam simulate-principal-policy --policy-source-arn "$ROLE_ARN" --action-names s3:GetObject \
  --resource-arns "arn:aws:s3:::$BUCKET/message.txt" --query 'EvaluationResults[0].EvalDecision' --output text)
if [[ "$DECISION" == "allowed" ]]; then pass "s3:GetObject is allowed"; else fail "s3:GetObject is $DECISION (check the Resource ARN in the policy)"; fi

if [[ "${1:-}" == "--reachability" ]]; then
  echo "6. VPC Reachability Analyzer: internet gateway -> instance tcp/80 (billed per analysis)"
  IGW=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$($TF output -raw vpc_id)" \
    --query 'InternetGateways[0].InternetGatewayId' --output text)
  PATH_ID=$(aws ec2 create-network-insights-path --source "$IGW" --destination "$INSTANCE" --protocol tcp \
    --destination-port 80 --query NetworkInsightsPath.NetworkInsightsPathId --output text)
  ANALYSIS=$(aws ec2 start-network-insights-analysis --network-insights-path-id "$PATH_ID" \
    --query NetworkInsightsAnalysis.NetworkInsightsAnalysisId --output text)
  for _ in $(seq 1 30); do
    STATUS=$(aws ec2 describe-network-insights-analyses --network-insights-analysis-ids "$ANALYSIS" \
      --query 'NetworkInsightsAnalyses[0].Status' --output text)
    [[ "$STATUS" != "running" ]] && break
    sleep 5
  done
  FOUND=$(aws ec2 describe-network-insights-analyses --network-insights-analysis-ids "$ANALYSIS" \
    --query 'NetworkInsightsAnalyses[0].NetworkPathFound' --output text)
  if [[ "$FOUND" == "True" ]]; then pass "path found"; else
    fail "no path. Blocking component:"
    aws ec2 describe-network-insights-analyses --network-insights-analysis-ids "$ANALYSIS" \
      --query 'NetworkInsightsAnalyses[0].Explanations[].[ExplanationCode,Component.Id]' --output text | sed 's/^/       /'
  fi
  aws ec2 delete-network-insights-analysis --network-insights-analysis-id "$ANALYSIS" >/dev/null
  aws ec2 delete-network-insights-path --network-insights-path-id "$PATH_ID" >/dev/null
fi

echo
if [[ $FAILED -eq 0 ]]; then echo "All checks passed."; else echo "At least one check failed. Read the matching write-up in docs/scenarios/."; fi
exit $FAILED
