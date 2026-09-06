.PHONY: bootstrap-preflight bootstrap-fmt bootstrap-validate bootstrap-lint bootstrap-plan bootstrap-apply iam-matrix-plan localstack-up localstack-down localstack-status plan apply destroy test test-concurrency lint validate conftest record-conftest-fixtures check-target check-env-id check-operator-cidr check-plan-file render-localstack-backend check-localstack-read localstack-state-list localstack-show-json localstack-output placeholder-build check-placeholder-image check-vhs demo print-preview-root print-target lease-list lease-get close

TARGET ?=
# preflight and terraform must check the same account and region
AWS_PROFILE ?= orbit
AWS_REGION ?= us-east-1

ifeq ($(TARGET),localstack)
PREVIEW_ROOT ?= .preview-runs/$(ENV_ID)
else
PREVIEW_ROOT ?= envs/preview
endif
PLAN_FILE ?= $(CURDIR)/envs/preview/tfplan.bin
export TARGET ENV_ID OPERATOR_CIDR AWS_REGION PREVIEW_ROOT PLAN_FILE
ifneq ($(TARGET),localstack)
export AWS_PROFILE
endif

LOCALSTACK_AWS_ENV = env -u AWS_PROFILE -u AWS_SESSION_TOKEN -u AWS_SECURITY_TOKEN AWS_ENDPOINT_URL=http://localhost:4566 AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 AWS_EC2_METADATA_DISABLED=true

check-target:
	@case "$$TARGET" in \
		aws|localstack) ;; \
		*) echo "TARGET must be aws or localstack, got: $$TARGET" >&2; exit 1 ;; \
	esac

bootstrap-plan bootstrap-apply: check-target

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

# Requires bootstrap to have been applied to LocalStack so all three trust
# documents are known; the inventory generator enforces that prerequisite.
iam-matrix-plan:
	@plan_json="$$(mktemp "$${TMPDIR:-/tmp}/orbit-iam-matrix.XXXXXX")"; \
	trap 'rm -f "$$plan_json"' EXIT; \
	POLICY_SIZE_PLAN_JSON_OUT="$$plan_json" bootstrap/policy-size-check.sh; \
	bash tests/iam-matrix-contracts.sh "$$plan_json"

# LocalStack applies are disposable; real AWS keeps the interactive confirmation
ifeq ($(TARGET),localstack)
bootstrap-plan:
	cp bootstrap/localstack.backend_override.tf.example bootstrap/backend_override.tf; \
	$(LOCALSTACK_AWS_ENV) TF_DATA_DIR=.terraform-localstack terraform -chdir=bootstrap init -reconfigure -input=false && \
	$(LOCALSTACK_AWS_ENV) TF_DATA_DIR=.terraform-localstack terraform -chdir=bootstrap plan -var "target=$$TARGET" -var budget_email=unused; \
	rc=$$?; rm -f bootstrap/backend_override.tf; exit $$rc

bootstrap-apply:
	cp bootstrap/localstack.backend_override.tf.example bootstrap/backend_override.tf; \
	$(LOCALSTACK_AWS_ENV) TF_DATA_DIR=.terraform-localstack terraform -chdir=bootstrap init -reconfigure -input=false && \
	$(LOCALSTACK_AWS_ENV) TF_DATA_DIR=.terraform-localstack terraform -chdir=bootstrap apply -var "target=$$TARGET" -var budget_email=unused -auto-approve; \
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
# directory. State itself uses the emulator's versioned state bucket at the
# same envs/preview/<env_id>.tfstate key layout as AWS.
render-localstack-backend:
	mkdir -p "$$PREVIEW_ROOT"
	rsync -a --delete --exclude '.terraform/' --exclude '.terraform-localstack*/' --exclude 'backend_override.tf' --exclude '*.tfstate*' envs/preview/ "$$PREVIEW_ROOT/"
	awk -v id="$$ENV_ID" '{ gsub(/ENV_ID_PLACEHOLDER/, id); print }' envs/preview/localstack.backend_override.tf.example > "$$PREVIEW_ROOT/backend_override.tf"

check-localstack-read: check-target check-env-id
	@if [ "$$TARGET" != localstack ]; then echo "LocalStack state reads require TARGET=localstack" >&2; exit 1; fi

localstack-state-list localstack-show-json localstack-output: check-localstack-read

localstack-state-list:
	@$(LOCALSTACK_AWS_ENV) TF_DATA_DIR=.terraform-localstack terraform -chdir="$$PREVIEW_ROOT" state list

