# This policy evaluates root-module resources only where Terraform configuration
# correlation is required. S3 protection requires one block with a whole-resource
# reference plus equal, known planned bucket names; use `.bucket` so Terraform can
# plan that value. An ALB exemption requires exactly one distinct security-group
# reference and a planned root ALB instance; known attachment and rule target IDs
# must match the group's known planned ID. Fresh creates are exempt only when the
# group, ALB attachment, and rule target are all unknown through exact whole-resource
# and `.id` references, and no managed non-load-balancer resource or root module
# call may consume the group. Prefix-list ingress fails closed outside this exemption;
# unknown legacy-rule direction is potentially ingress. Planned no-op resources are evaluated because sibling resources can be deleted
# or weakened independently. Data-source reads are excluded from every selector.
package main

root_resources := [resource |
	some resource in object.get(
		object.get(object.get(input, "configuration", {}), "root_module", {}),
		"resources",
		[],
	)
	resource.mode == "managed"
]

resource_changes := [resource_change |
	some resource_change in object.get(input, "resource_changes", [])
	resource_change.mode == "managed"
]

valid_plan_document if {
	is_array(input.resource_changes)
	input.configuration.root_module != null
}

deny contains msg if {
	not valid_plan_document

	msg := "input is not a terraform show -json plan document"
}

planned(resource_change) if {
	resource_change.change.after != null
}

has_unknown_leaf(x) if {
	x == true
}

has_unknown_leaf(x) if {
	walk(x, [path, value])
	count(path) > 0
	value == true
}

referenced_bucket_addresses(block) := addresses if {
	addresses := {address |
		some bucket in root_resources
		bucket.type == "aws_s3_bucket"

		references := object.get(
			object.get(object.get(block, "expressions", {}), "bucket", {}),
			"references",
			[],
		)
		some reference in references
		reference == bucket.address
		address := bucket.address
	}
}

protecting_block_addresses(bucket_address) := addresses if {
	addresses := {address |
		some block in root_resources
		block.type == "aws_s3_bucket_public_access_block"

		referenced_buckets := referenced_bucket_addresses(block)
		count(referenced_buckets) == 1
		bucket_address in referenced_buckets
		address := block.address
	}
}

bucket_is_protected(bucket_address) if {
	blocks := protecting_block_addresses(bucket_address)
	count(blocks) == 1
	some block_address in blocks

	some block_change in resource_changes
	block_change.address == block_address
	planned(block_change)
	bucket_target_matches(bucket_address, block_change)

	after := block_change.change.after
	after.block_public_acls == true
	after.block_public_policy == true
	after.ignore_public_acls == true
	after.restrict_public_buckets == true
}

bucket_target_matches(bucket_address, block_change) if {
	some bucket_change in resource_changes
	bucket_change.address == bucket_address
	planned(bucket_change)

	bucket_name := object.get(bucket_change.change.after, "bucket", null)
	is_string(bucket_name)
	object.get(object.get(bucket_change.change, "after_unknown", {}), "bucket", false) != true

	block_bucket_name := object.get(block_change.change.after, "bucket", null)
	is_string(block_bucket_name)
	object.get(object.get(block_change.change, "after_unknown", {}), "bucket", false) != true
	block_bucket_name == bucket_name
}

bucket_block_target_invalid(bucket_address) if {
	blocks := protecting_block_addresses(bucket_address)
	count(blocks) == 1
	some block_address in blocks

	some block_change in resource_changes
	block_change.address == block_address
	planned(block_change)
	not bucket_target_matches(bucket_address, block_change)
}

deny contains msg if {
	some bucket in resource_changes
	bucket.type == "aws_s3_bucket"
	planned(bucket)
	startswith(bucket.address, "module.")

	msg := sprintf(
		"%s: child-module bucket correlation unsupported; declare the bucket at the root or extend the policy",
		[bucket.address],
	)
}

deny contains msg if {
	some bucket in resource_changes
	bucket.type == "aws_s3_bucket"
	planned(bucket)
	not startswith(bucket.address, "module.")
	contains(bucket.address, "[")

	msg := sprintf("%s: S3 bucket instance correlation unsupported", [bucket.address])
}

