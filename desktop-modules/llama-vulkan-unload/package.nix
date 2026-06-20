{
  pkgs,
  llama-apiBase,
  ...
}:
let
  layerSrc = pkgs.writeText "layer.cpp" (builtins.readFile ./layer.cpp);
in
pkgs.stdenv.mkDerivation {
  name = "llama-vulkan-unload";

  dontUnpack = true;
  dontConfigure = true;

  nativeBuildInputs = [ pkgs.gcc pkgs.nlohmann_json ];
  buildInputs = [
    pkgs.vulkan-loader
    pkgs.vulkan-headers
    pkgs.curl
  ];

  buildPhase = ''
    cp ${layerSrc} layer.cpp
    g++ -O2 -fPIC -shared -o libVkLayer_llama_unload.so \
      -DLLAMA_API_BASE="\"${llama-apiBase}\"" \
      layer.cpp \
      -lvulkan -lcurl
  '';

  installPhase = ''
    mkdir -p $out/lib $out/share/vulkan/implicit_layer.d
    cp libVkLayer_llama_unload.so $out/lib/
    cat > $out/share/vulkan/implicit_layer.d/VkLayer_llama_unload.json <<'EOF'
    {
      "file_format_version": "1.0.0",
      "layer": {
        "name": "VK_LAYER_llama_unload",
        "type": "GLOBAL",
        "library_path": "${pkgs.lib.placeholder "out"}/lib/libVkLayer_llama_unload.so",
        "api_version": "1.3.0",
        "implementation_version": "1",
        "description": "Unloads llama.cpp models to free up VRAM on Vulkan app start",
        "enable_environment": {
          "FREE_LLAMA_VRAM": "1"
        },
        "disable_environment": {
          "DISABLE_LLAMA_UNLOAD": "1"
        }
      }
    }
    EOF
  '';
}
