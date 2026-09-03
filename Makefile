.PHONY: bootstrap-preflight bootstrap-fmt bootstrap-validate bootstrap-lint bootstrap-plan bootstrap-apply localstack-up localstack-down localstack-status plan apply destroy test lint validate check-target check-env-id check-operator-cidr render-localstack-backend placeholder-build check-placeholder-image

TARGET ?= aws
# preflight and terraform must check the same account and region
AWS_PROFILE ?= orbit
AWS_REGION ?= us-east-1

export TARGET ENV_ID OPERATOR_CIDR AWS_PROFILE AWS_REGION

check-target:
	@case "$$TARGET" in \
		aws|localstack) ;; \
		*) echo "TARGET must be aws or localstack, got: $$TARGET" >&2; exit 1 ;; \
	esac

bootstrap-preflight:
	bootstrap/preflight.sh

bootstrap-fmt:
	terraform -chdir=bootstrap fmt -check

bootstrap-validate:
	terraform -chdir=bootstrap init -backend=false -input=false >/dev/null
	terraform -chdir=bootstrap validate

bootstrap-lint:
	tflint --chdir bootstrap --init --recursive --config "$(CURDIR)/.tflint.hcl"
	tflint --chdir bootstrap --recursive --config "$(CURDIR)/.tflint.hcl"

# LocalStack applies are disposable; real AWS keeps the interactive confirmation
ifeq ($(TARGET),localstack)
bootstrap-plan:
	cp bootstrap/localstack.backend_override.tf.example bootstrap/backend_override.tf; \
	TF_DATA_DIR=.terraform-localstack terraform -chdir=bootstrap init -reconfigure -input=false && \
	TF_DATA_DIR=.terraform-localstack terraform -chdir=bootstrap plan -var "target=$$TARGET" -var budget_email=unused; \
	rc=$$?; rm -f bootstrap/backend_override.tf; exit $$rc

bootstrap-apply:
	cp bootstrap/localstack.backend_override.tf.example bootstrap/backend_override.tf; \
	TF_DATA_DIR=.terraform-localstack terraform -chdir=bootstrap init -reconfigure -input=false && \
	TF_DATA_DIR=.terraform-localstack terraform -chdir=bootstrap apply -var "target=$$TARGET" -var budget_email=unused -auto-approve; \
	rc=$$?; rm -f bootstrap/backend_override.tf; exit $$rc
else
bootstrap-plan:
	rm -f bootstrap/backend_override.tf
	terraform -chdir=bootstrap plan -var-file=terraform.tfvars -var "target=$$TARGET" -var "region=$$AWS_REGION"

bootstrap-apply: bootstrap-preflight
	rm -f bootstrap/backend_override.tf
	terraform -chdir=bootstrap apply -var-file=terraform.tfvars -var "target=$$TARGET" -var "region=$$AWS_REGION"
endif

localstack-up:
	localstack start -d
	localstack wait -t 120

localstack-down:
	localstack stop

localstack-status:
	localstack status services

placeholder-build:
	docker build --platform linux/arm64 -t placeholder:local placeholder/

check-placeholder-image:
	@if [ -n "$$TF_VAR_api_image" ] && [ "$$TF_VAR_api_image" != "placeholder:local" ]; then \
		echo "api_image override in effect; skipping placeholder image check"; \
	else \
		docker image inspect placeholder:local >/dev/null 2>&1 || { echo "placeholder:local image not found; run make placeholder-build first" >&2; exit 1; }; \
	fi

# Intentionally no bootstrap-destroy target: every bootstrap resource has
# prevent_destroy = true and this state must never be torn down via make.

