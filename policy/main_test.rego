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
			{"address": "aws_s3_bucket.data", "mode": "managed", "type": "aws_s3_bucket"},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"mode": "managed", "type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": ["aws_s3_bucket.data.bucket", "aws_s3_bucket.data"]}},
			},
		]}},
		"resource_changes": [
			{"address": "aws_s3_bucket.data", "mode": "managed", "type": "aws_s3_bucket", "change": {"after": {"bucket": "planned-data"}}},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"mode": "managed", "type": "aws_s3_bucket_public_access_block",
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
			{"address": "aws_s3_bucket.data", "mode": "managed", "type": "aws_s3_bucket"},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"mode": "managed", "type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": ["aws_s3_bucket.data"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_s3_bucket.data[0]",
				"mode": "managed", "type": "aws_s3_bucket",
				"change": {"actions": ["create"], "after": {}},
			},
			{
				"address": "aws_s3_bucket_public_access_block.data[0]",
				"mode": "managed", "type": "aws_s3_bucket_public_access_block",
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
			{"address": "module.x.aws_s3_bucket.y", "mode": "managed", "type": "aws_s3_bucket"},
			{
				"address": "module.x.aws_s3_bucket_public_access_block.y",
				"mode": "managed", "type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": ["module.x.aws_s3_bucket.y"]}},
			},
		]}}}}},
		"resource_changes": [
			{"address": "module.x.aws_s3_bucket.y", "mode": "managed", "type": "aws_s3_bucket", "change": {"after": {}}},
			{
				"address": "module.x.aws_s3_bucket_public_access_block.y",
				"mode": "managed", "type": "aws_s3_bucket_public_access_block",
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
			{"address": "aws_s3_bucket.data", "mode": "managed", "type": "aws_s3_bucket"},
		]}},
		"resource_changes": [
			{"address": "aws_s3_bucket.data", "mode": "managed", "type": "aws_s3_bucket", "change": {"after": {}}},
		],
	}

	count(messages) == 1
	has_message(messages, "aws_s3_bucket.data")
}

test_bucket_with_false_public_access_flag_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_s3_bucket.data", "mode": "managed", "type": "aws_s3_bucket"},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"mode": "managed", "type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": ["aws_s3_bucket.data"]}},
			},
		]}},
		"resource_changes": [
			{"address": "aws_s3_bucket.data", "mode": "managed", "type": "aws_s3_bucket", "change": {"after": {"bucket": "planned-data"}}},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"mode": "managed", "type": "aws_s3_bucket_public_access_block",
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
			{"address": "aws_s3_bucket.data", "mode": "managed", "type": "aws_s3_bucket"},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"mode": "managed", "type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": ["aws_s3_bucket.data"]}},
			},
		]}},
		"resource_changes": [
			{"address": "aws_s3_bucket.data", "mode": "managed", "type": "aws_s3_bucket", "change": {"actions": ["no-op"], "after": {"bucket": "planned-data"}}},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"mode": "managed", "type": "aws_s3_bucket_public_access_block",
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
			{"address": "aws_s3_bucket.data", "mode": "managed", "type": "aws_s3_bucket"},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"mode": "managed", "type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": ["aws_s3_bucket.data"]}},
			},
		]}},
		"resource_changes": [
			{"address": "aws_s3_bucket.data", "mode": "managed", "type": "aws_s3_bucket", "change": {"actions": ["no-op"], "after": {}}},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"mode": "managed", "type": "aws_s3_bucket_public_access_block",
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
			{"address": "aws_s3_bucket.data", "mode": "managed", "type": "aws_s3_bucket"},
		]}},
		"resource_changes": [
			{"address": "aws_s3_bucket.data", "mode": "managed", "type": "aws_s3_bucket", "change": {"actions": ["delete"], "after": null}},
		],
	}

	count(messages) == 0
}

test_bucket_prefix_collision_denies_only_unprotected_bucket if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_s3_bucket.data", "mode": "managed", "type": "aws_s3_bucket"},
			{"address": "aws_s3_bucket.database", "mode": "managed", "type": "aws_s3_bucket"},
			{
				"address": "aws_s3_bucket_public_access_block.database",
				"mode": "managed", "type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": ["aws_s3_bucket.database", "aws_s3_bucket.database.id"]}},
			},
		]}},
		"resource_changes": [
			{"address": "aws_s3_bucket.data", "mode": "managed", "type": "aws_s3_bucket", "change": {"after": {"bucket": "planned-data"}}},
			{"address": "aws_s3_bucket.database", "mode": "managed", "type": "aws_s3_bucket", "change": {"after": {"bucket": "planned-database"}}},
			{
				"address": "aws_s3_bucket_public_access_block.database",
				"mode": "managed", "type": "aws_s3_bucket_public_access_block",
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
			{"address": "aws_s3_bucket.data", "mode": "managed", "type": "aws_s3_bucket"},
			{"address": "aws_s3_bucket.logs", "mode": "managed", "type": "aws_s3_bucket"},
			{
				"address": "aws_s3_bucket_public_access_block.shared",
				"mode": "managed", "type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": [
					"aws_s3_bucket.data",
					"aws_s3_bucket.data.id",
					"aws_s3_bucket.logs",
					"aws_s3_bucket.logs.id",
				]}},
			},
		]}},
		"resource_changes": [
			{"address": "aws_s3_bucket.data", "mode": "managed", "type": "aws_s3_bucket", "change": {"after": {}}},
			{"address": "aws_s3_bucket.logs", "mode": "managed", "type": "aws_s3_bucket", "change": {"after": {}}},
			{
				"address": "aws_s3_bucket_public_access_block.shared",
				"mode": "managed", "type": "aws_s3_bucket_public_access_block",
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
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb", "aws_security_group.alb.id"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"mode": "managed", "type": "aws_security_group",
				"change": {"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"], "ipv6_cidr_blocks": []}]}, "after_unknown": {"id": true}},
			},
			{"address": "aws_lb.public", "mode": "managed", "type": "aws_lb", "change": {"after": {"load_balancer_type": "application"}, "after_unknown": {"security_groups": true}}},
		],
	}

	count(messages) == 0
}

