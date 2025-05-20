# AWS Services Used by Polymarket

## 1. AWS Lambda
- **Repository:** routing-api
- **File:** `/bin/stacks/routing-lambda-stack.ts`
  - Used for handling API endpoint routing logic
- **File:** `/bin/stacks/routing-caching-stack.ts`
  - Used for caching liquidity pools

## 2. Amazon API Gateway
- **Repository:** routing-api
- **File:** `/bin/stacks/routing-api-stack.ts`
  - Deploys the REST API for the routing service

## 3. Amazon DynamoDB
- **Repository:** routing-api
- **File:** `/bin/stacks/routing-database-stack.ts`
- DynamoDB tables used include:
  - routesDynamoDb
  - routesDbCachingRequestFlagDynamoDb
  - cachedRoutesDynamoDb
  - cachingRequestFlagDynamoDb
  - cachedV3PoolsDynamoDb
  - cachedV2PairsDynamoDb
  - tokenPropertiesCachingDynamoDb

## 4. Amazon CloudWatch
- **Repository:** routing-api
- **File:** `/bin/stacks/routing-api-stack.ts`
  - Used for monitoring and alerting (e.g., 5XX/4XX errors, latency metrics)
- **File:** `/bin/stacks/routing-dashboard-stack.ts`
  - Defines a CloudWatch dashboard with various metrics

## 5. Amazon S3
- **Repository:** routing-api
- **File:** `/bin/stacks/routing-caching-stack.ts`
- S3 buckets used:
  - poolCacheBucket
  - poolCacheBucket2
  - tokenListCacheBucket
- **Repository:** s3x
- **Files:** `/cmd/api-*.go`
  - Implements an S3-compatible storage layer

## 6. AWS WAF (Web Application Firewall)
- **Repository:** routing-api
- **File:** `/bin/stacks/routing-api-stack.ts`
  - Configured for rate limiting and IP throttling

## 7. Amazon SNS (Simple Notification Service)
- **Repository:** routing-api
- **File:** `/bin/stacks/routing-api-stack.ts`
  - Used for alerting and chatbot notifications

## 8. Amazon CloudFront
- **Repository:** routing-api
- **File:** `/bin/stacks/routing-api-stack.ts`
  - Mentioned in comments regarding EDGE APIs and X-Forwarded-For headers

## 9. Amazon Route 53
- **Repository:** routing-api
- **File:** `/bin/stacks/routing-api-stack.ts`

## 10. AWS CDK (Cloud Development Kit)
- **Repository:** routing-api
- **Directory:** `/bin/stacks/` and other related files
  - Used to define infrastructure-as-code using TypeScript

## 11. AWS IAM (Identity and Access Management)
- **Repository:** routing-api
- **File:** `/bin/stacks/routing-lambda-stack.ts`
  - Defines IAM roles and policies for Lambda functions

## 12. AWS X-Ray
- **Repository:** routing-api
- Configuration: `tracing: aws_lambda.Tracing.ACTIVE`

## 13. Amazon CloudWatch Logs
- **Repository:** routing-api
- **File:** `/bin/stacks/routing-lambda-stack.ts`
  - Configures log retention: `logRetention: RetentionDays.TWO_WEEKS`
- **File:** `/bin/stacks/routing-api-stack.ts`
  - Defines log groups for API access logs

## 14. AWS Auto Scaling
- **Repository:** routing-api
- **File:** `/bin/stacks/routing-lambda-stack.ts`
  - Used for scaling Lambda provisioned concurrency

## 15. AWS Application Auto Scaling
- **Repository:** routing-api
- **File:** `/bin/stacks/routing-lambda-stack.ts`
  - Import: `import * as asg from 'aws-cdk-lib/aws-applicationautoscaling'`
