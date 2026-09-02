.PHONY: bootstrap-preflight bootstrap-fmt bootstrap-validate bootstrap-lint bootstrap-plan bootstrap-apply localstack-up localstack-down localstack-status plan apply destroy test lint validate check-env-id render-localstack-backend

TARGET ?= aws
# preflight and terraform must check the same account and region
AWS_PROFILE ?= orbit
AWS_REGION ?= us-east-1

bootstrap-preflight:
	AWS_PROFILE=$(AWS_PROFILE) AWS_REGION=$(AWS_REGION) bootstrap/preflight.sh

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
	cp bootstrap/localstack.backend_override.tf.example bootstrap/backend_override.tf; \
	TF_DATA_DIR=.terraform-localstack terraform -chdir=bootstrap init -reconfigure -input=false && \
	TF_DATA_DIR=.terraform-localstack terraform -chdir=bootstrap plan -var target=$(TARGET) -var budget_email=unused; \
	rc=$$?; rm -f bootstrap/backend_override.tf; exit $$rc

bootstrap-apply:
	cp bootstrap/localstack.backend_override.tf.example bootstrap/backend_override.tf; \
	TF_DATA_DIR=.terraform-localstack terraform -chdir=bootstrap init -reconfigure -input=false && \
	TF_DATA_DIR=.terraform-localstack terraform -chdir=bootstrap apply -var target=$(TARGET) -var budget_email=unused -auto-approve; \
	rc=$$?; rm -f bootstrap/backend_override.tf; exit $$rc
else
bootstrap-plan:
	rm -f bootstrap/backend_override.tf
	AWS_PROFILE=$(AWS_PROFILE) terraform -chdir=bootstrap plan -var-file=terraform.tfvars -var target=$(TARGET) -var region=$(AWS_REGION)

bootstrap-apply: bootstrap-preflight
	rm -f bootstrap/backend_override.tf
	AWS_PROFILE=$(AWS_PROFILE) terraform -chdir=bootstrap apply -var-file=terraform.tfvars -var target=$(TARGET) -var region=$(AWS_REGION)
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
	@for d in modules/*/; do \
		if [ -d "$${d}tests" ]; then \
			echo "== terraform test: $$d =="; \
			terraform -chdir="$$d" test || exit 1; \
		fi; \
	done

validate:
	terraform -chdir=bootstrap init -backend=false -input=false >/dev/null
	terraform -chdir=bootstrap validate
	@for d in modules/*/; do \
		echo "== terraform validate: $$d =="; \
		terraform -chdir="$$d" init -backend=false -input=false >/dev/null; \
		terraform -chdir="$$d" validate || exit 1; \
	done
	terraform -chdir=envs/preview init -backend=false -input=false >/dev/null
	terraform -chdir=envs/preview validate

lint:
	terraform fmt -check -recursive
	tflint --recursive
	checkov --config-file .checkov.yaml
