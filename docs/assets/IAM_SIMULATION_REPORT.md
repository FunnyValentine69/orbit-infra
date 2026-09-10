# IAM simulation report

This publication renders account `000000000000` only.

## Publication metadata

| Field | Value |
| --- | --- |
| recorded_on | 2026-09-10 |
| generator commit | 0ae9a1e |

## Case results

| Case ID | Mode | Expected | Observed | Matched Sids | Pass |
| --- | --- | --- | --- | --- | --- |
| case:aws_iam_policy.deployer_data:ClickhouseSecretCreateWithTag:ALL:aws:RequestTag/Project:absent | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:ClickhouseSecretCreateWithTag:ALL:aws:RequestTag/Project:matching | custom | allowed | allowed | ClickhouseSecretCreateWithTag | yes |
| case:aws_iam_policy.deployer_data:ClickhouseSecretCreateWithTag:ALL:aws:RequestTag/Project:non-matching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:ClickhouseSecretCreateWithTag:ALL:resource:nonmatching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:absent | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:matching | custom | allowed | allowed | ClickhouseSecretReadModifyWithResourceTag | yes |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:resource:nonmatching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:ClickhouseSecretTagResourceExisting:ALL:aws:ResourceTag/Project:absent | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:ClickhouseSecretTagResourceExisting:ALL:aws:ResourceTag/Project:matching | custom | allowed | allowed | ClickhouseSecretTagResourceExisting | yes |
| case:aws_iam_policy.deployer_data:ClickhouseSecretTagResourceExisting:ALL:aws:ResourceTag/Project:non-matching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:ClickhouseSecretTagResourceExisting:ALL:resource:nonmatching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:aws:RequestTag/Project:absent | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:aws:RequestTag/Project:matching | custom | allowed | allowed | CloudwatchAlarmCreateWithTag | yes |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:aws:RequestTag/Project:non-matching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:resource:nonmatching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:aws:ResourceTag/Project:absent | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:aws:ResourceTag/Project:matching | custom | allowed | allowed | CloudwatchAlarmRestWithResourceTag | yes |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:resource:nonmatching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:EcrVerificationAuth:ALL:none:matching | custom | allowed | allowed | EcrVerificationAuth | yes |
| case:aws_iam_policy.deployer_data:EcrVerificationPull:ALL:none:matching | custom | allowed | allowed | EcrVerificationPull | yes |
| case:aws_iam_policy.deployer_data:EcrVerificationPull:ALL:resource:nonmatching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | custom | allowed | allowed | EnvDataBucketLifecycle, S3BucketDescribeReads | yes |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:resource:nonmatching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:LogsCreateWithTag:ALL:aws:RequestTag/Project:absent | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:LogsCreateWithTag:ALL:aws:RequestTag/Project:matching | custom | allowed | allowed | LogsCreateWithTag | yes |
| case:aws_iam_policy.deployer_data:LogsCreateWithTag:ALL:aws:RequestTag/Project:non-matching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:LogsCreateWithTag:ALL:resource:nonmatching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:LogsDescribeStarOnly:ALL:none:matching | custom | allowed | allowed | LogsDescribeStarOnly | yes |
| case:aws_iam_policy.deployer_data:LogsModifyDeleteWithResourceTag:ALL:aws:ResourceTag/Project:absent | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:LogsModifyDeleteWithResourceTag:ALL:aws:ResourceTag/Project:matching | custom | allowed | allowed | LogsModifyDeleteWithResourceTag | yes |
| case:aws_iam_policy.deployer_data:LogsModifyDeleteWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:LogsModifyDeleteWithResourceTag:ALL:resource:nonmatching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:LogsTagResourceExisting:ALL:aws:ResourceTag/Project:absent | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:LogsTagResourceExisting:ALL:aws:ResourceTag/Project:matching | custom | allowed | allowed | LogsTagResourceExisting | yes |
| case:aws_iam_policy.deployer_data:LogsTagResourceExisting:ALL:aws:ResourceTag/Project:non-matching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:LogsTagResourceExisting:ALL:resource:nonmatching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:S3BucketDescribeReads:ALL:none:matching | custom | allowed | allowed | S3BucketDescribeReads | yes |
| case:aws_iam_policy.deployer_data:S3BucketDescribeReads:ALL:resource:nonmatching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:SigningPublicKeyRead:ALL:kms:ResourceAliases:absent | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:SigningPublicKeyRead:ALL:kms:ResourceAliases:none-matching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:SigningPublicKeyRead:ALL:kms:ResourceAliases:one-matching | custom | allowed | allowed | SigningPublicKeyRead | yes |
| case:aws_iam_policy.deployer_data:SigningPublicKeyRead:ALL:resource:nonmatching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:aws:RequestTag/Project:absent | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:aws:RequestTag/Project:matching | custom | allowed | allowed | SnsCreateWithTag | yes |
| case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:aws:RequestTag/Project:non-matching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:resource:nonmatching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:absent | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:matching | custom | allowed | allowed | SnsRestWithResourceTag | yes |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:resource:nonmatching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:SnsSubscriptionManage:ALL:none:matching | custom | allowed | implicitDeny | none | no |
| case:aws_iam_policy.deployer_data:SnsSubscriptionManage:ALL:resource:nonmatching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:TagDiscovery:ALL:none:matching | custom | allowed | allowed | TagDiscovery | yes |
| case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForCreateActions:ALL:aws:RequestTag/Project:absent | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForCreateActions:ALL:aws:RequestTag/Project:matching | custom | allowed | allowed | Ec2CreateTagsForCreateActions | yes |
| case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForCreateActions:ALL:aws:RequestTag/Project:non-matching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForCreateActions:ALL:ec2:CreateAction:absent | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForCreateActions:ALL:ec2:CreateAction:matching | custom | allowed | allowed | Ec2CreateTagsForCreateActions | yes |
| case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForCreateActions:ALL:ec2:CreateAction:non-matching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForResourceTag:ALL:ec2:ResourceTag/Project:absent | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForResourceTag:ALL:ec2:ResourceTag/Project:matching | custom | allowed | allowed | Ec2CreateTagsForResourceTag | yes |
| case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForResourceTag:ALL:ec2:ResourceTag/Project:non-matching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:absent | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:matching | custom | allowed | allowed | Ec2CreateWithTag | yes |
| case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:non-matching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_ec2:Ec2DeleteTags:ALL:ec2:ResourceTag/Project:absent | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_ec2:Ec2DeleteTags:ALL:ec2:ResourceTag/Project:matching | custom | allowed | allowed | Ec2DeleteTags | yes |
| case:aws_iam_policy.deployer_ec2:Ec2DeleteTags:ALL:ec2:ResourceTag/Project:non-matching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:absent | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:matching | custom | allowed | allowed | Ec2DescribeStarOnly | yes |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:non-matching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:absent | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | custom | allowed | allowed | Ec2ModifyDeleteWithResourceTag | yes |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:non-matching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_ec2:Ec2SecurityGroupRuleCreateWithTag:ALL:aws:RequestTag/Project:absent | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_ec2:Ec2SecurityGroupRuleCreateWithTag:ALL:aws:RequestTag/Project:matching | custom | allowed | allowed | Ec2SecurityGroupRuleCreateWithTag | yes |
| case:aws_iam_policy.deployer_ec2:Ec2SecurityGroupRuleCreateWithTag:ALL:aws:RequestTag/Project:non-matching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsCreateWithTag:ALL:aws:RequestTag/Project:absent | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsCreateWithTag:ALL:aws:RequestTag/Project:matching | custom | allowed | allowed | EcsCreateWithTag | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsCreateWithTag:ALL:aws:RequestTag/Project:non-matching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsListDescribeTasksForProjectClusters:ALL:ecs:cluster:absent | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsListDescribeTasksForProjectClusters:ALL:ecs:cluster:matching | custom | allowed | allowed | EcsListDescribeTasksForProjectClusters | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsListDescribeTasksForProjectClusters:ALL:ecs:cluster:non-matching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsListServicesClusterScoped:ALL:ecs:cluster:absent | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsListServicesClusterScoped:ALL:ecs:cluster:matching | custom | allowed | allowed | EcsListServicesClusterScoped | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsListServicesClusterScoped:ALL:ecs:cluster:non-matching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:absent | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:matching | custom | allowed | allowed | EcsModifyDeleteDescribeWithResourceTag | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:non-matching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsStarOnly:ALL:none:matching | custom | allowed | allowed | EcsStarOnly | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsTagResource:ALL:aws:RequestTag/Project:absent | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsTagResource:ALL:aws:RequestTag/Project:matching | custom | allowed | allowed | EcsTagResource | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsTagResource:ALL:aws:RequestTag/Project:non-matching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsTagResource:ALL:ecs:CreateAction:absent | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsTagResource:ALL:ecs:CreateAction:matching | custom | allowed | allowed | EcsTagResource | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsTagResource:ALL:ecs:CreateAction:non-matching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsTagResourceExisting:ALL:ecs:ResourceTag/Project:absent | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsTagResourceExisting:ALL:ecs:ResourceTag/Project:matching | custom | allowed | allowed | EcsTagResourceExisting | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsTagResourceExisting:ALL:ecs:ResourceTag/Project:non-matching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsUntabledActions:ALL:none:matching | custom | allowed | allowed | EcsUntabledActions | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsUntagAndListTags:ALL:ecs:ResourceTag/Project:absent | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsUntagAndListTags:ALL:ecs:ResourceTag/Project:matching | custom | allowed | allowed | EcsUntagAndListTags | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsUntagAndListTags:ALL:ecs:ResourceTag/Project:non-matching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbAddTags:ALL:aws:RequestTag/Project:absent | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbAddTags:ALL:aws:RequestTag/Project:matching | custom | allowed | allowed | ElbAddTags | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbAddTags:ALL:aws:RequestTag/Project:non-matching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbAddTags:ALL:elasticloadbalancing:CreateAction:absent | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbAddTags:ALL:elasticloadbalancing:CreateAction:matching | custom | allowed | allowed | ElbAddTags | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbAddTags:ALL:elasticloadbalancing:CreateAction:non-matching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbAddTagsForResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:absent | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbAddTagsForResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:matching | custom | allowed | allowed | ElbAddTagsForResourceTag | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbAddTagsForResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:non-matching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbCreateWithTag:ALL:aws:RequestTag/Project:absent | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbCreateWithTag:ALL:aws:RequestTag/Project:matching | custom | allowed | allowed | ElbCreateWithTag | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbCreateWithTag:ALL:aws:RequestTag/Project:non-matching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbDescribeStarOnly:ALL:none:matching | custom | allowed | allowed | ElbDescribeStarOnly | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbDescribeTargetHealth:ALL:none:matching | custom | allowed | allowed | ElbDescribeTargetHealth | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:absent | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:matching | custom | allowed | allowed | ElbModifyDeleteWithResourceTag | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:non-matching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbRemoveTags:ALL:elasticloadbalancing:ResourceTag/Project:absent | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbRemoveTags:ALL:elasticloadbalancing:ResourceTag/Project:matching | custom | allowed | allowed | ElbRemoveTags | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbRemoveTags:ALL:elasticloadbalancing:ResourceTag/Project:non-matching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:Route53HostedZoneRead:ALL:none:matching | custom | allowed | allowed | Route53HostedZoneRead | yes |
| case:aws_iam_policy.deployer_elb_ecs:Route53HostedZoneStarOnly:ALL:none:matching | custom | allowed | allowed | Route53HostedZoneStarOnly | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateNamespaceWithTag:ALL:aws:RequestTag/Project:absent | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateNamespaceWithTag:ALL:aws:RequestTag/Project:matching | custom | allowed | allowed | ServiceDiscoveryCreateNamespaceWithTag | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateNamespaceWithTag:ALL:aws:RequestTag/Project:non-matching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateServiceWithTag:ALL:aws:RequestTag/Project:absent | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateServiceWithTag:ALL:aws:RequestTag/Project:matching | custom | allowed | allowed | ServiceDiscoveryCreateServiceWithTag | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateServiceWithTag:ALL:aws:RequestTag/Project:non-matching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:absent | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:matching | custom | allowed | allowed | ServiceDiscoveryReadDeleteUpdateWithResourceTag | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryStarOnlyNoCondition:ALL:none:matching | custom | allowed | allowed | ServiceDiscoveryStarOnlyNoCondition | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryTagResource:ALL:aws:RequestTag/Project:absent | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryTagResource:ALL:aws:RequestTag/Project:matching | custom | allowed | allowed | ServiceDiscoveryTagResource | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryTagResource:ALL:aws:RequestTag/Project:non-matching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryTagResourceExisting:ALL:aws:ResourceTag/Project:absent | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryTagResourceExisting:ALL:aws:ResourceTag/Project:matching | custom | allowed | allowed | ServiceDiscoveryTagResourceExisting | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryTagResourceExisting:ALL:aws:ResourceTag/Project:non-matching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryUntagResource:ALL:aws:TagKeys:absent | custom | allowed | allowed | ServiceDiscoveryUntagResource | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryUntagResource:ALL:aws:TagKeys:all-matching | custom | allowed | allowed | ServiceDiscoveryUntagResource | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryUntagResource:ALL:aws:TagKeys:any-non-matching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:TagInventoryStarOnly:ALL:none:matching | custom | allowed | allowed | TagInventoryStarOnly | yes |
| case:aws_iam_policy.deployer_guard:DenyMutatingOwnControlRoles:ALL:none:non-protected-resource | custom | attribution-only | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_guard:DenyMutatingOwnControlRoles:ALL:none:protected-resource | custom | explicitDeny | explicitDeny | DenyMutatingOwnControlRoles | yes |
| case:aws_iam_policy.deployer_iam:DenyDeleteRolePermissionsBoundary:ALL:none:protected-resource | custom | explicitDeny | explicitDeny | DenyDeleteRolePermissionsBoundary | yes |
| case:aws_iam_policy.deployer_iam:DenyRoleMutationMissingBoundary:ALL:iam:PermissionsBoundary:absent | custom | explicitDeny | explicitDeny | DenyRoleMutationMissingBoundary, DenyRoleMutationWrongBoundary | yes |
| case:aws_iam_policy.deployer_iam:DenyRoleMutationMissingBoundary:ALL:iam:PermissionsBoundary:present | custom | attribution-only | explicitDeny | DenyRoleMutationWrongBoundary | yes |
| case:aws_iam_policy.deployer_iam:DenyRoleMutationMissingBoundary:ALL:none:protected-resource | custom | explicitDeny | explicitDeny | DenyRoleMutationMissingBoundary, DenyRoleMutationWrongBoundary | yes |
| case:aws_iam_policy.deployer_iam:DenyRoleMutationWrongBoundary:ALL:iam:PermissionsBoundary:absent | custom-isolated | explicitDeny | explicitDeny | DenyRoleMutationWrongBoundary | yes |
| case:aws_iam_policy.deployer_iam:DenyRoleMutationWrongBoundary:ALL:iam:PermissionsBoundary:different | custom | explicitDeny | explicitDeny | DenyRoleMutationWrongBoundary | yes |
| case:aws_iam_policy.deployer_iam:DenyRoleMutationWrongBoundary:ALL:iam:PermissionsBoundary:equal | custom | attribution-only | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:DenyRoleMutationWrongBoundary:ALL:none:protected-resource | custom | explicitDeny | explicitDeny | DenyRoleMutationWrongBoundary | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRoleAttachPolicy:ALL:iam:PermissionsBoundary:absent | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRoleAttachPolicy:ALL:iam:PermissionsBoundary:matching | custom | allowed | allowed | EnvServiceRoleAttachPolicy | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRoleAttachPolicy:ALL:iam:PermissionsBoundary:non-matching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRoleAttachPolicy:ALL:iam:PolicyARN:absent | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRoleAttachPolicy:ALL:iam:PolicyARN:matching | custom | allowed | allowed | EnvServiceRoleAttachPolicy | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRoleAttachPolicy:ALL:iam:PolicyARN:non-matching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRoleAttachPolicy:ALL:resource:nonmatching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRoleCreateWithBoundary:ALL:iam:PermissionsBoundary:absent | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRoleCreateWithBoundary:ALL:iam:PermissionsBoundary:matching | custom | allowed | allowed | EnvServiceRoleCreateWithBoundary | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRoleCreateWithBoundary:ALL:iam:PermissionsBoundary:non-matching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRoleCreateWithBoundary:ALL:resource:nonmatching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRoleLifecycle:ALL:none:matching | custom | allowed | allowed | EnvServiceRoleLifecycle | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRoleLifecycle:ALL:resource:nonmatching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRolePermissionsBoundarySet:ALL:iam:PermissionsBoundary:absent | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRolePermissionsBoundarySet:ALL:iam:PermissionsBoundary:matching | custom | allowed | allowed | EnvServiceRolePermissionsBoundarySet | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRolePermissionsBoundarySet:ALL:iam:PermissionsBoundary:non-matching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRolePermissionsBoundarySet:ALL:resource:nonmatching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRolePutPolicy:ALL:iam:PermissionsBoundary:absent | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRolePutPolicy:ALL:iam:PermissionsBoundary:matching | custom | allowed | allowed | EnvServiceRolePutPolicy | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRolePutPolicy:ALL:iam:PermissionsBoundary:non-matching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRolePutPolicy:ALL:resource:nonmatching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleEcs:ALL:iam:AWSServiceName:absent | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleEcs:ALL:iam:AWSServiceName:matching | custom | allowed | allowed | IamServiceLinkedRoleEcs | yes |
| case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleEcs:ALL:iam:AWSServiceName:non-matching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleEcs:ALL:resource:nonmatching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleElb:ALL:iam:AWSServiceName:absent | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleElb:ALL:iam:AWSServiceName:matching | custom | allowed | allowed | IamServiceLinkedRoleElb | yes |
| case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleElb:ALL:iam:AWSServiceName:non-matching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleElb:ALL:resource:nonmatching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:PassEnvRolesOnly:ALL:iam:PassedToService:absent | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:PassEnvRolesOnly:ALL:iam:PassedToService:matching | custom | allowed | allowed | PassEnvRolesOnly | yes |
| case:aws_iam_policy.deployer_iam:PassEnvRolesOnly:ALL:iam:PassedToService:non-matching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:PassEnvRolesOnly:ALL:resource:nonmatching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_state:ListStateBucket:ALL:resource:nonmatching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_state:ListStateBucket:ALL:s3:prefix:absent | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_state:ListStateBucket:ALL:s3:prefix:matching | custom | allowed | allowed | ListStateBucket | yes |
| case:aws_iam_policy.deployer_state:ListStateBucket:ALL:s3:prefix:non-matching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_state:StateAndLeaseObjects:ALL:none:matching | custom | allowed | allowed | StateAndLeaseObjects | yes |
| case:aws_iam_policy.deployer_state:StateAndLeaseObjects:ALL:resource:nonmatching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.task_boundary:EcrAuth:ALL:none:in-boundary | custom | allowed | allowed | EcrAuth | yes |
| case:aws_iam_policy.task_boundary:EcrAuth:ALL:none:outside-boundary | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.task_boundary:EcrPull:ALL:none:in-boundary | custom | allowed | allowed | EcrPull | yes |
| case:aws_iam_policy.task_boundary:EcrPull:ALL:none:outside-boundary | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.task_boundary:EcrPull:ALL:resource:nonmatching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.task_boundary:EcsExec:ALL:none:in-boundary | custom | allowed | allowed | EcsExec | yes |
| case:aws_iam_policy.task_boundary:EcsExec:ALL:none:outside-boundary | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.task_boundary:LogStreams:ALL:none:in-boundary | custom | allowed | allowed | LogStreams | yes |
| case:aws_iam_policy.task_boundary:LogStreams:ALL:none:outside-boundary | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.task_boundary:LogStreams:ALL:resource:nonmatching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.task_boundary:ProjectDataBucket:ALL:none:in-boundary | custom | allowed | allowed | ProjectDataBucket | yes |
| case:aws_iam_policy.task_boundary:ProjectDataBucket:ALL:none:outside-boundary | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.task_boundary:ProjectDataBucket:ALL:resource:nonmatching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.task_boundary:ProjectSecrets:ALL:none:in-boundary | custom | allowed | allowed | ProjectSecrets | yes |
| case:aws_iam_policy.task_boundary:ProjectSecrets:ALL:none:outside-boundary | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.task_boundary:ProjectSecrets:ALL:resource:nonmatching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:none:non-protected-resource | custom | attribution-only | {"s3:ListBucketVersions\|arn:aws:s3:::outside-79s5rw-resource":"implicitDeny","s3:ListBucket\|arn:aws:s3:::outside-79s5rw-resource":"explicitDeny"} | DenyListBucketOutsideScope | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:none:protected-resource | custom | explicitDeny | explicitDeny | DenyListBucketMissingPrefix, DenyListBucketOutsideScopePrefix | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:s3:prefix:absent | custom | explicitDeny | explicitDeny | DenyListBucketMissingPrefix, DenyListBucketOutsideScopePrefix | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:s3:prefix:present | custom | attribution-only | implicitDeny | none | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScope:ALL:none:non-protected-resource | custom | allowed | implicitDeny | none | no |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScope:ALL:none:protected-resource | custom | explicitDeny | explicitDeny | DenyListBucketOutsideScope | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:none:non-protected-resource | custom | attribution-only | {"s3:ListBucketVersions\|arn:aws:s3:::outside-79s5rw-resource":"implicitDeny","s3:ListBucket\|arn:aws:s3:::outside-79s5rw-resource":"explicitDeny"} | DenyListBucketOutsideScope | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:none:protected-resource | custom | explicitDeny | explicitDeny | DenyListBucketOutsideScopePrefix | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:s3:prefix:absent | custom | explicitDeny | explicitDeny | DenyListBucketMissingPrefix, DenyListBucketOutsideScopePrefix | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:s3:prefix:inside-set | custom | attribution-only | implicitDeny | none | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:s3:prefix:outside-set | custom | explicitDeny | explicitDeny | DenyListBucketOutsideScopePrefix | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenyReadStateObjectsOutsideScope:ALL:none:non-protected-resource | custom | attribution-only | implicitDeny | none | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenyReadStateObjectsOutsideScope:ALL:none:protected-resource | custom | explicitDeny | explicitDeny | DenyReadStateObjectsOutsideScope | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenySecretsAndParams:ALL:none:protected-resource | custom | explicitDeny | explicitDeny | DenySecretsAndParams | yes |
| case:aws_iam_role_policy.plan_reader_state:ListStatePrefixes:ALL:resource:nonmatching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_role_policy.plan_reader_state:ListStatePrefixes:ALL:s3:prefix:absent | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_role_policy.plan_reader_state:ListStatePrefixes:ALL:s3:prefix:matching | custom | allowed | allowed | ListStatePrefixes | yes |
| case:aws_iam_role_policy.plan_reader_state:ListStatePrefixes:ALL:s3:prefix:non-matching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_role_policy.plan_reader_state:ReadStateObjects:ALL:none:matching | custom | allowed | allowed | ReadStateObjects | yes |
| case:aws_iam_role_policy.plan_reader_state:ReadStateObjects:ALL:resource:nonmatching | custom-isolated | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_role_policy.publisher:EcrAuth:ALL:none:matching | custom | allowed | allowed | EcrAuth | yes |
| case:aws_iam_role_policy.publisher:EcrPushPull:ALL:none:matching | custom | allowed | allowed | EcrPushPull | yes |
| case:aws_iam_role_policy.publisher:EcrPushPull:ALL:resource:nonmatching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_role_policy.publisher:SigningKey:ALL:kms:ResourceAliases:absent | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_role_policy.publisher:SigningKey:ALL:kms:ResourceAliases:none-matching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_role_policy.publisher:SigningKey:ALL:kms:ResourceAliases:one-matching | custom | allowed | allowed | SigningKey | yes |
| case:aws_iam_role_policy.publisher:SigningKey:ALL:resource:nonmatching | custom | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:ClickhouseSecretCreateWithTag:ALL:aws:RequestTag/Project:matching | principal | allowed | allowed | ClickhouseSecretCreateWithTag | yes |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:absent | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:matching | principal | allowed | allowed | ClickhouseSecretReadModifyWithResourceTag | yes |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:resource:nonmatching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:ClickhouseSecretTagResourceExisting:ALL:aws:ResourceTag/Project:matching | principal | allowed | allowed | ClickhouseSecretTagResourceExisting | yes |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:aws:RequestTag/Project:absent | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:aws:RequestTag/Project:matching | principal | allowed | allowed | CloudwatchAlarmCreateWithTag | yes |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:aws:RequestTag/Project:non-matching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:resource:nonmatching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:aws:ResourceTag/Project:absent | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:aws:ResourceTag/Project:matching | principal | allowed | allowed | CloudwatchAlarmRestWithResourceTag | yes |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:resource:nonmatching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:EcrVerificationAuth:ALL:none:matching | principal | allowed | allowed | EcrVerificationAuth | yes |
| case:aws_iam_policy.deployer_data:EcrVerificationPull:ALL:none:matching | principal | allowed | allowed | EcrVerificationPull | yes |
| case:aws_iam_policy.deployer_data:EcrVerificationPull:ALL:resource:nonmatching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | principal | allowed | allowed | EnvDataBucketLifecycle, S3BucketDescribeReads | yes |
| case:aws_iam_policy.deployer_data:LogsCreateWithTag:ALL:aws:RequestTag/Project:matching | principal | allowed | allowed | LogsCreateWithTag | yes |
| case:aws_iam_policy.deployer_data:LogsDescribeStarOnly:ALL:none:matching | principal | allowed | allowed | LogsDescribeStarOnly | yes |
| case:aws_iam_policy.deployer_data:LogsModifyDeleteWithResourceTag:ALL:aws:ResourceTag/Project:absent | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:LogsModifyDeleteWithResourceTag:ALL:aws:ResourceTag/Project:matching | principal | allowed | allowed | LogsModifyDeleteWithResourceTag | yes |
| case:aws_iam_policy.deployer_data:LogsModifyDeleteWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:LogsModifyDeleteWithResourceTag:ALL:resource:nonmatching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:LogsTagResourceExisting:ALL:aws:ResourceTag/Project:matching | principal | allowed | allowed | LogsTagResourceExisting | yes |
| case:aws_iam_policy.deployer_data:S3BucketDescribeReads:ALL:none:matching | principal | allowed | allowed | S3BucketDescribeReads | yes |
| case:aws_iam_policy.deployer_data:SigningPublicKeyRead:ALL:kms:ResourceAliases:absent | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:SigningPublicKeyRead:ALL:kms:ResourceAliases:none-matching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:SigningPublicKeyRead:ALL:kms:ResourceAliases:one-matching | principal | allowed | allowed | SigningPublicKeyRead | yes |
| case:aws_iam_policy.deployer_data:SigningPublicKeyRead:ALL:resource:nonmatching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:aws:RequestTag/Project:absent | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:aws:RequestTag/Project:matching | principal | allowed | allowed | SnsCreateWithTag | yes |
| case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:aws:RequestTag/Project:non-matching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:resource:nonmatching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:absent | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:matching | principal | allowed | allowed | SnsRestWithResourceTag | yes |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:resource:nonmatching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:SnsSubscriptionManage:ALL:none:matching | principal | allowed | implicitDeny | none | no |
| case:aws_iam_policy.deployer_data:SnsSubscriptionManage:ALL:resource:nonmatching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_data:TagDiscovery:ALL:none:matching | principal | allowed | allowed | TagDiscovery | yes |
| case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForCreateActions:ALL:aws:RequestTag/Project:matching | principal | allowed | allowed | Ec2CreateTagsForCreateActions | yes |
| case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForCreateActions:ALL:ec2:CreateAction:matching | principal | allowed | allowed | Ec2CreateTagsForCreateActions | yes |
| case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForResourceTag:ALL:ec2:ResourceTag/Project:matching | principal | allowed | allowed | Ec2CreateTagsForResourceTag | yes |
| case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:absent | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:matching | principal | allowed | allowed | Ec2CreateWithTag | yes |
| case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:non-matching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_ec2:Ec2DeleteTags:ALL:ec2:ResourceTag/Project:absent | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_ec2:Ec2DeleteTags:ALL:ec2:ResourceTag/Project:matching | principal | allowed | allowed | Ec2DeleteTags | yes |
| case:aws_iam_policy.deployer_ec2:Ec2DeleteTags:ALL:ec2:ResourceTag/Project:non-matching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:absent | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:matching | principal | allowed | allowed | Ec2DescribeStarOnly | yes |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:non-matching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | principal | allowed | allowed | Ec2ModifyDeleteWithResourceTag | yes |
| case:aws_iam_policy.deployer_ec2:Ec2SecurityGroupRuleCreateWithTag:ALL:aws:RequestTag/Project:matching | principal | allowed | allowed | Ec2SecurityGroupRuleCreateWithTag | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsCreateWithTag:ALL:aws:RequestTag/Project:absent | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsCreateWithTag:ALL:aws:RequestTag/Project:matching | principal | allowed | allowed | EcsCreateWithTag | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsCreateWithTag:ALL:aws:RequestTag/Project:non-matching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsListDescribeTasksForProjectClusters:ALL:ecs:cluster:absent | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsListDescribeTasksForProjectClusters:ALL:ecs:cluster:matching | principal | allowed | allowed | EcsListDescribeTasksForProjectClusters | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsListDescribeTasksForProjectClusters:ALL:ecs:cluster:non-matching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsListServicesClusterScoped:ALL:ecs:cluster:absent | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsListServicesClusterScoped:ALL:ecs:cluster:matching | principal | allowed | allowed | EcsListServicesClusterScoped | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsListServicesClusterScoped:ALL:ecs:cluster:non-matching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:absent | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:matching | principal | allowed | allowed | EcsModifyDeleteDescribeWithResourceTag | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:non-matching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsStarOnly:ALL:none:matching | principal | allowed | allowed | EcsStarOnly | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsTagResource:ALL:aws:RequestTag/Project:matching | principal | allowed | allowed | EcsTagResource | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsTagResource:ALL:ecs:CreateAction:matching | principal | allowed | allowed | EcsTagResource | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsTagResourceExisting:ALL:ecs:ResourceTag/Project:matching | principal | allowed | allowed | EcsTagResourceExisting | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsUntabledActions:ALL:none:matching | principal | allowed | allowed | EcsUntabledActions | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsUntagAndListTags:ALL:ecs:ResourceTag/Project:absent | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsUntagAndListTags:ALL:ecs:ResourceTag/Project:matching | principal | allowed | allowed | EcsUntagAndListTags | yes |
| case:aws_iam_policy.deployer_elb_ecs:EcsUntagAndListTags:ALL:ecs:ResourceTag/Project:non-matching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbAddTags:ALL:aws:RequestTag/Project:matching | principal | allowed | allowed | ElbAddTags | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbAddTags:ALL:elasticloadbalancing:CreateAction:matching | principal | allowed | allowed | ElbAddTags | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbAddTagsForResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:matching | principal | allowed | allowed | ElbAddTagsForResourceTag | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbCreateWithTag:ALL:aws:RequestTag/Project:absent | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbCreateWithTag:ALL:aws:RequestTag/Project:matching | principal | allowed | allowed | ElbCreateWithTag | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbCreateWithTag:ALL:aws:RequestTag/Project:non-matching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbDescribeStarOnly:ALL:none:matching | principal | allowed | allowed | ElbDescribeStarOnly | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbDescribeTargetHealth:ALL:none:matching | principal | allowed | allowed | ElbDescribeTargetHealth | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:absent | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:matching | principal | allowed | allowed | ElbModifyDeleteWithResourceTag | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:non-matching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbRemoveTags:ALL:elasticloadbalancing:ResourceTag/Project:absent | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbRemoveTags:ALL:elasticloadbalancing:ResourceTag/Project:matching | principal | allowed | allowed | ElbRemoveTags | yes |
| case:aws_iam_policy.deployer_elb_ecs:ElbRemoveTags:ALL:elasticloadbalancing:ResourceTag/Project:non-matching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:Route53HostedZoneRead:ALL:none:matching | principal | allowed | allowed | Route53HostedZoneRead | yes |
| case:aws_iam_policy.deployer_elb_ecs:Route53HostedZoneStarOnly:ALL:none:matching | principal | allowed | allowed | Route53HostedZoneStarOnly | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateNamespaceWithTag:ALL:aws:RequestTag/Project:absent | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateNamespaceWithTag:ALL:aws:RequestTag/Project:matching | principal | allowed | allowed | ServiceDiscoveryCreateNamespaceWithTag | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateNamespaceWithTag:ALL:aws:RequestTag/Project:non-matching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateServiceWithTag:ALL:aws:RequestTag/Project:absent | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateServiceWithTag:ALL:aws:RequestTag/Project:matching | principal | allowed | allowed | ServiceDiscoveryCreateServiceWithTag | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateServiceWithTag:ALL:aws:RequestTag/Project:non-matching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:absent | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:matching | principal | allowed | allowed | ServiceDiscoveryReadDeleteUpdateWithResourceTag | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryStarOnlyNoCondition:ALL:none:matching | principal | allowed | allowed | ServiceDiscoveryStarOnlyNoCondition | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryTagResource:ALL:aws:RequestTag/Project:matching | principal | allowed | allowed | ServiceDiscoveryTagResource | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryTagResourceExisting:ALL:aws:ResourceTag/Project:matching | principal | allowed | allowed | ServiceDiscoveryTagResourceExisting | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryUntagResource:ALL:aws:TagKeys:absent | principal | allowed | allowed | ServiceDiscoveryUntagResource | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryUntagResource:ALL:aws:TagKeys:all-matching | principal | allowed | allowed | ServiceDiscoveryUntagResource | yes |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryUntagResource:ALL:aws:TagKeys:any-non-matching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_elb_ecs:TagInventoryStarOnly:ALL:none:matching | principal | allowed | allowed | TagInventoryStarOnly | yes |
| case:aws_iam_policy.deployer_guard:DenyMutatingOwnControlRoles:ALL:none:non-protected-resource | principal | attribution-only | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_guard:DenyMutatingOwnControlRoles:ALL:none:protected-resource | principal | explicitDeny | explicitDeny | DenyMutatingOwnControlRoles | yes |
| case:aws_iam_policy.deployer_iam:DenyDeleteRolePermissionsBoundary:ALL:none:protected-resource | principal | explicitDeny | explicitDeny | DenyDeleteRolePermissionsBoundary | yes |
| case:aws_iam_policy.deployer_iam:DenyRoleMutationMissingBoundary:ALL:iam:PermissionsBoundary:absent | principal | explicitDeny | explicitDeny | DenyRoleMutationMissingBoundary, DenyRoleMutationWrongBoundary | yes |
| case:aws_iam_policy.deployer_iam:DenyRoleMutationMissingBoundary:ALL:iam:PermissionsBoundary:present | principal | attribution-only | explicitDeny | DenyRoleMutationWrongBoundary | yes |
| case:aws_iam_policy.deployer_iam:DenyRoleMutationMissingBoundary:ALL:none:protected-resource | principal | explicitDeny | explicitDeny | DenyRoleMutationMissingBoundary, DenyRoleMutationWrongBoundary | yes |
| case:aws_iam_policy.deployer_iam:DenyRoleMutationWrongBoundary:ALL:iam:PermissionsBoundary:different | principal | explicitDeny | explicitDeny | DenyRoleMutationWrongBoundary | yes |
| case:aws_iam_policy.deployer_iam:DenyRoleMutationWrongBoundary:ALL:iam:PermissionsBoundary:equal | principal | attribution-only | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:DenyRoleMutationWrongBoundary:ALL:none:protected-resource | principal | explicitDeny | explicitDeny | DenyRoleMutationWrongBoundary | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRoleAttachPolicy:ALL:iam:PermissionsBoundary:matching | principal | allowed | allowed | EnvServiceRoleAttachPolicy | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRoleAttachPolicy:ALL:iam:PolicyARN:matching | principal | allowed | allowed | EnvServiceRoleAttachPolicy | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRoleCreateWithBoundary:ALL:iam:PermissionsBoundary:matching | principal | allowed | allowed | EnvServiceRoleCreateWithBoundary | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRoleLifecycle:ALL:none:matching | principal | allowed | allowed | EnvServiceRoleLifecycle | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRolePermissionsBoundarySet:ALL:iam:PermissionsBoundary:matching | principal | allowed | allowed | EnvServiceRolePermissionsBoundarySet | yes |
| case:aws_iam_policy.deployer_iam:EnvServiceRolePutPolicy:ALL:iam:PermissionsBoundary:matching | principal | allowed | allowed | EnvServiceRolePutPolicy | yes |
| case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleEcs:ALL:iam:AWSServiceName:absent | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleEcs:ALL:iam:AWSServiceName:matching | principal | allowed | allowed | IamServiceLinkedRoleEcs | yes |
| case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleEcs:ALL:iam:AWSServiceName:non-matching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleEcs:ALL:resource:nonmatching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleElb:ALL:iam:AWSServiceName:absent | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleElb:ALL:iam:AWSServiceName:matching | principal | allowed | allowed | IamServiceLinkedRoleElb | yes |
| case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleElb:ALL:iam:AWSServiceName:non-matching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleElb:ALL:resource:nonmatching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_policy.deployer_iam:PassEnvRolesOnly:ALL:iam:PassedToService:matching | principal | allowed | allowed | PassEnvRolesOnly | yes |
| case:aws_iam_policy.deployer_state:ListStateBucket:ALL:s3:prefix:matching | principal | allowed | allowed | ListStateBucket | yes |
| case:aws_iam_policy.deployer_state:StateAndLeaseObjects:ALL:none:matching | principal | allowed | allowed | StateAndLeaseObjects | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:none:non-protected-resource | principal | attribution-only | {"s3:ListBucketVersions\|arn:aws:s3:::outside-79s5rw-resource":"implicitDeny","s3:ListBucket\|arn:aws:s3:::outside-79s5rw-resource":"explicitDeny"} | DenyListBucketOutsideScope | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:none:protected-resource | principal | explicitDeny | explicitDeny | DenyListBucketMissingPrefix, DenyListBucketOutsideScopePrefix | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:s3:prefix:absent | principal | explicitDeny | explicitDeny | DenyListBucketMissingPrefix, DenyListBucketOutsideScopePrefix | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:s3:prefix:present | principal | attribution-only | {"s3:ListBucketVersions\|arn:aws:s3:::orbit-infra-79s5rw-tfstate":"implicitDeny","s3:ListBucket\|arn:aws:s3:::orbit-infra-79s5rw-tfstate":"allowed"} | ListStatePrefixes | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScope:ALL:none:non-protected-resource | principal | allowed | allowed | ListStatePrefixes | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScope:ALL:none:protected-resource | principal | explicitDeny | explicitDeny | DenyListBucketOutsideScope | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:none:non-protected-resource | principal | attribution-only | {"s3:ListBucketVersions\|arn:aws:s3:::outside-79s5rw-resource":"implicitDeny","s3:ListBucket\|arn:aws:s3:::outside-79s5rw-resource":"explicitDeny"} | DenyListBucketOutsideScope | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:none:protected-resource | principal | explicitDeny | explicitDeny | DenyListBucketOutsideScopePrefix | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:s3:prefix:absent | principal | explicitDeny | explicitDeny | DenyListBucketMissingPrefix, DenyListBucketOutsideScopePrefix | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:s3:prefix:inside-set | principal | attribution-only | implicitDeny | none | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:s3:prefix:outside-set | principal | explicitDeny | explicitDeny | DenyListBucketOutsideScopePrefix | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenyReadStateObjectsOutsideScope:ALL:none:non-protected-resource | principal | attribution-only | {"s3:GetObjectVersion\|arn:aws:s3:::orbit-infra-79s5rw-tfstate/bootstrap/preview":"implicitDeny","s3:GetObject\|arn:aws:s3:::orbit-infra-79s5rw-tfstate/bootstrap/preview":"allowed"} | ReadStateObjects | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenyReadStateObjectsOutsideScope:ALL:none:protected-resource | principal | explicitDeny | explicitDeny | DenyReadStateObjectsOutsideScope | yes |
| case:aws_iam_role_policy.plan_reader_deny:DenySecretsAndParams:ALL:none:protected-resource | principal | explicitDeny | explicitDeny | DenySecretsAndParams | yes |
| case:aws_iam_role_policy.plan_reader_state:ListStatePrefixes:ALL:s3:prefix:matching | principal | allowed | allowed | ListStatePrefixes | yes |
| case:aws_iam_role_policy.plan_reader_state:ReadStateObjects:ALL:none:matching | principal | allowed | allowed | ReadStateObjects | yes |
| case:aws_iam_role_policy.publisher:EcrAuth:ALL:none:matching | principal | allowed | allowed | EcrAuth | yes |
| case:aws_iam_role_policy.publisher:EcrPushPull:ALL:none:matching | principal | allowed | allowed | EcrPushPull | yes |
| case:aws_iam_role_policy.publisher:EcrPushPull:ALL:resource:nonmatching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_role_policy.publisher:SigningKey:ALL:kms:ResourceAliases:absent | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_role_policy.publisher:SigningKey:ALL:kms:ResourceAliases:none-matching | principal | implicitDeny | implicitDeny | none | yes |
| case:aws_iam_role_policy.publisher:SigningKey:ALL:kms:ResourceAliases:one-matching | principal | allowed | allowed | SigningKey | yes |
| case:aws_iam_role_policy.publisher:SigningKey:ALL:resource:nonmatching | principal | implicitDeny | implicitDeny | none | yes |

