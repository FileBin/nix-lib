{ lib, ... }:
let
  ru = "ru_RU.UTF-8";
in
{
  i18n.defaultLocale = "${ru}";
  i18n.extraLocales = [ "${ru}/UTF-8" ];
  i18n.extraLocaleSettings = {
    LC_MEASUREMENT = lib.mkDefault ru;
    LC_PAPER = lib.mkDefault ru;
    LC_TIME = lib.mkDefault ru;
  };
}