test_open_group_named_alb_without_load_balancer_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
		]}},
		"resource_changes": [{
			"address": "aws_security_group.alb",
			"mode": "managed", "type": "aws_security_group",
			"change": {"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]}},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group.alb")
}

test_open_group_referenced_only_by_unplanned_load_balancer_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.zero_lb", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.none",
				"mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.zero_lb"]}},
			},
		]}},
		"resource_changes": [{
			"address": "aws_security_group.zero_lb",
			"mode": "managed", "type": "aws_security_group",
			"change": {"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]}},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group.zero_lb")
}

test_open_group_referenced_by_deleted_load_balancer_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"mode": "managed", "type": "aws_security_group",
				"change": {"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]}},
			},
			{"address": "aws_lb.public", "mode": "managed", "type": "aws_lb", "change": {"actions": ["delete"], "after": null}},
		],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group.alb")
}

test_open_modern_ingress_rule_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_vpc_security_group_ingress_rule.open",
				"mode": "managed", "type": "aws_vpc_security_group_ingress_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.service", "aws_security_group.service.id"]}},
			},
		]}},
		"resource_changes": [{
			"address": "aws_vpc_security_group_ingress_rule.open",
			"mode": "managed", "type": "aws_vpc_security_group_ingress_rule",
			"change": {"after": {"cidr_ipv4": "0.0.0.0/0", "cidr_ipv6": null}},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_vpc_security_group_ingress_rule.open")
}

test_open_ipv6_modern_ingress_rule_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_vpc_security_group_ingress_rule.open_ipv6",
				"mode": "managed", "type": "aws_vpc_security_group_ingress_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.service"]}},
			},
		]}},
		"resource_changes": [{
			"address": "aws_vpc_security_group_ingress_rule.open_ipv6",
			"mode": "managed", "type": "aws_vpc_security_group_ingress_rule",
			"change": {"after": {"cidr_ipv4": null, "cidr_ipv6": "::/0"}},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_vpc_security_group_ingress_rule.open_ipv6")
}

test_open_modern_rule_attached_to_planned_alb_group_passes if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb"]}},
			},
			{
				"address": "aws_vpc_security_group_ingress_rule.http",
				"mode": "managed", "type": "aws_vpc_security_group_ingress_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.alb", "aws_security_group.alb.id"]}},
			},
		]}},
		"resource_changes": [
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group", "change": {"after": {"id": "sg-alb", "ingress": []}}},
			{"address": "aws_lb.public", "mode": "managed", "type": "aws_lb", "change": {"after": {"load_balancer_type": "application", "security_groups": ["sg-alb"]}}},
			{
				"address": "aws_vpc_security_group_ingress_rule.http",
				"mode": "managed", "type": "aws_vpc_security_group_ingress_rule",
				"change": {"after": {"security_group_id": "sg-alb", "cidr_ipv4": "0.0.0.0/0", "cidr_ipv6": null}},
			},
		],
	}

	count(messages) == 0
}

