package main

has_message(messages, address) if {
	some message in messages
	contains(message, address)
}

test_non_plan_document_denies if {
	messages := deny with input as {}

	count(messages) == 1
	"input is not a terraform show -json plan document" in messages
}

test_protected_bucket_passes if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_s3_bucket.data", "type": "aws_s3_bucket"},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": ["aws_s3_bucket.data.bucket", "aws_s3_bucket.data"]}},
			},
		]}},
		"resource_changes": [
			{"address": "aws_s3_bucket.data", "type": "aws_s3_bucket", "change": {"after": {"bucket": "planned-data"}}},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"type": "aws_s3_bucket_public_access_block",
				"change": {"after": {
					"bucket": "planned-data",
					"block_public_acls": true,
					"block_public_policy": true,
					"ignore_public_acls": true,
					"restrict_public_buckets": true,
				}},
			},
		],
	}

	count(messages) == 0
}

test_indexed_bucket_instance_denies_even_with_protecting_block if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_s3_bucket.data", "type": "aws_s3_bucket"},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": ["aws_s3_bucket.data"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_s3_bucket.data[0]",
				"type": "aws_s3_bucket",
				"change": {"actions": ["create"], "after": {}},
			},
			{
				"address": "aws_s3_bucket_public_access_block.data[0]",
				"type": "aws_s3_bucket_public_access_block",
				"change": {"actions": ["create"], "after": {
					"block_public_acls": true,
					"block_public_policy": true,
					"ignore_public_acls": true,
					"restrict_public_buckets": true,
				}},
			},
		],
	}

	count(messages) == 1
	"aws_s3_bucket.data[0]: S3 bucket instance correlation unsupported" in messages
}

test_child_module_bucket_denies_even_with_protecting_block if {
	messages := deny with input as {
		"configuration": {"root_module": {"module_calls": {"x": {"module": {"resources": [
			{"address": "module.x.aws_s3_bucket.y", "type": "aws_s3_bucket"},
			{
				"address": "module.x.aws_s3_bucket_public_access_block.y",
				"type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": ["module.x.aws_s3_bucket.y"]}},
			},
		]}}}}},
		"resource_changes": [
			{"address": "module.x.aws_s3_bucket.y", "type": "aws_s3_bucket", "change": {"after": {}}},
			{
				"address": "module.x.aws_s3_bucket_public_access_block.y",
				"type": "aws_s3_bucket_public_access_block",
				"change": {"after": {
					"block_public_acls": true,
					"block_public_policy": true,
					"ignore_public_acls": true,
					"restrict_public_buckets": true,
				}},
			},
		],
	}

	count(messages) == 1
	"module.x.aws_s3_bucket.y: child-module bucket correlation unsupported; declare the bucket at the root or extend the policy" in messages
}

test_bucket_without_public_access_block_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_s3_bucket.data", "type": "aws_s3_bucket"},
		]}},
		"resource_changes": [
			{"address": "aws_s3_bucket.data", "type": "aws_s3_bucket", "change": {"after": {}}},
		],
	}

	count(messages) == 1
	has_message(messages, "aws_s3_bucket.data")
}

test_bucket_with_false_public_access_flag_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_s3_bucket.data", "type": "aws_s3_bucket"},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": ["aws_s3_bucket.data"]}},
			},
		]}},
		"resource_changes": [
			{"address": "aws_s3_bucket.data", "type": "aws_s3_bucket", "change": {"after": {"bucket": "planned-data"}}},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"type": "aws_s3_bucket_public_access_block",
				"change": {"after": {
					"bucket": "planned-data",
					"block_public_acls": true,
					"block_public_policy": false,
					"ignore_public_acls": true,
					"restrict_public_buckets": true,
				}},
			},
		],
	}

	count(messages) == 1
	has_message(messages, "aws_s3_bucket.data")
}

test_noop_bucket_with_weakened_block_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_s3_bucket.data", "type": "aws_s3_bucket"},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": ["aws_s3_bucket.data"]}},
			},
		]}},
		"resource_changes": [
			{"address": "aws_s3_bucket.data", "type": "aws_s3_bucket", "change": {"actions": ["no-op"], "after": {"bucket": "planned-data"}}},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"type": "aws_s3_bucket_public_access_block",
				"change": {"actions": ["update"], "after": {
					"bucket": "planned-data",
					"block_public_acls": true,
					"block_public_policy": true,
					"ignore_public_acls": true,
					"restrict_public_buckets": false,
				}},
			},
		],
	}

	count(messages) == 1
	has_message(messages, "aws_s3_bucket.data")
}

