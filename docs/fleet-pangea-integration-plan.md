# Fleet + Pangea: Declarative DAG Infrastructure Orchestration

## Vision

Pangea becomes a Fleet backend. Infrastructure is never parameterized via CLI.
Everything is config-driven (shikumi pattern: Nix → YAML → Rust/Ruby).
Fleet's DAG flow system orchestrates Pangea templates with data passing between them.

```
Nix options → fleet.yaml (flows + pangea config) → Fleet CLI (DAG executor)
  → per-step: Pangea compile → OpenTofu plan/apply → output capture
  → next step receives previous outputs via terraform_remote_state
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Nix Layer                                 │
│  substrate/lib/infra/fleet-pangea-flake.nix                      │
│  - Generates fleet.yaml from typed Nix options                   │
│  - Wraps pangea + opentofu + fleet into nix run apps             │
│  - SDLC: validate / plan / apply / cycle / drift / destroy       │
└────────────────────────┬────────────────────────────────────────┘
                         │ fleet.yaml
┌────────────────────────▼────────────────────────────────────────┐
│                     Fleet (Rust)                                 │
│  New ActionDef variant: Pangea(PangeaActionDef)                  │
│  - compile: pangea plan --show-compiled → main.tf.json           │
│  - plan: tofu plan → plan.tfplan                                 │
│  - apply: tofu apply → outputs.json                              │
│  - Captures outputs → injects as config into downstream steps    │
│  - DAG validation: topo_levels() for parallel execution          │
│  - Conditions: skip steps based on output values                 │
└────────────────────────┬────────────────────────────────────────┘
                         │ per-step
┌────────────────────────▼────────────────────────────────────────┐
│                    Pangea (Ruby)                                  │
│  template :name do ... end                                       │
│  - Typed resource functions (pangea-aws, pangea-akeyless, etc.)  │
│  - Reads config from fleet-injected YAML                         │
│  - Compiles to main.tf.json                                      │
│  - terraform_remote_state for cross-template data                │
└────────────────────────┬────────────────────────────────────────┘
                         │ main.tf.json
┌────────────────────────▼────────────────────────────────────────┐
│                   OpenTofu                                        │
│  - init / plan / apply / destroy                                 │
│  - State per template (S3 or local)                              │
│  - Outputs captured by Fleet for downstream injection            │
└─────────────────────────────────────────────────────────────────┘
```

## Data Flow Between Templates

Today Pangea uses `terraform_remote_state` for cross-template data:

```ruby
# Template B reads outputs from Template A
data :terraform_remote_state, :permissions do
  backend "s3"
  config do
    bucket "zek-dev-terraform-state"
    key "pangea/development/k3s_node_role/terraform.tfstate"
    region "us-east-1"
  end
end

resource :aws_instance, :server do
  iam_instance_profile "${data.terraform_remote_state.permissions.outputs.instance_profile_name}"
end
```

With Fleet, this becomes **automatic** — Fleet captures outputs from step A and
injects the state backend coordinates into step B's config. No manual
`terraform_remote_state` blocks needed.

## fleet.yaml Extension

```yaml
# fleet.yaml — infrastructure flows
flows:
  k3s-dev-cluster:
    description: "Full K3s dev cluster in Akeyless dev account"
    steps:
      - id: permissions
        action:
          pangea:
            file: k3s_permissions.rb
            template: k3s_node_role
            namespace: development
        # No depends_on — runs first

      - id: network
        action:
          pangea:
            file: k3s_networking.rb
            template: k3s_network
            namespace: development
        # No depends_on — runs in parallel with permissions

      - id: storage
        action:
          pangea:
            file: k3s_storage.rb
            template: k3s_etcd_backup
            namespace: development
        depends_on: []  # Independent

      - id: compute
        action:
          pangea:
            file: k3s_compute.rb
            template: k3s_nodes
            namespace: development
            # Fleet auto-injects upstream outputs:
            inputs_from:
              - permissions  # Gets instance_profile_name, role_arn
              - network      # Gets vpc_id, subnet_ids, sg_id
              - storage      # Gets bucket_name
        depends_on:
          - permissions
          - network
          - storage

      - id: verify
        action:
          pangea:
            file: k3s_verify.rb
            template: k3s_health_check
            namespace: development
            inputs_from:
              - compute  # Gets instance_ids, server_ip
        depends_on:
          - compute
        condition: "test -n \"$PANGEA_VERIFY\""

  k3s-dev-destroy:
    description: "Destroy K3s dev cluster (reverse order)"
    steps:
      - id: compute
        action:
          pangea:
            file: k3s_compute.rb
            template: k3s_nodes
            namespace: development
            operation: destroy

      - id: storage
        action:
          pangea:
            file: k3s_storage.rb
            template: k3s_etcd_backup
            namespace: development
            operation: destroy
        depends_on: [compute]

      - id: network
        action:
          pangea:
            file: k3s_networking.rb
            template: k3s_network
            namespace: development
            operation: destroy
        depends_on: [compute]

      - id: permissions
        action:
          pangea:
            file: k3s_permissions.rb
            template: k3s_node_role
            namespace: development
            operation: destroy
        depends_on: [network, storage]
```

