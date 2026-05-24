{
  pkgs,
  lib,
}: final: prev: let
  # Many older sdist-only packages on PyPI use setuptools' legacy build_meta
  # backend but FORGET to declare setuptools in `build-system.requires`.
  # uv builds with `--no-build-isolation` (per pyproject.nix convention) which
  # surfaces this as a `ModuleNotFoundError: No module named 'setuptools'`.
  #
  # Fix: inject setuptools (and wheel) into nativeBuildInputs for the affected
  # packages. Listing a non-existent package name here is fine — it lazy-fails
  # only if that key is actually consumed downstream.
  addSetuptools = pkg:
    pkg.overrideAttrs (old: {
      nativeBuildInputs =
        (old.nativeBuildInputs or [])
        ++ [final.setuptools final.wheel];
    });

  # Alibaba Cloud SDK family — all pulled by the `dingtalk` extra.
  alibabaPatches = {
    alibabacloud-credentials-api = addSetuptools prev.alibabacloud-credentials-api;
    alibabacloud-credentials = addSetuptools prev.alibabacloud-credentials;
    alibabacloud-endpoint-util = addSetuptools prev.alibabacloud-endpoint-util;
    alibabacloud-gateway-dingtalk = addSetuptools prev.alibabacloud-gateway-dingtalk;
    alibabacloud-gateway-spi = addSetuptools prev.alibabacloud-gateway-spi;
    alibabacloud-openapi-util = addSetuptools prev.alibabacloud-openapi-util;
    alibabacloud-tea = addSetuptools prev.alibabacloud-tea;
    alibabacloud-tea-openapi = addSetuptools prev.alibabacloud-tea-openapi;
    alibabacloud-tea-util = addSetuptools prev.alibabacloud-tea-util;
    alibabacloud-tea-xml = addSetuptools prev.alibabacloud-tea-xml;
    alibabacloud-dingtalk = addSetuptools prev.alibabacloud-dingtalk;
    dingtalk-stream = addSetuptools prev.dingtalk-stream;

    # Matrix protocol (matrix-nio dep)
    python-olm = addSetuptools prev.python-olm;
  };
in
  alibabaPatches
  // {
    # Voice extras — portaudio
    sounddevice = prev.sounddevice.overrideAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [pkgs.portaudio];
      postFixup = ''
        patchelf --set-rpath ${pkgs.portaudio}/lib $out/lib/python*/site-packages/sounddevice*.so 2>/dev/null || true
      '';
    });

    # faster-whisper → soundfile → libsndfile
    soundfile = prev.soundfile.overrideAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [pkgs.libsndfile];
      postFixup = ''
        patchelf --set-rpath ${pkgs.libsndfile.out}/lib $out/lib/python*/site-packages/_soundfile_data/*.so 2>/dev/null || true
      '';
    });
  }
