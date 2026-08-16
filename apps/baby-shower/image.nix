{
  baby-shower,
  cacert,
  dockerTools,
  nodejs_22,
}:
dockerTools.buildLayeredImage {
  name = "baby-shower";
  tag = "latest";

  contents = [
    baby-shower
    cacert
    nodejs_22
  ];

  extraCommands = ''
    mkdir -p app data tmp
    cp -r ${baby-shower}/app/.output app/.output
    cp -r ${baby-shower}/app/drizzle app/drizzle
    chmod 1777 tmp
  '';

  config = {
    WorkingDir = "/app";
    Env = [
      "DATABASE_URL=/data/baby-shower.sqlite"
      "MIGRATIONS_DIR=/app/drizzle"
      "NODE_ENV=production"
      "PORT=3000"
      "SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt"
      "TMPDIR=/tmp"
    ];
    ExposedPorts."3000/tcp" = {};
    Volumes."/data" = {};
    Cmd = ["${nodejs_22}/bin/node" "/app/.output/server/index.mjs"];
  };
}
