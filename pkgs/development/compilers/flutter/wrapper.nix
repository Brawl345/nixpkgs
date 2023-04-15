{ lib
, stdenv
, callPackage
, flutter
, supportsLinuxDesktop ? stdenv.isLinux
, makeWrapper
, runCommandLocal
, writeShellScript
, git
, which
, pkg-config
, atk
, cairo
, gdk-pixbuf
, glib
, gtk3
, harfbuzz
, libepoxy
, pango
, libX11
, xorgproto
, libdeflate
, zlib
, cmake
, ninja
, clang
}:

let
  # By default, Flutter stores downloaded files (such as the Pub cache) in the SDK directory.
  # Wrap it to ensure that it does not do that, preferring home directories instead.
  immutableFlutter = writeShellScript "flutter_immutable" ''
    export PUB_CACHE=''${PUB_CACHE:-"$HOME/.pub-cache"}
    ${flutter}/bin/flutter "$@"
  '';

  # Tools that the Flutter tool depends on.
  tools = [ git which ];

  # Libraries that Flutter apps depend on at runtime.
  appRuntimeDeps = lib.optionals supportsLinuxDesktop [
    atk
    cairo
    gdk-pixbuf
    glib
    gtk3
    harfbuzz
    libepoxy
    pango
    libX11
    libdeflate
  ];

  # Development packages required for compilation.
  appBuildDeps =
    let
      # https://discourse.nixos.org/t/handling-transitive-c-dependencies/5942/3
      deps = pkg: builtins.filter lib.isDerivation ((pkg.buildInputs or [ ]) ++ (pkg.propagatedBuildInputs or [ ]));
      collect = pkg: lib.unique ([ pkg ] ++ deps pkg ++ builtins.concatMap collect (deps pkg));
    in
    builtins.concatMap collect appRuntimeDeps;

  # Some header files and libraries are not properly located by the Flutter SDK.
  # They must be manually included.
  appStaticBuildDeps = lib.optionals supportsLinuxDesktop [ libX11 xorgproto zlib ];

  # Tools used by the Flutter SDK to compile applications.
  buildTools = lib.optionals supportsLinuxDesktop [
    pkg-config
    cmake
    ninja
    clang
  ];

  # Nix-specific compiler configuration.
  pkgConfigDirectories = builtins.filter builtins.pathExists (builtins.concatMap (pkg: map (dir: "${lib.getOutput "dev" pkg}/${dir}/pkgconfig") [ "lib" "share" ]) appBuildDeps);
  cppFlags = map (pkg: "-isystem ${lib.getOutput "dev" pkg}/include") appStaticBuildDeps;
  linkerFlags = map (pkg: "-rpath,${lib.getOutput "lib" pkg}/lib") appRuntimeDeps;
in
(callPackage ./sdk-symlink.nix { }) (runCommandLocal "flutter-wrapped"
{
  nativeBuildInputs = [ makeWrapper ];

  passthru = flutter.passthru // {
    inherit (flutter) version;
    unwrapped = flutter;
  };

  inherit (flutter) meta;
} ''
  mkdir -p $out/bin
  makeWrapper '${immutableFlutter}' $out/bin/flutter \
    --set-default ANDROID_EMULATOR_USE_SYSTEM_LIBS 1 \
    --prefix PATH : '${lib.makeBinPath (tools ++ buildTools)}' \
    --prefix PKG_CONFIG_PATH : '${builtins.concatStringsSep ":" pkgConfigDirectories}' \
    --prefix LIBRARY_PATH : '${lib.makeLibraryPath appStaticBuildDeps}' \
    --prefix CXXFLAGS "''\t" '${builtins.concatStringsSep " " cppFlags}' \
    --prefix LDFLAGS "''\t" '${builtins.concatStringsSep " " (map (flag: "-Wl,${flag}") linkerFlags)}'
'')