test_open_legacy_ingress_rule_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_security_group_rule.legacy_open",
				"mode": "managed", "type": "aws_security_group_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.service"]}},
			},
		]}},
		"resource_changes": [{
			"address": "aws_security_group_rule.legacy_open",
			"mode": "managed", "type": "aws_security_group_rule",
			"change": {"after": {"type": "ingress", "cidr_blocks": ["0.0.0.0/0"], "ipv6_cidr_blocks": []}},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group_rule.legacy_open")
}

test_open_ipv6_legacy_ingress_rule_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_security_group_rule.legacy_open_ipv6",
				"mode": "managed", "type": "aws_security_group_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.service"]}},
			},
		]}},
		"resource_changes": [{
			"address": "aws_security_group_rule.legacy_open_ipv6",
			"mode": "managed", "type": "aws_security_group_rule",
			"change": {"after": {"type": "ingress", "cidr_blocks": [], "ipv6_cidr_blocks": ["::/0"]}},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group_rule.legacy_open_ipv6")
}

test_unknown_cidr_on_legacy_ingress_rule_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_security_group_rule.legacy_unknown",
				"mode": "managed", "type": "aws_security_group_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.service"]}},
			},
		]}},
		"resource_changes": [{
			"address": "aws_security_group_rule.legacy_unknown",
			"mode": "managed", "type": "aws_security_group_rule",
			"change": {
				"after": {"type": "ingress", "cidr_blocks": null, "ipv6_cidr_blocks": []},
				"after_unknown": {"cidr_blocks": true},
			},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group_rule.legacy_unknown")
}

test_unknown_cidr_list_leaf_on_legacy_ingress_rule_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_security_group_rule.legacy_unknown_leaf",
				"mode": "managed", "type": "aws_security_group_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.service"]}},
			},
		]}},
		"resource_changes": [{
			"address": "aws_security_group_rule.legacy_unknown_leaf",
			"mode": "managed", "type": "aws_security_group_rule",
			"change": {
				"after": {"type": "ingress", "cidr_blocks": [], "ipv6_cidr_blocks": []},
				"after_unknown": {"cidr_blocks": [true]},
			},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group_rule.legacy_unknown_leaf")
}

test_default_security_group_with_open_ingress_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": []}},
		"resource_changes": [{
			"address": "aws_default_security_group.default",
			"mode": "managed", "type": "aws_default_security_group",
			"change": {"after": {"ingress": [{"ipv6_cidr_blocks": ["::/0"]}]}},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_default_security_group.default")
}

test_unknown_inline_cidr_on_non_alb_group_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "mode": "managed", "type": "aws_security_group"},
		]}},
		"resource_changes": [{
			"address": "aws_security_group.service",
			"mode": "managed", "type": "aws_security_group",
			"change": {
				"after": {"ingress": [{"cidr_blocks": [], "ipv6_cidr_blocks": []}]},
				"after_unknown": {"ingress": [{"cidr_blocks": true}]},
			},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group.service")
}

test_unknown_inline_cidr_list_leaf_on_non_alb_group_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "mode": "managed", "type": "aws_security_group"},
		]}},
		"resource_changes": [{
			"address": "aws_security_group.service",
			"mode": "managed", "type": "aws_security_group",
			"change": {
				"after": {"ingress": [{"cidr_blocks": [], "ipv6_cidr_blocks": []}]},
				"after_unknown": {"ingress": [{"cidr_blocks": [true]}]},
			},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group.service")
}

test_false_inline_cidr_list_leaf_with_private_cidr_passes if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "mode": "managed", "type": "aws_security_group"},
		]}},
		"resource_changes": [{
			"address": "aws_security_group.service",
			"mode": "managed", "type": "aws_security_group",
			"change": {
				"after": {"ingress": [{"cidr_blocks": ["10.0.0.0/8"], "ipv6_cidr_blocks": []}]},
				"after_unknown": {"ingress": [{"cidr_blocks": [false]}]},
			},
		}],
	}

	count(messages) == 0
}

test_unknown_cidr_on_modern_rule_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_vpc_security_group_ingress_rule.unknown",
				"mode": "managed", "type": "aws_vpc_security_group_ingress_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.service"]}},
			},
		]}},
		"resource_changes": [{
			"address": "aws_vpc_security_group_ingress_rule.unknown",
			"mode": "managed", "type": "aws_vpc_security_group_ingress_rule",
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
			{"address": "aws_s3_bucket.data", "mode": "managed", "type": "aws_s3_bucket"},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"mode": "managed", "type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": ["aws_s3_bucket.data.bucket", "aws_s3_bucket.data"]}},
			},
		]}},
		"resource_changes": [
			{"address": address, "mode": "managed", "type": "aws_s3_bucket", "change": {"after": {"bucket": "planned-data-a"}}},
			{
				"address": "aws_s3_bucket_public_access_block.data[\"a\"]",
				"mode": "managed", "type": "aws_s3_bucket_public_access_block",
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
			{"address": "aws_s3_bucket.data", "mode": "managed", "type": "aws_s3_bucket"},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"mode": "managed", "type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": ["aws_s3_bucket.data.id", "aws_s3_bucket.data"]}},
			},
		]}},
		"resource_changes": [
			{"address": "aws_s3_bucket.data", "mode": "managed", "type": "aws_s3_bucket", "change": {"after": {"bucket": "planned-data"}}},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"mode": "managed", "type": "aws_s3_bucket_public_access_block",
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
			{"address": "aws_s3_bucket.data", "mode": "managed", "type": "aws_s3_bucket"},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"mode": "managed", "type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": ["aws_s3_bucket.data.id", "aws_s3_bucket.data"]}},
			},
		]}},
		"resource_changes": [
			{"address": "aws_s3_bucket.data", "mode": "managed", "type": "aws_s3_bucket", "change": {"after": {"bucket": "planned-data"}}},
			{
				"address": "aws_s3_bucket_public_access_block.data",
				"mode": "managed", "type": "aws_s3_bucket_public_access_block",
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
			{"address": "aws_s3_bucket.data", "mode": "managed", "type": "aws_s3_bucket"},
			{
				"address": "aws_s3_bucket_public_access_block.first",
				"mode": "managed", "type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": ["aws_s3_bucket.data.bucket", "aws_s3_bucket.data"]}},
			},
			{
				"address": "aws_s3_bucket_public_access_block.second",
				"mode": "managed", "type": "aws_s3_bucket_public_access_block",
				"expressions": {"bucket": {"references": ["aws_s3_bucket.data.bucket", "aws_s3_bucket.data"]}},
			},
		]}},
		"resource_changes": array.concat(
			[{"address": "aws_s3_bucket.data", "mode": "managed", "type": "aws_s3_bucket", "change": {"after": {"bucket": "planned-data"}}}],
			[{
				"address": sprintf("aws_s3_bucket_public_access_block.%s", [name]),
				"mode": "managed", "type": "aws_s3_bucket_public_access_block",
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
			{"address": "aws_security_group.first", "mode": "managed", "type": "aws_security_group"},
			{"address": "aws_security_group.second", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
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
				"mode": "managed", "type": "aws_security_group",
				"change": {
					"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]},
					"after_unknown": {"id": true},
				},
			} |
				some name in ["first", "second"]
			],
			[{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
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
				{"address": "module.child.aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
				{
					"address": "module.child.aws_lb.public",
					"mode": "managed", "type": "aws_lb",
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
				"mode": "managed", "type": "aws_security_group",
				"change": {
					"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]},
					"after_unknown": {"id": true},
				},
			},
			{
				"address": "module.child.aws_lb.public",
				"mode": "managed", "type": "aws_lb",
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
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb.id", "aws_security_group.alb"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"mode": "managed", "type": "aws_security_group",
				"change": {
					"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]},
					"after_unknown": {"id": true},
				},
			},
			{
				"address": "aws_lb.public[0]",
				"mode": "managed", "type": "aws_lb",
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
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb.id", "aws_security_group.alb"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"mode": "managed", "type": "aws_security_group",
				"change": {
					"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]},
					"after_unknown": {"id": true},
				},
			},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
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

test_unknown_load_balancer_type_does_not_exempt_group if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"mode": "managed", "type": "aws_security_group",
				"change": {
					"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]},
					"after_unknown": {"id": true},
				},
			},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"change": {
					"after": {},
					"after_unknown": {"load_balancer_type": true, "security_groups": true},
				},
			},
		],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group.alb")
}

test_missing_load_balancer_type_does_not_exempt_group if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"mode": "managed", "type": "aws_security_group",
				"change": {
					"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]},
					"after_unknown": {"id": true},
				},
			},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"change": {"after": {}, "after_unknown": {"security_groups": true}},
			},
		],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group.alb")
}