## Findings

- `case:aws_iam_policy.deployer_data:SnsSubscriptionManage:ALL:none:matching` (custom). Expected: `allowed`; observed: `implicitDeny`. Matched Sids: none.
- `case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScope:ALL:none:non-protected-resource` (custom). Expected: `allowed`; observed: `implicitDeny`. Matched Sids: none.
- `case:aws_iam_policy.deployer_data:SnsSubscriptionManage:ALL:none:matching` (role). Expected: `allowed`; observed: `implicitDeny`. Matched Sids: none.

## Divergences

| Case ID | Scope | Expected | Custom observed | SCP-excluded | Default |
| --- | --- | --- | --- | --- | --- |
| case:aws_iam_policy.deployer_data:ClickhouseSecretCreateWithTag:ALL:aws:RequestTag/Project:matching | Organizations: secretsmanager:CreateSecret arn:aws:secretsmanager:us-east-1:000000000000:secret:orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretCreateWithTag:ALL:aws:RequestTag/Project:matching | Organizations: secretsmanager:TagResource arn:aws:secretsmanager:us-east-1:000000000000:secret:orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:absent | Organizations: secretsmanager:DeleteSecret arn:aws:secretsmanager:us-east-1:000000000000:secret:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:absent | Organizations: secretsmanager:DescribeSecret arn:aws:secretsmanager:us-east-1:000000000000:secret:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:absent | Organizations: secretsmanager:GetResourcePolicy arn:aws:secretsmanager:us-east-1:000000000000:secret:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:absent | Organizations: secretsmanager:GetSecretValue arn:aws:secretsmanager:us-east-1:000000000000:secret:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:absent | Organizations: secretsmanager:PutSecretValue arn:aws:secretsmanager:us-east-1:000000000000:secret:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:absent | Organizations: secretsmanager:UntagResource arn:aws:secretsmanager:us-east-1:000000000000:secret:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:matching | Organizations: secretsmanager:DeleteSecret arn:aws:secretsmanager:us-east-1:000000000000:secret:orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:matching | Organizations: secretsmanager:DescribeSecret arn:aws:secretsmanager:us-east-1:000000000000:secret:orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:matching | Organizations: secretsmanager:GetResourcePolicy arn:aws:secretsmanager:us-east-1:000000000000:secret:orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:matching | Organizations: secretsmanager:GetSecretValue arn:aws:secretsmanager:us-east-1:000000000000:secret:orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:matching | Organizations: secretsmanager:PutSecretValue arn:aws:secretsmanager:us-east-1:000000000000:secret:orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:matching | Organizations: secretsmanager:UntagResource arn:aws:secretsmanager:us-east-1:000000000000:secret:orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | Organizations: secretsmanager:DeleteSecret arn:aws:secretsmanager:us-east-1:000000000000:secret:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | Organizations: secretsmanager:DescribeSecret arn:aws:secretsmanager:us-east-1:000000000000:secret:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | Organizations: secretsmanager:GetResourcePolicy arn:aws:secretsmanager:us-east-1:000000000000:secret:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | Organizations: secretsmanager:GetSecretValue arn:aws:secretsmanager:us-east-1:000000000000:secret:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | Organizations: secretsmanager:PutSecretValue arn:aws:secretsmanager:us-east-1:000000000000:secret:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | Organizations: secretsmanager:UntagResource arn:aws:secretsmanager:us-east-1:000000000000:secret:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:resource:nonmatching | Organizations: secretsmanager:DeleteSecret arn:aws:secretsmanager:us-east-1:000000000000:secret:outside-79s5rw-example | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:resource:nonmatching | Organizations: secretsmanager:DescribeSecret arn:aws:secretsmanager:us-east-1:000000000000:secret:outside-79s5rw-example | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:resource:nonmatching | Organizations: secretsmanager:GetResourcePolicy arn:aws:secretsmanager:us-east-1:000000000000:secret:outside-79s5rw-example | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:resource:nonmatching | Organizations: secretsmanager:GetSecretValue arn:aws:secretsmanager:us-east-1:000000000000:secret:outside-79s5rw-example | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:resource:nonmatching | Organizations: secretsmanager:PutSecretValue arn:aws:secretsmanager:us-east-1:000000000000:secret:outside-79s5rw-example | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:resource:nonmatching | Organizations: secretsmanager:UntagResource arn:aws:secretsmanager:us-east-1:000000000000:secret:outside-79s5rw-example | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:ClickhouseSecretTagResourceExisting:ALL:aws:ResourceTag/Project:matching | Organizations: secretsmanager:TagResource arn:aws:secretsmanager:us-east-1:000000000000:secret:orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:aws:RequestTag/Project:absent | Organizations: cloudwatch:PutMetricAlarm arn:aws:cloudwatch:us-east-1:000000000000:alarm:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:aws:RequestTag/Project:absent | Organizations: cloudwatch:TagResource arn:aws:cloudwatch:us-east-1:000000000000:alarm:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:aws:RequestTag/Project:matching | Organizations: cloudwatch:PutMetricAlarm arn:aws:cloudwatch:us-east-1:000000000000:alarm:orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:aws:RequestTag/Project:matching | Organizations: cloudwatch:TagResource arn:aws:cloudwatch:us-east-1:000000000000:alarm:orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:aws:RequestTag/Project:non-matching | Organizations: cloudwatch:PutMetricAlarm arn:aws:cloudwatch:us-east-1:000000000000:alarm:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:aws:RequestTag/Project:non-matching | Organizations: cloudwatch:TagResource arn:aws:cloudwatch:us-east-1:000000000000:alarm:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:resource:nonmatching | Organizations: cloudwatch:PutMetricAlarm arn:aws:cloudwatch:us-east-1:000000000000:alarm:outside-79s5rw-example | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:resource:nonmatching | Organizations: cloudwatch:TagResource arn:aws:cloudwatch:us-east-1:000000000000:alarm:outside-79s5rw-example | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:aws:ResourceTag/Project:absent | Organizations: cloudwatch:DeleteAlarms arn:aws:cloudwatch:us-east-1:000000000000:alarm:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:aws:ResourceTag/Project:absent | Organizations: cloudwatch:UntagResource arn:aws:cloudwatch:us-east-1:000000000000:alarm:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:aws:ResourceTag/Project:matching | Organizations: cloudwatch:DeleteAlarms arn:aws:cloudwatch:us-east-1:000000000000:alarm:orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:aws:ResourceTag/Project:matching | Organizations: cloudwatch:UntagResource arn:aws:cloudwatch:us-east-1:000000000000:alarm:orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | Organizations: cloudwatch:DeleteAlarms arn:aws:cloudwatch:us-east-1:000000000000:alarm:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | Organizations: cloudwatch:UntagResource arn:aws:cloudwatch:us-east-1:000000000000:alarm:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:resource:nonmatching | Organizations: cloudwatch:DeleteAlarms arn:aws:cloudwatch:us-east-1:000000000000:alarm:outside-79s5rw-example | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:resource:nonmatching | Organizations: cloudwatch:UntagResource arn:aws:cloudwatch:us-east-1:000000000000:alarm:outside-79s5rw-example | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:EcrVerificationAuth:ALL:none:matching | Organizations: ecr:GetAuthorizationToken * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EcrVerificationPull:ALL:none:matching | Organizations: ecr:BatchGetImage arn:aws:ecr:us-east-1:000000000000:repository/orbit-infra-79s5rw/mirror/clickhouse | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EcrVerificationPull:ALL:none:matching | Organizations: ecr:GetDownloadUrlForLayer arn:aws:ecr:us-east-1:000000000000:repository/orbit-infra-79s5rw/mirror/clickhouse | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EcrVerificationPull:ALL:resource:nonmatching | Organizations: ecr:BatchGetImage arn:aws:ecr:us-east-1:000000000000:repository/outside-79s5rw/example | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:EcrVerificationPull:ALL:resource:nonmatching | Organizations: ecr:GetDownloadUrlForLayer arn:aws:ecr:us-east-1:000000000000:repository/outside-79s5rw/example | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:AbortMultipartUpload arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:AbortMultipartUpload arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:CreateBucket arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:CreateBucket arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:DeleteBucket arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:DeleteBucket arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:DeleteBucketOwnershipControls arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:DeleteBucketOwnershipControls arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:DeleteBucketPolicy arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:DeleteBucketPolicy arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:DeleteBucketPublicAccessBlock arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:DeleteBucketPublicAccessBlock arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:DeleteObject arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:DeleteObject arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:DeleteObjectVersion arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:DeleteObjectVersion arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:GetBucketOwnershipControls arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:GetBucketOwnershipControls arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:GetBucketPolicy arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:GetBucketPolicy arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:GetBucketPublicAccessBlock arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:GetBucketPublicAccessBlock arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:GetBucketTagging arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:GetBucketTagging arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:GetBucketVersioning arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:GetBucketVersioning arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:GetEncryptionConfiguration arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:GetEncryptionConfiguration arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:GetLifecycleConfiguration arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:GetLifecycleConfiguration arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:GetObject arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:GetObject arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:ListBucket arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:ListBucket arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:ListBucketMultipartUploads arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:ListBucketMultipartUploads arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:ListBucketVersions arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:ListBucketVersions arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:PutBucketOwnershipControls arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:PutBucketOwnershipControls arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:PutBucketPolicy arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:PutBucketPolicy arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:PutBucketPublicAccessBlock arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:PutBucketPublicAccessBlock arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:PutBucketTagging arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:PutBucketTagging arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:PutBucketVersioning arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:PutBucketVersioning arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:PutEncryptionConfiguration arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:PutEncryptionConfiguration arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:PutLifecycleConfiguration arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:PutLifecycleConfiguration arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:PutObject arn:aws:s3:::orbit-infra-79s5rw-preview-data | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | Organizations: s3:PutObject arn:aws:s3:::orbit-infra-79s5rw-preview-data/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:S3BucketDescribeReads:ALL:none:matching | Organizations: s3:GetAccelerateConfiguration arn:aws:s3:::orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:S3BucketDescribeReads:ALL:none:matching | Organizations: s3:GetBucketAcl arn:aws:s3:::orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:S3BucketDescribeReads:ALL:none:matching | Organizations: s3:GetBucketCORS arn:aws:s3:::orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:S3BucketDescribeReads:ALL:none:matching | Organizations: s3:GetBucketLogging arn:aws:s3:::orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:S3BucketDescribeReads:ALL:none:matching | Organizations: s3:GetBucketObjectLockConfiguration arn:aws:s3:::orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:S3BucketDescribeReads:ALL:none:matching | Organizations: s3:GetBucketOwnershipControls arn:aws:s3:::orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:S3BucketDescribeReads:ALL:none:matching | Organizations: s3:GetBucketPolicy arn:aws:s3:::orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:S3BucketDescribeReads:ALL:none:matching | Organizations: s3:GetBucketPolicyStatus arn:aws:s3:::orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:S3BucketDescribeReads:ALL:none:matching | Organizations: s3:GetBucketPublicAccessBlock arn:aws:s3:::orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:S3BucketDescribeReads:ALL:none:matching | Organizations: s3:GetBucketRequestPayment arn:aws:s3:::orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:S3BucketDescribeReads:ALL:none:matching | Organizations: s3:GetBucketTagging arn:aws:s3:::orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:S3BucketDescribeReads:ALL:none:matching | Organizations: s3:GetBucketVersioning arn:aws:s3:::orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:S3BucketDescribeReads:ALL:none:matching | Organizations: s3:GetBucketWebsite arn:aws:s3:::orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:S3BucketDescribeReads:ALL:none:matching | Organizations: s3:GetEncryptionConfiguration arn:aws:s3:::orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:S3BucketDescribeReads:ALL:none:matching | Organizations: s3:GetLifecycleConfiguration arn:aws:s3:::orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:S3BucketDescribeReads:ALL:none:matching | Organizations: s3:GetReplicationConfiguration arn:aws:s3:::orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:S3BucketDescribeReads:ALL:none:matching | Organizations: s3:ListBucket arn:aws:s3:::orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:SigningPublicKeyRead:ALL:kms:ResourceAliases:absent | Organizations: kms:GetPublicKey arn:aws:kms:us-east-1:000000000000:key/preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SigningPublicKeyRead:ALL:kms:ResourceAliases:none-matching | Organizations: kms:GetPublicKey arn:aws:kms:us-east-1:000000000000:key/preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SigningPublicKeyRead:ALL:kms:ResourceAliases:one-matching | Organizations: kms:GetPublicKey arn:aws:kms:us-east-1:000000000000:key/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:SigningPublicKeyRead:ALL:resource:nonmatching | Organizations: kms:GetPublicKey arn:aws:kms:us-west-2:000000000000:key/outside-key-id | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:aws:RequestTag/Project:absent | Organizations: sns:CreateTopic arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:aws:RequestTag/Project:absent | Organizations: sns:TagResource arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:aws:RequestTag/Project:matching | Organizations: sns:CreateTopic arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:aws:RequestTag/Project:matching | Organizations: sns:TagResource arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:aws:RequestTag/Project:non-matching | Organizations: sns:CreateTopic arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:aws:RequestTag/Project:non-matching | Organizations: sns:TagResource arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:resource:nonmatching | Organizations: sns:CreateTopic arn:aws:sns:us-east-1:000000000000:outside-79s5rw-topic | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:resource:nonmatching | Organizations: sns:TagResource arn:aws:sns:us-east-1:000000000000:outside-79s5rw-topic | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:absent | Organizations: sns:DeleteTopic arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:absent | Organizations: sns:GetTopicAttributes arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:absent | Organizations: sns:ListSubscriptionsByTopic arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:absent | Organizations: sns:ListTagsForResource arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:absent | Organizations: sns:SetTopicAttributes arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:absent | Organizations: sns:Subscribe arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:absent | Organizations: sns:UntagResource arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:matching | Organizations: sns:DeleteTopic arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:matching | Organizations: sns:GetTopicAttributes arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:matching | Organizations: sns:ListSubscriptionsByTopic arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:matching | Organizations: sns:ListTagsForResource arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:matching | Organizations: sns:SetTopicAttributes arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:matching | Organizations: sns:Subscribe arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:matching | Organizations: sns:UntagResource arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | Organizations: sns:DeleteTopic arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | Organizations: sns:GetTopicAttributes arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | Organizations: sns:ListSubscriptionsByTopic arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | Organizations: sns:ListTagsForResource arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | Organizations: sns:SetTopicAttributes arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | Organizations: sns:Subscribe arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | Organizations: sns:UntagResource arn:aws:sns:us-east-1:000000000000:orbit-infra-79s5rw-preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:resource:nonmatching | Organizations: sns:DeleteTopic arn:aws:sns:us-east-1:000000000000:outside-79s5rw-topic | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:resource:nonmatching | Organizations: sns:GetTopicAttributes arn:aws:sns:us-east-1:000000000000:outside-79s5rw-topic | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:resource:nonmatching | Organizations: sns:ListSubscriptionsByTopic arn:aws:sns:us-east-1:000000000000:outside-79s5rw-topic | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:resource:nonmatching | Organizations: sns:ListTagsForResource arn:aws:sns:us-east-1:000000000000:outside-79s5rw-topic | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:resource:nonmatching | Organizations: sns:SetTopicAttributes arn:aws:sns:us-east-1:000000000000:outside-79s5rw-topic | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:resource:nonmatching | Organizations: sns:Subscribe arn:aws:sns:us-east-1:000000000000:outside-79s5rw-topic | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:resource:nonmatching | Organizations: sns:UntagResource arn:aws:sns:us-east-1:000000000000:outside-79s5rw-topic | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_data:TagDiscovery:ALL:none:matching | Organizations: tag:GetResources * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForCreateActions:ALL:aws:RequestTag/Project:matching | Organizations: ec2:CreateTags * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForCreateActions:ALL:ec2:CreateAction:matching | Organizations: ec2:CreateTags * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForResourceTag:ALL:ec2:ResourceTag/Project:matching | Organizations: ec2:CreateTags * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:absent | Organizations: ec2:CreateInternetGateway * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:absent | Organizations: ec2:CreateRouteTable * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:absent | Organizations: ec2:CreateSecurityGroup * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:absent | Organizations: ec2:CreateSubnet * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:absent | Organizations: ec2:CreateVpc * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:absent | Organizations: ec2:CreateVpcEndpoint * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:matching | Organizations: ec2:CreateInternetGateway * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:matching | Organizations: ec2:CreateRouteTable * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:matching | Organizations: ec2:CreateSecurityGroup * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:matching | Organizations: ec2:CreateSubnet * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:matching | Organizations: ec2:CreateVpc * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:matching | Organizations: ec2:CreateVpcEndpoint * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:non-matching | Organizations: ec2:CreateInternetGateway * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:non-matching | Organizations: ec2:CreateRouteTable * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:non-matching | Organizations: ec2:CreateSecurityGroup * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:non-matching | Organizations: ec2:CreateSubnet * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:non-matching | Organizations: ec2:CreateVpc * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:non-matching | Organizations: ec2:CreateVpcEndpoint * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DeleteTags:ALL:ec2:ResourceTag/Project:absent | Organizations: ec2:DeleteTags * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DeleteTags:ALL:ec2:ResourceTag/Project:matching | Organizations: ec2:DeleteTags * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DeleteTags:ALL:ec2:ResourceTag/Project:non-matching | Organizations: ec2:DeleteTags * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:absent | Organizations: ec2:DescribeAvailabilityZones * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:absent | Organizations: ec2:DescribeInternetGateways * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:absent | Organizations: ec2:DescribeNetworkInterfaces * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:absent | Organizations: ec2:DescribeRouteTables * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:absent | Organizations: ec2:DescribeSecurityGroupRules * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:absent | Organizations: ec2:DescribeSecurityGroups * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:absent | Organizations: ec2:DescribeSubnets * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:absent | Organizations: ec2:DescribeTags * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:absent | Organizations: ec2:DescribeVpcAttribute * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:absent | Organizations: ec2:DescribeVpcEndpoints * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:absent | Organizations: ec2:DescribeVpcs * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:matching | Organizations: ec2:DescribeAvailabilityZones * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:matching | Organizations: ec2:DescribeInternetGateways * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:matching | Organizations: ec2:DescribeNetworkInterfaces * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:matching | Organizations: ec2:DescribeRouteTables * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:matching | Organizations: ec2:DescribeSecurityGroupRules * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:matching | Organizations: ec2:DescribeSecurityGroups * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:matching | Organizations: ec2:DescribeSubnets * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:matching | Organizations: ec2:DescribeTags * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:matching | Organizations: ec2:DescribeVpcAttribute * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:matching | Organizations: ec2:DescribeVpcEndpoints * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:matching | Organizations: ec2:DescribeVpcs * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:non-matching | Organizations: ec2:DescribeAvailabilityZones * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:non-matching | Organizations: ec2:DescribeInternetGateways * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:non-matching | Organizations: ec2:DescribeNetworkInterfaces * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:non-matching | Organizations: ec2:DescribeRouteTables * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:non-matching | Organizations: ec2:DescribeSecurityGroupRules * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:non-matching | Organizations: ec2:DescribeSecurityGroups * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:non-matching | Organizations: ec2:DescribeSubnets * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:non-matching | Organizations: ec2:DescribeTags * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:non-matching | Organizations: ec2:DescribeVpcAttribute * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:non-matching | Organizations: ec2:DescribeVpcEndpoints * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:non-matching | Organizations: ec2:DescribeVpcs * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | Organizations: ec2:AssociateRouteTable * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | Organizations: ec2:AttachInternetGateway * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | Organizations: ec2:AuthorizeSecurityGroupEgress * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | Organizations: ec2:AuthorizeSecurityGroupIngress * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | Organizations: ec2:CreateRoute * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | Organizations: ec2:DeleteInternetGateway * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | Organizations: ec2:DeleteRoute * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | Organizations: ec2:DeleteRouteTable * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | Organizations: ec2:DeleteSecurityGroup * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | Organizations: ec2:DeleteSubnet * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | Organizations: ec2:DeleteVpc * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | Organizations: ec2:DeleteVpcEndpoints * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | Organizations: ec2:DetachInternetGateway * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | Organizations: ec2:DisassociateRouteTable * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | Organizations: ec2:ModifySecurityGroupRules * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | Organizations: ec2:ModifySubnetAttribute * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | Organizations: ec2:ModifyVpcAttribute * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | Organizations: ec2:ModifyVpcEndpoint * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | Organizations: ec2:ReplaceRoute * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | Organizations: ec2:ReplaceRouteTableAssociation * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | Organizations: ec2:RevokeSecurityGroupEgress * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | Organizations: ec2:RevokeSecurityGroupIngress * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2SecurityGroupRuleCreateWithTag:ALL:aws:RequestTag/Project:matching | Organizations: ec2:AuthorizeSecurityGroupEgress * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_ec2:Ec2SecurityGroupRuleCreateWithTag:ALL:aws:RequestTag/Project:matching | Organizations: ec2:AuthorizeSecurityGroupIngress * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsCreateWithTag:ALL:aws:RequestTag/Project:absent | Organizations: ecs:CreateCluster * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsCreateWithTag:ALL:aws:RequestTag/Project:absent | Organizations: ecs:CreateService * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsCreateWithTag:ALL:aws:RequestTag/Project:absent | Organizations: ecs:RegisterTaskDefinition * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsCreateWithTag:ALL:aws:RequestTag/Project:matching | Organizations: ecs:CreateCluster * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsCreateWithTag:ALL:aws:RequestTag/Project:matching | Organizations: ecs:CreateService * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsCreateWithTag:ALL:aws:RequestTag/Project:matching | Organizations: ecs:RegisterTaskDefinition * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsCreateWithTag:ALL:aws:RequestTag/Project:non-matching | Organizations: ecs:CreateCluster * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsCreateWithTag:ALL:aws:RequestTag/Project:non-matching | Organizations: ecs:CreateService * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsCreateWithTag:ALL:aws:RequestTag/Project:non-matching | Organizations: ecs:RegisterTaskDefinition * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsListDescribeTasksForProjectClusters:ALL:ecs:cluster:absent | Organizations: ecs:DescribeTasks * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsListDescribeTasksForProjectClusters:ALL:ecs:cluster:absent | Organizations: ecs:ListTasks * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsListDescribeTasksForProjectClusters:ALL:ecs:cluster:matching | Organizations: ecs:DescribeTasks * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsListDescribeTasksForProjectClusters:ALL:ecs:cluster:matching | Organizations: ecs:ListTasks * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsListDescribeTasksForProjectClusters:ALL:ecs:cluster:non-matching | Organizations: ecs:DescribeTasks * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsListDescribeTasksForProjectClusters:ALL:ecs:cluster:non-matching | Organizations: ecs:ListTasks * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsListServicesClusterScoped:ALL:ecs:cluster:absent | Organizations: ecs:ListServices * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsListServicesClusterScoped:ALL:ecs:cluster:matching | Organizations: ecs:ListServices * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsListServicesClusterScoped:ALL:ecs:cluster:non-matching | Organizations: ecs:ListServices * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:absent | Organizations: ecs:DeleteCluster * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:absent | Organizations: ecs:DeleteService * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:absent | Organizations: ecs:DeleteTaskDefinitions * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:absent | Organizations: ecs:DescribeClusters * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:absent | Organizations: ecs:DescribeServices * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:absent | Organizations: ecs:UpdateService * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:matching | Organizations: ecs:DeleteCluster * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:matching | Organizations: ecs:DeleteService * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:matching | Organizations: ecs:DeleteTaskDefinitions * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:matching | Organizations: ecs:DescribeClusters * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:matching | Organizations: ecs:DescribeServices * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:matching | Organizations: ecs:UpdateService * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:non-matching | Organizations: ecs:DeleteCluster * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:non-matching | Organizations: ecs:DeleteService * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:non-matching | Organizations: ecs:DeleteTaskDefinitions * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:non-matching | Organizations: ecs:DescribeClusters * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:non-matching | Organizations: ecs:DescribeServices * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:non-matching | Organizations: ecs:UpdateService * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsStarOnly:ALL:none:matching | Organizations: ecs:DeregisterTaskDefinition * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsStarOnly:ALL:none:matching | Organizations: ecs:DescribeTaskDefinition * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsTagResource:ALL:aws:RequestTag/Project:matching | Organizations: ecs:TagResource * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsTagResource:ALL:ecs:CreateAction:matching | Organizations: ecs:TagResource * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsTagResourceExisting:ALL:ecs:ResourceTag/Project:matching | Organizations: ecs:TagResource * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsUntabledActions:ALL:none:matching | Organizations: ecs:ListTaskDefinitions * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsUntagAndListTags:ALL:ecs:ResourceTag/Project:absent | Organizations: ecs:ListTagsForResource * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsUntagAndListTags:ALL:ecs:ResourceTag/Project:absent | Organizations: ecs:UntagResource * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsUntagAndListTags:ALL:ecs:ResourceTag/Project:matching | Organizations: ecs:ListTagsForResource * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsUntagAndListTags:ALL:ecs:ResourceTag/Project:matching | Organizations: ecs:UntagResource * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsUntagAndListTags:ALL:ecs:ResourceTag/Project:non-matching | Organizations: ecs:ListTagsForResource * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:EcsUntagAndListTags:ALL:ecs:ResourceTag/Project:non-matching | Organizations: ecs:UntagResource * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbAddTags:ALL:aws:RequestTag/Project:matching | Organizations: elasticloadbalancing:AddTags * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbAddTags:ALL:elasticloadbalancing:CreateAction:matching | Organizations: elasticloadbalancing:AddTags * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbAddTagsForResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:matching | Organizations: elasticloadbalancing:AddTags * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbCreateWithTag:ALL:aws:RequestTag/Project:absent | Organizations: elasticloadbalancing:CreateListener * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbCreateWithTag:ALL:aws:RequestTag/Project:absent | Organizations: elasticloadbalancing:CreateLoadBalancer * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbCreateWithTag:ALL:aws:RequestTag/Project:absent | Organizations: elasticloadbalancing:CreateTargetGroup * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbCreateWithTag:ALL:aws:RequestTag/Project:matching | Organizations: elasticloadbalancing:CreateListener * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbCreateWithTag:ALL:aws:RequestTag/Project:matching | Organizations: elasticloadbalancing:CreateLoadBalancer * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbCreateWithTag:ALL:aws:RequestTag/Project:matching | Organizations: elasticloadbalancing:CreateTargetGroup * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbCreateWithTag:ALL:aws:RequestTag/Project:non-matching | Organizations: elasticloadbalancing:CreateListener * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbCreateWithTag:ALL:aws:RequestTag/Project:non-matching | Organizations: elasticloadbalancing:CreateLoadBalancer * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbCreateWithTag:ALL:aws:RequestTag/Project:non-matching | Organizations: elasticloadbalancing:CreateTargetGroup * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbDescribeStarOnly:ALL:none:matching | Organizations: elasticloadbalancing:DescribeListenerAttributes * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbDescribeStarOnly:ALL:none:matching | Organizations: elasticloadbalancing:DescribeListeners * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbDescribeStarOnly:ALL:none:matching | Organizations: elasticloadbalancing:DescribeLoadBalancerAttributes * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbDescribeStarOnly:ALL:none:matching | Organizations: elasticloadbalancing:DescribeLoadBalancers * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbDescribeStarOnly:ALL:none:matching | Organizations: elasticloadbalancing:DescribeTags * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbDescribeStarOnly:ALL:none:matching | Organizations: elasticloadbalancing:DescribeTargetGroupAttributes * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbDescribeStarOnly:ALL:none:matching | Organizations: elasticloadbalancing:DescribeTargetGroups * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbDescribeTargetHealth:ALL:none:matching | Organizations: elasticloadbalancing:DescribeTargetHealth * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:absent | Organizations: elasticloadbalancing:DeleteListener * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:absent | Organizations: elasticloadbalancing:DeleteLoadBalancer * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:absent | Organizations: elasticloadbalancing:DeleteTargetGroup * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:absent | Organizations: elasticloadbalancing:DeregisterTargets * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:absent | Organizations: elasticloadbalancing:ModifyListener * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:absent | Organizations: elasticloadbalancing:ModifyLoadBalancerAttributes * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:absent | Organizations: elasticloadbalancing:ModifyTargetGroup * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:absent | Organizations: elasticloadbalancing:ModifyTargetGroupAttributes * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:absent | Organizations: elasticloadbalancing:RegisterTargets * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:matching | Organizations: elasticloadbalancing:DeleteListener * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:matching | Organizations: elasticloadbalancing:DeleteLoadBalancer * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:matching | Organizations: elasticloadbalancing:DeleteTargetGroup * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:matching | Organizations: elasticloadbalancing:DeregisterTargets * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:matching | Organizations: elasticloadbalancing:ModifyListener * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:matching | Organizations: elasticloadbalancing:ModifyLoadBalancerAttributes * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:matching | Organizations: elasticloadbalancing:ModifyTargetGroup * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:matching | Organizations: elasticloadbalancing:ModifyTargetGroupAttributes * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:matching | Organizations: elasticloadbalancing:RegisterTargets * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:non-matching | Organizations: elasticloadbalancing:DeleteListener * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:non-matching | Organizations: elasticloadbalancing:DeleteLoadBalancer * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:non-matching | Organizations: elasticloadbalancing:DeleteTargetGroup * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:non-matching | Organizations: elasticloadbalancing:DeregisterTargets * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:non-matching | Organizations: elasticloadbalancing:ModifyListener * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:non-matching | Organizations: elasticloadbalancing:ModifyLoadBalancerAttributes * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:non-matching | Organizations: elasticloadbalancing:ModifyTargetGroup * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:non-matching | Organizations: elasticloadbalancing:ModifyTargetGroupAttributes * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:non-matching | Organizations: elasticloadbalancing:RegisterTargets * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbRemoveTags:ALL:elasticloadbalancing:ResourceTag/Project:absent | Organizations: elasticloadbalancing:RemoveTags * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbRemoveTags:ALL:elasticloadbalancing:ResourceTag/Project:matching | Organizations: elasticloadbalancing:RemoveTags * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ElbRemoveTags:ALL:elasticloadbalancing:ResourceTag/Project:non-matching | Organizations: elasticloadbalancing:RemoveTags * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateNamespaceWithTag:ALL:aws:RequestTag/Project:absent | Organizations: servicediscovery:CreatePrivateDnsNamespace * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateNamespaceWithTag:ALL:aws:RequestTag/Project:matching | Organizations: servicediscovery:CreatePrivateDnsNamespace * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateNamespaceWithTag:ALL:aws:RequestTag/Project:non-matching | Organizations: servicediscovery:CreatePrivateDnsNamespace * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateServiceWithTag:ALL:aws:RequestTag/Project:absent | Organizations: servicediscovery:CreateService * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateServiceWithTag:ALL:aws:RequestTag/Project:matching | Organizations: servicediscovery:CreateService * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateServiceWithTag:ALL:aws:RequestTag/Project:non-matching | Organizations: servicediscovery:CreateService * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:absent | Organizations: servicediscovery:DeleteNamespace * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:absent | Organizations: servicediscovery:DeleteService * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:absent | Organizations: servicediscovery:GetNamespace * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:absent | Organizations: servicediscovery:GetService * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:absent | Organizations: servicediscovery:UpdateService * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:matching | Organizations: servicediscovery:DeleteNamespace * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:matching | Organizations: servicediscovery:DeleteService * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:matching | Organizations: servicediscovery:GetNamespace * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:matching | Organizations: servicediscovery:GetService * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:matching | Organizations: servicediscovery:UpdateService * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | Organizations: servicediscovery:DeleteNamespace * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | Organizations: servicediscovery:DeleteService * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | Organizations: servicediscovery:GetNamespace * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | Organizations: servicediscovery:GetService * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | Organizations: servicediscovery:UpdateService * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryStarOnlyNoCondition:ALL:none:matching | Organizations: servicediscovery:GetOperation * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryStarOnlyNoCondition:ALL:none:matching | Organizations: servicediscovery:ListNamespaces * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryStarOnlyNoCondition:ALL:none:matching | Organizations: servicediscovery:ListServices * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryStarOnlyNoCondition:ALL:none:matching | Organizations: servicediscovery:ListTagsForResource * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryTagResource:ALL:aws:RequestTag/Project:matching | Organizations: servicediscovery:TagResource * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryTagResourceExisting:ALL:aws:ResourceTag/Project:matching | Organizations: servicediscovery:TagResource * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryUntagResource:ALL:aws:TagKeys:absent | Organizations: servicediscovery:UntagResource * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryUntagResource:ALL:aws:TagKeys:all-matching | Organizations: servicediscovery:UntagResource * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryUntagResource:ALL:aws:TagKeys:any-non-matching | Organizations: servicediscovery:UntagResource * | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_policy.deployer_elb_ecs:TagInventoryStarOnly:ALL:none:matching | Organizations: tag:GetResources * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_state:ListStateBucket:ALL:s3:prefix:matching | Organizations: s3:ListBucket arn:aws:s3:::orbit-infra-79s5rw-tfstate | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_state:ListStateBucket:ALL:s3:prefix:matching | Organizations: s3:ListBucketVersions arn:aws:s3:::orbit-infra-79s5rw-tfstate | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_state:StateAndLeaseObjects:ALL:none:matching | Organizations: s3:DeleteObject arn:aws:s3:::orbit-infra-79s5rw-tfstate/envs/preview/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_state:StateAndLeaseObjects:ALL:none:matching | Organizations: s3:DeleteObjectVersion arn:aws:s3:::orbit-infra-79s5rw-tfstate/envs/preview/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_state:StateAndLeaseObjects:ALL:none:matching | Organizations: s3:GetObject arn:aws:s3:::orbit-infra-79s5rw-tfstate/envs/preview/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_policy.deployer_state:StateAndLeaseObjects:ALL:none:matching | Organizations: s3:PutObject arn:aws:s3:::orbit-infra-79s5rw-tfstate/envs/preview/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:none:non-protected-resource | Organizations: s3:ListBucketVersions arn:aws:s3:::outside-79s5rw-resource | attribution-only | {"s3:ListBucketVersions\|arn:aws:s3:::outside-79s5rw-resource":"implicitDeny","s3:ListBucket\|arn:aws:s3:::outside-79s5rw-resource":"explicitDeny"} | implicitDeny | explicitDeny |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:s3:prefix:present | principal/custom | attribution-only | implicitDeny | {"s3:ListBucketVersions\|arn:aws:s3:::orbit-infra-79s5rw-tfstate":"implicitDeny","s3:ListBucket\|arn:aws:s3:::orbit-infra-79s5rw-tfstate":"allowed"} | explicitDeny |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:s3:prefix:present | Organizations: s3:ListBucket arn:aws:s3:::orbit-infra-79s5rw-tfstate | attribution-only | implicitDeny | allowed | explicitDeny |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:s3:prefix:present | Organizations: s3:ListBucketVersions arn:aws:s3:::orbit-infra-79s5rw-tfstate | attribution-only | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScope:ALL:none:non-protected-resource | principal/custom | allowed | implicitDeny | allowed | explicitDeny |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScope:ALL:none:non-protected-resource | Organizations: s3:ListBucket arn:aws:s3:::orbit-infra-79s5rw-tfstate | allowed | implicitDeny | allowed | explicitDeny |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:none:non-protected-resource | Organizations: s3:ListBucketVersions arn:aws:s3:::outside-79s5rw-resource | attribution-only | {"s3:ListBucketVersions\|arn:aws:s3:::outside-79s5rw-resource":"implicitDeny","s3:ListBucket\|arn:aws:s3:::outside-79s5rw-resource":"explicitDeny"} | implicitDeny | explicitDeny |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:s3:prefix:inside-set | Organizations: s3:ListBucket arn:aws:s3:::orbit-infra-79s5rw-tfstate | attribution-only | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:s3:prefix:inside-set | Organizations: s3:ListBucketVersions arn:aws:s3:::orbit-infra-79s5rw-tfstate | attribution-only | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_role_policy.plan_reader_deny:DenyReadStateObjectsOutsideScope:ALL:none:non-protected-resource | principal/custom | attribution-only | implicitDeny | {"s3:GetObjectVersion\|arn:aws:s3:::orbit-infra-79s5rw-tfstate/bootstrap/preview":"implicitDeny","s3:GetObject\|arn:aws:s3:::orbit-infra-79s5rw-tfstate/bootstrap/preview":"allowed"} | explicitDeny |
| case:aws_iam_role_policy.plan_reader_deny:DenyReadStateObjectsOutsideScope:ALL:none:non-protected-resource | Organizations: s3:GetObject arn:aws:s3:::orbit-infra-79s5rw-tfstate/bootstrap/preview | attribution-only | implicitDeny | allowed | explicitDeny |
| case:aws_iam_role_policy.plan_reader_deny:DenyReadStateObjectsOutsideScope:ALL:none:non-protected-resource | Organizations: s3:GetObjectVersion arn:aws:s3:::orbit-infra-79s5rw-tfstate/bootstrap/preview | attribution-only | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_role_policy.plan_reader_state:ListStatePrefixes:ALL:s3:prefix:matching | Organizations: s3:ListBucket arn:aws:s3:::orbit-infra-79s5rw-tfstate | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_role_policy.plan_reader_state:ReadStateObjects:ALL:none:matching | Organizations: s3:GetObject arn:aws:s3:::orbit-infra-79s5rw-tfstate/bootstrap/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_role_policy.publisher:EcrAuth:ALL:none:matching | Organizations: ecr:GetAuthorizationToken * | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_role_policy.publisher:EcrPushPull:ALL:none:matching | Organizations: ecr:BatchCheckLayerAvailability arn:aws:ecr:us-east-1:000000000000:repository/orbit-infra-79s5rw/mirror/clickhouse | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_role_policy.publisher:EcrPushPull:ALL:none:matching | Organizations: ecr:BatchGetImage arn:aws:ecr:us-east-1:000000000000:repository/orbit-infra-79s5rw/mirror/clickhouse | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_role_policy.publisher:EcrPushPull:ALL:none:matching | Organizations: ecr:CompleteLayerUpload arn:aws:ecr:us-east-1:000000000000:repository/orbit-infra-79s5rw/mirror/clickhouse | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_role_policy.publisher:EcrPushPull:ALL:none:matching | Organizations: ecr:DescribeImages arn:aws:ecr:us-east-1:000000000000:repository/orbit-infra-79s5rw/mirror/clickhouse | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_role_policy.publisher:EcrPushPull:ALL:none:matching | Organizations: ecr:DescribeRepositories arn:aws:ecr:us-east-1:000000000000:repository/orbit-infra-79s5rw/mirror/clickhouse | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_role_policy.publisher:EcrPushPull:ALL:none:matching | Organizations: ecr:GetDownloadUrlForLayer arn:aws:ecr:us-east-1:000000000000:repository/orbit-infra-79s5rw/mirror/clickhouse | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_role_policy.publisher:EcrPushPull:ALL:none:matching | Organizations: ecr:InitiateLayerUpload arn:aws:ecr:us-east-1:000000000000:repository/orbit-infra-79s5rw/mirror/clickhouse | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_role_policy.publisher:EcrPushPull:ALL:none:matching | Organizations: ecr:ListImages arn:aws:ecr:us-east-1:000000000000:repository/orbit-infra-79s5rw/mirror/clickhouse | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_role_policy.publisher:EcrPushPull:ALL:none:matching | Organizations: ecr:PutImage arn:aws:ecr:us-east-1:000000000000:repository/orbit-infra-79s5rw/mirror/clickhouse | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_role_policy.publisher:EcrPushPull:ALL:none:matching | Organizations: ecr:UploadLayerPart arn:aws:ecr:us-east-1:000000000000:repository/orbit-infra-79s5rw/mirror/clickhouse | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_role_policy.publisher:EcrPushPull:ALL:resource:nonmatching | Organizations: ecr:BatchCheckLayerAvailability arn:aws:ecr:us-east-1:000000000000:repository/outside-79s5rw/example | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_role_policy.publisher:EcrPushPull:ALL:resource:nonmatching | Organizations: ecr:BatchGetImage arn:aws:ecr:us-east-1:000000000000:repository/outside-79s5rw/example | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_role_policy.publisher:EcrPushPull:ALL:resource:nonmatching | Organizations: ecr:CompleteLayerUpload arn:aws:ecr:us-east-1:000000000000:repository/outside-79s5rw/example | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_role_policy.publisher:EcrPushPull:ALL:resource:nonmatching | Organizations: ecr:DescribeImages arn:aws:ecr:us-east-1:000000000000:repository/outside-79s5rw/example | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_role_policy.publisher:EcrPushPull:ALL:resource:nonmatching | Organizations: ecr:DescribeRepositories arn:aws:ecr:us-east-1:000000000000:repository/outside-79s5rw/example | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_role_policy.publisher:EcrPushPull:ALL:resource:nonmatching | Organizations: ecr:GetDownloadUrlForLayer arn:aws:ecr:us-east-1:000000000000:repository/outside-79s5rw/example | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_role_policy.publisher:EcrPushPull:ALL:resource:nonmatching | Organizations: ecr:InitiateLayerUpload arn:aws:ecr:us-east-1:000000000000:repository/outside-79s5rw/example | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_role_policy.publisher:EcrPushPull:ALL:resource:nonmatching | Organizations: ecr:ListImages arn:aws:ecr:us-east-1:000000000000:repository/outside-79s5rw/example | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_role_policy.publisher:EcrPushPull:ALL:resource:nonmatching | Organizations: ecr:PutImage arn:aws:ecr:us-east-1:000000000000:repository/outside-79s5rw/example | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_role_policy.publisher:EcrPushPull:ALL:resource:nonmatching | Organizations: ecr:UploadLayerPart arn:aws:ecr:us-east-1:000000000000:repository/outside-79s5rw/example | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_role_policy.publisher:SigningKey:ALL:kms:ResourceAliases:absent | Organizations: kms:GetPublicKey arn:aws:kms:us-east-1:000000000000:key/preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_role_policy.publisher:SigningKey:ALL:kms:ResourceAliases:absent | Organizations: kms:Sign arn:aws:kms:us-east-1:000000000000:key/preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_role_policy.publisher:SigningKey:ALL:kms:ResourceAliases:absent | Organizations: kms:Verify arn:aws:kms:us-east-1:000000000000:key/preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_role_policy.publisher:SigningKey:ALL:kms:ResourceAliases:none-matching | Organizations: kms:GetPublicKey arn:aws:kms:us-east-1:000000000000:key/preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_role_policy.publisher:SigningKey:ALL:kms:ResourceAliases:none-matching | Organizations: kms:Sign arn:aws:kms:us-east-1:000000000000:key/preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_role_policy.publisher:SigningKey:ALL:kms:ResourceAliases:none-matching | Organizations: kms:Verify arn:aws:kms:us-east-1:000000000000:key/preview | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_role_policy.publisher:SigningKey:ALL:kms:ResourceAliases:one-matching | Organizations: kms:GetPublicKey arn:aws:kms:us-east-1:000000000000:key/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_role_policy.publisher:SigningKey:ALL:kms:ResourceAliases:one-matching | Organizations: kms:Sign arn:aws:kms:us-east-1:000000000000:key/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_role_policy.publisher:SigningKey:ALL:kms:ResourceAliases:one-matching | Organizations: kms:Verify arn:aws:kms:us-east-1:000000000000:key/preview | allowed | allowed | allowed | explicitDeny |
| case:aws_iam_role_policy.publisher:SigningKey:ALL:resource:nonmatching | Organizations: kms:GetPublicKey arn:aws:kms:us-west-2:000000000000:key/outside-key-id | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_role_policy.publisher:SigningKey:ALL:resource:nonmatching | Organizations: kms:Sign arn:aws:kms:us-west-2:000000000000:key/outside-key-id | implicitDeny | implicitDeny | implicitDeny | explicitDeny |
| case:aws_iam_role_policy.publisher:SigningKey:ALL:resource:nonmatching | Organizations: kms:Verify arn:aws:kms:us-west-2:000000000000:key/outside-key-id | implicitDeny | implicitDeny | implicitDeny | explicitDeny |