test_noop_bucket_with_deleted_block_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_s3_bucket.data", "type": "aws_s3_bucket"},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": ["aws_s3_bucket.data"]}},
			},
		]}},
		"resource_changes": [
			{"address": "aws_s3_bucket.data", "type": "aws_s3_bucket", "change": {"actions": ["no-op"], "after": {}}},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"type": "aws_s3_bucket_public_access_block",
				"change": {"actions": ["delete"], "after": null},
			},
		],
	}

	count(messages) == 1
	has_message(messages, "aws_s3_bucket.data")
}

test_pure_bucket_delete_is_skipped if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_s3_bucket.data", "type": "aws_s3_bucket"},
		]}},
		"resource_changes": [
			{"address": "aws_s3_bucket.data", "type": "aws_s3_bucket", "change": {"actions": ["delete"], "after": null}},
		],
	}

	count(messages) == 0
}

test_bucket_prefix_collision_denies_only_unprotected_bucket if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_s3_bucket.data", "type": "aws_s3_bucket"},
			{"address": "aws_s3_bucket.database", "type": "aws_s3_bucket"},
			{
				"address": "aws_s3_bucket_public_access_block.database",
				"type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": ["aws_s3_bucket.database", "aws_s3_bucket.database.id"]}},
			},
		]}},
		"resource_changes": [
			{"address": "aws_s3_bucket.data", "type": "aws_s3_bucket", "change": {"after": {"bucket": "planned-data"}}},
			{"address": "aws_s3_bucket.database", "type": "aws_s3_bucket", "change": {"after": {"bucket": "planned-database"}}},
			{
				"address": "aws_s3_bucket_public_access_block.database",
				"type": "aws_s3_bucket_public_access_block",
				"change": {"after": {
					"bucket": "planned-database",
					"block_public_acls": true,
					"block_public_policy": true,
					"ignore_public_acls": true,
					"restrict_public_buckets": true,
				}},
			},
		],
	}

	count(messages) == 1
	has_message(messages, "aws_s3_bucket.data")
	not has_message(messages, "aws_s3_bucket.database")
}

test_block_referencing_two_buckets_denies_both if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_s3_bucket.data", "type": "aws_s3_bucket"},
			{"address": "aws_s3_bucket.logs", "type": "aws_s3_bucket"},
			{
				"address": "aws_s3_bucket_public_access_block.shared",
				"type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": [
					"aws_s3_bucket.data",
					"aws_s3_bucket.data.id",
					"aws_s3_bucket.logs",
					"aws_s3_bucket.logs.id",
				]}},
			},
		]}},
		"resource_changes": [
			{"address": "aws_s3_bucket.data", "type": "aws_s3_bucket", "change": {"after": {}}},
			{"address": "aws_s3_bucket.logs", "type": "aws_s3_bucket", "change": {"after": {}}},
			{
				"address": "aws_s3_bucket_public_access_block.shared",
				"type": "aws_s3_bucket_public_access_block",
				"change": {"after": {
					"block_public_acls": true,
					"block_public_policy": true,
					"ignore_public_acls": true,
					"restrict_public_buckets": true,
				}},
			},
		],
	}

	count(messages) == 2
	has_message(messages, "aws_s3_bucket.data")
	has_message(messages, "aws_s3_bucket.logs")
}

test_open_group_referenced_by_planned_alb_passes if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb", "aws_security_group.alb.id"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"type": "aws_security_group",
				"change": {"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"], "ipv6_cidr_blocks": []}]}, "after_unknown": {"id": true}},
			},
			{"address": "aws_lb.public", "type": "aws_lb", "change": {"after": {"load_balancer_type": "application"}, "after_unknown": {"security_groups": true}}},
		],
	}

	count(messages) == 0
}

test_open_group_named_alb_without_load_balancer_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "type": "aws_security_group"},
		]}},
		"resource_changes": [{
			"address": "aws_security_group.alb",
			"type": "aws_security_group",
			"change": {"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]}},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group.alb")
}

test_open_group_referenced_only_by_unplanned_load_balancer_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.zero_lb", "type": "aws_security_group"},
			{
				"address": "aws_lb.none",
				"type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.zero_lb"]}},
			},
		]}},
		"resource_changes": [{
			"address": "aws_security_group.zero_lb",
			"type": "aws_security_group",
			"change": {"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]}},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group.zero_lb")
}

test_open_group_referenced_by_deleted_load_balancer_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"type": "aws_security_group",
				"change": {"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]}},
			},
			{"address": "aws_lb.public", "type": "aws_lb", "change": {"actions": ["delete"], "after": null}},
		],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group.alb")
}

