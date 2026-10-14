// Autenticação Flutter -> Motoca Premium: reaproveita o Firebase Auth que o
// app já usa (chat/chat_service.dart). O Flutter manda o ID token do usuário
// logado como Bearer; aqui validamos a assinatura contra o JWKS público do
// Google e conferimos iss/aud contra o project id do Firebase.

import { createRemoteJWKSet, jwtVerify } from "jose";

const JWKS_URL = "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";
let jwks: ReturnType<typeof createRemoteJWKSet> | null = null;

export interface MotoboyIdentity {
  uid: string;
  email?: string;
}

export async function validarFirebaseIdToken(
  authHeader: string | null,
  firebaseProjectId: string,
): Promise<MotoboyIdentity | null> {
  if (!authHeader?.startsWith("Bearer ")) return null;
  const token = authHeader.slice("Bearer ".length).trim();
  if (!token) return null;

  jwks ??= createRemoteJWKSet(new URL(JWKS_URL));

  try {
    const { payload } = await jwtVerify(token, jwks, {
      issuer: `https://securetoken.google.com/${firebaseProjectId}`,
      audience: firebaseProjectId,
    });
    if (typeof payload.sub !== "string") return null;
    return { uid: payload.sub, email: typeof payload.email === "string" ? payload.email : undefined };
  } catch {
    return null;
  }
}
