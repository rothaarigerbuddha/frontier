import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Build a self-contained server bundle for a slim Docker image.
  output: "standalone",

  images: {
    // Article images are served same-origin (relative `/images/posts/...`)
    // through the gateway, so they need no remote pattern. Only the external
    // Unsplash fallback used by <Image> components is listed here.
    remotePatterns: [
      {
        protocol: "https",
        hostname: "images.unsplash.com",
        pathname: "/**",
      },
    ],
  },

  experimental: {
    // The app runs behind a reverse proxy (Caddy gateway) and is reachable via
    // tunnels (Cloudflare / ngrok). Server Actions enforce an Origin<->Host
    // match for CSRF protection, so every host the app may be served under must
    // be whitelisted here, otherwise actions (login, create/update) get 403.
    serverActions: {
      allowedOrigins: [
        "localhost:8080",
        "127.0.0.1:8080",
        "localhost:3000",
        "127.0.0.1:3000",
        "*.trycloudflare.com",
        "*.ngrok-free.app",
        "*.ngrok-free.dev",
        "*.ngrok.app",
        "*.ngrok.io",
      ],
    },
  },
};

export default nextConfig;