test_known_load_balancer_group_mismatch_does_not_exempt if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb.id", "aws_security_group.alb"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"mode": "managed", "type": "aws_security_group",
				"change": {"after": {"id": "sg-planned", "ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]}},
			},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
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
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb.id", "aws_security_group.alb"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"mode": "managed", "type": "aws_security_group",
				"change": {"after": {"id": "sg-planned", "ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]}},
			},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
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
			{"address": "aws_security_group.service", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_security_group_rule.unknown_direction",
				"mode": "managed", "type": "aws_security_group_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.service"]}},
			},
		]}},
		"resource_changes": [{
			"address": "aws_security_group_rule.unknown_direction",
			"mode": "managed", "type": "aws_security_group_rule",
			"change": {
				"after": {"type": null, "cidr_blocks": ["0.0.0.0/0"], "ipv6_cidr_blocks": []},
				"after_unknown": {"type": true},
			},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group_rule.unknown_direction")
}

test_conditional_rule_known_literal_with_unknown_alb_group_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb"]}},
			},
			{
				"address": "aws_vpc_security_group_ingress_rule.http",
				"mode": "managed", "type": "aws_vpc_security_group_ingress_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.alb.id", "aws_security_group.alb"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"mode": "managed", "type": "aws_security_group",
				"change": {"after": {"ingress": []}, "after_unknown": {"id": true}},
			},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"change": {"after": {"load_balancer_type": "application"}, "after_unknown": {"security_groups": true}},
			},
			{
				"address": "aws_vpc_security_group_ingress_rule.http",
				"mode": "managed", "type": "aws_vpc_security_group_ingress_rule",
				"change": {"after": {"security_group_id": "sg-literal", "cidr_ipv4": "0.0.0.0/0"}},
			},
		],
	}

	count(messages) == 1
	has_message(messages, "aws_vpc_security_group_ingress_rule.http")
}

test_known_legacy_rule_target_mismatch_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb"]}},
			},
			{
				"address": "aws_security_group_rule.http",
				"mode": "managed", "type": "aws_security_group_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.alb"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"mode": "managed", "type": "aws_security_group",
				"change": {"after": {"id": "sg-alb", "ingress": []}},
			},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"change": {"after": {"load_balancer_type": "application", "security_groups": ["sg-alb"]}},
			},
			{
				"address": "aws_security_group_rule.http",
				"mode": "managed", "type": "aws_security_group_rule",
				"change": {"after": {"security_group_id": "sg-other", "type": "ingress", "cidr_blocks": ["0.0.0.0/0"]}},
			},
		],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group_rule.http")
}

test_fresh_create_rule_and_single_alb_group_both_unknown_passes if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb", "aws_security_group.alb.id"]}},
			},
			{
				"address": "aws_vpc_security_group_ingress_rule.http",
				"mode": "managed", "type": "aws_vpc_security_group_ingress_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.alb", "aws_security_group.alb.id"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"mode": "managed", "type": "aws_security_group",
				"change": {"after": {"ingress": []}, "after_unknown": {"id": true}},
			},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"change": {"after": {"load_balancer_type": "application"}, "after_unknown": {"security_groups": true}},
			},
			{
				"address": "aws_vpc_security_group_ingress_rule.http",
				"mode": "managed", "type": "aws_vpc_security_group_ingress_rule",
				"change": {
					"after": {"security_group_id": null, "cidr_ipv4": "0.0.0.0/0"},
					"after_unknown": {"security_group_id": true},
				},
			},
		],
	}

	count(messages) == 0
}

