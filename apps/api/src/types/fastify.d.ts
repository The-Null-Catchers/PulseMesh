import "fastify";

declare module "fastify" {
  interface FastifyRequest {
    auth: { userId: string; sessionId: string } | null;
  }

  interface FastifyInstance {
    authenticate(request: FastifyRequest): Promise<void>;
  }
}