deny contains msg if {
	some bucket in resource_changes
	bucket.type == "aws_s3_bucket"
	planned(bucket)
	not startswith(bucket.address, "module.")
	not contains(bucket.address, "[")
	bucket_block_target_invalid(bucket.address)

	msg := sprintf(
		"%s: public access block target is unknown or does not match at plan time; reference the bucket via .bucket",
		[bucket.address],
	)
}

deny contains msg if {
	some bucket in resource_changes
	bucket.type == "aws_s3_bucket"
	planned(bucket)
	not startswith(bucket.address, "module.")
	not contains(bucket.address, "[")
	not bucket_block_target_invalid(bucket.address)
	not bucket_is_protected(bucket.address)

	msg := sprintf(
		"%s: planned S3 bucket must have exactly one unambiguous planned public access block with all four protections enabled",
		[bucket.address],
	)
}

load_balancer_group_addresses(load_balancer) := addresses if {
	addresses := {address |
		some group in root_resources
		group.type == "aws_security_group"
		references := object.get(
			object.get(object.get(load_balancer, "expressions", {}), "security_groups", {}),
			"references",
			[],
		)
		some reference in references
		reference == group.address
		address := group.address
	}
}

expression_references_exactly_group(resource, expression_name, group_address) if {
	references := object.get(
		object.get(object.get(resource, "expressions", {}), expression_name, {}),
		"references",
		[],
	)
	is_array(references)
	{reference | some reference in references} == {
		group_address,
		sprintf("%s.id", [group_address]),
	}
}

load_balancer_instance_matches(configuration_address, instance_address) if {
	instance_address == configuration_address
}

load_balancer_instance_matches(configuration_address, instance_address) if {
	startswith(instance_address, sprintf("%s[", [configuration_address]))
	endswith(instance_address, "]")
}

planned_group_id(group_address) := id if {
	some group_change in resource_changes
	group_change.address == group_address
	planned(group_change)
	object.get(object.get(group_change.change, "after_unknown", {}), "id", false) != true
	id := object.get(group_change.change.after, "id", null)
	is_string(id)
}

planned_group_id_unknown(group_address) if {
	some group_change in resource_changes
	group_change.address == group_address
	planned(group_change)
	object.get(object.get(group_change.change, "after_unknown", {}), "id", false) == true
}

load_balancer_attaches_group(load_balancer, load_balancer_change, group_address) if {
	object.get(object.get(load_balancer_change.change, "after_unknown", {}), "security_groups", false) == true
	planned_group_id_unknown(group_address)
	expression_references_exactly_group(load_balancer, "security_groups", group_address)
}

load_balancer_attaches_group(load_balancer, load_balancer_change, group_address) if {
	load_balancer_instance_matches(load_balancer.address, load_balancer_change.address)
	object.get(object.get(load_balancer_change.change, "after_unknown", {}), "security_groups", false) != true
	security_groups := object.get(load_balancer_change.change.after, "security_groups", null)
	is_array(security_groups)
	group_id := planned_group_id(group_address)
	group_id in security_groups
}

planned_alb_groups contains address if {
	some load_balancer in root_resources
	load_balancer.type == "aws_lb"
	groups := load_balancer_group_addresses(load_balancer)
	count(groups) == 1
	some address in groups

	some load_balancer_change in resource_changes
	load_balancer_instance_matches(load_balancer.address, load_balancer_change.address)
	planned(load_balancer_change)
	object.get(load_balancer_change.change.after, "load_balancer_type", null) == "application"
	object.get(object.get(load_balancer_change.change, "after_unknown", {}), "load_balancer_type", false) != true
	load_balancer_attaches_group(load_balancer, load_balancer_change, address)
}

reference_targets_group(reference, group_address) if {
	reference == group_address
}

reference_targets_group(reference, group_address) if {
	is_string(reference)
	startswith(reference, sprintf("%s.", [group_address]))
}

group_rule_resource(resource) if {
	resource.type in {
		"aws_security_group_rule",
		"aws_vpc_security_group_ingress_rule",
		"aws_vpc_security_group_egress_rule",
	}
}

