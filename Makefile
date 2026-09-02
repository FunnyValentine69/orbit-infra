.PHONY: bootstrap-preflight bootstrap-fmt bootstrap-validate bootstrap-lint bootstrap-plan bootstrap-apply

bootstrap-preflight:
	bootstrap/preflight.sh

bootstrap-fmt:
	terraform -chdir=bootstrap fmt -check

bootstrap-validate:
	terraform -chdir=bootstrap init -backend=false -input=false >/dev/null
	terraform -chdir=bootstrap validate

bootstrap-lint:
	tflint --chdir bootstrap

bootstrap-plan:
	terraform -chdir=bootstrap plan -var-file=terraform.tfvars

bootstrap-apply:
	terraform -chdir=bootstrap apply -var-file=terraform.tfvars

# Intentionally no bootstrap-destroy target: every bootstrap resource has
# prevent_destroy = true and this state must never be torn down via make.
