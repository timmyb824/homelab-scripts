module.exports = {
  apps: [
    {
      name: "redis-commander",
      script: "/home/tbryant/DEV/homelab/homelab-scripts/scripts/tools/redis-commander/start_redis_commander.sh",
      interpreter: "none", // script has its own #!/usr/bin/env bash shebang
      cwd: "/home/tbryant",
      autorestart: true,
      watch: false,
      max_restarts: 10,
      restart_delay: 5000,
      env: {},
    },
  ],
};
