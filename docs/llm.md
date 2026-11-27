# Self-hosted Inkling 2 Mini on Tycho (Aperture + Tailscale Services)

Tycho self-hosts Thinking Machines Lab's **Inkling 2 Mini** (`inkling-2-mini`)
using `llama.cpp` v1.1.0 with the Vulkan (RADV) backend and publishes its
OpenAI-compatible endpoint over the tailnet as `svc:llm`
(`https://llm.tailf3d82.ts.net`) for **Tailscale Aperture**.

## Model and hardware configuration

- **Hardware:** Framework Desktop (AMD Ryzen AI Max+ 395 / Radeon 8060S
  `gfx1151`, 64 GB unified RAM, 1 TB NVMe).
- **Unified memory pool:** `hosts/tycho/hardware.nix` enables
  `hardware.graphics` and configures a 44 GiB dynamic GTT/TTM pool
  (`amd_iommu=off`, `amdgpu.gttsize=45056`, `ttm.pages_limit=11534336`,
  `ttm.page_pool_size=11534336`). This leaves ~20 GiB for the OS, BookOrbit,
  Home Assistant, Grafana, and InfluxDB. Keep the BIOS iGPU UMA reservation small
  (e.g., `512 MB`) so memory stays dynamically shared when inference is idle.
- **Model files (`unsloth/Inkling-2-Mini-GGUF`):**
  - `Inkling-2-Mini-UD-Q8_K_XL.gguf` (~22.9 GB, 8-bit dynamic quantization)
  - `mmproj-F16.gguf` (~639 MB, multimodal vision projector)
- **Inference server (`modules/nixos/llm/default.nix`):**
  - `llama-server` built from `llama.cpp` v1.1.0 with Vulkan support
  - Bound to loopback only (`127.0.0.1:8080`), `--alias inkling-2-mini`,
    `--ctx-size 262144`, `--parallel 3`, `--kv-unified` (overriding the module
    defaults of `ctxSize = 65536` / `parallel = 1` in `hosts/tycho/llm.nix`),
    `--n-gpu-layers 99`, `--device Vulkan0`, `--load-mode none`,
    `--flash-attn on`, `--jinja`, and `GGML_VK_ALLOW_GRAPHICS_QUEUE=1`.
  - Uses `ConditionPathExists` so Tycho boots cleanly even before weights are
    downloaded.

## Deploy on Tycho

