# Oh My Pi configuration

## Luna startup thinking level

Observed with OMP 18.0.6.

### Desired behavior

A fresh `omp` invocation should select `instacart-openai/gpt-5.6-luna` at `xhigh` effort. Sol and Terra should remain at `high` when selected.

### Configuration

In `~/.omp/agent/config.yml`, keep Luna first in `enabledModels` and make its effort match the default role:

```yaml
enabledModels:
  - instacart-openai/gpt-5.6-luna:xhigh
  - instacart-openai/gpt-5.6-sol:high
  - instacart-openai/gpt-5.6-terra:high

modelRoles:
  default: instacart-openai/gpt-5.6-luna:xhigh

defaultThinkingLevel: xhigh
```

In `~/.omp/agent/models.yml`, Luna's model-level fallback default is:

```yaml
providers:
  instacart-openai:
    models:
      - id: gpt-5.6-luna
        thinking:
          mode: effort
          efforts:
            - low
            - medium
            - high
            - xhigh
            - max
          defaultLevel: xhigh
```

### Why ordering matters

`enabledModels` is both an allow-list/order and a source of per-model thinking levels. During startup, OMP seeds the initial thinking level from the first explicitly suffixed `enabledModels` entry. This can happen even when `modelRoles.default` selects a different model.

The previous order began with `instacart-openai/gpt-5.6-sol:high`. OMP selected Luna as the default model but seeded its startup effort from Sol, so the status line showed Luna at `high`.

Moving `instacart-openai/gpt-5.6-luna:xhigh` to the first position fixed startup while preserving `high` for Sol and Terra when they are selected.

Invariant: the first `enabledModels` entry should match `modelRoles.default`, including its thinking suffix.

### Should `enabledModels` include thinking suffixes?

Yes, when models should use different effort defaults during model cycling. Removing the suffixes would cause the global `defaultThinkingLevel: xhigh` to apply to the scoped models, making Sol and Terra use `xhigh` as well.

The model-level `thinking.defaultLevel` is a fallback. The explicit `enabledModels` and role suffixes control this startup path.

### Verification

After changing the configuration, launch a completely new `omp` process. The status line should show GPT-5.6 Luna at `xhigh`. After sending a prompt, the new session JSONL under `~/.omp/agent/sessions/` should begin with entries equivalent to:

```json
{"type":"model_change","model":"instacart-openai/gpt-5.6-luna"}
{"type":"thinking_level_change","thinkingLevel":"xhigh"}
```
