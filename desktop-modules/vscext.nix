{ pkgs, ... }:
let
  vscext-script = pkgs.writeScriptBin "vscext" ''
    N="$1"

    publisher=$(echo "$N" | cut -d "." -f 1)
    name=$(echo "$N" | cut -d "." -f 2)

    # Create a tempdir for the extension download.
    EXTTMP=$(mktemp -d -t vscode_exts_XXXXXXXX)

    URL="https://$publisher.gallery.vsassets.io/_apis/public/gallery/publisher/$publisher/extension/$name/latest/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage"

    # Quietly but delicately curl down the file, blowing up at the first sign of trouble.
    curl --silent --show-error --retry 3 --fail -X GET -o "$EXTTMP/$N.zip" "$URL"
    # Unpack the file we need to stdout then pull out the version
    VER=$(${pkgs.jq}/bin/jq -r '.version' <(${pkgs.unzip}/bin/unzip -qc "$EXTTMP/$N.zip" "extension/package.json"))
    # Calculate the hash
    HASH=$(nix-hash --flat --sri --type sha256 "$EXTTMP/$N.zip")

    # Clean up.
    rm -Rf "$EXTTMP"
    # I don't like 'rm -Rf' lurking in my scripts but this seems appropriate.

    cat <<-EOF
    {
      name = "$name";
      publisher = "$publisher";
      version = "$VER";
      hash = "$HASH";
    }
    EOF
  '';
in
{
  environment.systemPackages = [ vscext-script ];
}