## Counts by outcome

| Lane | Total | Passed | Failed | Runner failures |
| --- | ---: | ---: | ---: | ---: |
| custom | 239 | 237 | 2 | 0 |
| role | 156 | 155 | 1 | 0 |

## Submitted document SHA-256s

| Lane | Case ID | Input | SHA-256 |
| --- | --- | --- | --- |
| custom | case:aws_iam_policy.deployer_data:ClickhouseSecretCreateWithTag:ALL:aws:RequestTag/Project:absent | policy_input_list | d1385a503a7a490c85e84009a3c8e63504ab6ac3e8926bfb5222a133403de255 |
| custom | case:aws_iam_policy.deployer_data:ClickhouseSecretCreateWithTag:ALL:aws:RequestTag/Project:matching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:ClickhouseSecretCreateWithTag:ALL:aws:RequestTag/Project:non-matching | policy_input_list | d1385a503a7a490c85e84009a3c8e63504ab6ac3e8926bfb5222a133403de255 |
| custom | case:aws_iam_policy.deployer_data:ClickhouseSecretCreateWithTag:ALL:resource:nonmatching | policy_input_list | d1385a503a7a490c85e84009a3c8e63504ab6ac3e8926bfb5222a133403de255 |
| custom | case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:absent | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:matching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:resource:nonmatching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:ClickhouseSecretTagResourceExisting:ALL:aws:ResourceTag/Project:absent | policy_input_list | c5779af5d8cc658d5e94b3848308dd9c2b8c73b782f8feb066271a6c89d34f6b |
| custom | case:aws_iam_policy.deployer_data:ClickhouseSecretTagResourceExisting:ALL:aws:ResourceTag/Project:matching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:ClickhouseSecretTagResourceExisting:ALL:aws:ResourceTag/Project:non-matching | policy_input_list | c5779af5d8cc658d5e94b3848308dd9c2b8c73b782f8feb066271a6c89d34f6b |
| custom | case:aws_iam_policy.deployer_data:ClickhouseSecretTagResourceExisting:ALL:resource:nonmatching | policy_input_list | c5779af5d8cc658d5e94b3848308dd9c2b8c73b782f8feb066271a6c89d34f6b |
| custom | case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:aws:RequestTag/Project:absent | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:aws:RequestTag/Project:matching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:aws:RequestTag/Project:non-matching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:resource:nonmatching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:aws:ResourceTag/Project:absent | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:aws:ResourceTag/Project:matching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:resource:nonmatching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:EcrVerificationAuth:ALL:none:matching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:EcrVerificationPull:ALL:none:matching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:EcrVerificationPull:ALL:resource:nonmatching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:resource:nonmatching | policy_input_list | 04534532fd896707a70635610f6dd26a474357093c4c472dbf43cb44b1135412 |
| custom | case:aws_iam_policy.deployer_data:LogsCreateWithTag:ALL:aws:RequestTag/Project:absent | policy_input_list | f58f0324513cef3a026e48d430ec39a9502128d2ee3cbd45c19613ed5b3cb732 |
| custom | case:aws_iam_policy.deployer_data:LogsCreateWithTag:ALL:aws:RequestTag/Project:matching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:LogsCreateWithTag:ALL:aws:RequestTag/Project:non-matching | policy_input_list | f58f0324513cef3a026e48d430ec39a9502128d2ee3cbd45c19613ed5b3cb732 |
| custom | case:aws_iam_policy.deployer_data:LogsCreateWithTag:ALL:resource:nonmatching | policy_input_list | f58f0324513cef3a026e48d430ec39a9502128d2ee3cbd45c19613ed5b3cb732 |
| custom | case:aws_iam_policy.deployer_data:LogsDescribeStarOnly:ALL:none:matching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:LogsModifyDeleteWithResourceTag:ALL:aws:ResourceTag/Project:absent | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:LogsModifyDeleteWithResourceTag:ALL:aws:ResourceTag/Project:matching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:LogsModifyDeleteWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:LogsModifyDeleteWithResourceTag:ALL:resource:nonmatching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:LogsTagResourceExisting:ALL:aws:ResourceTag/Project:absent | policy_input_list | cb9bd58428ed8972e42bcf1a44a5c23a38c2a94afa1febc37cfcb22aaaa0676e |
| custom | case:aws_iam_policy.deployer_data:LogsTagResourceExisting:ALL:aws:ResourceTag/Project:matching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:LogsTagResourceExisting:ALL:aws:ResourceTag/Project:non-matching | policy_input_list | cb9bd58428ed8972e42bcf1a44a5c23a38c2a94afa1febc37cfcb22aaaa0676e |
| custom | case:aws_iam_policy.deployer_data:LogsTagResourceExisting:ALL:resource:nonmatching | policy_input_list | cb9bd58428ed8972e42bcf1a44a5c23a38c2a94afa1febc37cfcb22aaaa0676e |
| custom | case:aws_iam_policy.deployer_data:S3BucketDescribeReads:ALL:none:matching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:S3BucketDescribeReads:ALL:resource:nonmatching | policy_input_list | b917c7c64675eb8e2909acd45b3b03a3c42da38adc0151345a411171f8965b1b |
| custom | case:aws_iam_policy.deployer_data:SigningPublicKeyRead:ALL:kms:ResourceAliases:absent | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:SigningPublicKeyRead:ALL:kms:ResourceAliases:none-matching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:SigningPublicKeyRead:ALL:kms:ResourceAliases:one-matching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:SigningPublicKeyRead:ALL:resource:nonmatching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:aws:RequestTag/Project:absent | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:aws:RequestTag/Project:matching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:aws:RequestTag/Project:non-matching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:resource:nonmatching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:absent | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:matching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:resource:nonmatching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:SnsSubscriptionManage:ALL:none:matching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:SnsSubscriptionManage:ALL:resource:nonmatching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_data:TagDiscovery:ALL:none:matching | policy_input_list | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| custom | case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForCreateActions:ALL:aws:RequestTag/Project:absent | policy_input_list | 8951f16ea43f83af2c03e7ceb015bf9872e4eac57c5b7e5cd85da7bb088c4f21 |
| custom | case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForCreateActions:ALL:aws:RequestTag/Project:matching | policy_input_list | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| custom | case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForCreateActions:ALL:aws:RequestTag/Project:non-matching | policy_input_list | 8951f16ea43f83af2c03e7ceb015bf9872e4eac57c5b7e5cd85da7bb088c4f21 |
| custom | case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForCreateActions:ALL:ec2:CreateAction:absent | policy_input_list | 8951f16ea43f83af2c03e7ceb015bf9872e4eac57c5b7e5cd85da7bb088c4f21 |
| custom | case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForCreateActions:ALL:ec2:CreateAction:matching | policy_input_list | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| custom | case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForCreateActions:ALL:ec2:CreateAction:non-matching | policy_input_list | 8951f16ea43f83af2c03e7ceb015bf9872e4eac57c5b7e5cd85da7bb088c4f21 |
| custom | case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForResourceTag:ALL:ec2:ResourceTag/Project:absent | policy_input_list | a05820e1172822cbf276c12dcaa959295797177ea53f0aa9c27881a8e92358fc |
| custom | case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForResourceTag:ALL:ec2:ResourceTag/Project:matching | policy_input_list | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| custom | case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForResourceTag:ALL:ec2:ResourceTag/Project:non-matching | policy_input_list | a05820e1172822cbf276c12dcaa959295797177ea53f0aa9c27881a8e92358fc |
| custom | case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:absent | policy_input_list | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| custom | case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:matching | policy_input_list | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| custom | case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:non-matching | policy_input_list | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| custom | case:aws_iam_policy.deployer_ec2:Ec2DeleteTags:ALL:ec2:ResourceTag/Project:absent | policy_input_list | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| custom | case:aws_iam_policy.deployer_ec2:Ec2DeleteTags:ALL:ec2:ResourceTag/Project:matching | policy_input_list | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| custom | case:aws_iam_policy.deployer_ec2:Ec2DeleteTags:ALL:ec2:ResourceTag/Project:non-matching | policy_input_list | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| custom | case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:absent | policy_input_list | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| custom | case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:matching | policy_input_list | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| custom | case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:non-matching | policy_input_list | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| custom | case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:absent | policy_input_list | 03b80a3f9fc4fe8fb90bd68560b7f82c64b128311abdd936f0366a320c04e3d1 |
| custom | case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | policy_input_list | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| custom | case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:non-matching | policy_input_list | 03b80a3f9fc4fe8fb90bd68560b7f82c64b128311abdd936f0366a320c04e3d1 |
| custom | case:aws_iam_policy.deployer_ec2:Ec2SecurityGroupRuleCreateWithTag:ALL:aws:RequestTag/Project:absent | policy_input_list | 518fd4c89c419af2d95b7fa9375b11203bf5cf99d13b3fa6bc99c94861d9ec03 |
| custom | case:aws_iam_policy.deployer_ec2:Ec2SecurityGroupRuleCreateWithTag:ALL:aws:RequestTag/Project:matching | policy_input_list | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| custom | case:aws_iam_policy.deployer_ec2:Ec2SecurityGroupRuleCreateWithTag:ALL:aws:RequestTag/Project:non-matching | policy_input_list | 518fd4c89c419af2d95b7fa9375b11203bf5cf99d13b3fa6bc99c94861d9ec03 |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsCreateWithTag:ALL:aws:RequestTag/Project:absent | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsCreateWithTag:ALL:aws:RequestTag/Project:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsCreateWithTag:ALL:aws:RequestTag/Project:non-matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsListDescribeTasksForProjectClusters:ALL:ecs:cluster:absent | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsListDescribeTasksForProjectClusters:ALL:ecs:cluster:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsListDescribeTasksForProjectClusters:ALL:ecs:cluster:non-matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsListServicesClusterScoped:ALL:ecs:cluster:absent | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsListServicesClusterScoped:ALL:ecs:cluster:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsListServicesClusterScoped:ALL:ecs:cluster:non-matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:absent | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:non-matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsStarOnly:ALL:none:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsTagResource:ALL:aws:RequestTag/Project:absent | policy_input_list | 7b79e5a2c8e6c32b3f222d800eae07bc8739c77461cc90f7311866a1a93e46ae |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsTagResource:ALL:aws:RequestTag/Project:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsTagResource:ALL:aws:RequestTag/Project:non-matching | policy_input_list | 7b79e5a2c8e6c32b3f222d800eae07bc8739c77461cc90f7311866a1a93e46ae |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsTagResource:ALL:ecs:CreateAction:absent | policy_input_list | 7b79e5a2c8e6c32b3f222d800eae07bc8739c77461cc90f7311866a1a93e46ae |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsTagResource:ALL:ecs:CreateAction:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsTagResource:ALL:ecs:CreateAction:non-matching | policy_input_list | 7b79e5a2c8e6c32b3f222d800eae07bc8739c77461cc90f7311866a1a93e46ae |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsTagResourceExisting:ALL:ecs:ResourceTag/Project:absent | policy_input_list | f413bb42275ab3c2bc647f5f017dd99f4f60756315e5999fa69c3063dc96d451 |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsTagResourceExisting:ALL:ecs:ResourceTag/Project:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsTagResourceExisting:ALL:ecs:ResourceTag/Project:non-matching | policy_input_list | f413bb42275ab3c2bc647f5f017dd99f4f60756315e5999fa69c3063dc96d451 |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsUntabledActions:ALL:none:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsUntagAndListTags:ALL:ecs:ResourceTag/Project:absent | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsUntagAndListTags:ALL:ecs:ResourceTag/Project:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:EcsUntagAndListTags:ALL:ecs:ResourceTag/Project:non-matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ElbAddTags:ALL:aws:RequestTag/Project:absent | policy_input_list | 5db90cd7a1e3ec7970661531f4191bcfe3963dd2137986b385eeff59bc88bd15 |
| custom | case:aws_iam_policy.deployer_elb_ecs:ElbAddTags:ALL:aws:RequestTag/Project:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ElbAddTags:ALL:aws:RequestTag/Project:non-matching | policy_input_list | 5db90cd7a1e3ec7970661531f4191bcfe3963dd2137986b385eeff59bc88bd15 |
| custom | case:aws_iam_policy.deployer_elb_ecs:ElbAddTags:ALL:elasticloadbalancing:CreateAction:absent | policy_input_list | 5db90cd7a1e3ec7970661531f4191bcfe3963dd2137986b385eeff59bc88bd15 |
| custom | case:aws_iam_policy.deployer_elb_ecs:ElbAddTags:ALL:elasticloadbalancing:CreateAction:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ElbAddTags:ALL:elasticloadbalancing:CreateAction:non-matching | policy_input_list | 5db90cd7a1e3ec7970661531f4191bcfe3963dd2137986b385eeff59bc88bd15 |
| custom | case:aws_iam_policy.deployer_elb_ecs:ElbAddTagsForResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:absent | policy_input_list | 48d8c5c840ae0b57be2952daa2602080057fd216b03bfda2edcf4d864394443b |
| custom | case:aws_iam_policy.deployer_elb_ecs:ElbAddTagsForResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ElbAddTagsForResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:non-matching | policy_input_list | 48d8c5c840ae0b57be2952daa2602080057fd216b03bfda2edcf4d864394443b |
| custom | case:aws_iam_policy.deployer_elb_ecs:ElbCreateWithTag:ALL:aws:RequestTag/Project:absent | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ElbCreateWithTag:ALL:aws:RequestTag/Project:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ElbCreateWithTag:ALL:aws:RequestTag/Project:non-matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ElbDescribeStarOnly:ALL:none:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ElbDescribeTargetHealth:ALL:none:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:absent | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:non-matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ElbRemoveTags:ALL:elasticloadbalancing:ResourceTag/Project:absent | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ElbRemoveTags:ALL:elasticloadbalancing:ResourceTag/Project:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ElbRemoveTags:ALL:elasticloadbalancing:ResourceTag/Project:non-matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:Route53HostedZoneRead:ALL:none:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:Route53HostedZoneStarOnly:ALL:none:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateNamespaceWithTag:ALL:aws:RequestTag/Project:absent | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateNamespaceWithTag:ALL:aws:RequestTag/Project:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateNamespaceWithTag:ALL:aws:RequestTag/Project:non-matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateServiceWithTag:ALL:aws:RequestTag/Project:absent | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateServiceWithTag:ALL:aws:RequestTag/Project:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateServiceWithTag:ALL:aws:RequestTag/Project:non-matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:absent | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryStarOnlyNoCondition:ALL:none:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryTagResource:ALL:aws:RequestTag/Project:absent | policy_input_list | 9cd0b1b4932c90cb94387865fced8a8662ff3797d93299add23d814c763fb886 |
| custom | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryTagResource:ALL:aws:RequestTag/Project:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryTagResource:ALL:aws:RequestTag/Project:non-matching | policy_input_list | 9cd0b1b4932c90cb94387865fced8a8662ff3797d93299add23d814c763fb886 |
| custom | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryTagResourceExisting:ALL:aws:ResourceTag/Project:absent | policy_input_list | cd75bd84075937ee48db83bd1d5f28850df4e7d4c7ca267b2944aeac221593b4 |
| custom | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryTagResourceExisting:ALL:aws:ResourceTag/Project:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryTagResourceExisting:ALL:aws:ResourceTag/Project:non-matching | policy_input_list | cd75bd84075937ee48db83bd1d5f28850df4e7d4c7ca267b2944aeac221593b4 |
| custom | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryUntagResource:ALL:aws:TagKeys:absent | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryUntagResource:ALL:aws:TagKeys:all-matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryUntagResource:ALL:aws:TagKeys:any-non-matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_elb_ecs:TagInventoryStarOnly:ALL:none:matching | policy_input_list | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| custom | case:aws_iam_policy.deployer_guard:DenyMutatingOwnControlRoles:ALL:none:non-protected-resource | policy_input_list | b1198b2ed182297f09172bf96917ce6a1e18cef2657361a195dfa28765017832 |
| custom | case:aws_iam_policy.deployer_guard:DenyMutatingOwnControlRoles:ALL:none:protected-resource | policy_input_list | b1198b2ed182297f09172bf96917ce6a1e18cef2657361a195dfa28765017832 |
| custom | case:aws_iam_policy.deployer_iam:DenyDeleteRolePermissionsBoundary:ALL:none:protected-resource | policy_input_list | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| custom | case:aws_iam_policy.deployer_iam:DenyRoleMutationMissingBoundary:ALL:iam:PermissionsBoundary:absent | policy_input_list | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| custom | case:aws_iam_policy.deployer_iam:DenyRoleMutationMissingBoundary:ALL:iam:PermissionsBoundary:present | policy_input_list | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| custom | case:aws_iam_policy.deployer_iam:DenyRoleMutationMissingBoundary:ALL:none:protected-resource | policy_input_list | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| custom | case:aws_iam_policy.deployer_iam:DenyRoleMutationWrongBoundary:ALL:iam:PermissionsBoundary:absent | policy_input_list | 2b2d4308c60b970b9b4c406873b64007545c3910a6d2029851cd5abdbabade7b |
| custom | case:aws_iam_policy.deployer_iam:DenyRoleMutationWrongBoundary:ALL:iam:PermissionsBoundary:different | policy_input_list | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| custom | case:aws_iam_policy.deployer_iam:DenyRoleMutationWrongBoundary:ALL:iam:PermissionsBoundary:equal | policy_input_list | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| custom | case:aws_iam_policy.deployer_iam:DenyRoleMutationWrongBoundary:ALL:none:protected-resource | policy_input_list | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| custom | case:aws_iam_policy.deployer_iam:EnvServiceRoleAttachPolicy:ALL:iam:PermissionsBoundary:absent | policy_input_list | 394ee0c62bb3c8f1667c1aa74e7168fb637938e71af649c0debbf94ed7709c7b |
| custom | case:aws_iam_policy.deployer_iam:EnvServiceRoleAttachPolicy:ALL:iam:PermissionsBoundary:matching | policy_input_list | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| custom | case:aws_iam_policy.deployer_iam:EnvServiceRoleAttachPolicy:ALL:iam:PermissionsBoundary:non-matching | policy_input_list | 394ee0c62bb3c8f1667c1aa74e7168fb637938e71af649c0debbf94ed7709c7b |
| custom | case:aws_iam_policy.deployer_iam:EnvServiceRoleAttachPolicy:ALL:iam:PolicyARN:absent | policy_input_list | 394ee0c62bb3c8f1667c1aa74e7168fb637938e71af649c0debbf94ed7709c7b |
| custom | case:aws_iam_policy.deployer_iam:EnvServiceRoleAttachPolicy:ALL:iam:PolicyARN:matching | policy_input_list | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| custom | case:aws_iam_policy.deployer_iam:EnvServiceRoleAttachPolicy:ALL:iam:PolicyARN:non-matching | policy_input_list | 394ee0c62bb3c8f1667c1aa74e7168fb637938e71af649c0debbf94ed7709c7b |
| custom | case:aws_iam_policy.deployer_iam:EnvServiceRoleAttachPolicy:ALL:resource:nonmatching | policy_input_list | 394ee0c62bb3c8f1667c1aa74e7168fb637938e71af649c0debbf94ed7709c7b |
| custom | case:aws_iam_policy.deployer_iam:EnvServiceRoleCreateWithBoundary:ALL:iam:PermissionsBoundary:absent | policy_input_list | ad68d8e44222e72d0e379772d566659a24495207c8b94038487c18c0f38c408f |
| custom | case:aws_iam_policy.deployer_iam:EnvServiceRoleCreateWithBoundary:ALL:iam:PermissionsBoundary:matching | policy_input_list | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| custom | case:aws_iam_policy.deployer_iam:EnvServiceRoleCreateWithBoundary:ALL:iam:PermissionsBoundary:non-matching | policy_input_list | ad68d8e44222e72d0e379772d566659a24495207c8b94038487c18c0f38c408f |
| custom | case:aws_iam_policy.deployer_iam:EnvServiceRoleCreateWithBoundary:ALL:resource:nonmatching | policy_input_list | ad68d8e44222e72d0e379772d566659a24495207c8b94038487c18c0f38c408f |
| custom | case:aws_iam_policy.deployer_iam:EnvServiceRoleLifecycle:ALL:none:matching | policy_input_list | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| custom | case:aws_iam_policy.deployer_iam:EnvServiceRoleLifecycle:ALL:resource:nonmatching | policy_input_list | 8fc3eeb573b658040f18c07e14a1bd3d4696987bff710d82af091402fe543c3d |
| custom | case:aws_iam_policy.deployer_iam:EnvServiceRolePermissionsBoundarySet:ALL:iam:PermissionsBoundary:absent | policy_input_list | 1357bf47cf3b5bafc552d011ee41d771c61f00d2df3d16593ed399b388c76cea |
| custom | case:aws_iam_policy.deployer_iam:EnvServiceRolePermissionsBoundarySet:ALL:iam:PermissionsBoundary:matching | policy_input_list | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| custom | case:aws_iam_policy.deployer_iam:EnvServiceRolePermissionsBoundarySet:ALL:iam:PermissionsBoundary:non-matching | policy_input_list | 1357bf47cf3b5bafc552d011ee41d771c61f00d2df3d16593ed399b388c76cea |
| custom | case:aws_iam_policy.deployer_iam:EnvServiceRolePermissionsBoundarySet:ALL:resource:nonmatching | policy_input_list | 1357bf47cf3b5bafc552d011ee41d771c61f00d2df3d16593ed399b388c76cea |
| custom | case:aws_iam_policy.deployer_iam:EnvServiceRolePutPolicy:ALL:iam:PermissionsBoundary:absent | policy_input_list | 0ae5710dd6d1fdb3f93a2efcef1a133946d0e3eb264fcc0ad6d97cdad8729677 |
| custom | case:aws_iam_policy.deployer_iam:EnvServiceRolePutPolicy:ALL:iam:PermissionsBoundary:matching | policy_input_list | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| custom | case:aws_iam_policy.deployer_iam:EnvServiceRolePutPolicy:ALL:iam:PermissionsBoundary:non-matching | policy_input_list | 0ae5710dd6d1fdb3f93a2efcef1a133946d0e3eb264fcc0ad6d97cdad8729677 |
| custom | case:aws_iam_policy.deployer_iam:EnvServiceRolePutPolicy:ALL:resource:nonmatching | policy_input_list | 0ae5710dd6d1fdb3f93a2efcef1a133946d0e3eb264fcc0ad6d97cdad8729677 |
| custom | case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleEcs:ALL:iam:AWSServiceName:absent | policy_input_list | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| custom | case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleEcs:ALL:iam:AWSServiceName:matching | policy_input_list | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| custom | case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleEcs:ALL:iam:AWSServiceName:non-matching | policy_input_list | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| custom | case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleEcs:ALL:resource:nonmatching | policy_input_list | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| custom | case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleElb:ALL:iam:AWSServiceName:absent | policy_input_list | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| custom | case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleElb:ALL:iam:AWSServiceName:matching | policy_input_list | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| custom | case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleElb:ALL:iam:AWSServiceName:non-matching | policy_input_list | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| custom | case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleElb:ALL:resource:nonmatching | policy_input_list | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| custom | case:aws_iam_policy.deployer_iam:PassEnvRolesOnly:ALL:iam:PassedToService:absent | policy_input_list | c642a43c6104be34aa846771b514112701d77520de4c3a31910fd5494289bdf9 |
| custom | case:aws_iam_policy.deployer_iam:PassEnvRolesOnly:ALL:iam:PassedToService:matching | policy_input_list | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| custom | case:aws_iam_policy.deployer_iam:PassEnvRolesOnly:ALL:iam:PassedToService:non-matching | policy_input_list | c642a43c6104be34aa846771b514112701d77520de4c3a31910fd5494289bdf9 |
| custom | case:aws_iam_policy.deployer_iam:PassEnvRolesOnly:ALL:resource:nonmatching | policy_input_list | c642a43c6104be34aa846771b514112701d77520de4c3a31910fd5494289bdf9 |
| custom | case:aws_iam_policy.deployer_state:ListStateBucket:ALL:resource:nonmatching | policy_input_list | 74b1d9ac80423e8c930e688bae3ef8c212a3bf44ba3256402d870538fff19f93 |
| custom | case:aws_iam_policy.deployer_state:ListStateBucket:ALL:s3:prefix:absent | policy_input_list | 74b1d9ac80423e8c930e688bae3ef8c212a3bf44ba3256402d870538fff19f93 |
| custom | case:aws_iam_policy.deployer_state:ListStateBucket:ALL:s3:prefix:matching | policy_input_list | d00c754a8dfc3e1bbfc88aef122a1036e2d8a4be0ef7aa536c6ab37f26693340 |
| custom | case:aws_iam_policy.deployer_state:ListStateBucket:ALL:s3:prefix:non-matching | policy_input_list | 74b1d9ac80423e8c930e688bae3ef8c212a3bf44ba3256402d870538fff19f93 |
| custom | case:aws_iam_policy.deployer_state:StateAndLeaseObjects:ALL:none:matching | policy_input_list | d00c754a8dfc3e1bbfc88aef122a1036e2d8a4be0ef7aa536c6ab37f26693340 |
| custom | case:aws_iam_policy.deployer_state:StateAndLeaseObjects:ALL:resource:nonmatching | policy_input_list | feaa178b880d11ab9e072da1db5fa823e7801fc4028b3d6b0d39e68c2a702d51 |
| custom | case:aws_iam_policy.task_boundary:EcrAuth:ALL:none:in-boundary | permissions_boundary_policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:EcrAuth:ALL:none:in-boundary | policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:EcrAuth:ALL:none:outside-boundary | permissions_boundary_policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:EcrAuth:ALL:none:outside-boundary | policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:EcrAuth:ALL:none:outside-boundary | policy_input_list | 8b24b4ac0409893ffcfce5f12b7e11e8c06309abc400b51dd8c5218649c16be9 |
| custom | case:aws_iam_policy.task_boundary:EcrPull:ALL:none:in-boundary | permissions_boundary_policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:EcrPull:ALL:none:in-boundary | policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:EcrPull:ALL:none:outside-boundary | permissions_boundary_policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:EcrPull:ALL:none:outside-boundary | policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:EcrPull:ALL:none:outside-boundary | policy_input_list | 8b24b4ac0409893ffcfce5f12b7e11e8c06309abc400b51dd8c5218649c16be9 |
| custom | case:aws_iam_policy.task_boundary:EcrPull:ALL:resource:nonmatching | permissions_boundary_policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:EcrPull:ALL:resource:nonmatching | policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:EcsExec:ALL:none:in-boundary | permissions_boundary_policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:EcsExec:ALL:none:in-boundary | policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:EcsExec:ALL:none:outside-boundary | permissions_boundary_policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:EcsExec:ALL:none:outside-boundary | policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:EcsExec:ALL:none:outside-boundary | policy_input_list | 8b24b4ac0409893ffcfce5f12b7e11e8c06309abc400b51dd8c5218649c16be9 |
| custom | case:aws_iam_policy.task_boundary:LogStreams:ALL:none:in-boundary | permissions_boundary_policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:LogStreams:ALL:none:in-boundary | policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:LogStreams:ALL:none:outside-boundary | permissions_boundary_policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:LogStreams:ALL:none:outside-boundary | policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:LogStreams:ALL:none:outside-boundary | policy_input_list | 8b24b4ac0409893ffcfce5f12b7e11e8c06309abc400b51dd8c5218649c16be9 |
| custom | case:aws_iam_policy.task_boundary:LogStreams:ALL:resource:nonmatching | permissions_boundary_policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:LogStreams:ALL:resource:nonmatching | policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:ProjectDataBucket:ALL:none:in-boundary | permissions_boundary_policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:ProjectDataBucket:ALL:none:in-boundary | policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:ProjectDataBucket:ALL:none:outside-boundary | permissions_boundary_policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:ProjectDataBucket:ALL:none:outside-boundary | policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:ProjectDataBucket:ALL:none:outside-boundary | policy_input_list | 8b24b4ac0409893ffcfce5f12b7e11e8c06309abc400b51dd8c5218649c16be9 |
| custom | case:aws_iam_policy.task_boundary:ProjectDataBucket:ALL:resource:nonmatching | permissions_boundary_policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:ProjectDataBucket:ALL:resource:nonmatching | policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:ProjectSecrets:ALL:none:in-boundary | permissions_boundary_policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:ProjectSecrets:ALL:none:in-boundary | policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:ProjectSecrets:ALL:none:outside-boundary | permissions_boundary_policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:ProjectSecrets:ALL:none:outside-boundary | policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:ProjectSecrets:ALL:none:outside-boundary | policy_input_list | 8b24b4ac0409893ffcfce5f12b7e11e8c06309abc400b51dd8c5218649c16be9 |
| custom | case:aws_iam_policy.task_boundary:ProjectSecrets:ALL:resource:nonmatching | permissions_boundary_policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_policy.task_boundary:ProjectSecrets:ALL:resource:nonmatching | policy_input_list | 136c75e891ca322af096e5ec1ed1cee81f07c447fb8dda5d0b4dd40b22c11597 |
| custom | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:none:non-protected-resource | policy_input_list | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| custom | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:none:protected-resource | policy_input_list | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| custom | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:s3:prefix:absent | policy_input_list | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| custom | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:s3:prefix:present | policy_input_list | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| custom | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScope:ALL:none:non-protected-resource | policy_input_list | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| custom | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScope:ALL:none:protected-resource | policy_input_list | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| custom | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:none:non-protected-resource | policy_input_list | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| custom | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:none:protected-resource | policy_input_list | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| custom | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:s3:prefix:absent | policy_input_list | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| custom | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:s3:prefix:inside-set | policy_input_list | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| custom | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:s3:prefix:outside-set | policy_input_list | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| custom | case:aws_iam_role_policy.plan_reader_deny:DenyReadStateObjectsOutsideScope:ALL:none:non-protected-resource | policy_input_list | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| custom | case:aws_iam_role_policy.plan_reader_deny:DenyReadStateObjectsOutsideScope:ALL:none:protected-resource | policy_input_list | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| custom | case:aws_iam_role_policy.plan_reader_deny:DenySecretsAndParams:ALL:none:protected-resource | policy_input_list | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| custom | case:aws_iam_role_policy.plan_reader_state:ListStatePrefixes:ALL:resource:nonmatching | policy_input_list | 94d0cab8496c3c28370263aeebd7c4243103a3e8735ea3ea61b43719d606c120 |
| custom | case:aws_iam_role_policy.plan_reader_state:ListStatePrefixes:ALL:s3:prefix:absent | policy_input_list | 94d0cab8496c3c28370263aeebd7c4243103a3e8735ea3ea61b43719d606c120 |
| custom | case:aws_iam_role_policy.plan_reader_state:ListStatePrefixes:ALL:s3:prefix:matching | policy_input_list | 60a7119c9bbda9dd260d5af0e017346b6a8c9fca0137f85795a73e646c4a0dd7 |
| custom | case:aws_iam_role_policy.plan_reader_state:ListStatePrefixes:ALL:s3:prefix:non-matching | policy_input_list | 94d0cab8496c3c28370263aeebd7c4243103a3e8735ea3ea61b43719d606c120 |
| custom | case:aws_iam_role_policy.plan_reader_state:ReadStateObjects:ALL:none:matching | policy_input_list | 60a7119c9bbda9dd260d5af0e017346b6a8c9fca0137f85795a73e646c4a0dd7 |
| custom | case:aws_iam_role_policy.plan_reader_state:ReadStateObjects:ALL:resource:nonmatching | policy_input_list | f7421adfd5fbdd724ff75a8cddfe31b1711d75fdc035a6d3a3050c01adaddd1e |
| custom | case:aws_iam_role_policy.publisher:EcrAuth:ALL:none:matching | policy_input_list | 42dbf1f6c41183b0205a606cb46fa1680e78886759139365993fe8ea435b1977 |
| custom | case:aws_iam_role_policy.publisher:EcrPushPull:ALL:none:matching | policy_input_list | 42dbf1f6c41183b0205a606cb46fa1680e78886759139365993fe8ea435b1977 |
| custom | case:aws_iam_role_policy.publisher:EcrPushPull:ALL:resource:nonmatching | policy_input_list | 42dbf1f6c41183b0205a606cb46fa1680e78886759139365993fe8ea435b1977 |
| custom | case:aws_iam_role_policy.publisher:SigningKey:ALL:kms:ResourceAliases:absent | policy_input_list | 42dbf1f6c41183b0205a606cb46fa1680e78886759139365993fe8ea435b1977 |
| custom | case:aws_iam_role_policy.publisher:SigningKey:ALL:kms:ResourceAliases:none-matching | policy_input_list | 42dbf1f6c41183b0205a606cb46fa1680e78886759139365993fe8ea435b1977 |
| custom | case:aws_iam_role_policy.publisher:SigningKey:ALL:kms:ResourceAliases:one-matching | policy_input_list | 42dbf1f6c41183b0205a606cb46fa1680e78886759139365993fe8ea435b1977 |
| custom | case:aws_iam_role_policy.publisher:SigningKey:ALL:resource:nonmatching | policy_input_list | 42dbf1f6c41183b0205a606cb46fa1680e78886759139365993fe8ea435b1977 |
| role | case:aws_iam_policy.deployer_data:ClickhouseSecretCreateWithTag:ALL:aws:RequestTag/Project:matching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:ClickhouseSecretCreateWithTag:ALL:aws:RequestTag/Project:matching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:absent | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:absent | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:matching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:matching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:resource:nonmatching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:ClickhouseSecretReadModifyWithResourceTag:ALL:resource:nonmatching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:ClickhouseSecretTagResourceExisting:ALL:aws:ResourceTag/Project:matching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:ClickhouseSecretTagResourceExisting:ALL:aws:ResourceTag/Project:matching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:aws:RequestTag/Project:absent | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:aws:RequestTag/Project:absent | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:aws:RequestTag/Project:matching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:aws:RequestTag/Project:matching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:aws:RequestTag/Project:non-matching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:aws:RequestTag/Project:non-matching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:resource:nonmatching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:CloudwatchAlarmCreateWithTag:ALL:resource:nonmatching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:aws:ResourceTag/Project:absent | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:aws:ResourceTag/Project:absent | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:aws:ResourceTag/Project:matching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:aws:ResourceTag/Project:matching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:resource:nonmatching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:CloudwatchAlarmRestWithResourceTag:ALL:resource:nonmatching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:EcrVerificationAuth:ALL:none:matching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:EcrVerificationAuth:ALL:none:matching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:EcrVerificationPull:ALL:none:matching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:EcrVerificationPull:ALL:none:matching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:EcrVerificationPull:ALL:resource:nonmatching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:EcrVerificationPull:ALL:resource:nonmatching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:LogsCreateWithTag:ALL:aws:RequestTag/Project:matching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:LogsCreateWithTag:ALL:aws:RequestTag/Project:matching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:LogsDescribeStarOnly:ALL:none:matching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:LogsDescribeStarOnly:ALL:none:matching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:LogsModifyDeleteWithResourceTag:ALL:aws:ResourceTag/Project:absent | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:LogsModifyDeleteWithResourceTag:ALL:aws:ResourceTag/Project:absent | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:LogsModifyDeleteWithResourceTag:ALL:aws:ResourceTag/Project:matching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:LogsModifyDeleteWithResourceTag:ALL:aws:ResourceTag/Project:matching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:LogsModifyDeleteWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:LogsModifyDeleteWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:LogsModifyDeleteWithResourceTag:ALL:resource:nonmatching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:LogsModifyDeleteWithResourceTag:ALL:resource:nonmatching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:LogsTagResourceExisting:ALL:aws:ResourceTag/Project:matching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:LogsTagResourceExisting:ALL:aws:ResourceTag/Project:matching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:S3BucketDescribeReads:ALL:none:matching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:S3BucketDescribeReads:ALL:none:matching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SigningPublicKeyRead:ALL:kms:ResourceAliases:absent | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SigningPublicKeyRead:ALL:kms:ResourceAliases:absent | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SigningPublicKeyRead:ALL:kms:ResourceAliases:none-matching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SigningPublicKeyRead:ALL:kms:ResourceAliases:none-matching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SigningPublicKeyRead:ALL:kms:ResourceAliases:one-matching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SigningPublicKeyRead:ALL:kms:ResourceAliases:one-matching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SigningPublicKeyRead:ALL:resource:nonmatching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SigningPublicKeyRead:ALL:resource:nonmatching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:aws:RequestTag/Project:absent | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:aws:RequestTag/Project:absent | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:aws:RequestTag/Project:matching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:aws:RequestTag/Project:matching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:aws:RequestTag/Project:non-matching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:aws:RequestTag/Project:non-matching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:resource:nonmatching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SnsCreateWithTag:ALL:resource:nonmatching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:absent | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:absent | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:matching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:matching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:resource:nonmatching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SnsRestWithResourceTag:ALL:resource:nonmatching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SnsSubscriptionManage:ALL:none:matching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SnsSubscriptionManage:ALL:none:matching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SnsSubscriptionManage:ALL:resource:nonmatching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:SnsSubscriptionManage:ALL:resource:nonmatching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:TagDiscovery:ALL:none:matching | custom_lane | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_data:TagDiscovery:ALL:none:matching | put_role_policy | dd7dfe68310186b0986857a5fd1fbf45f16f3df5c1ea2f98d65f3a07f7991e40 |
| role | case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForCreateActions:ALL:aws:RequestTag/Project:matching | custom_lane | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForCreateActions:ALL:aws:RequestTag/Project:matching | put_role_policy | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForCreateActions:ALL:ec2:CreateAction:matching | custom_lane | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForCreateActions:ALL:ec2:CreateAction:matching | put_role_policy | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForResourceTag:ALL:ec2:ResourceTag/Project:matching | custom_lane | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2CreateTagsForResourceTag:ALL:ec2:ResourceTag/Project:matching | put_role_policy | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:absent | custom_lane | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:absent | put_role_policy | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:matching | custom_lane | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:matching | put_role_policy | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:non-matching | custom_lane | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2CreateWithTag:ALL:aws:RequestTag/Project:non-matching | put_role_policy | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2DeleteTags:ALL:ec2:ResourceTag/Project:absent | custom_lane | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2DeleteTags:ALL:ec2:ResourceTag/Project:absent | put_role_policy | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2DeleteTags:ALL:ec2:ResourceTag/Project:matching | custom_lane | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2DeleteTags:ALL:ec2:ResourceTag/Project:matching | put_role_policy | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2DeleteTags:ALL:ec2:ResourceTag/Project:non-matching | custom_lane | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2DeleteTags:ALL:ec2:ResourceTag/Project:non-matching | put_role_policy | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:absent | custom_lane | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:absent | put_role_policy | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:matching | custom_lane | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:matching | put_role_policy | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:non-matching | custom_lane | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2DescribeStarOnly:ALL:ec2:Region:non-matching | put_role_policy | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | custom_lane | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2ModifyDeleteWithResourceTag:ALL:ec2:ResourceTag/Project:matching | put_role_policy | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2SecurityGroupRuleCreateWithTag:ALL:aws:RequestTag/Project:matching | custom_lane | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_ec2:Ec2SecurityGroupRuleCreateWithTag:ALL:aws:RequestTag/Project:matching | put_role_policy | 6ff61772e9e7e9dd8f02552601a8e6673ccce01fc613cb32ffb67ed5aa9d7d6b |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsCreateWithTag:ALL:aws:RequestTag/Project:absent | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsCreateWithTag:ALL:aws:RequestTag/Project:absent | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsCreateWithTag:ALL:aws:RequestTag/Project:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsCreateWithTag:ALL:aws:RequestTag/Project:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsCreateWithTag:ALL:aws:RequestTag/Project:non-matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsCreateWithTag:ALL:aws:RequestTag/Project:non-matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsListDescribeTasksForProjectClusters:ALL:ecs:cluster:absent | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsListDescribeTasksForProjectClusters:ALL:ecs:cluster:absent | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsListDescribeTasksForProjectClusters:ALL:ecs:cluster:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsListDescribeTasksForProjectClusters:ALL:ecs:cluster:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsListDescribeTasksForProjectClusters:ALL:ecs:cluster:non-matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsListDescribeTasksForProjectClusters:ALL:ecs:cluster:non-matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsListServicesClusterScoped:ALL:ecs:cluster:absent | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsListServicesClusterScoped:ALL:ecs:cluster:absent | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsListServicesClusterScoped:ALL:ecs:cluster:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsListServicesClusterScoped:ALL:ecs:cluster:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsListServicesClusterScoped:ALL:ecs:cluster:non-matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsListServicesClusterScoped:ALL:ecs:cluster:non-matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:absent | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:absent | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:non-matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsModifyDeleteDescribeWithResourceTag:ALL:ecs:ResourceTag/Project:non-matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsStarOnly:ALL:none:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsStarOnly:ALL:none:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsTagResource:ALL:aws:RequestTag/Project:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsTagResource:ALL:aws:RequestTag/Project:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsTagResource:ALL:ecs:CreateAction:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsTagResource:ALL:ecs:CreateAction:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsTagResourceExisting:ALL:ecs:ResourceTag/Project:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsTagResourceExisting:ALL:ecs:ResourceTag/Project:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsUntabledActions:ALL:none:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsUntabledActions:ALL:none:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsUntagAndListTags:ALL:ecs:ResourceTag/Project:absent | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsUntagAndListTags:ALL:ecs:ResourceTag/Project:absent | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsUntagAndListTags:ALL:ecs:ResourceTag/Project:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsUntagAndListTags:ALL:ecs:ResourceTag/Project:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsUntagAndListTags:ALL:ecs:ResourceTag/Project:non-matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:EcsUntagAndListTags:ALL:ecs:ResourceTag/Project:non-matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbAddTags:ALL:aws:RequestTag/Project:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbAddTags:ALL:aws:RequestTag/Project:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbAddTags:ALL:elasticloadbalancing:CreateAction:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbAddTags:ALL:elasticloadbalancing:CreateAction:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbAddTagsForResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbAddTagsForResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbCreateWithTag:ALL:aws:RequestTag/Project:absent | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbCreateWithTag:ALL:aws:RequestTag/Project:absent | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbCreateWithTag:ALL:aws:RequestTag/Project:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbCreateWithTag:ALL:aws:RequestTag/Project:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbCreateWithTag:ALL:aws:RequestTag/Project:non-matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbCreateWithTag:ALL:aws:RequestTag/Project:non-matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbDescribeStarOnly:ALL:none:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbDescribeStarOnly:ALL:none:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbDescribeTargetHealth:ALL:none:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbDescribeTargetHealth:ALL:none:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:absent | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:absent | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:non-matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbModifyDeleteWithResourceTag:ALL:elasticloadbalancing:ResourceTag/Project:non-matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbRemoveTags:ALL:elasticloadbalancing:ResourceTag/Project:absent | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbRemoveTags:ALL:elasticloadbalancing:ResourceTag/Project:absent | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbRemoveTags:ALL:elasticloadbalancing:ResourceTag/Project:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbRemoveTags:ALL:elasticloadbalancing:ResourceTag/Project:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbRemoveTags:ALL:elasticloadbalancing:ResourceTag/Project:non-matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ElbRemoveTags:ALL:elasticloadbalancing:ResourceTag/Project:non-matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:Route53HostedZoneRead:ALL:none:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:Route53HostedZoneRead:ALL:none:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:Route53HostedZoneStarOnly:ALL:none:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:Route53HostedZoneStarOnly:ALL:none:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateNamespaceWithTag:ALL:aws:RequestTag/Project:absent | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateNamespaceWithTag:ALL:aws:RequestTag/Project:absent | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateNamespaceWithTag:ALL:aws:RequestTag/Project:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateNamespaceWithTag:ALL:aws:RequestTag/Project:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateNamespaceWithTag:ALL:aws:RequestTag/Project:non-matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateNamespaceWithTag:ALL:aws:RequestTag/Project:non-matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateServiceWithTag:ALL:aws:RequestTag/Project:absent | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateServiceWithTag:ALL:aws:RequestTag/Project:absent | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateServiceWithTag:ALL:aws:RequestTag/Project:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateServiceWithTag:ALL:aws:RequestTag/Project:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateServiceWithTag:ALL:aws:RequestTag/Project:non-matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryCreateServiceWithTag:ALL:aws:RequestTag/Project:non-matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:absent | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:absent | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryReadDeleteUpdateWithResourceTag:ALL:aws:ResourceTag/Project:non-matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryStarOnlyNoCondition:ALL:none:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryStarOnlyNoCondition:ALL:none:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryTagResource:ALL:aws:RequestTag/Project:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryTagResource:ALL:aws:RequestTag/Project:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryTagResourceExisting:ALL:aws:ResourceTag/Project:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryTagResourceExisting:ALL:aws:ResourceTag/Project:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryUntagResource:ALL:aws:TagKeys:absent | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryUntagResource:ALL:aws:TagKeys:absent | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryUntagResource:ALL:aws:TagKeys:all-matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryUntagResource:ALL:aws:TagKeys:all-matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryUntagResource:ALL:aws:TagKeys:any-non-matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:ServiceDiscoveryUntagResource:ALL:aws:TagKeys:any-non-matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:TagInventoryStarOnly:ALL:none:matching | custom_lane | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_elb_ecs:TagInventoryStarOnly:ALL:none:matching | put_role_policy | 968d308a24d996da4eb875a66a87b28270335a626d61f621e2315e00bdc1d1fe |
| role | case:aws_iam_policy.deployer_guard:DenyMutatingOwnControlRoles:ALL:none:non-protected-resource | custom_lane | b1198b2ed182297f09172bf96917ce6a1e18cef2657361a195dfa28765017832 |
| role | case:aws_iam_policy.deployer_guard:DenyMutatingOwnControlRoles:ALL:none:non-protected-resource | put_role_policy | b1198b2ed182297f09172bf96917ce6a1e18cef2657361a195dfa28765017832 |
| role | case:aws_iam_policy.deployer_guard:DenyMutatingOwnControlRoles:ALL:none:protected-resource | custom_lane | b1198b2ed182297f09172bf96917ce6a1e18cef2657361a195dfa28765017832 |
| role | case:aws_iam_policy.deployer_guard:DenyMutatingOwnControlRoles:ALL:none:protected-resource | put_role_policy | b1198b2ed182297f09172bf96917ce6a1e18cef2657361a195dfa28765017832 |
| role | case:aws_iam_policy.deployer_iam:DenyDeleteRolePermissionsBoundary:ALL:none:protected-resource | custom_lane | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:DenyDeleteRolePermissionsBoundary:ALL:none:protected-resource | put_role_policy | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:DenyRoleMutationMissingBoundary:ALL:iam:PermissionsBoundary:absent | custom_lane | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:DenyRoleMutationMissingBoundary:ALL:iam:PermissionsBoundary:absent | put_role_policy | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:DenyRoleMutationMissingBoundary:ALL:iam:PermissionsBoundary:present | custom_lane | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:DenyRoleMutationMissingBoundary:ALL:iam:PermissionsBoundary:present | put_role_policy | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:DenyRoleMutationMissingBoundary:ALL:none:protected-resource | custom_lane | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:DenyRoleMutationMissingBoundary:ALL:none:protected-resource | put_role_policy | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:DenyRoleMutationWrongBoundary:ALL:iam:PermissionsBoundary:different | custom_lane | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:DenyRoleMutationWrongBoundary:ALL:iam:PermissionsBoundary:different | put_role_policy | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:DenyRoleMutationWrongBoundary:ALL:iam:PermissionsBoundary:equal | custom_lane | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:DenyRoleMutationWrongBoundary:ALL:iam:PermissionsBoundary:equal | put_role_policy | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:DenyRoleMutationWrongBoundary:ALL:none:protected-resource | custom_lane | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:DenyRoleMutationWrongBoundary:ALL:none:protected-resource | put_role_policy | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:EnvServiceRoleAttachPolicy:ALL:iam:PermissionsBoundary:matching | custom_lane | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:EnvServiceRoleAttachPolicy:ALL:iam:PermissionsBoundary:matching | put_role_policy | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:EnvServiceRoleAttachPolicy:ALL:iam:PolicyARN:matching | custom_lane | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:EnvServiceRoleAttachPolicy:ALL:iam:PolicyARN:matching | put_role_policy | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:EnvServiceRoleCreateWithBoundary:ALL:iam:PermissionsBoundary:matching | custom_lane | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:EnvServiceRoleCreateWithBoundary:ALL:iam:PermissionsBoundary:matching | put_role_policy | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:EnvServiceRoleLifecycle:ALL:none:matching | custom_lane | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:EnvServiceRoleLifecycle:ALL:none:matching | put_role_policy | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:EnvServiceRolePermissionsBoundarySet:ALL:iam:PermissionsBoundary:matching | custom_lane | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:EnvServiceRolePermissionsBoundarySet:ALL:iam:PermissionsBoundary:matching | put_role_policy | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:EnvServiceRolePutPolicy:ALL:iam:PermissionsBoundary:matching | custom_lane | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:EnvServiceRolePutPolicy:ALL:iam:PermissionsBoundary:matching | put_role_policy | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleEcs:ALL:iam:AWSServiceName:absent | custom_lane | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleEcs:ALL:iam:AWSServiceName:absent | put_role_policy | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleEcs:ALL:iam:AWSServiceName:matching | custom_lane | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleEcs:ALL:iam:AWSServiceName:matching | put_role_policy | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleEcs:ALL:iam:AWSServiceName:non-matching | custom_lane | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleEcs:ALL:iam:AWSServiceName:non-matching | put_role_policy | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleEcs:ALL:resource:nonmatching | custom_lane | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleEcs:ALL:resource:nonmatching | put_role_policy | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleElb:ALL:iam:AWSServiceName:absent | custom_lane | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleElb:ALL:iam:AWSServiceName:absent | put_role_policy | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleElb:ALL:iam:AWSServiceName:matching | custom_lane | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleElb:ALL:iam:AWSServiceName:matching | put_role_policy | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleElb:ALL:iam:AWSServiceName:non-matching | custom_lane | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleElb:ALL:iam:AWSServiceName:non-matching | put_role_policy | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleElb:ALL:resource:nonmatching | custom_lane | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:IamServiceLinkedRoleElb:ALL:resource:nonmatching | put_role_policy | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:PassEnvRolesOnly:ALL:iam:PassedToService:matching | custom_lane | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_iam:PassEnvRolesOnly:ALL:iam:PassedToService:matching | put_role_policy | 56484064fff8cb8fa0e54b089173808533cb365e2adcfeac9b8c2aa561258203 |
| role | case:aws_iam_policy.deployer_state:ListStateBucket:ALL:s3:prefix:matching | custom_lane | d00c754a8dfc3e1bbfc88aef122a1036e2d8a4be0ef7aa536c6ab37f26693340 |
| role | case:aws_iam_policy.deployer_state:ListStateBucket:ALL:s3:prefix:matching | put_role_policy | d00c754a8dfc3e1bbfc88aef122a1036e2d8a4be0ef7aa536c6ab37f26693340 |
| role | case:aws_iam_policy.deployer_state:StateAndLeaseObjects:ALL:none:matching | custom_lane | d00c754a8dfc3e1bbfc88aef122a1036e2d8a4be0ef7aa536c6ab37f26693340 |
| role | case:aws_iam_policy.deployer_state:StateAndLeaseObjects:ALL:none:matching | put_role_policy | d00c754a8dfc3e1bbfc88aef122a1036e2d8a4be0ef7aa536c6ab37f26693340 |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:none:non-protected-resource | custom_lane | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:none:non-protected-resource | put_role_policy | ca4e12443217456e103482cafb6b98a7b2472fcbe5984e61898bf549da11bee1 |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:none:protected-resource | custom_lane | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:none:protected-resource | put_role_policy | ca4e12443217456e103482cafb6b98a7b2472fcbe5984e61898bf549da11bee1 |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:s3:prefix:absent | custom_lane | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:s3:prefix:absent | put_role_policy | ca4e12443217456e103482cafb6b98a7b2472fcbe5984e61898bf549da11bee1 |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:s3:prefix:present | custom_lane | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketMissingPrefix:ALL:s3:prefix:present | put_role_policy | ca4e12443217456e103482cafb6b98a7b2472fcbe5984e61898bf549da11bee1 |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScope:ALL:none:non-protected-resource | custom_lane | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScope:ALL:none:non-protected-resource | put_role_policy | ca4e12443217456e103482cafb6b98a7b2472fcbe5984e61898bf549da11bee1 |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScope:ALL:none:protected-resource | custom_lane | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScope:ALL:none:protected-resource | put_role_policy | ca4e12443217456e103482cafb6b98a7b2472fcbe5984e61898bf549da11bee1 |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:none:non-protected-resource | custom_lane | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:none:non-protected-resource | put_role_policy | ca4e12443217456e103482cafb6b98a7b2472fcbe5984e61898bf549da11bee1 |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:none:protected-resource | custom_lane | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:none:protected-resource | put_role_policy | ca4e12443217456e103482cafb6b98a7b2472fcbe5984e61898bf549da11bee1 |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:s3:prefix:absent | custom_lane | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:s3:prefix:absent | put_role_policy | ca4e12443217456e103482cafb6b98a7b2472fcbe5984e61898bf549da11bee1 |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:s3:prefix:inside-set | custom_lane | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:s3:prefix:inside-set | put_role_policy | ca4e12443217456e103482cafb6b98a7b2472fcbe5984e61898bf549da11bee1 |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:s3:prefix:outside-set | custom_lane | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyListBucketOutsideScopePrefix:ALL:s3:prefix:outside-set | put_role_policy | ca4e12443217456e103482cafb6b98a7b2472fcbe5984e61898bf549da11bee1 |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyReadStateObjectsOutsideScope:ALL:none:non-protected-resource | custom_lane | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyReadStateObjectsOutsideScope:ALL:none:non-protected-resource | put_role_policy | ca4e12443217456e103482cafb6b98a7b2472fcbe5984e61898bf549da11bee1 |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyReadStateObjectsOutsideScope:ALL:none:protected-resource | custom_lane | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| role | case:aws_iam_role_policy.plan_reader_deny:DenyReadStateObjectsOutsideScope:ALL:none:protected-resource | put_role_policy | ca4e12443217456e103482cafb6b98a7b2472fcbe5984e61898bf549da11bee1 |
| role | case:aws_iam_role_policy.plan_reader_deny:DenySecretsAndParams:ALL:none:protected-resource | custom_lane | f8eb92ce799744d4866360a99bcdc75d231292abbd2a6d86d60432651dcfb96b |
| role | case:aws_iam_role_policy.plan_reader_deny:DenySecretsAndParams:ALL:none:protected-resource | put_role_policy | ca4e12443217456e103482cafb6b98a7b2472fcbe5984e61898bf549da11bee1 |
| role | case:aws_iam_role_policy.plan_reader_state:ListStatePrefixes:ALL:s3:prefix:matching | custom_lane | 60a7119c9bbda9dd260d5af0e017346b6a8c9fca0137f85795a73e646c4a0dd7 |
| role | case:aws_iam_role_policy.plan_reader_state:ListStatePrefixes:ALL:s3:prefix:matching | put_role_policy | ca4e12443217456e103482cafb6b98a7b2472fcbe5984e61898bf549da11bee1 |
| role | case:aws_iam_role_policy.plan_reader_state:ReadStateObjects:ALL:none:matching | custom_lane | 60a7119c9bbda9dd260d5af0e017346b6a8c9fca0137f85795a73e646c4a0dd7 |
| role | case:aws_iam_role_policy.plan_reader_state:ReadStateObjects:ALL:none:matching | put_role_policy | ca4e12443217456e103482cafb6b98a7b2472fcbe5984e61898bf549da11bee1 |
| role | case:aws_iam_role_policy.publisher:EcrAuth:ALL:none:matching | custom_lane | 42dbf1f6c41183b0205a606cb46fa1680e78886759139365993fe8ea435b1977 |
| role | case:aws_iam_role_policy.publisher:EcrAuth:ALL:none:matching | put_role_policy | 42dbf1f6c41183b0205a606cb46fa1680e78886759139365993fe8ea435b1977 |
| role | case:aws_iam_role_policy.publisher:EcrPushPull:ALL:none:matching | custom_lane | 42dbf1f6c41183b0205a606cb46fa1680e78886759139365993fe8ea435b1977 |
| role | case:aws_iam_role_policy.publisher:EcrPushPull:ALL:none:matching | put_role_policy | 42dbf1f6c41183b0205a606cb46fa1680e78886759139365993fe8ea435b1977 |
| role | case:aws_iam_role_policy.publisher:EcrPushPull:ALL:resource:nonmatching | custom_lane | 42dbf1f6c41183b0205a606cb46fa1680e78886759139365993fe8ea435b1977 |
| role | case:aws_iam_role_policy.publisher:EcrPushPull:ALL:resource:nonmatching | put_role_policy | 42dbf1f6c41183b0205a606cb46fa1680e78886759139365993fe8ea435b1977 |
| role | case:aws_iam_role_policy.publisher:SigningKey:ALL:kms:ResourceAliases:absent | custom_lane | 42dbf1f6c41183b0205a606cb46fa1680e78886759139365993fe8ea435b1977 |
| role | case:aws_iam_role_policy.publisher:SigningKey:ALL:kms:ResourceAliases:absent | put_role_policy | 42dbf1f6c41183b0205a606cb46fa1680e78886759139365993fe8ea435b1977 |
| role | case:aws_iam_role_policy.publisher:SigningKey:ALL:kms:ResourceAliases:none-matching | custom_lane | 42dbf1f6c41183b0205a606cb46fa1680e78886759139365993fe8ea435b1977 |
| role | case:aws_iam_role_policy.publisher:SigningKey:ALL:kms:ResourceAliases:none-matching | put_role_policy | 42dbf1f6c41183b0205a606cb46fa1680e78886759139365993fe8ea435b1977 |
| role | case:aws_iam_role_policy.publisher:SigningKey:ALL:kms:ResourceAliases:one-matching | custom_lane | 42dbf1f6c41183b0205a606cb46fa1680e78886759139365993fe8ea435b1977 |
| role | case:aws_iam_role_policy.publisher:SigningKey:ALL:kms:ResourceAliases:one-matching | put_role_policy | 42dbf1f6c41183b0205a606cb46fa1680e78886759139365993fe8ea435b1977 |
| role | case:aws_iam_role_policy.publisher:SigningKey:ALL:resource:nonmatching | custom_lane | 42dbf1f6c41183b0205a606cb46fa1680e78886759139365993fe8ea435b1977 |
| role | case:aws_iam_role_policy.publisher:SigningKey:ALL:resource:nonmatching | put_role_policy | 42dbf1f6c41183b0205a606cb46fa1680e78886759139365993fe8ea435b1977 |
