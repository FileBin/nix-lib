# ai.voice2voice — локальный voice-to-voice (смена голоса)

Модуль ставит в `environment.systemPackages` бинарник `voice2voice` — обёртку над
[Seed-VC](https://github.com/Plachtaa/Seed-VC) (zero-shot смена голоса): по референсу
целевого голоса (1–25 с) переозвучивает вашу запись.

Два режима:

- **speech** (по умолчанию, `f0_condition = false`) — 22.05 кГц, озвучка/дубляж.
- **singing** (`--f0-condition True`) — 44.1 кГц, перенос мелодии (F0, RMVPE).

## Подключение (flake)

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nix-lib.url = "github:FileBin/nix-lib";
  };

  outputs = { nixpkgs, nix-lib, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nix-lib.nixosModules.default
        {
          ai.voice2voice.enable = true;
        }
      ];
    };
  };
}
```

## Подключение (классический конфиг, без flake)

```nix
{ config, pkgs, ... }:
let
  nix-lib = builtins.getFlake "github:FileBin/nix-lib";
in
{
  imports = [ nix-lib.nixosModules.default ];

  ai.voice2voice.enable = true;
}
```

После `nixos-rebuild switch` бинарник доступен:

```
voice2voice -s input.wav -t reference.wav -o output.wav
```

## Использование

```
# смена голоса (speech)
voice2voice -s моя-запись.wav -t референс-голоса.wav -o out.wav

# пение: перенос мелодии из source на голос из reference
voice2voice -s вокал.wav -t референс.wav -o out.wav --f0-condition True

# качество/скорость
voice2voice ... --diffusion-steps 50        # 25=быстро, 30–50=качественнее
voice2voice ... --semi-tone-shift 2         # сдвиг высоты (только singing)
```

## Основные опции (`ai.voice2voice.*`)

- `enable` — включить модуль (по умолчанию `false`).
- `user` — пользователь, которому добавляются группы `render`/`video` для доступа
  к `/dev/kfd` (по умолчанию `"filebin"`).
- `torchChannel` — индекс колёс PyTorch: `rocm6.3` | `rocm6.4` | `cpu`
  (по умолчанию `rocm6.3`).
- `gfxVersion` — `HSA_OVERRIDE_GFX_VERSION` для torch+ROCm (RX 6600 = `10.3.0`).
- `torchVersion` — колесо torch (по умолчанию `2.7.1+rocm6.3`).

Остальные опции — пины URL/хешей моделей и версий зависимостей; см. `default.nix`.

## Примеры настройки custom-опций

Опции задаются через тот же атрибут `ai.voice2voice`, что и `enable`.
Примеры ниже можно копировать в свой конфиг.

### CPU-режим (нет ROCm-совместимого GPU)

```nix
{ config, pkgs, ... }: {
  ai.voice2voice = {
    enable = true;
    user = "myuser";        # кому выдаются группы render/video (если GPU есть)
    torchChannel = "cpu";   # fallback без ROCm — заметно медленнее
  };
}
```

### Смена версии ROCm / настройка под другой GPU

```nix
{ config, pkgs, ... }: {
  ai.voice2voice = {
    enable = true;
    torchChannel = "rocm6.4";
    torchVersion = "2.7.1+rocm6.4";
    gfxVersion = "11.0.0";  # HSA_OVERRIDE_GFX_VERSION (RX 6600 = 10.3.0)
  };
}
```

### Подмена модели/чекпойнта (URL + хеш задаются парой)

```nix
{ config, pkgs, ... }: {
  ai.voice2voice = {
    enable = true;
    ditCheckpointUrl = "https://huggingface.co/.../custom-dit.pth";
    ditCheckpointHash = "sha256-...";  # nix-prefetch-url или nix flake prefetch
  };
}
```

## Первый запуск и ресурсы

- Веса моделей (~1.8 ГБ) скачиваются в nix store при сборке конфигурации
  (`fetchurl`).
- При первом запуске создаётся venv с torch+torchaudio (ROCm) и зависимостями
  (~20 ГБ) в `~/.local/share/voice2voice` (переопределяется через `VOICE2VOICE_CACHE`).
- Нужен GPU с ROCm; иначе задайте `ai.voice2voice.torchChannel = "cpu"`
  (заметно медленнее).
