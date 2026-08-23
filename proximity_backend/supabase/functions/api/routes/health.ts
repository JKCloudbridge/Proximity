import { Hono } from "npm:hono";

export const healthRoute = new Hono();

healthRoute.get("/health", (c) => c.json({ data: { status: "ok" } }));
