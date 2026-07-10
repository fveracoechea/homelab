{pkgs, ...}: {
  services.ollama = {
    enable = true;
    package = pkgs.ollama-rocm;
    host = "127.0.0.1";
    port = 11434;
    rocmOverrideGfx = "11.0.0";
    loadModels = ["qwen3.5:9b"];
    environmentVariables = {
      ROCR_VISIBLE_DEVICES = "0";
    };
  };
}
