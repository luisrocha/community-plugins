{ currentFile, newestFile }:
let
  current = builtins.fromJSON (builtins.readFile currentFile);
  newest = builtins.fromJSON (builtins.readFile newestFile);
  key = p: p.scope + ":" + p.name;
  keys = builtins.attrNames (builtins.listToAttrs (map (p: { name = key p; value = true; }) (current ++ newest)));
  matches = records: k: builtins.filter (p: key p == k) records;
  versions = records:
    if records == [] then "—" else
    builtins.concatStringsSep ", " (builtins.attrNames (builtins.listToAttrs
      (map (p: { name = if p.version == "" then "unknown" else p.version; value = true; }) records)));
  line = k:
    let old = matches current k; new = matches newest k; p = builtins.head (old ++ new);
    in builtins.concatStringsSep "\t" [ p.scope p.name (versions old) (versions new) ];
in builtins.concatStringsSep "\n" (map line keys)