test_known_equal_legacy_rule_and_alb_group_ids_passes if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb"]}},
			},
			{
				"address": "aws_security_group_rule.http",
				"mode": "managed", "type": "aws_security_group_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.alb"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"mode": "managed", "type": "aws_security_group",
				"change": {"after": {"id": "sg-alb", "ingress": []}},
			},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"change": {"after": {"load_balancer_type": "application", "security_groups": ["sg-alb"]}},
			},
			{
				"address": "aws_security_group_rule.http",
				"mode": "managed", "type": "aws_security_group_rule",
				"change": {"after": {"security_group_id": "sg-alb", "type": "ingress", "cidr_blocks": ["0.0.0.0/0"]}},
			},
		],
	}

	count(messages) == 0
}

test_data_source_bucket_without_public_access_block_passes if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "data.aws_s3_bucket.external", "mode": "data", "type": "aws_s3_bucket"},
		]}},
		"resource_changes": [
			{
				"address": "data.aws_s3_bucket.external",
				"mode": "data", "type": "aws_s3_bucket",
				"change": {"after": {"bucket": "external"}},
			},
		],
	}

	count(messages) == 0
}

test_data_source_load_balancer_does_not_exempt_managed_group if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "data.aws_lb.public",
				"mode": "data", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.service"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.service",
				"mode": "managed", "type": "aws_security_group",
				"change": {
					"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]},
					"after_unknown": {"id": true},
				},
			},
			{
				"address": "data.aws_lb.public",
				"mode": "data", "type": "aws_lb",
				"change": {"after": {"load_balancer_type": "application"}, "after_unknown": {"security_groups": true}},
			},
		],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group.service")
}

test_unknown_load_balancer_attachment_with_condition_reference_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": [
					"var.x",
					"aws_security_group.alb",
					"aws_security_group.alb.id",
				]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"mode": "managed", "type": "aws_security_group",
				"change": {
					"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]},
					"after_unknown": {"id": true},
				},
			},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"change": {
					"after": {"load_balancer_type": "application"},
					"after_unknown": {"security_groups": true},
				},
			},
		],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group.alb")
}

test_unknown_rule_target_with_condition_reference_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb", "aws_security_group.alb.id"]}},
			},
			{
				"address": "aws_vpc_security_group_ingress_rule.http",
				"mode": "managed", "type": "aws_vpc_security_group_ingress_rule",
				"expressions": {"security_group_id": {"references": [
					"var.x",
					"aws_security_group.alb",
					"aws_security_group.alb.id",
				]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"mode": "managed", "type": "aws_security_group",
				"change": {"after": {"ingress": []}, "after_unknown": {"id": true}},
			},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"change": {"after": {"load_balancer_type": "application"}, "after_unknown": {"security_groups": true}},
			},
			{
				"address": "aws_vpc_security_group_ingress_rule.http",
				"mode": "managed", "type": "aws_vpc_security_group_ingress_rule",
				"change": {
					"after": {"security_group_id": null, "cidr_ipv4": "0.0.0.0/0"},
					"after_unknown": {"security_group_id": true},
				},
			},
		],
	}

	count(messages) == 1
	has_message(messages, "aws_vpc_security_group_ingress_rule.http")
}

test_inline_prefix_list_ingress_on_non_alb_group_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "mode": "managed", "type": "aws_security_group"},
		]}},
		"resource_changes": [{
			"address": "aws_security_group.service",
			"mode": "managed", "type": "aws_security_group",
			"change": {"after": {"ingress": [{
				"cidr_blocks": [],
				"ipv6_cidr_blocks": [],
				"prefix_list_ids": ["pl-open"],
			}]}},
		}],
	}

	count(messages) == 1
	"aws_security_group.service: non-ALB security group prefix-list ingress cannot be proven safe by this gate" in messages
}

test_inline_prefix_list_ingress_on_planned_alb_group_passes if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb", "aws_security_group.alb.id"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"mode": "managed", "type": "aws_security_group",
				"change": {"after": {"id": "sg-alb", "ingress": [{
					"cidr_blocks": [],
					"ipv6_cidr_blocks": [],
					"prefix_list_ids": ["pl-open"],
				}]}},
			},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"change": {"after": {"load_balancer_type": "application", "security_groups": ["sg-alb"]}},
			},
		],
	}

	count(messages) == 0
}

test_modern_prefix_list_ingress_on_non_alb_group_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_vpc_security_group_ingress_rule.prefix",
				"mode": "managed", "type": "aws_vpc_security_group_ingress_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.service"]}},
			},
		]}},
		"resource_changes": [{
			"address": "aws_vpc_security_group_ingress_rule.prefix",
			"mode": "managed", "type": "aws_vpc_security_group_ingress_rule",
			"change": {"after": {
				"security_group_id": "sg-service",
				"cidr_ipv4": null,
				"cidr_ipv6": null,
				"prefix_list_id": "pl-open",
			}},
		}],
	}

	count(messages) == 1
	"aws_vpc_security_group_ingress_rule.prefix: non-ALB ingress rule prefix-list ingress cannot be proven safe by this gate" in messages
}

