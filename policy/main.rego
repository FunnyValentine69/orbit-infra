# This policy evaluates root-module resources only where Terraform configuration
# correlation is required. ALB exemptions are structural references, never name
# based. Planned no-op resources are evaluated because a sibling protection
# resource can be deleted or weakened while the protected resource is unchanged.
package main

root_resources := object.get(
	object.get(object.get(input, "configuration", {}), "root_module", {}),
	"resources",
	[],
)

resource_changes := object.get(input, "resource_changes", [])

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

	after := block_change.change.after
	after.block_public_acls == true
	after.block_public_policy == true
	after.ignore_public_acls == true
	after.restrict_public_buckets == true
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
	not bucket_is_protected(bucket.address)

	msg := sprintf(
		"%s: planned S3 bucket must have exactly one unambiguous planned public access block with all four protections enabled",
		[bucket.address],
	)
}

planned_alb_groups contains address if {
	some load_balancer in root_resources
	load_balancer.type == "aws_lb"

	some load_balancer_change in resource_changes
	load_balancer_change.address == load_balancer.address
	planned(load_balancer_change)
	object.get(load_balancer_change.change.after, "load_balancer_type", "application") == "application"

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

is_planned_alb_group(address) if {
	address in planned_alb_groups
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
	value == true
	count(path) > 0
	field := path[count(path) - 1]
	field in {"cidr_blocks", "ipv6_cidr_blocks"}
}

deny contains msg if {
	some group in resource_changes
	group.type in {"aws_security_group", "aws_default_security_group"}
	planned(group)
	not is_planned_alb_group(group.address)
	inline_ipv4_open(group.change.after)

	msg := sprintf("%s: non-ALB security group has IPv4 ingress open to 0.0.0.0/0", [group.address])
}

deny contains msg if {
	some group in resource_changes
	group.type in {"aws_security_group", "aws_default_security_group"}
	planned(group)
	not is_planned_alb_group(group.address)
	inline_ipv6_open(group.change.after)

	msg := sprintf("%s: non-ALB security group has IPv6 ingress open to ::/0", [group.address])
}

deny contains msg if {
	some group in resource_changes
	group.type in {"aws_security_group", "aws_default_security_group"}
	planned(group)
	not is_planned_alb_group(group.address)
	inline_cidr_unknown(group.change)

	msg := sprintf("%s: non-ALB security group ingress CIDR is unknown at plan time", [group.address])
}

referenced_group_addresses(rule_address) := addresses if {
	addresses := {address |
		some rule in root_resources
		rule.address == rule_address

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

rule_is_for_planned_alb(rule_address) if {
	groups := referenced_group_addresses(rule_address)
	count(groups) == 1
	some group_address in groups
	is_planned_alb_group(group_address)
}

standalone_cidr_unknown(change) if {
	object.get(object.get(change, "after_unknown", {}), "cidr_ipv4", false) == true
}

standalone_cidr_unknown(change) if {
	object.get(object.get(change, "after_unknown", {}), "cidr_ipv6", false) == true
}

deny contains msg if {
	some rule in resource_changes
	rule.type == "aws_vpc_security_group_ingress_rule"
	planned(rule)
	not rule_is_for_planned_alb(rule.address)
	rule.change.after.cidr_ipv4 == "0.0.0.0/0"

	msg := sprintf("%s: non-ALB ingress rule is open to 0.0.0.0/0", [rule.address])
}

deny contains msg if {
	some rule in resource_changes
	rule.type == "aws_vpc_security_group_ingress_rule"
	planned(rule)
	not rule_is_for_planned_alb(rule.address)
	rule.change.after.cidr_ipv6 == "::/0"

	msg := sprintf("%s: non-ALB ingress rule is open to ::/0", [rule.address])
}

deny contains msg if {
	some rule in resource_changes
	rule.type == "aws_vpc_security_group_ingress_rule"
	planned(rule)
	not rule_is_for_planned_alb(rule.address)
	standalone_cidr_unknown(rule.change)

	msg := sprintf("%s: non-ALB ingress rule CIDR is unknown at plan time", [rule.address])
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
	object.get(object.get(change, "after_unknown", {}), "cidr_blocks", false) == true
}

legacy_cidr_unknown(change) if {
	object.get(object.get(change, "after_unknown", {}), "ipv6_cidr_blocks", false) == true
}

deny contains msg if {
	some rule in resource_changes
	rule.type == "aws_security_group_rule"
	planned(rule)
	rule.change.after.type == "ingress"
	not rule_is_for_planned_alb(rule.address)
	legacy_ipv4_open(rule.change.after)

	msg := sprintf("%s: non-ALB legacy ingress rule is open to 0.0.0.0/0", [rule.address])
}

deny contains msg if {
	some rule in resource_changes
	rule.type == "aws_security_group_rule"
	planned(rule)
	rule.change.after.type == "ingress"
	not rule_is_for_planned_alb(rule.address)
	legacy_ipv6_open(rule.change.after)

	msg := sprintf("%s: non-ALB legacy ingress rule is open to ::/0", [rule.address])
}

deny contains msg if {
	some rule in resource_changes
	rule.type == "aws_security_group_rule"
	planned(rule)
	rule.change.after.type == "ingress"
	not rule_is_for_planned_alb(rule.address)
	legacy_cidr_unknown(rule.change)

	msg := sprintf("%s: non-ALB legacy ingress rule CIDR is unknown at plan time", [rule.address])
}
