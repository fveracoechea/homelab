{...}: {
  virtualisation.podman.enable = true;

  virtualisation.oci-containers.containers.paperless-gpt = {
    image = "ghcr.io/icereed/paperless-gpt:latest";
    autoStart = true;
    extraOptions = ["--network=host"];
    environment = {
      LISTEN_INTERFACE = "127.0.0.1:8080";
      PAPERLESS_BASE_URL = "http://127.0.0.1:28981";
      LLM_PROVIDER = "ollama";
      LLM_MODEL = "qwen3.5:9b";
      OLLAMA_HOST = "http://127.0.0.1:11434";
      OLLAMA_CONTEXT_LENGTH = "8192";
      OLLAMA_THINK = "false";
      OCR_PROVIDER = "llm";
      VISION_LLM_PROVIDER = "ollama";
      VISION_LLM_MODEL = "minicpm-v4.5";
      OCR_PROCESS_MODE = "image";
      LLM_LANGUAGE = "English";
      LOG_LEVEL = "info";
      CREATE_NEW_TAGS = "true";
    };
    environmentFiles = ["/var/lib/paperless-gpt/paperless-gpt.env"];
    volumes = [
      "/var/lib/paperless-gpt/prompts:/app/prompts"
      "/var/lib/paperless-gpt/config:/app/config"
      "/var/lib/paperless-gpt/data:/app/data"
    ];
  };

  services.caddy.virtualHosts."ai-docs.veracoechea.com".extraConfig = ''
    tls /var/lib/acme/veracoechea.com/fullchain.pem /var/lib/acme/veracoechea.com/key.pem
    reverse_proxy 127.0.0.1:8080
  '';
}