security_group_rule_source_reference(resource, path) if {
	resource.type == "aws_security_group"
	count(path) >= 3
	path[0] in {"ingress", "egress"}
	path[count(path) - 2] == "security_groups"
}

root_resource_consumes_group(group_address) if {
	some resource in root_resources
	resource.type != "aws_lb"
	not group_rule_resource(resource)
	walk(object.get(resource, "expressions", {}), [path, value])
	count(path) > 0
	path[count(path) - 1] == "references"
	is_array(value)
	some reference in value
	reference_targets_group(reference, group_address)
	not security_group_rule_source_reference(resource, path)
}

module_call_consumes_group(group_address) if {
	root_module := object.get(object.get(input, "configuration", {}), "root_module", {})
	module_calls := object.get(root_module, "module_calls", {})
	is_object(module_calls)
	some _, module_call in module_calls
	walk(object.get(module_call, "expressions", {}), [path, value])
	count(path) > 0
	path[count(path) - 1] == "references"
	is_array(value)
	some reference in value
	reference_targets_group(reference, group_address)
}

group_has_non_load_balancer_consumer(group_address) if {
	root_resource_consumes_group(group_address)
}

group_has_non_load_balancer_consumer(group_address) if {
	module_call_consumes_group(group_address)
}

planned_alb_group_shared(address) if {
	address in planned_alb_groups
	group_has_non_load_balancer_consumer(address)
}

group_deny_message(group_address, default_message) := msg if {
	planned_alb_group_shared(group_address)
	msg := sprintf("%s: ALB group is shared with a non-load-balancer consumer", [group_address])
}

group_deny_message(group_address, default_message) := default_message if {
	not planned_alb_group_shared(group_address)
}

is_planned_alb_group(address) if {
	address in planned_alb_groups
	not group_has_non_load_balancer_consumer(address)
}

inline_ipv4_open(after) if {
	some ingress in object.get(after, "ingress", [])
	some cidr in object.get(ingress, "cidr_blocks", [])
	cidr == "0.0.0.0/0"
}

inline_ipv6_open(after) if {
	some ingress in object.get(after, "ingress", [])
	some cidr in object.get(ingress, "ipv6_cidr_blocks", [])
	cidr == "::/0"
}

inline_cidr_unknown(change) if {
	ingress_unknown := object.get(object.get(change, "after_unknown", {}), "ingress", false)
	ingress_unknown == true
}

inline_cidr_unknown(change) if {
	ingress_unknown := object.get(object.get(change, "after_unknown", {}), "ingress", false)
	ingress_unknown != true
	walk(ingress_unknown, [path, value])
	count(path) > 0
	field := path[count(path) - 1]
	field in {"cidr_blocks", "ipv6_cidr_blocks"}
	has_unknown_leaf(value)
}

inline_prefix_list_unverifiable(change) if {
	some ingress in object.get(change.after, "ingress", [])
	prefix_list_ids := object.get(ingress, "prefix_list_ids", [])
	is_array(prefix_list_ids)
	count(prefix_list_ids) > 0
}

inline_prefix_list_unverifiable(change) if {
	ingress_unknown := object.get(object.get(change, "after_unknown", {}), "ingress", false)
	ingress_unknown == true
}

inline_prefix_list_unverifiable(change) if {
	ingress_unknown := object.get(object.get(change, "after_unknown", {}), "ingress", false)
	ingress_unknown != true
	walk(ingress_unknown, [path, value])
	count(path) > 0
	path[count(path) - 1] == "prefix_list_ids"
	has_unknown_leaf(value)
}

deny contains msg if {
	some group in resource_changes
	group.type in {"aws_security_group", "aws_default_security_group"}
	planned(group)
	not is_planned_alb_group(group.address)
	inline_ipv4_open(group.change.after)

	msg := group_deny_message(group.address, sprintf("%s: non-ALB security group has IPv4 ingress open to 0.0.0.0/0", [group.address]))
}

deny contains msg if {
	some group in resource_changes
	group.type in {"aws_security_group", "aws_default_security_group"}
	planned(group)
	not is_planned_alb_group(group.address)
	inline_ipv6_open(group.change.after)

	msg := group_deny_message(group.address, sprintf("%s: non-ALB security group has IPv6 ingress open to ::/0", [group.address]))
}