1. Rebuild and activate Tycho using the [remote rebuild procedure](../README.md#build-and-update-the-servers).
   The first build compiles `llama.cpp` v1.1.0 with Vulkan support on Tycho.
2. Reboot Tycho once so the `amdgpu.gttsize` and `ttm.pages_limit` kernel
   parameters take effect, then verify the expanded pool:

   ```sh
   cat /sys/module/ttm/parameters/pages_limit
   ```

   Expect `11534336`.

## Download weights and start `llama-cpp`

Run the Nix-provided fetch helper on Tycho to download and verify the pinned
SHA-256 checksums into `/var/lib/llama-cpp/models`:

```sh
sudo llm-fetch-models
sudo systemctl start llama-cpp
systemctl status llama-cpp
```

Verify the local OpenAI-compatible endpoints on Tycho:

```sh
curl -fsS http://127.0.0.1:8080/health
curl -fsS http://127.0.0.1:8080/v1/models
```

Port `8080` is loopback-only and must not be reachable from the LAN.

## Publish `svc:llm` and wire Tailscale Aperture

1. **Tailscale admin console (Services & Grants):**
   - Under **Services -> Advertise -> Define a Service**, create `llm` (`svc:llm`, ports `tcp:443` and `tcp:80`, allowing `tag:tycho-services`).
   - Approve the `tycho-services` host advertisement for `svc:llm` (`llm.tailf3d82.ts.net`, HTTPS 443 -> `127.0.0.1:8080`, HTTP 80 -> `127.0.0.1:8081`). If `svc:llm` was defined after `tailnet-services-publish` started, clear and re-advertise it on Tycho:

     ```sh
     sudo tailscale --socket=/run/tailnet-services/tailscaled.sock serve clear svc:llm
     sudo systemctl restart tailnet-services-publish.service
     ```

   - In **Access Controls**, add a `grants` rule allowing Aperture and your tailnet devices to reach `svc:llm`:

     ```json
     {
       "src": ["ncwade@github"],
       "dst": ["svc:llm"],
       "ip": ["tcp:80", "tcp:443"]
     }
     ```

   - From Luna or another tailnet device, verify the service endpoint (note: the first HTTPS request triggers ACME DNS-01 certificate issuance, which takes ~30 seconds before TLS is ready):

     ```sh
     curl -fsS https://llm.tailf3d82.ts.net/v1/models
     ```

2. **Aperture admin console (`/admin/settings/config` or Administration -> Providers):**
   Add Tycho as a private OpenAI-compatible provider (omit any trailing slash on
   `baseurl`, because Aperture appends `/v1/chat/completions`):

   ```json
   {
     "providers": {
       "tycho": {
         "baseurl": "https://llm.tailf3d82.ts.net",
         "models": ["inkling-2-mini"]
       }
     }
   }
   ```

3. **Aperture model grants and verification:**
   - Under **Administration -> Grants**, allow your tailnet identity/group to
     query `inkling-2-mini`.
   - Under **Administration -> Models**, click the test/play icon next to
     `inkling-2-mini` and confirm a passing response.

## Tuning and recovery

- **Speculative decoding (optional):** Set `personal.llm.dspark.enable = true;`
  in `hosts/tycho/llm.nix` to download `dspark-Inkling-2-Mini-Q8_0.gguf`
  (~504 MB) and enable `--spec-type draft-dspark --spec-draft-n-max 2`.
- **Quantization or context adjustments:** `personal.llm.modelFile` /
  `modelSha256` (e.g., switching to `Inkling-2-Mini-UD-Q4_K_XL.gguf` for faster
  generation and larger KV cache), `personal.llm.ctxSize`, `personal.llm.parallel`,
  and `personal.llm.kvUnified` can be changed in `hosts/tycho/llm.nix`.
- **Recovery:** Model weights in `/var/lib/llama-cpp/models` are intentionally
  excluded from NAS1 backups; on a replacement host, re-run `sudo llm-fetch-models`
  to re-download and SHA-256 verify them.

## Validation on 2026-11-27

- Offline NixOS test suites (`nas1`, `tycho`, `bookorbit`, `tailnet-services`) and `tests/tailnet-services-publish.py` passed.
- Deployed to Tycho with pre-change `/etc/nixos` backed up at `/var/lib/nixos-source-backups/llm-20261127T005830Z`.
- Post-reboot kernel pool verified: `ttm.pages_limit = 11534336`, `mem_info_gtt_total = 47244640256` (~44 GiB), `Vulkan0: AMD Radeon 8060S Graphics (RADV STRIX_HALO) (45568 MiB)`.
- `Inkling-2-Mini-UD-Q8_K_XL.gguf` and `mmproj-F16.gguf` SHA-256 verified and loaded in `llama-cpp.service` (`llama.cpp v1.1.0`, `n_ctx = 65536`, multimodal enabled).
- Verified end-to-end over `https://llm.tailf3d82.ts.net` (Let's Encrypt cert, HTTP 308 redirect, `/health`, `/v1/models`, `/v1/chat/completions`) and through Aperture (`http://aperture.tailf3d82.ts.net/v1/chat/completions`, `HTTP 200`, ~24 tok/s), with BookOrbit, Grafana, and Home Assistant healthy and `0` failed systemd units.
- Raised context to `256K` (`n_ctx = 262144`) with `parallel = 3` and `--kv-unified` (pre-change `/etc/nixos` backed up at `/var/lib/nixos-source-backups/llm-20261127T183955Z`): `/props` and `/slots` report `n_ctx = 262144` across all 3 slots, GTT reached ~33.94 GiB / 44.00 GiB under 3-way concurrent `/v1/chat/completions` requests with 24 GiB host RAM available, and `0` failed systemd units.
