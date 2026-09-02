.PHONY: bootstrap-preflight bootstrap-fmt bootstrap-validate bootstrap-lint bootstrap-plan bootstrap-apply localstack-up localstack-down localstack-status plan apply destroy test lint check-env-id render-localstack-backend

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
	TF_DATA_DIR=.terraform-localstack terraform -chdir=bootstrap plan -var target=$(TARGET) -var budget_email=unused

bootstrap-apply:
	cp bootstrap/localstack.backend_override.tf.example bootstrap/backend_override.tf
	TF_DATA_DIR=.terraform-localstack terraform -chdir=bootstrap init -reconfigure -input=false
	TF_DATA_DIR=.terraform-localstack terraform -chdir=bootstrap apply -var target=$(TARGET) -var budget_email=unused -auto-approve
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

# envs/preview: TARGET and ENV_ID are both required for plan/apply/destroy.
OPERATOR_CIDR ?= $(shell curl -s https://checkip.amazonaws.com | awk '{print $$1"/32"}')

ifeq ($(TARGET),localstack)
plan apply destroy: check-env-id

check-env-id:
	@if [ -z "$(ENV_ID)" ]; then echo "ENV_ID is required, e.g. make plan TARGET=localstack ENV_ID=dev" >&2; exit 1; fi

render-localstack-backend:
	sed 's/ENV_ID_PLACEHOLDER/$(ENV_ID)/' envs/preview/localstack.backend_override.tf.example > envs/preview/backend_override.tf

plan:
	$(MAKE) render-localstack-backend
	TF_DATA_DIR=.terraform-localstack terraform -chdir=envs/preview init -reconfigure -input=false
	TF_DATA_DIR=.terraform-localstack terraform -chdir=envs/preview plan -var target=$(TARGET) -var env_id=$(ENV_ID) -var operator_cidr=$(OPERATOR_CIDR)

apply:
	$(MAKE) render-localstack-backend
	TF_DATA_DIR=.terraform-localstack terraform -chdir=envs/preview init -reconfigure -input=false
	TF_DATA_DIR=.terraform-localstack terraform -chdir=envs/preview apply -var target=$(TARGET) -var env_id=$(ENV_ID) -var operator_cidr=$(OPERATOR_CIDR) -auto-approve

destroy:
	$(MAKE) render-localstack-backend
	TF_DATA_DIR=.terraform-localstack terraform -chdir=envs/preview init -reconfigure -input=false
	TF_DATA_DIR=.terraform-localstack terraform -chdir=envs/preview destroy -var target=$(TARGET) -var env_id=$(ENV_ID) -var operator_cidr=$(OPERATOR_CIDR) -auto-approve
else
plan apply destroy: check-env-id

check-env-id:
	@if [ -z "$(ENV_ID)" ]; then echo "ENV_ID is required, e.g. make plan TARGET=localstack ENV_ID=dev" >&2; exit 1; fi

# backend.aws.hcl is operator-provided (copied from backend.aws.hcl.example,
# not committed); fall back to the example when it's absent, since the
# example carries no secrets.
BACKEND_HCL := $(if $(wildcard envs/preview/backend.aws.hcl),envs/preview/backend.aws.hcl,envs/preview/backend.aws.hcl.example)

plan:
	rm -f envs/preview/backend_override.tf
	terraform -chdir=envs/preview init -reconfigure -backend-config=$(BACKEND_HCL) -backend-config="key=envs/preview/$(ENV_ID).tfstate"
	terraform -chdir=envs/preview plan -var target=$(TARGET) -var env_id=$(ENV_ID) -var operator_cidr=$(OPERATOR_CIDR)

apply:
	rm -f envs/preview/backend_override.tf
	terraform -chdir=envs/preview init -reconfigure -backend-config=$(BACKEND_HCL) -backend-config="key=envs/preview/$(ENV_ID).tfstate"
	terraform -chdir=envs/preview apply -var target=$(TARGET) -var env_id=$(ENV_ID) -var operator_cidr=$(OPERATOR_CIDR)

destroy:
	rm -f envs/preview/backend_override.tf
	terraform -chdir=envs/preview init -reconfigure -backend-config=$(BACKEND_HCL) -backend-config="key=envs/preview/$(ENV_ID).tfstate"
	terraform -chdir=envs/preview destroy -var target=$(TARGET) -var env_id=$(ENV_ID) -var operator_cidr=$(OPERATOR_CIDR)
endif

test:
	terraform -chdir=modules/network test

lint:
	terraform -chdir=modules/network fmt -check -diff
	terraform -chdir=envs/preview fmt -check -diff
	tflint --chdir modules/network
	tflint --chdir envs/preview
	checkov -d modules -d envs --quiet --compact
