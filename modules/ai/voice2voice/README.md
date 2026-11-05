# ai.voice2voice — локальный voice-to-voice (смена голоса)

Модуль ставит в `environment.systemPackages` бинарник `voice2voice` — обёртку над
[Seed-VC](https://github.com/Plachtaa/Seed-VC) (zero-shot смена голоса): по референсу
целевого голоса (1–25 с) переозвучивает вашу запись.

Два режима:

- **speech** (по умолчанию, `f0_condition = false`) — 22.05 кГц, озвучка/дубляж.
- **singing** (`--f0-condition True`) — 44.1 кГц, перенос мелодии (F0, RMVPE).

## Быстрый старт (RX 6600 / ROCm)

Для RX 6600 достаточно включить модуль — дефолты уже правильные
(`torchChannel = "rocm6.3"`, `torchVersion = "2.7.1+rocm6.3"`, `gfxVersion = "10.3.0"`):

```nix
ai.voice2voice.enable = true;   # user по умолчанию "filebin"
```

> ⚠️ **`torchChannel` — это НЕ тип GPU.** Допустимо ровно три значения:
> `"rocm6.3"`, `"rocm6.4"`, `"cpu"`. Значение `"rocm"` (или `"cuda"`) **неверно**
> и даёт ошибку pip `Could not find a version that satisfies the requirement
> torch==...` — на индексе `whl/rocm` колёс нет.

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
- `torchChannel` — ветка колёс PyTorch: **только** `"rocm6.3"` | `"rocm6.4"` | `"cpu"`
  (по умолчанию `"rocm6.3"`).
- `torchVersion` — версия колеса torch; **должна соответствовать `torchChannel`**
  (см. таблицу ниже).
- `gfxVersion` — `HSA_OVERRIDE_GFX_VERSION` для torch+ROCm (RX 6600 = `"10.3.0"`).

Остальные опции — пины URL/хешей моделей и версий зависимостей; см. `default.nix`.

### Соответствие `torchChannel` ↔ `torchVersion`

| `torchChannel` | `torchVersion` | Для чего |
|---|---|---|
| `"rocm6.3"` | `"2.7.1+rocm6.3"` (дефолт) | RX 6600 / gfx1032 (через override 10.3.0) |
| `"rocm6.4"` | `"2.8.0+rocm6.4"` | более новые карты; на ветке 6.4 минимальная версия — **2.8.0** (2.7.1 там нет) |
| `"cpu"` | `"2.7.1"` (или `"2.7.1+cpu"`) | без GPU, заметно медленнее |

**Меняя `torchChannel`, меняйте и `torchVersion`** — иначе pip не найдёт колесо.

## Примеры настройки custom-опций

Опции задаются через тот же атрибут `ai.voice2voice`, что и `enable`.

### CPU-фолбэк (нет ROCm-совместимого GPU)

Нужно поменять **оба** значения — и channel, и version:

```nix
{ config, pkgs, ... }: {
  ai.voice2voice = {
    enable = true;
    torchChannel = "cpu";
    torchVersion = "2.7.1";   # без "+rocmX"
  };
}
```

### Другая ветка ROCm / другой GPU

```nix
{ config, pkgs, ... }: {
  ai.voice2voice = {
    enable = true;
    torchChannel = "rocm6.4";
    torchVersion = "2.8.0+rocm6.4";  # на rocm6.4 минимум 2.8.0
    gfxVersion = "11.0.0";           # HSA_OVERRIDE_GFX_VERSION (RX 6600 = 10.3.0)
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

- Веса моделей (~1.8 ГБ; singing-чекпойнт — ещё ~1.4 ГБ) скачиваются в nix store
  при сборке конфигурации (`fetchurl`).
- При первом запуске создаётся venv с torch+torchaudio (ROCm) и зависимостями
  (~20 ГБ) в `~/.local/share/voice2voice` (переопределяется через `VOICE2VOICE_CACHE`).
- Нужен GPU с ROCm; иначе `torchChannel = "cpu"` + `torchVersion = "2.7.1"`
  (заметно медленнее).
- Если первый запуск прервался — удалите `~/.local/share/voice2voice`, модуль
  пересоздаст venv сам (в нём есть маркер завершённой установки).

## Troubleshooting

**`ERROR: Could not find a version that satisfies the requirement torch==...`**

Частые причины:

1. **Опечатка в `torchChannel`** — например `"rocm"`/`"cuda"` вместо
   `"rocm6.3"`/`"rocm6.4"`/`"cpu"`. На индексе `whl/rocm` колёс нет вообще.
2. **`torchVersion` не совпадает с `torchChannel`** (поменяли channel, забыли
   version). Сверьтесь с таблицей «channel ↔ version».
3. **Нет сети до `download.pytorch.org`** (прокси/файрвол) — pip не видит индекс.

После исправления конфига (`nixos-rebuild switch`) при необходимости удалите
полусобранный venv: `rm -rf ~/.local/share/voice2voice`.
