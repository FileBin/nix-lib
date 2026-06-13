{ pkgs, ... }: {
  nixpkgs.overlays = [
    (final: prev: {
      obs-studio = prev.obs-studio.overrideAttrs (oldAttrs: {
        # obs-studio is a bit of a mess, so we need to override it
        # to add a postInstall step that wraps the binary in a way that
        # allows it to run in X11 mode on Wayland.
        postInstall = (oldAttrs.postInstall or "") + ''
          wrapProgram $out/bin/obs --set QT_QPA_PLATFORM "xcb"
        '';
      });
    })
  ];

  programs.obs-studio = {
    enable = true;

    # Enable virtual camera
    enableVirtualCamera = true;

    plugins = with pkgs.obs-studio-plugins; [
      wlrobs
      obs-backgroundremoval
      obs-pipewire-audio-capture
      obs-vaapi #optional AMD hardware acceleration
      obs-gstreamer
      obs-vkcapture
      input-overlay
    ];
  };

}