# envs/preview: TARGET and ENV_ID are both required for plan/apply/destroy.
OPERATOR_CIDR ?= $(shell curl -sf --max-time 5 https://checkip.amazonaws.com | awk '{print $$1"/32"}')
OPERATOR_CIDR := $(OPERATOR_CIDR)

check-operator-cidr:
	@if [ -z "$$OPERATOR_CIDR" ]; then echo "OPERATOR_CIDR auto-detect failed; pass OPERATOR_CIDR=<cidr>" >&2; exit 1; fi

ifeq ($(TARGET),localstack)
plan apply destroy: check-target check-env-id check-operator-cidr

check-env-id:
	@if [ -z "$$ENV_ID" ]; then echo "ENV_ID is required, e.g. make plan TARGET=localstack ENV_ID=dev" >&2; exit 1; fi
	@printf '%s' "$$ENV_ID" | grep -Eq '^[a-z0-9]([a-z0-9-]{0,10}[a-z0-9])?$$' || { echo "ENV_ID must match ^[a-z0-9]([a-z0-9-]{0,10}[a-z0-9])?\$$, got: $$ENV_ID" >&2; exit 1; }

render-localstack-backend:
	awk -v id="$$ENV_ID" '{ gsub(/ENV_ID_PLACEHOLDER/, id); print }' envs/preview/localstack.backend_override.tf.example > envs/preview/backend_override.tf

# Per-ENV_ID TF_DATA_DIR keeps concurrent LocalStack environments'
# plugin/provider caches isolated; backend_override.tf is rendered and
# removed within the same subshell so it never persists past this command.
plan:
	( \
		trap 'rm -f envs/preview/backend_override.tf' EXIT; \
		$(MAKE) render-localstack-backend; \
		TF_DATA_DIR=.terraform-localstack-$$ENV_ID terraform -chdir=envs/preview init -reconfigure -input=false && \
		TF_DATA_DIR=.terraform-localstack-$$ENV_ID terraform -chdir=envs/preview plan -var "target=$$TARGET" -var "env_id=$$ENV_ID" -var "operator_cidr=$$OPERATOR_CIDR"; \
	)

apply: check-placeholder-image
	( \
		trap 'rm -f envs/preview/backend_override.tf' EXIT; \
		$(MAKE) render-localstack-backend; \
		TF_DATA_DIR=.terraform-localstack-$$ENV_ID terraform -chdir=envs/preview init -reconfigure -input=false && \
		TF_DATA_DIR=.terraform-localstack-$$ENV_ID terraform -chdir=envs/preview apply -var "target=$$TARGET" -var "env_id=$$ENV_ID" -var "operator_cidr=$$OPERATOR_CIDR" -auto-approve; \
	)

destroy:
	( \
		trap 'rm -f envs/preview/backend_override.tf' EXIT; \
		$(MAKE) render-localstack-backend; \
		TF_DATA_DIR=.terraform-localstack-$$ENV_ID terraform -chdir=envs/preview init -reconfigure -input=false && \
		TF_DATA_DIR=.terraform-localstack-$$ENV_ID terraform -chdir=envs/preview destroy -var "target=$$TARGET" -var "env_id=$$ENV_ID" -var "operator_cidr=$$OPERATOR_CIDR" -auto-approve; \
	)
else
plan apply destroy: check-target check-env-id check-operator-cidr

check-env-id:
	@if [ -z "$$ENV_ID" ]; then echo "ENV_ID is required, e.g. make plan TARGET=localstack ENV_ID=dev" >&2; exit 1; fi
	@printf '%s' "$$ENV_ID" | grep -Eq '^[a-z0-9]([a-z0-9-]{0,10}[a-z0-9])?$$' || { echo "ENV_ID must match ^[a-z0-9]([a-z0-9-]{0,10}[a-z0-9])?\$$, got: $$ENV_ID" >&2; exit 1; }

# backend.aws.hcl is operator-provided (copied from backend.aws.hcl.example,
# not committed); it is resolved as an absolute path since terraform
# -chdir=envs/preview resolves -backend-config paths relative to
# envs/preview, not to $(CURDIR).
BACKEND_HCL ?= $(CURDIR)/envs/preview/backend.aws.hcl
export BACKEND_HCL

check-backend-hcl:
	@if [ ! -f "$(BACKEND_HCL)" ]; then \
		echo "copy envs/preview/backend.aws.hcl.example to envs/preview/backend.aws.hcl and fill in the bucket" >&2; \
		exit 1; \
	fi
	@if [ -f envs/preview/backend_override.tf ]; then \
		echo "LocalStack override present; remove envs/preview/backend_override.tf before targeting aws" >&2; \
		exit 1; \
	fi

plan: check-backend-hcl
	terraform -chdir=envs/preview init -reconfigure -backend-config="$$BACKEND_HCL" -backend-config="key=envs/preview/$$ENV_ID.tfstate"
	terraform -chdir=envs/preview plan -var "target=$$TARGET" -var "env_id=$$ENV_ID" -var "operator_cidr=$$OPERATOR_CIDR"

apply: check-backend-hcl
	terraform -chdir=envs/preview init -reconfigure -backend-config="$$BACKEND_HCL" -backend-config="key=envs/preview/$$ENV_ID.tfstate"
	terraform -chdir=envs/preview apply -var "target=$$TARGET" -var "env_id=$$ENV_ID" -var "operator_cidr=$$OPERATOR_CIDR"

destroy: check-backend-hcl
	terraform -chdir=envs/preview init -reconfigure -backend-config="$$BACKEND_HCL" -backend-config="key=envs/preview/$$ENV_ID.tfstate"
	terraform -chdir=envs/preview destroy -var "target=$$TARGET" -var "env_id=$$ENV_ID" -var "operator_cidr=$$OPERATOR_CIDR"
endif

test:
	@for d in modules/*/; do \
		if [ -d "$${d}tests" ]; then \
			echo "== terraform test: $$d =="; \
			terraform -chdir="$$d" init -backend=false -input=false >/dev/null && \
			terraform -chdir="$$d" test || exit 1; \
		fi; \
	done
	@for d in envs/*/; do \
		if [ -d "$${d}tests" ]; then \
			echo "== terraform test: $$d =="; \
			( \
				trap 'rm -f "$${d}backend_override.tf"' EXIT; \
				sed 's/ENV_ID_PLACEHOLDER/tftest/' "$${d}localstack.backend_override.tf.example" > "$${d}backend_override.tf"; \
				TF_DATA_DIR=.terraform-localstack-tftest terraform -chdir="$$d" init -reconfigure -input=false >/dev/null && \
				TF_DATA_DIR=.terraform-localstack-tftest terraform -chdir="$$d" test; \
			) || exit $$?; \
		fi; \
	done

validate:
	terraform -chdir=bootstrap init -backend=false -input=false >/dev/null
	terraform -chdir=bootstrap validate
	@for d in modules/*/; do \
		echo "== terraform validate: $$d =="; \
		terraform -chdir="$$d" init -backend=false -input=false >/dev/null && \
		terraform -chdir="$$d" validate || exit 1; \
	done
	terraform -chdir=envs/preview init -backend=false -input=false >/dev/null
	terraform -chdir=envs/preview validate

lint:
	terraform fmt -check -recursive
	tflint --init --recursive --config "$(CURDIR)/.tflint.hcl"
	tflint --recursive --config "$(CURDIR)/.tflint.hcl"
	checkov --config-file .checkov.yaml