deny contains msg if {
	some group in resource_changes
	group.type in {"aws_security_group", "aws_default_security_group"}
	planned(group)
	not is_planned_alb_group(group.address)
	inline_cidr_unknown(group.change)

	msg := group_deny_message(group.address, sprintf("%s: non-ALB security group ingress CIDR is unknown at plan time", [group.address]))
}

deny contains msg if {
	some group in resource_changes
	group.type in {"aws_security_group", "aws_default_security_group"}
	planned(group)
	not is_planned_alb_group(group.address)
	inline_prefix_list_unverifiable(group.change)

	msg := group_deny_message(
		group.address,
		sprintf(
			"%s: non-ALB security group prefix-list ingress cannot be proven safe by this gate",
			[group.address],
		),
	)
}

referenced_group_addresses(rule_address) := addresses if {
	addresses := {address |
		some rule in root_resources
		load_balancer_instance_matches(rule.address, rule_address)

		some group in root_resources
		group.type == "aws_security_group"
		references := object.get(
			object.get(object.get(rule, "expressions", {}), "security_group_id", {}),
			"references",
			[],
		)
		some reference in references
		reference == group.address
		address := group.address
	}
}

rule_target_matches_group(rule, rule_change, group_address) if {
	load_balancer_instance_matches(rule.address, rule_change.address)
	object.get(object.get(rule_change.change, "after_unknown", {}), "security_group_id", false) != true
	rule_group_id := object.get(rule_change.change.after, "security_group_id", null)
	is_string(rule_group_id)
	group_id := planned_group_id(group_address)
	rule_group_id == group_id
}

rule_target_matches_group(rule, rule_change, group_address) if {
	object.get(object.get(rule_change.change, "after_unknown", {}), "security_group_id", false) == true
	planned_group_id_unknown(group_address)
	expression_references_exactly_group(rule, "security_group_id", group_address)
}

rule_planned_alb_group(rule_change) := group_address if {
	some rule in root_resources
	load_balancer_instance_matches(rule.address, rule_change.address)
	groups := referenced_group_addresses(rule_change.address)
	count(groups) == 1
	some group_address in groups
	group_address in planned_alb_groups
	rule_target_matches_group(rule, rule_change, group_address)
}

rule_is_for_planned_alb(rule_change) if {
	group_address := rule_planned_alb_group(rule_change)
	not group_has_non_load_balancer_consumer(group_address)
}

rule_is_for_shared_planned_alb(rule_change) if {
	group_address := rule_planned_alb_group(rule_change)
	group_has_non_load_balancer_consumer(group_address)
}

rule_deny_message(rule_change, default_message) := msg if {
	rule_is_for_shared_planned_alb(rule_change)
	group_address := rule_planned_alb_group(rule_change)
	msg := sprintf(
		"%s: ALB group %s is shared with a non-load-balancer consumer",
		[rule_change.address, group_address],
	)
}

rule_deny_message(rule_change, default_message) := default_message if {
	not rule_is_for_shared_planned_alb(rule_change)
}

standalone_cidr_unknown(change) if {
	has_unknown_leaf(object.get(object.get(change, "after_unknown", {}), "cidr_ipv4", false))
}

standalone_cidr_unknown(change) if {
	has_unknown_leaf(object.get(object.get(change, "after_unknown", {}), "cidr_ipv6", false))
}

standalone_prefix_list_unverifiable(change) if {
	prefix_list_id := object.get(change.after, "prefix_list_id", null)
	is_string(prefix_list_id)
	prefix_list_id != ""
}

standalone_prefix_list_unverifiable(change) if {
	has_unknown_leaf(object.get(object.get(change, "after_unknown", {}), "prefix_list_id", false))
}

deny contains msg if {
	some rule in resource_changes
	rule.type == "aws_vpc_security_group_ingress_rule"
	planned(rule)
	not rule_is_for_planned_alb(rule)
	rule.change.after.cidr_ipv4 == "0.0.0.0/0"

	msg := rule_deny_message(rule, sprintf("%s: non-ALB ingress rule is open to 0.0.0.0/0", [rule.address]))
}