test_open_modern_ingress_rule_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "type": "aws_security_group"},
			{
				"address": "aws_vpc_security_group_ingress_rule.open",
				"type": "aws_vpc_security_group_ingress_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.service", "aws_security_group.service.id"]}},
			},
		]}},
		"resource_changes": [{
			"address": "aws_vpc_security_group_ingress_rule.open",
			"type": "aws_vpc_security_group_ingress_rule",
			"change": {"after": {"cidr_ipv4": "0.0.0.0/0", "cidr_ipv6": null}},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_vpc_security_group_ingress_rule.open")
}

test_open_ipv6_modern_ingress_rule_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "type": "aws_security_group"},
			{
				"address": "aws_vpc_security_group_ingress_rule.open_ipv6",
				"type": "aws_vpc_security_group_ingress_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.service"]}},
			},
		]}},
		"resource_changes": [{
			"address": "aws_vpc_security_group_ingress_rule.open_ipv6",
			"type": "aws_vpc_security_group_ingress_rule",
			"change": {"after": {"cidr_ipv4": null, "cidr_ipv6": "::/0"}},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_vpc_security_group_ingress_rule.open_ipv6")
}

test_open_modern_rule_attached_to_planned_alb_group_passes if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb"]}},
			},
			{
				"address": "aws_vpc_security_group_ingress_rule.http",
				"type": "aws_vpc_security_group_ingress_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.alb", "aws_security_group.alb.id"]}},
			},
		]}},
		"resource_changes": [
			{"address": "aws_security_group.alb", "type": "aws_security_group", "change": {"after": {"ingress": []}, "after_unknown": {"id": true}}},
			{"address": "aws_lb.public", "type": "aws_lb", "change": {"after": {}, "after_unknown": {"security_groups": true}}},
			{
				"address": "aws_vpc_security_group_ingress_rule.http",
				"type": "aws_vpc_security_group_ingress_rule",
				"change": {"after": {"cidr_ipv4": "0.0.0.0/0", "cidr_ipv6": null}},
			},
		],
	}

	count(messages) == 0
}

test_open_legacy_ingress_rule_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "type": "aws_security_group"},
			{
				"address": "aws_security_group_rule.legacy_open",
				"type": "aws_security_group_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.service"]}},
			},
		]}},
		"resource_changes": [{
			"address": "aws_security_group_rule.legacy_open",
			"type": "aws_security_group_rule",
			"change": {"after": {"type": "ingress", "cidr_blocks": ["0.0.0.0/0"], "ipv6_cidr_blocks": []}},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group_rule.legacy_open")
}

test_open_ipv6_legacy_ingress_rule_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "type": "aws_security_group"},
			{
				"address": "aws_security_group_rule.legacy_open_ipv6",
				"type": "aws_security_group_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.service"]}},
			},
		]}},
		"resource_changes": [{
			"address": "aws_security_group_rule.legacy_open_ipv6",
			"type": "aws_security_group_rule",
			"change": {"after": {"type": "ingress", "cidr_blocks": [], "ipv6_cidr_blocks": ["::/0"]}},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group_rule.legacy_open_ipv6")
}

test_unknown_cidr_on_legacy_ingress_rule_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "type": "aws_security_group"},
			{
				"address": "aws_security_group_rule.legacy_unknown",
				"type": "aws_security_group_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.service"]}},
			},
		]}},
		"resource_changes": [{
			"address": "aws_security_group_rule.legacy_unknown",
			"type": "aws_security_group_rule",
			"change": {
				"after": {"type": "ingress", "cidr_blocks": null, "ipv6_cidr_blocks": []},
				"after_unknown": {"cidr_blocks": true},
			},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group_rule.legacy_unknown")
}

test_default_security_group_with_open_ingress_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": []}},
		"resource_changes": [{
			"address": "aws_default_security_group.default",
			"type": "aws_default_security_group",
			"change": {"after": {"ingress": [{"ipv6_cidr_blocks": ["::/0"]}]}},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_default_security_group.default")
}

test_unknown_inline_cidr_on_non_alb_group_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "type": "aws_security_group"},
		]}},
		"resource_changes": [{
			"address": "aws_security_group.service",
			"type": "aws_security_group",
			"change": {
				"after": {"ingress": [{"cidr_blocks": [], "ipv6_cidr_blocks": []}]},
				"after_unknown": {"ingress": [{"cidr_blocks": true}]},
			},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group.service")
}

test_unknown_cidr_on_modern_rule_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "type": "aws_security_group"},
			{
				"address": "aws_vpc_security_group_ingress_rule.unknown",
				"type": "aws_vpc_security_group_ingress_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.service"]}},
			},
		]}},
		"resource_changes": [{
			"address": "aws_vpc_security_group_ingress_rule.unknown",
			"type": "aws_vpc_security_group_ingress_rule",
			"change": {
				"after": {"cidr_ipv4": null, "cidr_ipv6": null},
				"after_unknown": {"cidr_ipv4": true},
			},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_vpc_security_group_ingress_rule.unknown")
}

test_string_key_bucket_instance_denies_as_unsupported if {
	address := "aws_s3_bucket.data[\"a\"]"
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_s3_bucket.data", "type": "aws_s3_bucket"},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": ["aws_s3_bucket.data.bucket", "aws_s3_bucket.data"]}},
			},
		]}},
		"resource_changes": [
			{"address": address, "type": "aws_s3_bucket", "change": {"after": {"bucket": "planned-data-a"}}},
			{
				"address": "aws_s3_bucket_public_access_block.data[\"a\"]",
				"type": "aws_s3_bucket_public_access_block",
				"change": {"after": {
					"bucket": "planned-data-a",
					"block_public_acls": true,
					"block_public_policy": true,
					"ignore_public_acls": true,
					"restrict_public_buckets": true,
				}},
			},
		],
	}

	count(messages) == 1
	sprintf("%s: S3 bucket instance correlation unsupported", [address]) in messages
}

