# Локальный voice-to-voice (смена голоса) на Seed-VC, zero-shot, speech-режим.
#
# Ставит обёртку `voice2voice` в systemPackages:
#   voice2voice -s <ваша запись> -t <референс голоса> -o <out.wav>
# Режим речи (f0_condition=False), озвучка/дубляж; пение не поддерживается этим модулем.
#
# Модели качаются в nix store при сборке (fetchurl, ~1.8 ГБ), а venv с torch+ROCm
# (~20 ГБ) создаётся при первом запуске в ~/.local/share/voice2voice.
{
  pkgs,
  lib,
  moduleConfig,
  ...
}:
let
  cfg = moduleConfig;

  python = pkgs.python312;

  # manylinux-колёса torch/torchaudio тянут системные библиотеки из окружения.
  ldPath = lib.makeLibraryPath [
    pkgs.gcc.cc.lib
    pkgs.zstd
    pkgs.zlib
    pkgs.ncurses
    pkgs.numactl
    pkgs.libdrm
  ];

  # --- Исходники Seed-VC (дают modules/, campplus_cn_common.bin) ------------
  seedvcSrc = builtins.fetchGit {
    url = "https://github.com/Plachtaa/Seed-VC.git";
    rev = cfg.seedvcRev;
  };

  # --- Веса моделей (pinned в nix store) ------------------------------------
  ditCheckpoint = pkgs.fetchurl {
    url = cfg.ditCheckpointUrl;
    sha256 = cfg.ditCheckpointHash;
  };

  ditConfig = pkgs.fetchurl {
    url = cfg.ditConfigUrl;
    sha256 = cfg.ditConfigHash;
  };

  ditF0Checkpoint = pkgs.fetchurl {
    url = cfg.ditF0CheckpointUrl;
    sha256 = cfg.ditF0CheckpointHash;
  };

  ditF0Config = pkgs.fetchurl {
    url = cfg.ditF0ConfigUrl;
    sha256 = cfg.ditF0ConfigHash;
  };

  rmvpe = pkgs.fetchurl {
    url = cfg.rmvpeUrl;
    sha256 = cfg.rmvpeHash;
  };

  # CAM++ уже лежит в исходниках Seed-VC (обычный git-blob, не LFS).
  campplusBin = "${seedvcSrc}/campplus_cn_common.bin";

  bigvganDir = pkgs.runCommand "bigvgan-22k-256x" { } ''
    mkdir -p $out
    cp ${pkgs.fetchurl {
      url = cfg.bigvganGeneratorUrl;
      sha256 = cfg.bigvganGeneratorHash;
    }} $out/bigvgan_generator.pt
    cp ${pkgs.fetchurl {
      url = cfg.bigvganConfigUrl;
      sha256 = cfg.bigvganConfigHash;
    }} $out/config.json
    chmod -R u+w $out
  '';

  bigvganF0Dir = pkgs.runCommand "bigvgan-44k-512x" { } ''
    mkdir -p $out
    cp ${pkgs.fetchurl {
      url = cfg.bigvganF0GeneratorUrl;
      sha256 = cfg.bigvganF0GeneratorHash;
    }} $out/bigvgan_generator.pt
    cp ${pkgs.fetchurl {
      url = cfg.bigvganF0ConfigUrl;
      sha256 = cfg.bigvganF0ConfigHash;
    }} $out/config.json
    chmod -R u+w $out
  '';

  whisperDir = pkgs.runCommand "whisper-small" { } ''
    mkdir -p $out
    cp ${pkgs.fetchurl {
      url = cfg.whisperModelUrl;
      sha256 = cfg.whisperModelHash;
    }} $out/model.safetensors
    cp ${pkgs.fetchurl {
      url = cfg.whisperConfigUrl;
      sha256 = cfg.whisperConfigHash;
    }} $out/config.json
    cp ${pkgs.fetchurl {
      url = cfg.whisperPreprocessorUrl;
      sha256 = cfg.whisperPreprocessorHash;
    }} $out/preprocessor_config.json
    cp ${pkgs.fetchurl {
      url = cfg.whisperGenerationUrl;
      sha256 = cfg.whisperGenerationHash;
    }} $out/generation_config.json
    chmod -R u+w $out
  '';

  # --- Внутренний скрипт: venv bootstrap + запуск inference ------------------
  inner = pkgs.writeShellScript "voice2voice-inner" ''
    set -euo pipefail
    CACHE="''${VOICE2VOICE_CACHE:-$HOME/.local/share/voice2voice}"
    VENV="$CACHE/venv"
    MARKER="$VENV/.complete"
    mkdir -p "$CACHE"

    # Маркер, а не проверка бинарника: прерванная установка даёт «ядовитый» venv,
    # который проходит проверку `[ -x python ]`, но падает на `import torch.sparse`.
    if [ ! -f "$MARKER" ]; then
      echo "[voice2voice] первый запуск: создаю venv и ставлю torch+torchaudio (ROCm) и зависимости (~20 ГБ, несколько минут)." >&2
      rm -rf "$VENV"
      ${python}/bin/python3.12 -m venv "$VENV"
      "$VENV/bin/pip" install -q --upgrade pip
      "$VENV/bin/pip" install -q \
        "torch==${cfg.torchVersion}" "torchaudio==${cfg.torchVersion}" \
        --index-url https://download.pytorch.org/whl/${cfg.torchChannel}
      "$VENV/bin/pip" install -q \
        "transformers==${cfg.transformersVersion}" \
        "huggingface-hub==${cfg.huggingfaceHubVersion}" \
        "librosa==${cfg.librosaVersion}" \
        "scipy==${cfg.scipyVersion}" \
        "numpy==${cfg.numpyVersion}" \
        "soundfile==${cfg.soundfileVersion}" \
        "munch==${cfg.munchVersion}" \
        "einops==${cfg.einopsVersion}" \
        "descript-audio-codec==${cfg.dacVersion}" \
        tqdm pyyaml
      touch "$MARKER"
    fi

    export LD_LIBRARY_PATH="${ldPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export HSA_OVERRIDE_GFX_VERSION="${cfg.gfxVersion}"
    export VOICE2VOICE_SRC="${seedvcSrc}"
    # модели локальные — запрещаем сетевые обращения к HF
    export HF_HUB_OFFLINE=1
    export TRANSFORMERS_OFFLINE=1
    export VOICE2VOICE_CHECKPOINT="${ditCheckpoint}"
    export VOICE2VOICE_CONFIG="${ditConfig}"
    export VOICE2VOICE_CHECKPOINT_F0="${ditF0Checkpoint}"
    export VOICE2VOICE_CONFIG_F0="${ditF0Config}"
    export VOICE2VOICE_CAMPLUS="${campplusBin}"
    export VOICE2VOICE_BIGVGAN_DIR="${bigvganDir}"
    export VOICE2VOICE_BIGVGAN_DIR_F0="${bigvganF0Dir}"
    export VOICE2VOICE_RMVPE="${rmvpe}"
    export VOICE2VOICE_WHISPER_DIR="${whisperDir}"
    # mp3/flac на входе читает librosa через audioread -> нужен ffmpeg
    PATH=${lib.makeBinPath [ pkgs.ffmpeg-headless ]}:$PATH \
      exec "$VENV/bin/python" "${./infer.py.in}" "$@"
  '';

  fhs = pkgs.buildFHSEnv {
    name = "voice2voice-env";
    targetPkgs = p: [ ];
    runScript = "${inner}";
  };

  voice2voice = pkgs.writeShellScriptBin "voice2voice" ''
    exec ${fhs}/bin/voice2voice-env "$@"
  '';
