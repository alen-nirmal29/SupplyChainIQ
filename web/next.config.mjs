/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Server-only Snowflake driver must never be bundled for the client.
  serverExternalPackages: ["snowflake-sdk"],
};

export default nextConfig;