## Fleet Rust Changes

### New ActionDef variant

```rust
// src/config.rs
#[derive(Debug, Deserialize)]
pub enum ActionDef {
    // ... existing variants ...
    #[serde(rename = "pangea")]
    Pangea(PangeaActionDef),
}

#[derive(Debug, Deserialize)]
pub struct PangeaActionDef {
    pub file: String,
    pub template: Option<String>,
    pub namespace: String,
    #[serde(default = "default_operation")]
    pub operation: PangeaOperation,  // plan, apply, destroy
    pub inputs_from: Option<Vec<String>>,  // step IDs for data passing
}

#[derive(Debug, Deserialize, Default)]
pub enum PangeaOperation {
    #[default]
    Apply,
    Plan,
    Destroy,
}
```

### New Pangea executor

```rust
// src/pangea.rs
pub struct PangeaExecutor {
    working_dir: PathBuf,
    pangea_bin: PathBuf,
    tofu_bin: PathBuf,
}

impl PangeaExecutor {
    /// Compile template to Terraform JSON
    pub fn compile(&self, action: &PangeaActionDef) -> Result<PathBuf> {
        let mut cmd = Command::new(&self.pangea_bin);
        cmd.arg("plan").arg(&action.file)
           .arg("--namespace").arg(&action.namespace)
           .arg("--show-compiled");
        if let Some(template) = &action.template {
            cmd.arg("--template").arg(template);
        }
        // ... execute, capture JSON output, write to workspace
    }

    /// Run tofu plan/apply/destroy
    pub fn execute(&self, action: &PangeaActionDef, workspace: &Path) -> Result<PangeaOutput> {
        match action.operation {
            PangeaOperation::Plan => self.tofu_plan(workspace),
            PangeaOperation::Apply => self.tofu_apply(workspace),
            PangeaOperation::Destroy => self.tofu_destroy(workspace),
        }
    }

    /// Capture terraform outputs for downstream injection
    pub fn capture_outputs(&self, workspace: &Path) -> Result<HashMap<String, Value>> {
        let output = Command::new(&self.tofu_bin)
            .args(["output", "-json"])
            .current_dir(workspace)
            .output()?;
        serde_json::from_slice(&output.stdout)
    }
}
```

### Flow executor changes

```rust
// src/flow.rs — extend execute_step
async fn execute_step(step: &StepDef, upstream_outputs: &StepOutputs) -> Result<StepResult> {
    match &step.action {
        ActionDef::Pangea(pangea_action) => {
            let executor = PangeaExecutor::new(working_dir, pangea_bin, tofu_bin);

            // Inject upstream outputs as env vars or config
            if let Some(inputs) = &pangea_action.inputs_from {
                for input_step in inputs {
                    let outputs = upstream_outputs.get(input_step)?;
                    // Write outputs to a YAML file that the template can read
                    // Or inject as environment variables
                }
            }

            // Compile → Plan/Apply → Capture outputs
            let workspace = executor.compile(pangea_action)?;
            let result = executor.execute(pangea_action, &workspace)?;

            if matches!(pangea_action.operation, PangeaOperation::Apply) {
                let outputs = executor.capture_outputs(&workspace)?;
                Ok(StepResult::success_with_outputs(outputs))
            } else {
                Ok(StepResult::success())
            }
        }
        // ... existing action handlers
    }
}
```

## Nix/Substrate Layer

### fleet-pangea-flake.nix (new substrate pattern)

