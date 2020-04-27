export function sanitizeEnv() {
  const requiredEnvVars = [
    "DATABASE_OWNER",
    "DATABASE_OWNER_PASSWORD",
    "DATABASE_AUTHENTICATOR",
    "DATABASE_AUTHENTICATOR_PASSWORD",
    "NODE_ENV",
  ];
  requiredEnvVars.forEach((envvar) => {
    if (!process.env[envvar]) {
      throw new Error(
        `Could not find process.env.${envvar} - did you remember to run the setup script? Have you sourced the environmental variables file '.env'?`
      );
    }
  });
}
