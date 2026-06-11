-- Garante que a RPC de relacionados nao herde o statement_timeout=8s do role
-- authenticated/authenticator usado pelo frontend via PostgREST.

ALTER FUNCTION public.oraculo_relacionados_ticket(UUID, INT)
  SET statement_timeout TO '90s';