in
{
  customOptions = {
    user = lib.mkOption {
      type = lib.types.str;
      default = "filebin";
      description = "Пользователь, которому нужны группы render/video для /dev/kfd";
    };

    seedvcRev = lib.mkOption {
      type = lib.types.str;
      default = "51383efd921027683c89e5348211d93ff12ac2a8";
      description = "git-ревизия Plachtaa/Seed-VC (modules/ + campplus_cn_common.bin)";
    };

    ditCheckpointUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://huggingface.co/Plachta/Seed-VC/resolve/main/DiT_seed_v2_uvit_whisper_small_wavenet_bigvgan_pruned.pth";
      description = "DiT-чекпойнт (speech, whisper-small + wavenet)";
    };

    ditCheckpointHash = lib.mkOption {
      type = lib.types.str;
      default = "sha256-jsiEGyC7Rt+ffo5XCmlGpLh7lAEzx/DneEh/8zhB9yA=";
    };

    ditConfigUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://huggingface.co/Plachta/Seed-VC/resolve/main/config_dit_mel_seed_uvit_whisper_small_wavenet.yml";
      description = "Конфиг DiT (тот же, что качает inference.py из HF)";
    };

    ditConfigHash = lib.mkOption {
      type = lib.types.str;
      default = "sha256-J6kaxBvbQdC2lRxjZC15G0pw1gufxVUOtkX53cs8lNo=";
    };

    bigvganGeneratorUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://huggingface.co/nvidia/bigvgan_v2_22khz_80band_256x/resolve/main/bigvgan_generator.pt";
    };

    bigvganGeneratorHash = lib.mkOption {
      type = lib.types.str;
      default = "sha256-6VuiWXLT3gYo2ZzRVukxWpwBiJm/c5mIlZ6+NUQIDO0=";
    };

    bigvganConfigUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://huggingface.co/nvidia/bigvgan_v2_22khz_80band_256x/resolve/main/config.json";
    };

    bigvganConfigHash = lib.mkOption {
      type = lib.types.str;
      default = "sha256-iKH0es90fbCyHpejidg4VmFH96VGRYP/XI2BnYcPA+4=";
    };

    whisperModelUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://huggingface.co/openai/whisper-small/resolve/main/model.safetensors";
    };

    whisperModelHash = lib.mkOption {
      type = lib.types.str;
      default = "sha256-HXc0iEh08aFRPtmqdgpPjpeqoC/W2To6hdJ7KunKWWs=";
    };

    whisperConfigUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://huggingface.co/openai/whisper-small/resolve/main/config.json";
    };

    whisperConfigHash = lib.mkOption {
      type = lib.types.str;
      default = "sha256-5qK0idobWu1lqOuNHnRm+oZ61WQ6i8E4unCL1WsodcQ=";
    };

    whisperPreprocessorUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://huggingface.co/openai/whisper-small/resolve/main/preprocessor_config.json";
    };

    whisperPreprocessorHash = lib.mkOption {
      type = lib.types.str;
      default = "sha256-m1zQOjb7uKYnxk2YpbWxJurZWndyByOURIcxHwEQtmY=";
    };

    whisperGenerationUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://huggingface.co/openai/whisper-small/resolve/main/generation_config.json";
    };

    whisperGenerationHash = lib.mkOption {
      type = lib.types.str;
      default = "sha256-cVZbjvUNC/ehGT7Uu+0ZW5TnDBiJTYG7ovEjPc7Dq1M=";
    };

    ditF0CheckpointUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://huggingface.co/Plachta/Seed-VC/resolve/main/DiT_seed_v2_uvit_whisper_base_f0_44k_bigvgan_pruned_ft_ema_v2.pth";
      description = "DiT-чекпойнт (singing, 44.1 кГц, f0)";
    };

    ditF0CheckpointHash = lib.mkOption {
      type = lib.types.str;
      default = "sha256-Qq75P/5lhXyEDScCUvoED3ugRRSUXsRg86wawqlt5oQ=";
    };

    ditF0ConfigUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://huggingface.co/Plachta/Seed-VC/resolve/main/config_dit_mel_seed_uvit_whisper_base_f0_44k.yml";
    };

    ditF0ConfigHash = lib.mkOption {
      type = lib.types.str;
      default = "sha256-/4bzQ7CMLe9AXwdQIu6xDa+6I8Tto20VEBD0ym16Ggo=";
    };

    bigvganF0GeneratorUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://huggingface.co/nvidia/bigvgan_v2_44khz_128band_512x/resolve/main/bigvgan_generator.pt";
    };

    bigvganF0GeneratorHash = lib.mkOption {
      type = lib.types.str;
      default = "sha256-2f5+xr0LRO2dZpc9UBLYGBwVcLAeXHLfUZc+JB3M01c=";
    };

    bigvganF0ConfigUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://huggingface.co/nvidia/bigvgan_v2_44khz_128band_512x/resolve/main/config.json";
    };

    bigvganF0ConfigHash = lib.mkOption {
      type = lib.types.str;
      default = "sha256-Zbf0h7+vFSVgVqdfZmfvX2QCFMmBkioRGSeHNwXqTds=";
    };

    rmvpeUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://huggingface.co/lj1995/VoiceConversionWebUI/resolve/main/rmvpe.pt";
      description = "RMVPE — F0-экстрактор для singing";
    };

    rmvpeHash = lib.mkOption {
      type = lib.types.str;
      default = "sha256-bWIhX0MG48ongkYYhgcgnwmvPcd+1CMu/dBpeYxOwZM=";
    };

    torchVersion = lib.mkOption {
      type = lib.types.str;
      default = "2.7.1+rocm6.3";
      description = "Колесо torch (ветка 2.7.x несёт ядра gfx1030 для RX 6600)";
    };

    torchChannel = lib.mkOption {
      type = lib.types.str;
      default = "rocm6.3";
      description = "Индекс колёс torch: rocm6.3 | rocm6.4 | cpu";
    };

    gfxVersion = lib.mkOption {
      type = lib.types.str;
      default = "10.3.0";
      description = "HSA_OVERRIDE_GFX_VERSION для torch+ROCm (RX 6600 = 10.3.0)";
    };

    transformersVersion = lib.mkOption {
      type = lib.types.str;
      default = "4.46.3";
    };

    huggingfaceHubVersion = lib.mkOption {
      type = lib.types.str;
      default = "0.28.1";
    };

    librosaVersion = lib.mkOption {
      type = lib.types.str;
      default = "0.10.2";
    };

    scipyVersion = lib.mkOption {
      type = lib.types.str;
      default = "1.13.1";
    };

    numpyVersion = lib.mkOption {
      type = lib.types.str;
      default = "1.26.4";
    };

    soundfileVersion = lib.mkOption {
      type = lib.types.str;
      default = "0.12.1";
    };

    munchVersion = lib.mkOption {
      type = lib.types.str;
      default = "4.0.0";
    };

    einopsVersion = lib.mkOption {
      type = lib.types.str;
      default = "0.8.0";
    };

    dacVersion = lib.mkOption {
      type = lib.types.str;
      default = "1.0.0";
      description = "descript-audio-codec (импорт dac.nn.quantize в length_regulator)";
    };
  };

  environment.systemPackages = [
    voice2voice
  ];

  users.users.${cfg.user}.extraGroups = [
    "render"
    "video"
  ];

  hardware.graphics.enable = true;
}
