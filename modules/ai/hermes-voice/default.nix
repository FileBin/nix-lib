# Локальный голос для Hermes Agent: STT (whisper.cpp на GPU) + TTS (kokoro на GPU / piper на CPU).
#
# Ставит обёртки в systemPackages:
#   hermes-stt    — whisper.cpp -f <audio> -l <lang>, транскрипт в stdout
#   hermes-kokoro — kokoro TTS на GPU (torch+ROCm), -i <text> -f <out.wav>
#   hermes-tts    — piper TTS на CPU, -i <text> -f <out.wav> (лёгкая альтернатива)
{
  pkgs,
  lib,
  moduleConfig,
  ...
}:
let
  cfg = moduleConfig;

  # --- STT: whisper.cpp ----------------------------------------------------
  whisper = pkgs.whisper-cpp.override {
    cudaSupport = cfg.gpu == "cuda";
    rocmSupport = cfg.gpu == "rocm";
  };

  whisperModel = pkgs.fetchurl {
    url = cfg.whisperModelUrl;
    sha256 = cfg.whisperModelHash;
  };

  hermes-stt = pkgs.writeShellScriptBin "hermes-stt" ''
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    # ffmpeg нужен для opus/webm/mp3 — голосовые сообщения приходят в opus
    PATH=${lib.makeBinPath [ pkgs.ffmpeg-headless ]}:$PATH \
      ${lib.getExe whisper} \
        -m ${whisperModel} \
        "$@" \
        -otxt -of "$tmp/out" >/dev/null
    cat "$tmp/out.txt"
  '';

  # --- TTS: piper (CPU) ----------------------------------------------------
  # piper не собирается, когда в nixpkgs включён cudaSupport (падает CUDA-цепочка),
  # поэтому берём его из отдельного экземпляра nixpkgs без CUDA.
  cpuPkgs = import pkgs.path {
    system = pkgs.stdenv.hostPlatform.system;
    config = { cudaSupport = false; };
  };
  piper = cpuPkgs.piper-tts.override {
    withTrain = false;
    withJapanese = false;
  };

  piperVoice = pkgs.runCommand "piper-voice" { } ''
    mkdir -p $out
    cp ${pkgs.fetchurl {
      url = cfg.piperVoiceModelUrl;
      sha256 = cfg.piperVoiceModelHash;
    }} $out/voice.onnx
    cp ${pkgs.fetchurl {
      url = cfg.piperVoiceConfigUrl;
      sha256 = cfg.piperVoiceConfigHash;
    }} $out/voice.onnx.json
    chmod +w $out/voice.onnx $out/voice.onnx.json
  '';

  hermes-tts = pkgs.writeShellScriptBin "hermes-tts" ''
    exec ${lib.getExe piper} \
      -m ${piperVoice}/voice.onnx \
      "$@"
  '';

  # --- TTS: kokoro (GPU через torch+ROCm) ----------------------------------
  # Генератор держим отдельным файлом в репозитории: см. modules/ai/hermes-voice/.
  kokoroPython = pkgs.python312;

  # manylinux-колесо torch тянет libstdc++/libzstd/… из системного окружения.
  kokoroLdPath = lib.makeLibraryPath [
    pkgs.gcc.cc.lib
    pkgs.zstd
    pkgs.zlib
    pkgs.ncurses
    pkgs.numactl
    pkgs.libdrm
  ];

  kokoroSrc = builtins.fetchGit {
    url = "https://huggingface.co/zaakirio/kokoro-ru";
    rev = cfg.kokoroRev;
  };

  kokoroAssets = pkgs.runCommand "kokoro-ru-assets" { } ''
    mkdir -p $out
    cp ${kokoroSrc}/ru_g2p.py ${kokoroSrc}/kokoro-config.json $out/
    chmod -R u+w $out
  '';

  kokoroVoices = pkgs.runCommand "kokoro-ru-voices" { } ''
    mkdir -p $out
    cp ${pkgs.fetchurl {
      url = "https://huggingface.co/zaakirio/kokoro-ru/resolve/main/voices/sveta.pt";
      sha256 = "sha256-JIwA6Y984gwx/1U3tS6j07IEpYhF2G2nOWDzDxEvYKc=";
    }} $out/sveta.pt
    cp ${pkgs.fetchurl {
      url = "https://huggingface.co/zaakirio/kokoro-ru/resolve/main/voices/masha.pt";
      sha256 = "sha256-Rk1krnk2R8Oz+dHwjOWxHGQaYXmfC8pl8RHmqtXQo2I=";
    }} $out/masha.pt
    cp ${pkgs.fetchurl {
      url = "https://huggingface.co/zaakirio/kokoro-ru/resolve/main/voices/dima.pt";
      sha256 = "sha256-gNTSFrWQbCMu3kjywHqzruB4XjTR327G3Iz0R2fXTGk=";
    }} $out/dima.pt
  '';

  kokoroModelBase = pkgs.fetchurl {
    url = "https://huggingface.co/zaakirio/kokoro-ru/resolve/main/kokoro-ru-v2-base.pth";
    sha256 = "sha256-O77lvAXPoYKvw2W5EW6u2DVfk5w8CviqDkP9xFNDyhU=";
  };

  kokoroModelDima = pkgs.fetchurl {
    url = "https://huggingface.co/zaakirio/kokoro-ru/resolve/main/kokoro-ru-v2-dima.pth";
    sha256 = "sha256-ZYrkfiQiQlfqn4PIjqd0PFyfCSLGvDOYBf/rz9vLKyQ=";
  };

  kokoroInner = pkgs.writeShellScript "hermes-kokoro-inner" ''
    set -euo pipefail
    CACHE="''${KOKORO_CACHE:-$HOME/.local/share/hermes-kokoro}"
    VENV="$CACHE/venv"
    mkdir -p "$CACHE"
    if [ ! -x "$VENV/bin/python" ] || ! "$VENV/bin/python" -c 'import sys' 2>/dev/null; then
      echo "[kokoro] первый запуск: создаю venv и ставлю torch+kokoro (~2.5 ГБ)." >&2
      ${kokoroPython}/bin/python3.12 -m venv "$VENV"
      "$VENV/bin/pip" install -q --upgrade pip
      "$VENV/bin/pip" install -q "torch==${cfg.kokoroTorchVersion}" \
        --index-url https://download.pytorch.org/whl/${cfg.kokoroTorchChannel}
      "$VENV/bin/pip" install -q "kokoro==${cfg.kokoroVersion}" "ruaccent==${cfg.ruaccentVersion}" soundfile
    fi
    export LD_LIBRARY_PATH="${kokoroLdPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export HSA_OVERRIDE_GFX_VERSION="${cfg.kokoroGfxVersion}"
    export KOKORO_ASSETS="${kokoroAssets}"
    export KOKORO_VOICE_DIR="${kokoroVoices}"
    export KOKORO_MODEL_PTH="${kokoroModelBase}"
    export KOKORO_MODEL_DIMA_PTH="${kokoroModelDima}"
    export KOKORO_CACHE="$CACHE"
    export HF_HOME="$CACHE/huggingface"
    exec "$VENV/bin/python" "${./kokoro_gen.py}" "$@"
  '';

  kokoroEnv = pkgs.buildFHSEnv {
    name = "hermes-kokoro-env";
    targetPkgs = p: [ ];
    runScript = "${kokoroInner}";
  };

  hermes-kokoro = pkgs.writeShellScriptBin "hermes-kokoro" ''
    exec ${kokoroEnv}/bin/hermes-kokoro-env "$@"
  '';