```nix
# substrate/lib/infra/fleet-pangea-flake.nix
{ nixpkgs, ruby-nix, flake-utils, substrate, forge, fleet }:
{ self, name }:

flake-utils.lib.eachSystem ["aarch64-darwin" "x86_64-linux"] (system:
  let
    pkgs = import nixpkgs { inherit system; };
    pangeaPkg = /* pangea gem environment */;
    fleetPkg = fleet.packages.${system}.default;
    tofuPkg = pkgs.opentofu;

    # Wrap everything: fleet + pangea + tofu in PATH
    wrappedFleet = pkgs.writeShellScriptBin "fleet-pangea" ''
      export PATH="${pangeaPkg}/bin:${tofuPkg}/bin:${fleetPkg}/bin:$PATH"
      exec fleet "$@"
    '';

    mkApp = command: {
      type = "app";
      program = toString (pkgs.writeShellScript "${name}-${command}" ''
        set -euo pipefail
        export PATH="${pangeaPkg}/bin:${tofuPkg}/bin:${fleetPkg}/bin:$PATH"
        cd "${self}"
        fleet flow run ${command} "$@"
      '');
    };
  in {
    packages.default = wrappedFleet;
    devShells.default = pkgs.mkShell {
      buildInputs = [ wrappedFleet pangeaPkg tofuPkg ];
    };
    apps = {
      # Full lifecycle
      plan     = mkApp "k3s-dev-plan";
      apply    = mkApp "k3s-dev-cluster";
      destroy  = mkApp "k3s-dev-destroy";
      validate = mkApp "k3s-dev-validate";

      # Individual layers
      plan-permissions = mkApp "k3s-permissions-only";
      plan-network     = mkApp "k3s-network-only";
      plan-compute     = mkApp "k3s-compute-only";
    };
  }
);
```

### Usage (zero CLI parameterization)

```bash
# Everything from config — no flags needed
nix run .#apply          # Full DAG: permissions → network → storage → compute → verify
nix run .#destroy        # Reverse DAG: compute → storage,network → permissions
nix run .#plan           # Dry run of full DAG
nix run .#validate       # RSpec synthesis tests only

# Individual layers (for debugging)
nix run .#plan-permissions
nix run .#plan-network

# Flow listing
fleet flow list          # Show all defined flows
fleet flow show k3s-dev-cluster  # Show DAG with dependencies
```

## Implementation Phases

### Phase 1: Fleet Pangea Action (Rust)
1. Add `PangeaActionDef` to Fleet's `ActionDef` enum
2. Implement `PangeaExecutor` (compile → plan/apply → capture outputs)
3. Add `inputs_from` support for cross-step data passing
4. Add `StepResult` with outputs hashmap
5. Tests: unit tests for DAG validation with pangea steps

### Phase 2: Cross-Template Data Flow
1. Implement output capture: `tofu output -json`
2. Write upstream outputs to YAML file per step
3. Templates read from `FLEET_STEP_INPUTS` env var or injected config
4. Auto-generate `terraform_remote_state` blocks from `inputs_from`
5. Tests: integration test with 2-step flow (A outputs → B inputs)

### Phase 3: Substrate SDLC Wrappers
1. Create `fleet-pangea-flake.nix` in substrate
2. Wrap fleet + pangea + tofu into single derivation
3. Generate nix run apps from fleet.yaml flows
4. Add gated pattern: RSpec tests before any plan/apply
5. Tests: nix eval tests for flake outputs

### Phase 4: Config-Only Orchestration
1. Shikumi pattern: Nix options → fleet.yaml
2. No CLI parameterization — everything from config
3. Environment promotion: dev → staging → prod via namespace
4. Flow listing: `fleet flow list`, `fleet flow show <name>`
5. Flow visualization: mermaid DAG output

### Phase 5: Beautiful Output + Export
1. Fleet step progress bars (indicatif)
2. Per-step timing and resource counts
3. JSON export of flow execution results
4. Mermaid DAG diagram generation
5. Integration with Datadog/observability

## Directory Structure for K3s Infra Project

```
k3s-infra/
├── flake.nix                    # Uses fleet-pangea-flake.nix
├── fleet.yaml                   # Flows + namespaces + secrets
├── pangea.yml                   # Pangea namespace/backend config
├── k3s_permissions.rb           # template :k3s_node_role
├── k3s_networking.rb            # template :k3s_network
├── k3s_storage.rb               # template :k3s_etcd_backup
├── k3s_compute.rb               # template :k3s_nodes
├── k3s_verify.rb                # template :k3s_health_check
├── Gemfile                      # gem 'pangea'
├── gemset.nix                   # Nix gem pins
└── spec/
    ├── architectures/           # Synthesis tests (Layer 2)
    └── security/                # Security invariants
```

## Key Design Principles

1. **Config-only** — No CLI parameterization. `fleet.yaml` + `pangea.yml` drive everything.
2. **DAG-native** — Templates are steps in a DAG. Dependencies are explicit.
3. **Data flows** — Upstream outputs automatically available to downstream steps.
4. **Parallel by default** — Independent steps run in parallel (Kahn's algorithm).
5. **Gated** — RSpec tests MUST pass before any cloud operation.
6. **Shikumi** — Nix → YAML → Rust/Ruby. No shell orchestration.
7. **Observable** — Every step has timing, resource counts, outputs.
8. **Reversible** — Destroy flows are the reverse DAG of apply flows.
