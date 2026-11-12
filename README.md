# Local LLMs on a CPU-only laptop: weight and KV-cache quantization

This repository belongs to my seminar paper "Running Local Large Language Models on a CPU-Only Laptop: Effects of Weight and KV-Cache Quantization" (Seminar STOIS 2026/2027, Master Intelligent Systems, Technische Hochschule Ulm).

It contains the scripts, the question set and the raw results of my experiments.

## Test setup

- Laptop without a dedicated GPU: Intel Core i7-1165G7, 16 GB DDR4-3200 (single channel), Windows 11
- All models ran on the CPU
- Ollama 0.40.15
- Settings for all requests: temperature 0, seed 42
- Before every test: charger connected, Windows power mode "Best performance", other programs closed, only one model loaded (checked with `ollama ps`)

## Models

| Model family | FP16 | Q8_0 | Q4_K_M |
|---|---|---|---|
| Llama 3.2 3B (Meta) | `llama3.2:3b-instruct-fp16` | `llama3.2:3b-instruct-q8_0` | `llama3.2:3b` |
| Qwen2.5 3B (Alibaba) | `qwen2.5:3b-instruct-fp16` | `qwen2.5:3b-instruct-q8_0` | `qwen2.5:3b-instruct-q4_K_M` |
| Gemma 3 4B (Google) | `gemma3:4b-it-fp16` | `gemma3:4b-it-q8_0` | `gemma3:4b-it-q4_K_M` |

## Folders

| Folder | Content |
|---|---|
| `scripts/` | The three PowerShell scripts used for the tests |
| `questions/` | The 10 accuracy questions with the correct answers |
| `results/raw/` | The original output files of the scripts (not changed after the tests) |
| `results/Results_Log.txt` | All results in tables, with notes |

## Experiment A: weight quantization

Each of the 9 models was tested with two scripts. The context length was 4096 tokens.

**Speed and memory** (`run_speed.ps1`)

```powershell
.\scripts\run_speed.ps1 -Model "llama3.2:3b"
```

- Sends the same question three times: "List the eight planets of the solar system in order from the Sun, and give one short fact about each."
- Ollama returns the number of tokens and the time in nanoseconds. The script divides the tokens by the time in seconds to get tokens per second.
- Saves the average generation speed and the sample standard deviation.
- Reads the memory of the loaded model from Ollama (`/api/ps`, same as `ollama ps`). 1 GB = 10^9 bytes.

**Accuracy** (`run_accuracy.ps1`)

```powershell
.\scripts\run_accuracy.ps1 -Model "llama3.2:3b"
```

- Sends 10 questions, each as a separate request.
- Adds "Answer with only the final answer, no explanation." before each question.
- Marks each answer as "OK" or "BAD" by checking if it contains the correct answer.

## Experiment B: KV-cache quantization

Only `llama3.2:3b` (Q4_K_M) was used. The cache type is a setting of the Ollama server, so the server has to be started by hand before the script:

```powershell
$env:OLLAMA_FLASH_ATTENTION = "1"
$env:OLLAMA_KV_CACHE_TYPE = "q8_0"   # or f16 / q4_0
ollama serve
```

Then, in a second window:

```powershell
.\scripts\run_kv.ps1 -KvType q8_0
```

- Tests the context lengths 4096, 8192 and 16384 tokens.
- A long prompt of numbered sentences fills about half of the context. Then 64 tokens are generated.
- The model is unloaded after each test.
- Each setup was run once, because one test took up to 47 minutes.
- The q4_0 test at 16384 tokens was run later in a separate session (file `kv_llama3.2_3b_q4_0.txt`). The q4_0 tests at 4096 and 8192 are in `kv_llama3.2_3b_q4_0_4096-8192.txt`.

## Notes

- The scripts save their output files in the same folder as the script.
- The results are from one laptop only. They can be different on other hardware.
