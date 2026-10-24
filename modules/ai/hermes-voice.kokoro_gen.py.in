#!/usr/bin/env python3
"""hermes-kokoro: русский TTS на Kokoro-82M (порт kokoro-ru) c GPU ROCm.

Модель, голоса и конфиг приходят из Nix-модуля через переменные окружения.

Аргументы (-i/-f/-v/-s) или env: KOKORO_IN, KOKORO_OUT, KOKORO_VOICE, KOKORO_SPEED.
Env модели: KOKORO_MODEL_PTH (base), KOKORO_MODEL_DIMA_PTH, KOKORO_VOICE_DIR,
KOKORO_ASSETS (ru_g2p.py + espeak-data + kokoro-config.json), KOKORO_CACHE.
"""
import argparse, os, sys
from pathlib import Path

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-i", "--input", default=os.environ.get("KOKORO_IN"))
    ap.add_argument("-f", "--output", default=os.environ.get("KOKORO_OUT"))
    ap.add_argument("-v", "--voice", default=os.environ.get("KOKORO_VOICE", "sveta"))
    ap.add_argument("-s", "--speed", type=float,
                    default=float(os.environ.get("KOKORO_SPEED", "1.0")))
    args = ap.parse_args()
    if not args.input or not args.output:
        sys.exit("need -i/-f or KOKORO_IN/KOKORO_OUT")
    # Absolutize before any chdir (RUAccent cache init changes cwd).
    args.input = str(Path(args.input).resolve())
    args.output = str(Path(args.output).resolve())

    text = Path(args.input).read_text(encoding="utf-8").strip()
    if not text:
        sys.exit("empty input text")

    cache = Path(os.environ.get("KOKORO_CACHE", os.path.expanduser("~/.local/share/hermes-kokoro")))
    os.environ.setdefault("HF_HOME", str(cache / "huggingface"))
    ruaccent_dir = cache / "ruaccent"
    ruaccent_dir.mkdir(parents=True, exist_ok=True)
    os.chdir(ruaccent_dir)  # RUAccent writes its ONNX models into cwd

    import torch
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"[kokoro] torch={torch.__version__} device={dev} voice={args.voice}",
          file=sys.stderr)

    sys.path.insert(0, os.environ["KOKORO_ASSETS"])  # ru_g2p.py + kokoro-config.json
    from ru_g2p import RuG2P

    voice_pt = Path(os.environ["KOKORO_VOICE_DIR"]) / f"{args.voice}.pt"
    if not voice_pt.exists():
        sys.exit(f"voice '{args.voice}' not found in {os.environ['KOKORO_VOICE_DIR']}")
    # dima's voicepack needs its own checkpoint; sveta/masha share base.
    pth = (os.environ["KOKORO_MODEL_DIMA_PTH"] if args.voice == "dima"
           else os.environ["KOKORO_MODEL_PTH"])

    # espeak-data lives in git-lfs: pure nix sources yield LFS pointers.
    # Prefer a complete real copy; otherwise download once into cache.
    def _espeak_ok(p):
        f = p / "phondata"
        return f.is_file() and f.stat().st_size > 1_000_000
    assets_espeak = Path(os.environ["KOKORO_ASSETS"]) / "espeak-data"
    if "KOKORO_ESPEAK_DATA" in os.environ and _espeak_ok(Path(os.environ["KOKORO_ESPEAK_DATA"])):
        espeak_data = Path(os.environ["KOKORO_ESPEAK_DATA"])
    elif _espeak_ok(assets_espeak):
        espeak_data = assets_espeak
    else:
        espeak_data = cache / "espeak-data"
        if not _espeak_ok(espeak_data):
            from huggingface_hub import snapshot_download
            snapshot_download("zaakirio/kokoro-ru", local_dir=str(cache),
                              allow_patterns=["espeak-data/*"])

    g2p = RuG2P(espeak_data=str(espeak_data))
    ipa, oov = g2p(text)
    if oov:
        print(f"[kokoro] OOV phonemes kept: {oov}", file=sys.stderr)

    from kokoro import KModel
    model = KModel(repo_id="zaakirio/kokoro-ru", model=pth).eval()

    pack = torch.load(voice_pt, map_location="cpu", weights_only=False)

    def to_dev(x):
        if isinstance(x, torch.Tensor):
            return x.to(dev)
        if isinstance(x, dict):
            return {k: to_dev(v) for k, v in x.items()}
        if isinstance(x, list):
            return [to_dev(v) for v in x]
        return x

    if dev == "cuda":
        model.to(dev)
        pack = to_dev(pack)

    with torch.no_grad():
        audio = model(ipa, pack[len(ipa) - 1], args.speed, return_output=True).audio

    import soundfile as sf
    sf.write(args.output, audio.detach().float().cpu().numpy(), 24000)
    print(f"[kokoro] wrote {args.output}", file=sys.stderr)

if __name__ == "__main__":
    main()