test_bucket_block_conditional_target_mismatch_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_s3_bucket.data", "type": "aws_s3_bucket"},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": ["aws_s3_bucket.data.id", "aws_s3_bucket.data"]}},
			},
		]}},
		"resource_changes": [
			{"address": "aws_s3_bucket.data", "type": "aws_s3_bucket", "change": {"after": {"bucket": "planned-data"}}},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"type": "aws_s3_bucket_public_access_block",
				"change": {"after": {
					"bucket": "other",
					"block_public_acls": true,
					"block_public_policy": true,
					"ignore_public_acls": true,
					"restrict_public_buckets": true,
				}},
			},
		],
	}

	count(messages) == 1
	"aws_s3_bucket.data: public access block target is unknown or does not match at plan time; reference the bucket via .bucket" in messages
}

test_bucket_block_unknown_target_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_s3_bucket.data", "type": "aws_s3_bucket"},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": ["aws_s3_bucket.data.id", "aws_s3_bucket.data"]}},
			},
		]}},
		"resource_changes": [
			{"address": "aws_s3_bucket.data", "type": "aws_s3_bucket", "change": {"after": {"bucket": "planned-data"}}},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"type": "aws_s3_bucket_public_access_block",
				"change": {
					"after": {
						"block_public_acls": true,
						"block_public_policy": true,
						"ignore_public_acls": true,
						"restrict_public_buckets": true,
					},
					"after_unknown": {"bucket": true},
				},
			},
		],
	}

	count(messages) == 1
	"aws_s3_bucket.data: public access block target is unknown or does not match at plan time; reference the bucket via .bucket" in messages
}

test_two_blocks_targeting_one_bucket_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_s3_bucket.data", "type": "aws_s3_bucket"},
			{
				"address": "aws_s3_bucket_public_access_block.first",
				"type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": ["aws_s3_bucket.data.bucket", "aws_s3_bucket.data"]}},
			},
			{
				"address": "aws_s3_bucket_public_access_block.second",
				"type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": ["aws_s3_bucket.data.bucket", "aws_s3_bucket.data"]}},
			},
		]}},
		"resource_changes": array.concat(
			[{"address": "aws_s3_bucket.data", "type": "aws_s3_bucket", "change": {"after": {"bucket": "planned-data"}}}],
			[{
				"address": sprintf("aws_s3_bucket_public_access_block.%s", [name]),
				"type": "aws_s3_bucket_public_access_block",
				"change": {"after": {
					"bucket": "planned-data",
					"block_public_acls": true,
					"block_public_policy": true,
					"ignore_public_acls": true,
					"restrict_public_buckets": true,
				}},
			} |
				some name in ["first", "second"]
			],
		),
	}

	count(messages) == 1
	has_message(messages, "aws_s3_bucket.data")
}