deny contains msg if {
	some rule in resource_changes
	rule.type == "aws_vpc_security_group_ingress_rule"
	planned(rule)
	not rule_is_for_planned_alb(rule)
	rule.change.after.cidr_ipv6 == "::/0"

	msg := rule_deny_message(rule, sprintf("%s: non-ALB ingress rule is open to ::/0", [rule.address]))
}

deny contains msg if {
	some rule in resource_changes
	rule.type == "aws_vpc_security_group_ingress_rule"
	planned(rule)
	not rule_is_for_planned_alb(rule)
	standalone_cidr_unknown(rule.change)

	msg := rule_deny_message(rule, sprintf("%s: non-ALB ingress rule CIDR is unknown at plan time", [rule.address]))
}

deny contains msg if {
	some rule in resource_changes
	rule.type == "aws_vpc_security_group_ingress_rule"
	planned(rule)
	not rule_is_for_planned_alb(rule)
	standalone_prefix_list_unverifiable(rule.change)

	msg := rule_deny_message(
		rule,
		sprintf(
			"%s: non-ALB ingress rule prefix-list ingress cannot be proven safe by this gate",
			[rule.address],
		),
	)
}

legacy_ipv4_open(after) if {
	some cidr in object.get(after, "cidr_blocks", [])
	cidr == "0.0.0.0/0"
}

legacy_ipv6_open(after) if {
	some cidr in object.get(after, "ipv6_cidr_blocks", [])
	cidr == "::/0"
}

legacy_cidr_unknown(change) if {
	has_unknown_leaf(object.get(object.get(change, "after_unknown", {}), "cidr_blocks", false))
}

legacy_cidr_unknown(change) if {
	has_unknown_leaf(object.get(object.get(change, "after_unknown", {}), "ipv6_cidr_blocks", false))
}

legacy_prefix_list_unverifiable(change) if {
	prefix_list_ids := object.get(change.after, "prefix_list_ids", [])
	is_array(prefix_list_ids)
	count(prefix_list_ids) > 0
}

legacy_prefix_list_unverifiable(change) if {
	has_unknown_leaf(object.get(object.get(change, "after_unknown", {}), "prefix_list_ids", false))
}

legacy_potential_ingress(change) if {
	object.get(change.after, "type", null) == "ingress"
}

legacy_potential_ingress(change) if {
	object.get(object.get(change, "after_unknown", {}), "type", false) == true
}

deny contains msg if {
	some rule in resource_changes
	rule.type == "aws_security_group_rule"
	planned(rule)
	legacy_potential_ingress(rule.change)
	not rule_is_for_planned_alb(rule)
	legacy_ipv4_open(rule.change.after)

	msg := rule_deny_message(rule, sprintf("%s: non-ALB legacy ingress rule is open to 0.0.0.0/0", [rule.address]))
}

deny contains msg if {
	some rule in resource_changes
	rule.type == "aws_security_group_rule"
	planned(rule)
	legacy_potential_ingress(rule.change)
	not rule_is_for_planned_alb(rule)
	legacy_ipv6_open(rule.change.after)

	msg := rule_deny_message(rule, sprintf("%s: non-ALB legacy ingress rule is open to ::/0", [rule.address]))
}

deny contains msg if {
	some rule in resource_changes
	rule.type == "aws_security_group_rule"
	planned(rule)
	legacy_potential_ingress(rule.change)
	not rule_is_for_planned_alb(rule)
	legacy_cidr_unknown(rule.change)

	msg := rule_deny_message(rule, sprintf("%s: non-ALB legacy ingress rule CIDR is unknown at plan time", [rule.address]))
}

deny contains msg if {
	some rule in resource_changes
	rule.type == "aws_security_group_rule"
	planned(rule)
	legacy_potential_ingress(rule.change)
	not rule_is_for_planned_alb(rule)
	legacy_prefix_list_unverifiable(rule.change)

	msg := rule_deny_message(
		rule,
		sprintf(
			"%s: non-ALB legacy ingress rule prefix-list ingress cannot be proven safe by this gate",
			[rule.address],
		),
	)
}