localstack-show-json:
	@$(LOCALSTACK_AWS_ENV) TF_DATA_DIR=.terraform-localstack terraform -chdir="$$PREVIEW_ROOT" show -json

localstack-output:
	@if [ -z "$$TF_OUTPUT" ]; then echo "TF_OUTPUT is required" >&2; exit 1; fi
	@$(LOCALSTACK_AWS_ENV) TF_DATA_DIR=.terraform-localstack terraform -chdir="$$PREVIEW_ROOT" output -raw "$$TF_OUTPUT"

plan:
	( \
		$(MAKE) render-localstack-backend && \
		$(LOCALSTACK_AWS_ENV) TF_DATA_DIR=.terraform-localstack terraform -chdir="$$PREVIEW_ROOT" init -reconfigure -input=false && \
		$(LOCALSTACK_AWS_ENV) TF_DATA_DIR=.terraform-localstack terraform -chdir="$$PREVIEW_ROOT" plan -var "target=$$TARGET" -var "env_id=$$ENV_ID" -var "operator_cidr=$$OPERATOR_CIDR" -var "region=$$AWS_REGION"; \
	)

apply: check-placeholder-image
	( \
		$(MAKE) render-localstack-backend && \
		$(LOCALSTACK_AWS_ENV) TF_DATA_DIR=.terraform-localstack terraform -chdir="$$PREVIEW_ROOT" init -reconfigure -input=false && \
		$(LOCALSTACK_AWS_ENV) TF_DATA_DIR=.terraform-localstack terraform -chdir="$$PREVIEW_ROOT" apply -var "target=$$TARGET" -var "env_id=$$ENV_ID" -var "operator_cidr=$$OPERATOR_CIDR" -var "region=$$AWS_REGION" -auto-approve; \
	)

destroy:
	( \
		$(MAKE) render-localstack-backend && \
		$(LOCALSTACK_AWS_ENV) TF_DATA_DIR=.terraform-localstack terraform -chdir="$$PREVIEW_ROOT" init -reconfigure -input=false && \
		$(LOCALSTACK_AWS_ENV) TF_DATA_DIR=.terraform-localstack terraform -chdir="$$PREVIEW_ROOT" destroy -var "target=$$TARGET" -var "env_id=$$ENV_ID" -var "operator_cidr=$$OPERATOR_CIDR" -var "region=$$AWS_REGION" -auto-approve; \
	)
else
plan apply destroy: check-target check-env-id check-operator-cidr

check-env-id:
	@if [ -z "$$ENV_ID" ]; then echo "ENV_ID is required, e.g. make plan TARGET=localstack ENV_ID=dev" >&2; exit 1; fi
	@printf '%s' "$$ENV_ID" | grep -Eq '^[a-z0-9]([a-z0-9-]{0,10}[a-z0-9])?$$' || { echo "ENV_ID must match ^[a-z0-9]([a-z0-9-]{0,10}[a-z0-9])?\$$, got: $$ENV_ID" >&2; exit 1; }

# backend.aws.hcl is generated by scripts/write-preview-backend.sh and is not
# committed; it is resolved as an absolute path since terraform
# -chdir=envs/preview resolves -backend-config paths relative to
# envs/preview, not to $(CURDIR).
BACKEND_HCL ?= $(CURDIR)/envs/preview/backend.aws.hcl
export BACKEND_HCL

check-backend-hcl:
	@if [ ! -f "$(BACKEND_HCL)" ]; then \
		echo "envs/preview/backend.aws.hcl is required; run scripts/write-preview-backend.sh" >&2; \
		exit 1; \
	fi
	@if [ -f envs/preview/backend_override.tf ]; then \
		echo "LocalStack override present; remove envs/preview/backend_override.tf before targeting aws" >&2; \
		exit 1; \
	fi

plan: check-backend-hcl
	terraform -chdir=envs/preview init -reconfigure -input=false -backend-config="$$BACKEND_HCL" -backend-config="key=envs/preview/$$ENV_ID.tfstate"
	terraform -chdir=envs/preview plan -input=false -out="$$PLAN_FILE" -var "target=$$TARGET" -var "env_id=$$ENV_ID" -var "operator_cidr=$$OPERATOR_CIDR" -var "region=$$AWS_REGION"

check-plan-file:
	@if [ ! -f "$$PLAN_FILE" ]; then echo "saved Terraform plan is required at $$PLAN_FILE; run make plan first" >&2; exit 1; fi