test_alb_conditional_between_two_groups_exempts_neither if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.first", "type": "aws_security_group"},
			{"address": "aws_security_group.second", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"type": "aws_lb",
				"expressions": {"security_groups": {"references": [
					"aws_security_group.first.id",
					"aws_security_group.first",
					"aws_security_group.second.id",
					"aws_security_group.second",
				]}},
			},
		]}},
		"resource_changes": array.concat(
			[{
				"address": sprintf("aws_security_group.%s", [name]),
				"type": "aws_security_group",
				"change": {
					"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]},
					"after_unknown": {"id": true},
				},
			} |
				some name in ["first", "second"]
			],
			[{
				"address": "aws_lb.public",
				"type": "aws_lb",
				"change": {
					"after": {"load_balancer_type": "application"},
					"after_unknown": {"security_groups": true},
				},
			}],
		),
	}

	count(messages) == 2
	has_message(messages, "aws_security_group.first")
	has_message(messages, "aws_security_group.second")
}

test_child_module_load_balancer_does_not_exempt_group if {
	messages := deny with input as {
		"configuration": {"root_module": {
			"resources": [],
			"module_calls": {"child": {"module": {"resources": [
				{"address": "module.child.aws_security_group.alb", "type": "aws_security_group"},
				{
					"address": "module.child.aws_lb.public",
					"type": "aws_lb",
					"expressions": {"security_groups": {"references": [
						"module.child.aws_security_group.alb.id",
						"module.child.aws_security_group.alb",
					]}},
				},
			]}}},
		}},
		"resource_changes": [
			{
				"address": "module.child.aws_security_group.alb",
				"type": "aws_security_group",
				"change": {
					"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]},
					"after_unknown": {"id": true},
				},
			},
			{
				"address": "module.child.aws_lb.public",
				"type": "aws_lb",
				"change": {"after": {}, "after_unknown": {"security_groups": true}},
			},
		],
	}

	count(messages) == 1
	has_message(messages, "module.child.aws_security_group.alb")
}

test_count_one_load_balancer_exempts_single_group if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb.id", "aws_security_group.alb"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"type": "aws_security_group",
				"change": {
					"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]},
					"after_unknown": {"id": true},
				},
			},
			{
				"address": "aws_lb.public[0]",
				"type": "aws_lb",
				"change": {
					"after": {"load_balancer_type": "application"},
					"after_unknown": {"security_groups": true},
				},
			},
		],
	}

	count(messages) == 0
}

test_network_load_balancer_does_not_exempt_group if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb.id", "aws_security_group.alb"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"type": "aws_security_group",
				"change": {
					"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]},
					"after_unknown": {"id": true},
				},
			},
			{
				"address": "aws_lb.public",
				"type": "aws_lb",
				"change": {
					"after": {"load_balancer_type": "network"},
					"after_unknown": {"security_groups": true},
				},
			},
		],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group.alb")
}

test_known_load_balancer_group_mismatch_does_not_exempt if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb.id", "aws_security_group.alb"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"type": "aws_security_group",
				"change": {"after": {"id": "sg-planned", "ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]}},
			},
			{
				"address": "aws_lb.public",
				"type": "aws_lb",
				"change": {"after": {
					"load_balancer_type": "application",
					"security_groups": ["sg-other"],
				}},
			},
		],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group.alb")
}

test_known_load_balancer_group_match_exempts if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb.id", "aws_security_group.alb"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"type": "aws_security_group",
				"change": {"after": {"id": "sg-planned", "ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]}},
			},
			{
				"address": "aws_lb.public",
				"type": "aws_lb",
				"change": {"after": {
					"load_balancer_type": "application",
					"security_groups": ["sg-planned"],
				}},
			},
		],
	}

	count(messages) == 0
}

test_unknown_legacy_rule_direction_with_open_ipv4_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "type": "aws_security_group"},
			{
				"address": "aws_security_group_rule.unknown_direction",
				"type": "aws_security_group_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.service"]}},
			},
		]}},
		"resource_changes": [{
			"address": "aws_security_group_rule.unknown_direction",
			"type": "aws_security_group_rule",
			"change": {
				"after": {"type": null, "cidr_blocks": ["0.0.0.0/0"], "ipv6_cidr_blocks": []},
				"after_unknown": {"type": true},
			},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group_rule.unknown_direction")
}
