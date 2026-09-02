.PHONY: bootstrap-preflight bootstrap-fmt bootstrap-validate bootstrap-lint bootstrap-plan bootstrap-apply localstack-up localstack-down localstack-status

TARGET ?= aws

bootstrap-preflight:
	bootstrap/preflight.sh

bootstrap-fmt:
	terraform -chdir=bootstrap fmt -check

bootstrap-validate:
	terraform -chdir=bootstrap init -backend=false -input=false >/dev/null
	terraform -chdir=bootstrap validate

bootstrap-lint:
	tflint --chdir bootstrap

# LocalStack applies are disposable; real AWS keeps the interactive confirmation
ifeq ($(TARGET),localstack)
bootstrap-plan:
	cp bootstrap/localstack.backend_override.tf.example bootstrap/backend_override.tf
	TF_DATA_DIR=.terraform-localstack terraform -chdir=bootstrap init -reconfigure -input=false
	TF_DATA_DIR=.terraform-localstack terraform -chdir=bootstrap plan -var target=$(TARGET) -var budget_email=none@localhost

bootstrap-apply:
	cp bootstrap/localstack.backend_override.tf.example bootstrap/backend_override.tf
	TF_DATA_DIR=.terraform-localstack terraform -chdir=bootstrap init -reconfigure -input=false
	TF_DATA_DIR=.terraform-localstack terraform -chdir=bootstrap apply -var target=$(TARGET) -var budget_email=none@localhost -auto-approve
else
bootstrap-plan:
	rm -f bootstrap/backend_override.tf
	terraform -chdir=bootstrap plan -var-file=terraform.tfvars -var target=$(TARGET)

bootstrap-apply: bootstrap-preflight
	rm -f bootstrap/backend_override.tf
	terraform -chdir=bootstrap apply -var-file=terraform.tfvars -var target=$(TARGET)
endif

localstack-up:
	localstack start -d
	localstack wait -t 120

localstack-down:
	localstack stop

localstack-status:
	localstack status services

# Intentionally no bootstrap-destroy target: every bootstrap resource has
# prevent_destroy = true and this state must never be torn down via make.