test_legacy_prefix_list_ingress_on_non_alb_group_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_security_group_rule.prefix",
				"mode": "managed", "type": "aws_security_group_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.service"]}},
			},
		]}},
		"resource_changes": [{
			"address": "aws_security_group_rule.prefix",
			"mode": "managed", "type": "aws_security_group_rule",
			"change": {"after": {
				"security_group_id": "sg-service",
				"type": "ingress",
				"cidr_blocks": [],
				"ipv6_cidr_blocks": [],
				"prefix_list_ids": ["pl-open"],
			}},
		}],
	}

	count(messages) == 1
	"aws_security_group_rule.prefix: non-ALB legacy ingress rule prefix-list ingress cannot be proven safe by this gate" in messages
}

test_unknown_inline_prefix_list_ingress_on_non_alb_group_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "mode": "managed", "type": "aws_security_group"},
		]}},
		"resource_changes": [{
			"address": "aws_security_group.service",
			"mode": "managed", "type": "aws_security_group",
			"change": {
				"after": {"ingress": [{
					"cidr_blocks": [],
					"ipv6_cidr_blocks": [],
					"prefix_list_ids": [],
				}]},
				"after_unknown": {"ingress": [{"prefix_list_ids": [true]}]},
			},
		}],
	}

	count(messages) == 1
	"aws_security_group.service: non-ALB security group prefix-list ingress cannot be proven safe by this gate" in messages
}

test_empty_inline_prefix_list_with_private_cidr_passes if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "mode": "managed", "type": "aws_security_group"},
		]}},
		"resource_changes": [{
			"address": "aws_security_group.service",
			"mode": "managed", "type": "aws_security_group",
			"change": {"after": {"ingress": [{
				"cidr_blocks": ["10.0.0.0/8"],
				"ipv6_cidr_blocks": [],
				"prefix_list_ids": [],
			}]}},
		}],
	}

	count(messages) == 0
}

test_indexed_rule_attached_to_planned_alb_group_passes if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb", "aws_security_group.alb.id"]}},
			},
			{
				"address": "aws_vpc_security_group_ingress_rule.http",
				"mode": "managed", "type": "aws_vpc_security_group_ingress_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.alb", "aws_security_group.alb.id"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"mode": "managed", "type": "aws_security_group",
				"change": {"after": {"id": "sg-alb", "ingress": []}},
			},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"change": {"after": {"load_balancer_type": "application", "security_groups": ["sg-alb"]}},
			},
			{
				"address": "aws_vpc_security_group_ingress_rule.http[0]",
				"mode": "managed", "type": "aws_vpc_security_group_ingress_rule",
				"change": {"after": {"security_group_id": "sg-alb", "cidr_ipv4": "0.0.0.0/0"}},
			},
		],
	}

	count(messages) == 0
}

test_indexed_rule_on_non_alb_group_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_vpc_security_group_ingress_rule.http",
				"mode": "managed", "type": "aws_vpc_security_group_ingress_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.service"]}},
			},
		]}},
		"resource_changes": [{
			"address": "aws_vpc_security_group_ingress_rule.http[0]",
			"mode": "managed", "type": "aws_vpc_security_group_ingress_rule",
			"change": {"after": {"security_group_id": "sg-service", "cidr_ipv4": "0.0.0.0/0"}},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_vpc_security_group_ingress_rule.http[0]")
}

test_unknown_prefix_list_id_on_modern_rule_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_vpc_security_group_ingress_rule.unknown_prefix",
				"mode": "managed", "type": "aws_vpc_security_group_ingress_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.service"]}},
			},
		]}},
		"resource_changes": [{
			"address": "aws_vpc_security_group_ingress_rule.unknown_prefix",
			"mode": "managed", "type": "aws_vpc_security_group_ingress_rule",
			"change": {
				"after": {"cidr_ipv4": null, "cidr_ipv6": null, "prefix_list_id": null},
				"after_unknown": {"prefix_list_id": true},
			},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_vpc_security_group_ingress_rule.unknown_prefix")
}

test_unknown_prefix_list_ids_on_legacy_rule_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_security_group_rule.unknown_prefix",
				"mode": "managed", "type": "aws_security_group_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.service"]}},
			},
		]}},
		"resource_changes": [{
			"address": "aws_security_group_rule.unknown_prefix",
			"mode": "managed", "type": "aws_security_group_rule",
			"change": {
				"after": {"type": "ingress", "cidr_blocks": [], "ipv6_cidr_blocks": [], "prefix_list_ids": null},
				"after_unknown": {"prefix_list_ids": true},
			},
		}],
	}

	count(messages) == 1
	has_message(messages, "aws_security_group_rule.unknown_prefix")
}