in
{
  customOptions = {
    user = lib.mkOption {
      type = lib.types.str;
      default = "filebin";
      description = "Пользователь, которому нужны группы render/video для /dev/kfd";
    };

    gpu = lib.mkOption {
      type = lib.types.enum [
        "rocm"
        "cuda"
        "cpu"
      ];
      default = "rocm";
      description = "Ускорение whisper.cpp: rocm | cuda | cpu";
    };

    whisperModelUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin";
      description = "URL GGML-модели whisper (small — хорош для русского)";
    };

    whisperModelHash = lib.mkOption {
      type = lib.types.str;
      default = "sha256-G+OpsgY4Z7k35k4ux0gzZKeZF+FX+pjF2UtcH//qmHs=";
      description = "sha256 GGML-модели (nix-prefetch-url)";
    };

    piperVoiceModelUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://huggingface.co/rhasspy/piper-voices/resolve/main/ru/ru_RU/dmitri/medium/ru_RU-dmitri-medium.onnx";
      description = "URL ONNX-голоса piper";
    };

    piperVoiceModelHash = lib.mkOption {
      type = lib.types.str;
      default = "sha256-8HM1brxL0PgMWvWN8pU6WYi9W9qx6zhjXOlgsHH778s=";
      description = "sha256 ONNX-голоса piper";
    };

    piperVoiceConfigUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://huggingface.co/rhasspy/piper-voices/resolve/main/ru/ru_RU/dmitri/medium/ru_RU-dmitri-medium.onnx.json";
      description = "URL конфига голоса piper";
    };

    piperVoiceConfigHash = lib.mkOption {
      type = lib.types.str;
      default = "sha256-Zn7zEXvGQsKJLf92kNi9yMpCKK6qeDstwUFt9jKFXg0=";
      description = "sha256 конфига голоса piper";
    };

    kokoroRev = lib.mkOption {
      type = lib.types.str;
      default = "d649c57b239b18c4c384378127cbf01dba039bc1";
      description = "git-ревизия zaakirio/kokoro-ru (ru_g2p.py, kokoro-config.json)";
    };

    kokoroVersion = lib.mkOption {
      type = lib.types.str;
      default = "0.9.4";
      description = "Версия pip-пакета kokoro";
    };

    kokoroTorchVersion = lib.mkOption {
      type = lib.types.str;
      default = "2.7.1+rocm6.3";
      description = "Колесо torch (ветка 2.7.x несёт ядра gfx1030 для RX 6600)";
    };

    kokoroTorchChannel = lib.mkOption {
      type = lib.types.str;
      default = "rocm6.3";
      description = "Индекс колёс torch: rocm6.3 | rocm6.4 | cpu";
    };

    ruaccentVersion = lib.mkOption {
      type = lib.types.str;
      default = "1.5.8.3";
      description = "Версия RUAccent — постановка ударений для русского G2P";
    };

    kokoroGfxVersion = lib.mkOption {
      type = lib.types.str;
      default = "10.3.0";
      description = "HSA_OVERRIDE_GFX_VERSION для torch+ROCm (RX 6600 = 10.3.0)";
    };
  };

  environment.systemPackages = [
    hermes-stt
    hermes-tts
    hermes-kokoro
  ];

  users.users.${cfg.user}.extraGroups = lib.mkIf (cfg.gpu == "rocm") [
    "render"
    "video"
  ];

  hardware.graphics.enable = true;
}
