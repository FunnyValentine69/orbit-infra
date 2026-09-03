.PHONY: bootstrap-preflight bootstrap-fmt bootstrap-validate bootstrap-lint bootstrap-plan bootstrap-apply localstack-up localstack-down localstack-status plan apply destroy test lint validate check-target check-env-id check-operator-cidr render-localstack-backend placeholder-build check-placeholder-image lease-list lease-get close

TARGET ?= aws
# preflight and terraform must check the same account and region
AWS_PROFILE ?= orbit
AWS_REGION ?= us-east-1

PREVIEW_ROOT ?= envs/preview
export TARGET ENV_ID OPERATOR_CIDR AWS_PROFILE AWS_REGION PREVIEW_ROOT

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

# Terraform loads every *_override.tf file in a directory, so concurrent
# LocalStack runs cannot be isolated by filename alone. Each ENV_ID gets
# its own rsync'd copy of envs/preview (same relative depth, so
# ../../modules/... module sources still resolve) under
# .preview-runs/<ENV_ID>/, with the override rendered inside that
# copy. PREVIEW_ROOT points there and is exported so Phase 3's
# scripts/close-env.sh and scripts/lease.sh can target the same run
# directory. rsync deletes stale source files but excludes Terraform data,
# the rendered backend override, and LocalStack state so those persist
# across runs sharing an ENV_ID.
render-localstack-backend:
	mkdir -p "$$PREVIEW_ROOT"
	rsync -a --delete --exclude '.terraform*' --exclude 'backend_override.tf' --exclude '*.tfstate*' envs/preview/ "$$PREVIEW_ROOT/"
	awk -v id="$$ENV_ID" '{ gsub(/ENV_ID_PLACEHOLDER/, id); print }' envs/preview/localstack.backend_override.tf.example > "$$PREVIEW_ROOT/backend_override.tf"

plan:
	( \
		export PREVIEW_ROOT=".preview-runs/$$ENV_ID"; \
		$(MAKE) render-localstack-backend && \
		TF_DATA_DIR=.terraform-localstack terraform -chdir="$$PREVIEW_ROOT" init -reconfigure -input=false && \
		TF_DATA_DIR=.terraform-localstack terraform -chdir="$$PREVIEW_ROOT" plan -var "target=$$TARGET" -var "env_id=$$ENV_ID" -var "operator_cidr=$$OPERATOR_CIDR" -var "region=$$AWS_REGION"; \
	)

apply: check-placeholder-image
	( \
		export PREVIEW_ROOT=".preview-runs/$$ENV_ID"; \
		$(MAKE) render-localstack-backend && \
		TF_DATA_DIR=.terraform-localstack terraform -chdir="$$PREVIEW_ROOT" init -reconfigure -input=false && \
		TF_DATA_DIR=.terraform-localstack terraform -chdir="$$PREVIEW_ROOT" apply -var "target=$$TARGET" -var "env_id=$$ENV_ID" -var "operator_cidr=$$OPERATOR_CIDR" -var "region=$$AWS_REGION" -auto-approve; \
	)

destroy:
	( \
		export PREVIEW_ROOT=".preview-runs/$$ENV_ID"; \
		$(MAKE) render-localstack-backend && \
		TF_DATA_DIR=.terraform-localstack terraform -chdir="$$PREVIEW_ROOT" init -reconfigure -input=false && \
		TF_DATA_DIR=.terraform-localstack terraform -chdir="$$PREVIEW_ROOT" destroy -var "target=$$TARGET" -var "env_id=$$ENV_ID" -var "operator_cidr=$$OPERATOR_CIDR" -var "region=$$AWS_REGION" -auto-approve; \
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
	terraform -chdir=envs/preview plan -var "target=$$TARGET" -var "env_id=$$ENV_ID" -var "operator_cidr=$$OPERATOR_CIDR" -var "region=$$AWS_REGION"

apply: check-backend-hcl
	terraform -chdir=envs/preview init -reconfigure -backend-config="$$BACKEND_HCL" -backend-config="key=envs/preview/$$ENV_ID.tfstate"
	terraform -chdir=envs/preview apply -var "target=$$TARGET" -var "env_id=$$ENV_ID" -var "operator_cidr=$$OPERATOR_CIDR" -var "region=$$AWS_REGION"

destroy: check-backend-hcl
	terraform -chdir=envs/preview init -reconfigure -backend-config="$$BACKEND_HCL" -backend-config="key=envs/preview/$$ENV_ID.tfstate"
	terraform -chdir=envs/preview destroy -var "target=$$TARGET" -var "env_id=$$ENV_ID" -var "operator_cidr=$$OPERATOR_CIDR" -var "region=$$AWS_REGION"
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
				run_dir=".preview-runs/tftest-$$(basename "$${d%/}")"; \
				mkdir -p "$$run_dir"; \
				rsync -a --delete --exclude '.terraform*' --exclude 'backend_override.tf' --exclude '*.tfstate*' "$$d" "$$run_dir/"; \
				sed 's/ENV_ID_PLACEHOLDER/tftest/' "$${d}localstack.backend_override.tf.example" > "$$run_dir/backend_override.tf"; \
				TF_DATA_DIR=.terraform-localstack terraform -chdir="$$run_dir" init -reconfigure -input=false >/dev/null && \
				TF_DATA_DIR=.terraform-localstack terraform -chdir="$$run_dir" test; \
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

# Preview environment leases (ADR 0006). See scripts/lease.sh --help.
lease-list:
	scripts/lease.sh list

lease-get: check-env-id
	scripts/lease.sh get "$$ENV_ID"

# TARGET=localstack routes close-env.sh at the LocalStack endpoint; TARGET=aws (default) closes against real AWS.
close: check-target check-env-id
ifeq ($(TARGET),localstack)
close:
	AWS_ENDPOINT_URL=http://localhost:4566 AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 scripts/close-env.sh "$$ENV_ID"
else
close:
	scripts/close-env.sh "$$ENV_ID"
endif
