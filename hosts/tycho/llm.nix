{ ... }:
{
  imports = [ ../../modules/nixos/llm ];

  personal.llm = {
    enable = true;
    ctxSize = 262144;
    parallel = 3;
    kvUnified = true;
  };
}