test_alb_group_shared_with_ecs_service_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb", "aws_security_group.alb.id"]}},
			},
			{
				"address": "aws_ecs_service.api",
				"mode": "managed", "type": "aws_ecs_service",
				"expressions": {"network_configuration": [{
					"security_groups": {"references": ["aws_security_group.alb.id", "aws_security_group.alb"]},
				}]},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"mode": "managed", "type": "aws_security_group",
				"change": {
					"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]},
					"after_unknown": {"id": true},
				},
			},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"change": {
					"after": {"load_balancer_type": "application"},
					"after_unknown": {"security_groups": true},
				},
			},
		],
	}

	count(messages) == 1
	"aws_security_group.alb: ALB group is shared with a non-load-balancer consumer" in messages
}

test_alb_group_passed_to_module_call_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {
			"resources": [
				{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
				{
					"address": "aws_lb.public",
					"mode": "managed", "type": "aws_lb",
					"expressions": {"security_groups": {"references": ["aws_security_group.alb", "aws_security_group.alb.id"]}},
				},
			],
			"module_calls": {"api": {"expressions": {
				"security_group_ids": {"references": ["aws_security_group.alb.id", "aws_security_group.alb"]},
			}}},
		}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"mode": "managed", "type": "aws_security_group",
				"change": {
					"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]},
					"after_unknown": {"id": true},
				},
			},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"change": {
					"after": {"load_balancer_type": "application"},
					"after_unknown": {"security_groups": true},
				},
			},
		],
	}

	count(messages) == 1
	"aws_security_group.alb: ALB group is shared with a non-load-balancer consumer" in messages
}

test_alb_group_referenced_only_by_rule_definitions_passes if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb", "aws_security_group.alb.id"]}},
			},
			{
				"address": "aws_security_group_rule.http",
				"mode": "managed", "type": "aws_security_group_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.alb.id", "aws_security_group.alb"]}},
			},
			{
				"address": "aws_vpc_security_group_ingress_rule.https",
				"mode": "managed", "type": "aws_vpc_security_group_ingress_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.alb.id", "aws_security_group.alb"]}},
			},
			{
				"address": "aws_vpc_security_group_egress_rule.all",
				"mode": "managed", "type": "aws_vpc_security_group_egress_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.alb.id", "aws_security_group.alb"]}},
			},
			{
				"address": "aws_security_group.backend",
				"mode": "managed", "type": "aws_security_group",
				"expressions": {"ingress": [{
					"security_groups": {"references": ["aws_security_group.alb.id", "aws_security_group.alb"]},
				}]},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"mode": "managed", "type": "aws_security_group",
				"change": {
					"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]},
					"after_unknown": {"id": true},
				},
			},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"change": {
					"after": {"load_balancer_type": "application"},
					"after_unknown": {"security_groups": true},
				},
			},
		],
	}

	count(messages) == 0
}

test_alb_group_referenced_as_egress_source_passes if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb", "aws_security_group.alb.id"]}},
			},
			{
				"address": "aws_security_group_rule.http",
				"mode": "managed", "type": "aws_security_group_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.alb.id", "aws_security_group.alb"]}},
			},
			{
				"address": "aws_vpc_security_group_ingress_rule.https",
				"mode": "managed", "type": "aws_vpc_security_group_ingress_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.alb.id", "aws_security_group.alb"]}},
			},
			{
				"address": "aws_vpc_security_group_egress_rule.all",
				"mode": "managed", "type": "aws_vpc_security_group_egress_rule",
				"expressions": {"security_group_id": {"references": ["aws_security_group.alb.id", "aws_security_group.alb"]}},
			},
			{
				"address": "aws_security_group.backend",
				"mode": "managed", "type": "aws_security_group",
				"expressions": {"egress": [{
					"security_groups": {"references": ["aws_security_group.alb.id", "aws_security_group.alb"]},
				}]},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb",
				"mode": "managed", "type": "aws_security_group",
				"change": {
					"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]},
					"after_unknown": {"id": true},
				},
			},
			{
				"address": "aws_lb.public",
				"mode": "managed", "type": "aws_lb",
				"change": {
					"after": {"load_balancer_type": "application"},
					"after_unknown": {"security_groups": true},
				},
			},
		],
	}

	count(messages) == 0
}

test_forgotten_bucket_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": []}},
		"resource_changes": [{
			"address": "aws_s3_bucket.data",
			"mode": "managed", "type": "aws_s3_bucket",
			"change": {"actions": ["forget"], "after": null},
		}],
	}

	count(messages) == 1
	"aws_s3_bucket.data: forgotten resource protections cannot be verified" in messages
}

test_forgotten_public_access_block_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": []}},
		"resource_changes": [{
			"address": "aws_s3_bucket_public_access_block.data",
			"mode": "managed", "type": "aws_s3_bucket_public_access_block",
			"change": {"actions": ["forget"], "after": null},
		}],
	}

	count(messages) == 1
	"aws_s3_bucket_public_access_block.data: forgotten resource protections cannot be verified" in messages
}

test_forgotten_security_group_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": []}},
		"resource_changes": [{
			"address": "aws_security_group.service",
			"mode": "managed", "type": "aws_security_group",
			"change": {"actions": ["forget"], "after": null},
		}],
	}

	count(messages) == 1
	"aws_security_group.service: forgotten resource protections cannot be verified" in messages
}

