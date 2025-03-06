list:
  just --list

# Recipe for running uvx with vllm configuration
uvx-vllm +args:
  uvx --with setuptools \
    --with vllm --extra-index-url https://wheels.vllm.ai/nightly \
    --with https://github.com/flashinfer-ai/flashinfer/releases/download/v0.2.2.post1/flashinfer_python-0.2.2.post1+cu124torch2.5-cp38-abi3-linux_x86_64.whl \
    {{args}}

# Recipe for running uvx with sglang configuration
uvx-sgl +args:
  #!/usr/bin/env bash
  uvx --with setuptools \
    --with 'transformers<4.49.0' \
    --with 'sglang[all]>=0.4.3.post2' \
    --find-links https://flashinfer.ai/whl/cu124/torch2.5/flashinfer-python \
    {{args}}

list-versions:
  just uvx-vllm vllm --version
  just uvx-sgl python -c "'import sglang; print(sglang.__version__)'"

# Clone only the benchmarks directory from vllm repository
clone-vllm-benchmarks target_dir="vllm-benchmarks":
  #!/usr/bin/env bash
  set -euo pipefail
  rm -rf {{target_dir}}
  git clone --filter=blob:none --no-checkout https://github.com/vllm-project/vllm.git {{target_dir}}
  cd {{target_dir}}
  git sparse-checkout init --no-cone
  echo "benchmarks/**" > .git/info/sparse-checkout
  git checkout

serve-vllm:
  VLLM_USE_V1=1 VLLM_ATTENTION_BACKEND=FLASHMLA VLLM_USE_FLASHINFER_SAMPLER=1 \
    just uvx-vllm vllm serve /home/vllm-dev/DeepSeek-R1 \
      --tensor-parallel-size 8 \
      --trust-remote-code \
      --load-format dummy \
      --disable-log-requests

serve-sgl:
  just uvx-sgl python -m sglang.launch_server \
    --model /home/vllm-dev/DeepSeek-R1 \
    --trust-remote-code \
    --tp 8 \
    --enable-flashinfer-mla

run-scenario backend="vllm" input_len="100" output_len="100" port="8000" model="/home/vllm-dev/DeepSeek-R1":
    python vllm-benchmarks/benchmarks/benchmark_serving.py \
    --model "{{model}}" \
    --port {{port}} \
    --dataset-name random --ignore-eos \
    --num-prompts 50 \
    --request-rate 10 \
    --random-input-len {{input_len}} --random-output-len {{output_len}} \
    --save-result \
    --result-dir results \
    --result-filename {{backend}}-{{input_len}}-{{output_len}}.json

run-sweeps backend="vllm" port="8000" model="/home/vllm-dev/DeepSeek-R1":
  just run-scenario {{backend}} "1000" "1000" {{port}} {{model}}
  just run-scenario {{backend}} "5000" "1000" {{port}} {{model}}
  just run-scenario {{backend}} "10000" "1000" {{port}} {{model}}
  just run-scenario {{backend}} "32000" "1000" {{port}} {{model}}

show-results:
  uvx --with rich --with pandas python extract-result.py