apply: check-backend-hcl check-plan-file
	terraform -chdir=envs/preview init -reconfigure -input=false -backend-config="$$BACKEND_HCL" -backend-config="key=envs/preview/$$ENV_ID.tfstate"
	terraform -chdir=envs/preview apply -input=false "$$PLAN_FILE"

destroy: check-backend-hcl
	terraform -chdir=envs/preview init -reconfigure -backend-config="$$BACKEND_HCL" -backend-config="key=envs/preview/$$ENV_ID.tfstate"
	terraform -chdir=envs/preview destroy -var "target=$$TARGET" -var "env_id=$$ENV_ID" -var "operator_cidr=$$OPERATOR_CIDR" -var "region=$$AWS_REGION"
endif

test:
	@bash tests/sweeper.sh
	@bash tests/cleanup-verifier.sh
	@bash tests/phase3-contracts.sh
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
				rsync -a --delete --exclude '.terraform/' --exclude '.terraform-localstack*/' --exclude 'backend_override.tf' --exclude '*.tfstate*' "$$d" "$$run_dir/"; \
				[ -f "$$run_dir/.terraform.lock.hcl" ] || { echo "missing committed provider lock file in $$run_dir" >&2; exit 1; }; \
				$(LOCALSTACK_AWS_ENV) TF_DATA_DIR=.terraform-localstack terraform -chdir="$$run_dir" init -backend=false -input=false >/dev/null && \
				$(LOCALSTACK_AWS_ENV) TF_DATA_DIR=.terraform-localstack terraform -chdir="$$run_dir" test; \
			) || exit $$?; \
		fi; \
	done

conftest:
	conftest verify --policy policy/
	bash tests/conftest-gate.sh

record-conftest-fixtures:
	@for name in good bad; do \
		root="tests/fixtures/conftest/$${name}-root"; \
		plan_file="$$root/plan.tfplan"; \
		output_file="tests/fixtures/conftest/$${name}-plan.json"; \
		temp_file="$$(mktemp "$${TMPDIR:-/tmp}/orbit-conftest-$${name}.XXXXXX")" || exit $$?; \
		rc=0; \
		env -u AWS_PROFILE AWS_ENDPOINT_URL=http://localhost:4566 AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 \
			terraform -chdir="$$root" init -input=false -upgrade=false && \
		env -u AWS_PROFILE AWS_ENDPOINT_URL=http://localhost:4566 AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 \
			terraform -chdir="$$root" plan -input=false -out=plan.tfplan && \
		env -u AWS_PROFILE AWS_ENDPOINT_URL=http://localhost:4566 AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 \
			terraform -chdir="$$root" show -json plan.tfplan > "$$temp_file" || rc=$$?; \
		if [ "$$rc" -eq 0 ]; then scripts/fixture-hygiene.sh "$$temp_file" || rc=$$?; fi; \
		if [ "$$rc" -eq 0 ]; then mv "$$temp_file" "$$output_file" || rc=$$?; fi; \
		rm -f "$$plan_file" "$$temp_file"; \
		[ "$$rc" -eq 0 ] || exit "$$rc"; \
	done

test-concurrency: check-target
	@if [ "$$TARGET" != localstack ]; then echo "test-concurrency requires TARGET=localstack" >&2; exit 1; fi
	@bash tests/localstack-concurrency.sh

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
lease-list: check-target
	$(if $(filter localstack,$(TARGET)),$(LOCALSTACK_AWS_ENV) ,)scripts/lease.sh list

lease-get: check-target check-env-id
	$(if $(filter localstack,$(TARGET)),$(LOCALSTACK_AWS_ENV) ,)scripts/lease.sh get "$$ENV_ID"

# TARGET is required; localstack routes every cleanup AWS call to the explicit endpoint.
close: check-target check-env-id
ifeq ($(TARGET),localstack)
close: render-localstack-backend
	$(LOCALSTACK_AWS_ENV) scripts/close-env.sh "$$ENV_ID"
else
close:
	scripts/close-env.sh "$$ENV_ID"
endif

check-vhs:
	@command -v vhs >/dev/null || { echo "vhs is required: brew install vhs" >&2; exit 1; }

print-preview-root:
	@printf '%s\n' "$(PREVIEW_ROOT)"

print-target:
	@printf '%s\n' "$(TARGET)"

# Records docs/assets/demo.gif from demo/demo.tape against LocalStack. Local, on-demand only.
# Usage: OPERATOR_CIDR=203.0.113.0/24 make demo
demo: check-vhs
	env -u PREVIEW_ROOT -u TARGET -u ENV_ID -u PLAN_FILE bash demo/record.sh