test_alb_group_also_attached_to_network_load_balancer_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.public", "mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb", "aws_security_group.alb.id"]}},
			},
			{
				"address": "aws_lb.network", "mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb", "aws_security_group.alb.id"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group",
				"change": {"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]}, "after_unknown": {"id": true}},
			},
			{
				"address": "aws_lb.public", "mode": "managed", "type": "aws_lb",
				"change": {"after": {"load_balancer_type": "application"}, "after_unknown": {"security_groups": true}},
			},
			{
				"address": "aws_lb.network", "mode": "managed", "type": "aws_lb",
				"change": {"after": {"load_balancer_type": "network"}, "after_unknown": {"security_groups": true}},
			},
		],
	}

	count(messages) == 1
	"aws_security_group.alb: ALB group is shared with a non-load-balancer consumer" in messages
}

test_alb_group_also_referenced_by_unknown_type_load_balancer_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.public", "mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb", "aws_security_group.alb.id"]}},
			},
			{
				"address": "aws_lb.unknown", "mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb", "aws_security_group.alb.id"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group",
				"change": {"after": {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]}, "after_unknown": {"id": true}},
			},
			{
				"address": "aws_lb.public", "mode": "managed", "type": "aws_lb",
				"change": {"after": {"load_balancer_type": "application"}, "after_unknown": {"security_groups": true}},
			},
			{
				"address": "aws_lb.unknown", "mode": "managed", "type": "aws_lb",
				"change": {
					"after": {"load_balancer_type": null},
					"after_unknown": {"load_balancer_type": true, "security_groups": true},
				},
			},
		],
	}

	count(messages) == 1
	"aws_security_group.alb: ALB group is shared with a non-load-balancer consumer" in messages
}

test_known_alb_group_consumed_by_child_module_ecs_planned_value_denies if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.public", "mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb", "aws_security_group.alb.id"]}},
			},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group",
				"change": {"after": {"id": "sg-alb", "ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]}},
			},
			{
				"address": "aws_lb.public", "mode": "managed", "type": "aws_lb",
				"change": {"after": {"load_balancer_type": "application", "security_groups": ["sg-alb"]}},
			},
			{
				"address": "module.api.aws_ecs_service.this", "mode": "managed", "type": "aws_ecs_service",
				"change": {"after": {"network_configuration": [{"security_groups": ["sg-alb"]}]}},
			},
		],
	}

	count(messages) == 1
	"aws_security_group.alb: ALB group is attached to a non-load-balancer resource by planned value" in messages
}

test_known_alb_group_planned_ingress_source_reference_passes if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
			{
				"address": "aws_lb.public", "mode": "managed", "type": "aws_lb",
				"expressions": {"security_groups": {"references": ["aws_security_group.alb", "aws_security_group.alb.id"]}},
			},
			{"address": "aws_security_group.backend", "mode": "managed", "type": "aws_security_group"},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group",
				"change": {"after": {"id": "sg-alb", "ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]}},
			},
			{
				"address": "aws_lb.public", "mode": "managed", "type": "aws_lb",
				"change": {"after": {"load_balancer_type": "application", "security_groups": ["sg-alb"]}},
			},
			{
				"address": "aws_security_group.backend", "mode": "managed", "type": "aws_security_group",
				"change": {"after": {"ingress": [{"security_groups": ["sg-alb"]}]}},
			},
		],
	}

	count(messages) == 0
}

test_fresh_create_alb_group_local_indirection_residual_passes if {
	messages := deny with input as {
		"configuration": {"root_module": {
			"resources": [
				{"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group"},
				{
					"address": "aws_lb.public", "mode": "managed", "type": "aws_lb",
					"expressions": {"security_groups": {"references": ["aws_security_group.alb", "aws_security_group.alb.id"]}},
				},
			],
			"module_calls": {"api": {"expressions": {
				"security_group_ids": {"references": ["local.x"]},
			}}},
		}},
		"resource_changes": [
			{
				"address": "aws_security_group.alb", "mode": "managed", "type": "aws_security_group",
				"change": {
					"after": {"id": null, "ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]},
					"after_unknown": {"id": true},
				},
			},
			{
				"address": "aws_lb.public", "mode": "managed", "type": "aws_lb",
				"change": {"after": {"load_balancer_type": "application"}, "after_unknown": {"security_groups": true}},
			},
			{
				"address": "module.api.aws_ecs_service.this", "mode": "managed", "type": "aws_ecs_service",
				"change": {
					"after": {"network_configuration": [{"security_groups": [null]}]},
					"after_unknown": {"network_configuration": [{"security_groups": [true]}]},
				},
			},
		],
	}

	count(messages) == 0
}

test_known_non_alb_group_planned_value_consumer_keeps_default_deny if {
	messages := deny with input as {
		"configuration": {"root_module": {"resources": [
			{"address": "aws_security_group.service", "mode": "managed", "type": "aws_security_group"},
		]}},
		"resource_changes": [
			{
				"address": "aws_security_group.service", "mode": "managed", "type": "aws_security_group",
				"change": {"after": {"id": "sg-service", "ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]}},
			},
			{
				"address": "module.api.aws_ecs_service.this", "mode": "managed", "type": "aws_ecs_service",
				"change": {"after": {"network_configuration": [{"security_groups": ["sg-service"]}]}},
			},
		],
	}

	count(messages) == 1
	"aws_security_group.service: non-ALB security group has IPv4 ingress open to 0.0.0.0/0" in messages
}
